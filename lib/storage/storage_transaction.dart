import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:locker/erasable/erasable.dart';
import 'package:locker/erasable/erasable_byte_array.dart';
import 'package:locker/security/models/cipher_func.dart';
import 'package:locker/security/models/password_cipher_func.dart';
import 'package:locker/storage/models/data/key_wrap.dart';
import 'package:locker/storage/models/data/origin.dart';
import 'package:locker/storage/models/data/storage_data.dart';
import 'package:locker/storage/models/data/storage_entry.dart';
import 'package:locker/storage/models/data/wrapped_key.dart';
import 'package:locker/storage/models/domain/entry_add_input.dart';
import 'package:locker/storage/models/domain/entry_id.dart';
import 'package:locker/storage/models/domain/entry_meta.dart';
import 'package:locker/storage/models/domain/entry_update_input.dart';
import 'package:locker/storage/models/domain/entry_value.dart';
import 'package:locker/storage/models/exceptions/storage_exception.dart';
import 'package:locker/utils/cryptography_utils.dart';

/// In-memory working copy of the storage for one open transaction; the file is
/// written once by the storage on close.
class StorageTransaction implements Erasable {
  StorageData _data;

  /// Snapshot at open, compared against the file on close (compare-and-swap).
  final StorageData baseData;

  /// The unwrapped master key used to (de)encrypt entry payloads.
  final ErasableByteArray masterKey;

  bool _dirty = false;
  bool _closed = false;

  StorageTransaction({
    required StorageData data,
    required this.masterKey,
  })  : _data = data,
        baseData = data;

  StorageData get data => _data;

  bool get isDirty => _dirty;

  bool get isClosed => _closed;

  @override
  bool get isErased => masterKey.isErased;

  Future<Map<EntryId, EntryMeta>> readAllMeta() async {
    _ensureActive();

    final result = <EntryId, EntryMeta>{};
    for (final e in _data.entries) {
      final decryptedMeta = await CryptographyUtils.decrypt(
        key: masterKey,
        data: e.encryptedMeta,
      );

      result[e.id] = EntryMeta.fromErasable(erasable: decryptedMeta);
    }

    return result;
  }

  Future<EntryValue> readValue(EntryId id) async {
    _ensureActive();

    final entry = _data.entries.firstWhereOrNull((e) => e.id == id);
    if (entry == null || entry.id.isEmpty) {
      throw StorageException.entryNotFound();
    }

    final decryptedValue = await CryptographyUtils.decrypt(
      key: masterKey,
      data: entry.encryptedValue,
    );

    return EntryValue.fromErasable(erasable: decryptedValue);
  }

  Future<EntryId> addEntry(EntryAddInput input) async {
    _ensureActive();

    final idString = input.id?.value ?? _generateEntryId();
    final entryId = EntryId(idString);

    if (input.id != null) {
      _validateNoDuplicateIds([entryId, ..._data.entries.map((e) => e.id)]);
    }

    final encryptedMeta = await CryptographyUtils.encrypt(
      key: masterKey,
      data: input.meta,
    );
    final encryptedValue = await CryptographyUtils.encrypt(
      key: masterKey,
      data: input.value,
    );

    final newEntry = StorageEntry(
      id: entryId,
      encryptedMeta: encryptedMeta,
      encryptedValue: encryptedValue,
    );

    _data = _data.copyWith(entries: [..._data.entries, newEntry]);
    _dirty = true;

    return entryId;
  }

  Future<void> updateEntry(EntryUpdateInput input) async {
    _ensureActive();

    if (input.meta == null && input.value == null) {
      throw StorageException.other('Either entryMeta or entryValue must be provided');
    }

    final index = _data.entries.indexWhere((e) => e.id == input.id);
    if (index < 0) {
      throw StorageException.entryNotFound();
    }

    final entry = _data.entries[index];

    Uint8List? encryptedMeta;
    Uint8List? encryptedValue;

    if (input.meta != null) {
      encryptedMeta = await CryptographyUtils.encrypt(
        key: masterKey,
        data: input.meta!,
      );
    }
    if (input.value != null) {
      encryptedValue = await CryptographyUtils.encrypt(
        key: masterKey,
        data: input.value!,
      );
    }

    final updatedEntry = entry.copyWith(
      encryptedMeta: encryptedMeta,
      encryptedValue: encryptedValue,
    );
    // Keep the entry in place so an update does not reorder the file.
    final newEntries = [..._data.entries];
    newEntries[index] = updatedEntry;

    _data = _data.copyWith(entries: newEntries);
    _dirty = true;
  }

  Future<void> deleteEntry(EntryId id) async {
    _ensureActive();

    final originalLength = _data.entries.length;
    final newEntries = _data.entries.where((e) => e.id != id).toList();

    if (newEntries.length == originalLength) {
      throw StorageException.entryNotFound();
    }

    _data = _data.copyWith(entries: newEntries);
    _dirty = true;
  }

  void close() {
    _closed = true;
  }

  Future<void> updateLockTimeout(int lockTimeout) async {
    _ensureActive();

    if (lockTimeout <= 0) {
      throw StorageException.other('Lock timeout must be greater than 0');
    }

    _data = _data.copyWith(lockTimeout: lockTimeout);
    _dirty = true;
  }

  /// Adds a wrap for the master key, or replaces the wrap of the same origin.
  Future<void> addOrReplaceWrap({required CipherFunc newWrapFunc}) async {
    _ensureActive();

    final encryptedMasterKey = await newWrapFunc.encrypt(masterKey);
    final newWrap = KeyWrap(
      origin: newWrapFunc.origin,
      encryptedKey: encryptedMasterKey,
    );

    final currentWraps = [..._data.masterKey.wraps];
    final index = currentWraps.indexWhere((w) => w.origin == newWrap.origin);

    if (index >= 0) {
      currentWraps[index] = newWrap;
    } else {
      currentWraps.add(newWrap);
    }

    Uint8List? newSalt;
    if (newWrapFunc is PasswordCipherFunc) {
      newSalt = newWrapFunc.salt;
    }

    _data = _data.copyWith(
      masterKey: WrappedKey(wraps: currentWraps),
      salt: newSalt,
    );
    _dirty = true;
  }

  /// Removes the wrap of [originToDelete]; throws if it is the last one.
  Future<void> deleteWrap({required Origin originToDelete}) async {
    _ensureActive();

    final currentWraps = _data.masterKey.wraps;
    final updatedWraps = currentWraps.where((w) => w.origin != originToDelete).toList();

    if (updatedWraps.length == currentWraps.length) {
      throw StorageException.other('The wrap to delete was not found');
    }

    if (updatedWraps.isEmpty) {
      throw StorageException.other('The wraps list would be empty after deletion, not allowed');
    }

    _data = _data.copyWith(masterKey: WrappedKey(wraps: updatedWraps));
    _dirty = true;
  }

  @override
  void erase() => masterKey.erase();

  void _validateNoDuplicateIds(List<EntryId> ids) {
    final seen = <String>{};
    for (final id in ids) {
      if (!seen.add(id.value)) {
        throw StorageException.duplicateEntry();
      }
    }
  }

  String _generateEntryId() => CryptographyUtils.generateUuid();

  void _ensureActive() {
    if (_closed) {
      throw StateError('Transaction is already closed');
    }
  }
}
