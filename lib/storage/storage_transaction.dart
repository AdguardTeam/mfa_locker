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

/// In-memory working copy of the storage for one transaction; the file is
/// written once by the storage on close, and erasing the key makes it unusable.
class StorageTransaction implements Erasable {
  StorageData _updatedData;

  /// Raw file content at open, compared against the file on close (compare-and-swap).
  final String baseContent;

  /// The unwrapped master key; erasing it makes the working copy unusable.
  final ErasableByteArray masterKey;

  bool _dirty = false;

  StorageTransaction({
    required StorageData data,
    required this.baseContent,
    required this.masterKey,
  }) : _updatedData = data;

  StorageData get updatedData => _updatedData;

  bool get isDirty => _dirty;

  @override
  bool get isErased => masterKey.isErased;

  Future<Map<EntryId, EntryMeta>> readAllMeta() async {
    _ensureActive();

    final result = <EntryId, EntryMeta>{};
    try {
      for (final e in _updatedData.entries) {
        final decryptedMeta = await CryptographyUtils.decrypt(
          key: masterKey,
          data: e.encryptedMeta,
        );

        result[e.id] = EntryMeta.fromErasable(erasable: decryptedMeta);
      }
    } catch (_) {
      // A mid-loop failure must not leave already decrypted metadata unerased.
      for (final meta in result.values) {
        meta.erase();
      }

      rethrow;
    }

    return result;
  }

  Future<EntryValue> readValue(EntryId id) async {
    _ensureActive();

    final entry = _updatedData.entries.firstWhereOrNull((e) => e.id == id);
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

    final entryId = input.id ?? EntryId.generate();

    _validateNoDuplicateIds([entryId, ..._updatedData.entries.map((e) => e.id)]);

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

    _updatedData = _updatedData.copyWith(entries: [..._updatedData.entries, newEntry]);
    _dirty = true;

    return entryId;
  }

  Future<void> updateEntry(EntryUpdateInput input) async {
    _ensureActive();

    if (input.meta == null && input.value == null) {
      throw StorageException.other('Either entryMeta or entryValue must be provided');
    }

    final index = _updatedData.entries.indexWhere((e) => e.id == input.id);
    if (index < 0) {
      throw StorageException.entryNotFound();
    }

    final entry = _updatedData.entries[index];

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
    final newEntries = [..._updatedData.entries];
    newEntries[index] = updatedEntry;

    _updatedData = _updatedData.copyWith(entries: newEntries);
    _dirty = true;
  }

  Future<void> deleteEntry(EntryId id) async {
    _ensureActive();

    final originalLength = _updatedData.entries.length;
    final newEntries = _updatedData.entries.where((e) => e.id != id).toList();

    if (newEntries.length == originalLength) {
      throw StorageException.entryNotFound();
    }

    _updatedData = _updatedData.copyWith(entries: newEntries);
    _dirty = true;
  }

  Future<void> updateLockTimeout(int lockTimeout) async {
    _ensureActive();

    if (lockTimeout <= 0) {
      throw StorageException.other('Lock timeout must be greater than 0');
    }

    _updatedData = _updatedData.copyWith(lockTimeout: lockTimeout);
    _dirty = true;
  }

  Future<void> addOrReplaceWrap({required CipherFunc newWrapFunc}) async {
    _ensureActive();

    final encryptedMasterKey = await newWrapFunc.encrypt(masterKey);
    final newWrap = KeyWrap(
      origin: newWrapFunc.origin,
      encryptedKey: encryptedMasterKey,
    );

    final currentWraps = [..._updatedData.masterKey.wraps];
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

    _updatedData = _updatedData.copyWith(
      masterKey: WrappedKey(wraps: currentWraps),
      salt: newSalt,
    );
    _dirty = true;
  }

  /// Throws if it is the last wrap.
  Future<void> deleteWrap({required Origin originToDelete}) async {
    _ensureActive();

    final currentWraps = _updatedData.masterKey.wraps;
    final updatedWraps = currentWraps.where((w) => w.origin != originToDelete).toList();

    if (updatedWraps.length == currentWraps.length) {
      throw StorageException.other('The wrap to delete was not found');
    }

    if (updatedWraps.isEmpty) {
      throw StorageException.other('The wraps list would be empty after deletion, not allowed');
    }

    _updatedData = _updatedData.copyWith(masterKey: WrappedKey(wraps: updatedWraps));
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

  void _ensureActive() {
    if (isErased) {
      throw StorageException.other('Transaction is erased');
    }
  }
}
