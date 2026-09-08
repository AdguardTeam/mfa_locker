import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:locker/erasable/erasable_byte_array.dart';
import 'package:locker/security/models/cipher_func.dart';
import 'package:locker/security/models/password_cipher_func.dart';
import 'package:locker/storage/encrypted_storage.dart';
import 'package:locker/storage/hmac_storage_mixin.dart';
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
import 'package:locker/storage/storage_change_set.dart';
import 'package:locker/utils/cryptography_utils.dart';
import 'package:locker/utils/sync.dart';
import 'package:path/path.dart' as p;

class EncryptedStorageImpl with HmacStorageMixin implements EncryptedStorage {
  final File file;

  EncryptedStorageImpl({
    required this.file,
  });

  final _sync = Sync();

  @override
  Future<bool> get isInitialized => _sync(() async {
        try {
          final isFileExists = await file.exists();
          if (!isFileExists) {
            return false;
          }

          final fileLength = await file.length();
          if (fileLength == 0) {
            await file.delete();
            return false;
          }

          final content = await file.readAsString();
          StorageData.fromJson(jsonDecode(content) as Map<String, Object?>);
        } catch (e) {
          return false;
        }

        return true;
      });

  @override
  Future<bool> get isBiometricEnabled => _sync(() async {
        try {
          final data = await _loadData();
          return data.masterKey.wraps.any((w) => w.origin == Origin.bio);
        } on StorageException catch (e) {
          // Storage not initialized is expected - biometric is simply not enabled yet
          if (e.type == StorageExceptionType.notInitialized) {
            return false;
          }
          rethrow;
        }
      });

  @override
  Future<Uint8List> get salt => _sync(() async {
        final data = await _loadData();

        return data.salt;
      });

  @override
  Future<int> get lockTimeout => _sync(() async {
        final data = await _loadData();

        return data.lockTimeout;
      });

  @override
  Future<void> init({
    required PasswordCipherFunc passwordCipherFunc,
    required List<EntryAddInput> initialEntries,
    required int lockTimeout,
  }) =>
      _sync(() async {
        if (await isInitialized) {
          throw StorageException.alreadyInitialized();
        }

        if (lockTimeout <= 0) {
          throw StorageException.other('Lock timeout must be greater than 0');
        }

        final explicitIds = initialEntries.map((e) => e.id).whereType<EntryId>().toList();
        _validateNoDuplicateIds(explicitIds);

        final masterKey = await CryptographyUtils.generateAESKey();

        try {
          final encryptedMasterKey = await passwordCipherFunc.encrypt(masterKey);
          final wrappedMasterKey = WrappedKey(
            wraps: [
              KeyWrap(
                origin: passwordCipherFunc.origin,
                encryptedKey: encryptedMasterKey,
              ),
            ],
          );

          final storageEntries = <StorageEntry>[];
          for (final entry in initialEntries) {
            final idString = entry.id?.value ?? _generateEntryId();
            final encryptedMeta = await CryptographyUtils.encrypt(
              key: masterKey,
              data: entry.meta,
            );
            final encryptedValue = await CryptographyUtils.encrypt(
              key: masterKey,
              data: entry.value,
            );
            storageEntries.add(
              StorageEntry(
                id: EntryId(idString),
                encryptedMeta: encryptedMeta,
                encryptedValue: encryptedValue,
              ),
            );
          }

          final storageData = StorageData(
            entries: storageEntries,
            masterKey: wrappedMasterKey,
            salt: passwordCipherFunc.salt,
            lockTimeout: lockTimeout,
          );

          await _signDataWithHmacAndSave(storageData, masterKey);
        } finally {
          masterKey.erase();
        }
      });

  @override
  Future<StorageChangeSet> openChangeSet({required CipherFunc cipherFunc}) => _sync(() async {
        final data = await _loadData();
        final masterKey = await _getDecryptedMasterKey(data: data, cipherFunc: cipherFunc);

        return StorageChangeSet(data: data, masterKey: masterKey);
      });

  @override
  Future<void> commitChangeSet(StorageChangeSet changeSet) => _sync(
        () => _persistChangeSet(changeSet, checkConflict: true),
      );

  /// Runs a single entry [operation] over an ephemeral change set and persists
  /// it atomically. The change set (and its key) is always erased.
  Future<T> _withChangeSet<T>({
    required CipherFunc cipherFunc,
    required Future<T> Function(StorageChangeSet changeSet) operation,
  }) async {
    final changeSet = await openChangeSet(cipherFunc: cipherFunc);
    try {
      final result = await operation(changeSet);
      await _persistChangeSet(changeSet, checkConflict: false);

      return result;
    } finally {
      changeSet.erase();
    }
  }

  /// Persists [changeSet] if it has any changes.
  ///
  /// When [checkConflict] is true performs a compare-and-swap against the file
  /// (used for long-lived transactions); one-shot operations skip it because
  /// they run under the storage lock, so the file cannot have changed.
  Future<void> _persistChangeSet(
    StorageChangeSet changeSet, {
    required bool checkConflict,
  }) async {
    if (changeSet.isCommitted) {
      return;
    }
    if (changeSet.isErased) {
      throw StateError('Change set is erased');
    }

    if (changeSet.isDirty) {
      if (checkConflict) {
        final current = await _loadData();
        if (!_storageDataEquals(current, changeSet.baseData)) {
          throw StorageException.conflict();
        }
      }

      await _signDataWithHmacAndSave(changeSet.data, changeSet.masterKey);
    }

    changeSet.markCommitted();
  }

  @override
  Future<void> addOrReplaceWrap({
    required CipherFunc newWrapFunc,
    required CipherFunc existingWrapFunc,
  }) =>
      _sync(() async {
        ErasableByteArray? masterKey;

        try {
          final data = await _loadData();
          final wrappedKey = data.masterKey;

          masterKey = await _getDecryptedMasterKey(data: data, cipherFunc: existingWrapFunc);

          final encryptedMasterKey = await newWrapFunc.encrypt(masterKey);
          final newWrap = KeyWrap(
            origin: newWrapFunc.origin,
            encryptedKey: encryptedMasterKey,
          );

          final currentWraps = [...wrappedKey.wraps];
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

          final updatedKey = WrappedKey(wraps: currentWraps);
          final newData = data.copyWith(masterKey: updatedKey, salt: newSalt);

          await _signDataWithHmacAndSave(newData, masterKey);
        } finally {
          masterKey?.erase();
        }
      });

  @override
  Future<void> deleteWrap({
    required Origin originToDelete,
    required CipherFunc cipherFunc,
  }) =>
      _sync(() async {
        ErasableByteArray? masterKey;
        try {
          final data = await _loadData();

          final currentWraps = data.masterKey.wraps;
          final updatedWraps = currentWraps.where((w) => w.origin != originToDelete).toList();

          if (updatedWraps.length == currentWraps.length) {
            throw StorageException.other('The wrap to delete was not found');
          }

          if (updatedWraps.isEmpty) {
            throw StorageException.other('The wraps list would be empty after deletion, not allowed');
          }

          final updatedWrappedKey = WrappedKey(wraps: updatedWraps);
          final newData = data.copyWith(masterKey: updatedWrappedKey);

          masterKey = await _getDecryptedMasterKey(data: data, cipherFunc: cipherFunc);
          await _signDataWithHmacAndSave(newData, masterKey);
        } finally {
          masterKey?.erase();
        }
      });

  @override
  Future<void> deleteEntry({
    required EntryId id,
    required CipherFunc cipherFunc,
  }) =>
      _sync(
        () => _withChangeSet(
          cipherFunc: cipherFunc,
          operation: (changeSet) => changeSet.deleteEntry(id),
        ),
      );

  @override
  Future<EntryId> addEntry({
    required EntryAddInput input,
    required CipherFunc cipherFunc,
  }) =>
      _sync(
        () => _withChangeSet(
          cipherFunc: cipherFunc,
          operation: (changeSet) => changeSet.addEntry(input),
        ),
      );

  @override
  Future<void> updateEntry({
    required EntryUpdateInput input,
    required CipherFunc cipherFunc,
  }) =>
      _sync(
        () => _withChangeSet(
          cipherFunc: cipherFunc,
          operation: (changeSet) => changeSet.updateEntry(input),
        ),
      );

  @override
  Future<Map<EntryId, EntryMeta>> readAllMeta({required CipherFunc cipherFunc}) => _sync(
        () => _withChangeSet(
          cipherFunc: cipherFunc,
          operation: (changeSet) => changeSet.readAllMeta(),
        ),
      );

  @override
  Future<EntryValue> readValue({
    required EntryId id,
    required CipherFunc cipherFunc,
  }) =>
      _sync(
        () => _withChangeSet(
          cipherFunc: cipherFunc,
          operation: (changeSet) => changeSet.readValue(id),
        ),
      );

  @override
  Future<void> updateLockTimeout({
    required int lockTimeout,
    required CipherFunc cipherFunc,
  }) =>
      _sync(() async {
        if (lockTimeout <= 0) {
          throw StorageException.other('Lock timeout must be greater than 0');
        }

        ErasableByteArray? masterKey;

        try {
          final data = await _loadData();
          masterKey = await _getDecryptedMasterKey(data: data, cipherFunc: cipherFunc);

          final newData = data.copyWith(lockTimeout: lockTimeout);
          await _signDataWithHmacAndSave(newData, masterKey);
        } finally {
          masterKey?.erase();
        }
      });

  @override
  Future<void> erase() => _sync(() async {
        final isFileExists = await file.exists();

        if (!isFileExists) {
          return;
        }

        await file.delete();
      });

  /// Loads the file content and parses a StorageData
  Future<StorageData> _loadData() async {
    final exists = await file.exists();
    if (!exists) {
      throw StorageException.notInitialized();
    }

    try {
      final content = await file.readAsString();
      return StorageData.fromJson(jsonDecode(content) as Map<String, Object?>);
    } catch (_) {
      throw StorageException.invalidStorage();
    }
  }

  /// Retrieves the master key from one of the existing wraps, verifying HMAC.
  Future<ErasableByteArray> _getDecryptedMasterKey({
    required StorageData data,
    required CipherFunc cipherFunc,
  }) async {
    ErasableByteArray? decryptedMasterKey;
    ErasableByteArray? decryptedHmacKey;

    try {
      final wrappedKey = data.masterKey;
      final encryptedHmacKey = data.hmacKey;

      if (encryptedHmacKey == null) {
        throw StorageException.invalidStorage(message: 'HMAC key is null!');
      }

      final wrapForOrigin = wrappedKey.getWrapForOrigin(cipherFunc.origin);

      decryptedMasterKey = await cipherFunc.decrypt(
        wrapForOrigin.encryptedKey,
      );

      decryptedHmacKey = await CryptographyUtils.decrypt(
        key: decryptedMasterKey,
        data: encryptedHmacKey,
      );

      final isHmacValid = await verifySignature(data, decryptedHmacKey);

      if (!isHmacValid) {
        throw StorageException.invalidStorage(message: 'HMAC is invalid!');
      }

      return decryptedMasterKey;
    } catch (_) {
      decryptedMasterKey?.erase();

      rethrow;
    } finally {
      decryptedHmacKey?.erase();
    }
  }

  /// Saves [data] to the file, generating new hmacKey/hmacSignature
  Future<void> _signDataWithHmacAndSave(StorageData data, ErasableByteArray masterKey) async {
    final signedData = await signDataWithHmac(data: data, masterKey: masterKey);

    await _writeDataToFile(signedData);
  }

  /// Compares two snapshots by their canonical JSON form.
  bool _storageDataEquals(StorageData a, StorageData b) => jsonEncode(a.toJson()) == jsonEncode(b.toJson());

  // TODO(m.semenov): investigate if this will work on all operating systems. ChatGPT told this could be a problem on Windows

  /// Write to a temp file, then rename
  Future<void> _writeDataToFile(StorageData data) async {
    final jsonStr = jsonEncode(data.toJson());

    final tmpSuffix = CryptographyUtils.generateUuid();
    final tmpFile = File(p.join(file.parent.path, 'stor_$tmpSuffix.tmp'));
    await tmpFile.writeAsString(jsonStr, flush: true);

    await _restrictFilePermissionsIfSupported(tmpFile);

    if (await file.exists()) {
      await file.delete();
    }

    await tmpFile.rename(file.path);

    await _restrictFilePermissionsIfSupported(file);
  }

  Future<void> _restrictFilePermissionsIfSupported(File target) async {
    try {
      if (Platform.isMacOS) {
        await Process.run('chmod', ['600', target.path]);
      }
    } catch (_) {
      // Suppress: chmod is best-effort; failure does not affect storage integrity
    }
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
