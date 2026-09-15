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

/// In-memory working copy of the storage for one open transaction. Mutations
/// touch memory only; the file is written once by the storage on commit.
class StorageChangeSet implements Erasable {
  StorageData _data;

  /// Snapshot of the storage at the moment the change set was opened.
  final StorageData baseData;

  /// The unwrapped master key used to (de)encrypt entry payloads.
  final ErasableByteArray masterKey;

  bool _dirty = false;
  bool _committed = false;
  bool _erased = false;

  StorageChangeSet({
    required StorageData data,
    required this.masterKey,
  })  : _data = data,
        baseData = data;

  /// The current (possibly mutated) storage data.
  StorageData get data => _data;

  /// Whether any entry operation has been applied since opening.
  bool get isDirty => _dirty;

  /// Whether the change set has been committed (persisted).
  bool get isCommitted => _committed;

  @override
  bool get isErased => _erased || masterKey.isErased;

  void _ensureActive() {
    if (_committed) {
      throw StateError('Change set is already committed');
    }
    if (_erased) {
      throw StateError('Change set is erased');
    }
  }

  /// Decrypts and returns all entry metadata.
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

  /// Decrypts and returns the value of the entry identified by [id].
  ///
  /// Throws [StorageException.entryNotFound] if the entry does not exist.
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

  /// Adds a new entry and returns its id.
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

  /// Updates an existing entry.
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

  /// Deletes the entry identified by [id].
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

  /// Marks the change set as committed (persisted).
  void markCommitted() {
    _committed = true;
  }

  /// Updates the auto-lock timeout in milliseconds.
  Future<void> updateLockTimeout(int lockTimeout) async {
    _ensureActive();

    if (lockTimeout <= 0) {
      throw StorageException.other('Lock timeout must be greater than 0');
    }

    _data = _data.copyWith(lockTimeout: lockTimeout);
    _dirty = true;
  }

  /// Adds a wrap for the master key or replaces the wrap with the same origin.
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

  /// Removes the wrap of [originToDelete].
  ///
  /// Throws [StorageException] if there is no such wrap or if it is the last
  /// remaining one.
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
  void erase() {
    if (_erased) {
      return;
    }

    _erased = true;
    masterKey.erase();
  }

  /// Validates that [ids] contains no duplicates.
  ///
  /// Throws [StorageException.duplicateEntry] if a duplicate is found.
  void _validateNoDuplicateIds(List<EntryId> ids) {
    final seen = <String>{};
    for (final id in ids) {
      if (!seen.add(id.value)) {
        throw StorageException.duplicateEntry();
      }
    }
  }

  String _generateEntryId() => CryptographyUtils.generateUuid();
}
