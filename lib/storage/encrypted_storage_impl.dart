import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:adguard_logger/adguard_logger.dart';
import 'package:collection/collection.dart';
import 'package:locker/erasable/erasable_byte_array.dart';
import 'package:locker/security/models/cipher_func.dart';
import 'package:locker/security/models/exceptions/biometric_exception.dart';
import 'package:locker/security/models/password_cipher_func.dart';
import 'package:locker/storage/encrypted_storage.dart';
import 'package:locker/storage/hmac_storage_mixin.dart';
import 'package:locker/storage/models/data/key_wrap.dart';
import 'package:locker/storage/models/data/origin.dart';
import 'package:locker/storage/models/data/storage_data.dart';
import 'package:locker/storage/models/data/storage_entry.dart';
import 'package:locker/storage/models/data/wrapped_key.dart';
import 'package:locker/storage/models/domain/entry_id.dart';
import 'package:locker/storage/models/domain/entry_meta.dart';
import 'package:locker/storage/models/domain/entry_value.dart';
import 'package:locker/storage/models/exceptions/decrypt_failed_exception.dart';
import 'package:locker/storage/models/exceptions/storage_exception.dart';
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

  // TODO: (d.seloustev) A test needs to be added
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
          logger.logError('EncryptedStorageImpl: Failed get isBiometricEnabled', error: e);

          return false;
        } catch (e, st) {
          logger.logError('EncryptedStorageImpl: Failed get isBiometricEnabled', error: e, stackTrace: st);

          return false;
        }
      });

  @override
  Future<Uint8List?> get salt => _sync(() async {
        try {
          final data = await _loadData();

          return data.salt;
        } catch (e, st) {
          logger.logError('EncryptedStorageImpl: Failed to load salt', error: e, stackTrace: st);

          return null;
        }
      });

  @override
  Future<int?> get lockTimeout => _sync(() async {
        try {
          final data = await _loadData();

          return data.lockTimeout;
        } catch (e, st) {
          logger.logError('EncryptedStorageImpl: Failed to load lockTimeout', error: e, stackTrace: st);

          return null;
        }
      });

  @override
  Future<void> init({
    required PasswordCipherFunc passwordCipherFunc,
    required EntryMeta initialEntryMeta,
    required EntryValue initialEntryValue,
    required int lockTimeout,
  }) =>
      _sync(() async {
        if (await isInitialized) {
          throw StorageException.alreadyInitialized();
        }

        if (lockTimeout <= 0) {
          throw StorageException.other('Lock timeout must be greater than 0');
        }

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

          final idString = _generateEntryId();
          final encryptedEntryMeta = await CryptographyUtils.encrypt(
            key: masterKey,
            data: initialEntryMeta,
          );
          final encryptedEntryValue = await CryptographyUtils.encrypt(
            key: masterKey,
            data: initialEntryValue,
          );

          final storageEntry = StorageEntry(
            id: EntryId(idString),
            encryptedMeta: encryptedEntryMeta,
            encryptedValue: encryptedEntryValue,
          );

          final storageData = StorageData(
            entries: [storageEntry],
            masterKey: wrappedMasterKey,
            salt: passwordCipherFunc.salt,
            lockTimeout: lockTimeout,
          );

          await _signDataWithHmacAndSave(storageData, masterKey);
        } catch (e, st) {
          logger.logError('EncryptedStorageImpl: Failed to init', error: e, stackTrace: st);
          rethrow;
        } finally {
          masterKey.erase();
        }
      });

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
        } on DecryptFailedException catch (_) {
          rethrow;
        } on BiometricException {
          rethrow;
        } catch (e, st) {
          logger.logError('EncryptedStorageImpl: Failed to add wrap', error: e, stackTrace: st);
          rethrow;
        } finally {
          masterKey?.erase();
        }
      });

  @override
  Future<bool> deleteWrap({
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

          return true;
        } on DecryptFailedException catch (_) {
          rethrow;
        } on BiometricException {
          rethrow;
        } catch (e, st) {
          logger.logError('EncryptedStorageImpl: Failed to delete wrap', error: e, stackTrace: st);

          return false;
        } finally {
          masterKey?.erase();
        }
      });

  @override
  Future<bool> deleteEntry({
    required EntryId id,
    required CipherFunc cipherFunc,
  }) =>
      _sync(() async {
        ErasableByteArray? masterKey;

        try {
          final data = await _loadData();

          final originalLength = data.entries.length;
          final newEntries = data.entries.where((e) => e.id != id).toList();

          if (newEntries.length == originalLength) {
            throw StorageException.entryNotFound(entryId: id.value);
          }

          final newData = data.copyWith(entries: newEntries);

          masterKey = await _getDecryptedMasterKey(data: data, cipherFunc: cipherFunc);
          await _signDataWithHmacAndSave(newData, masterKey);

          return true;
        } on DecryptFailedException catch (_) {
          rethrow;
        } on BiometricException {
          rethrow;
        } catch (e, st) {
          logger.logError('EncryptedStorageImpl: Failed to delete entry', error: e, stackTrace: st);

          return false;
        } finally {
          masterKey?.erase();
        }
      });

  @override
  Future<EntryId> addEntry({
    required EntryMeta entryMeta,
    required EntryValue entryValue,
    required CipherFunc cipherFunc,
  }) =>
      _sync(() async {
        ErasableByteArray? masterKey;
        try {
          final data = await _loadData();
          masterKey = await _getDecryptedMasterKey(data: data, cipherFunc: cipherFunc);

          final idString = _generateEntryId();
          final entryId = EntryId(idString);

          final encryptedMeta = await CryptographyUtils.encrypt(
            key: masterKey,
            data: entryMeta,
          );

          final encryptedValue = await CryptographyUtils.encrypt(
            key: masterKey,
            data: entryValue,
          );

          final newEntry = StorageEntry(
            id: entryId,
            encryptedMeta: encryptedMeta,
            encryptedValue: encryptedValue,
          );

          final newEntries = [...data.entries, newEntry];
          final newData = data.copyWith(entries: newEntries);

          await _signDataWithHmacAndSave(newData, masterKey);

          return entryId;
        } on DecryptFailedException catch (_) {
          rethrow;
        } on BiometricException {
          rethrow;
        } catch (e, st) {
          logger.logError('EncryptedStorageImpl: Failed to add entry', error: e, stackTrace: st);

          rethrow;
        } finally {
          masterKey?.erase();
        }
      });

  @override
  Future<void> updateEntry({
    required EntryId id,
    required CipherFunc cipherFunc,
    EntryMeta? entryMeta,
    EntryValue? entryValue,
  }) =>
      _sync(() async {
        ErasableByteArray? masterKey;

        try {
          if (entryMeta == null && entryValue == null) {
            throw StorageException.other('Either entryMeta or entryValue must be provided');
          }

          final data = await _loadData();
          final entry = data.entries.firstWhereOrNull((e) => e.id == id);

          if (entry == null) {
            throw StorageException.entryNotFound(entryId: id.value);
          }

          masterKey = await _getDecryptedMasterKey(data: data, cipherFunc: cipherFunc);

          Uint8List? encryptedMeta;
          Uint8List? encryptedValue;

          if (entryMeta != null) {
            encryptedMeta = await CryptographyUtils.encrypt(
              key: masterKey,
              data: entryMeta,
            );
          }

          if (entryValue != null) {
            encryptedValue = await CryptographyUtils.encrypt(
              key: masterKey,
              data: entryValue,
            );
          }

          final updatedEntry = entry.copyWith(
            encryptedMeta: encryptedMeta,
            encryptedValue: encryptedValue,
          );

          final entriesWithoutUpdated = data.entries.where((e) => e.id != id).toList();
          final newEntries = [...entriesWithoutUpdated, updatedEntry];
          final newData = data.copyWith(entries: newEntries);

          await _signDataWithHmacAndSave(newData, masterKey);
        } on DecryptFailedException catch (_) {
          rethrow;
        } on BiometricException {
          rethrow;
        } catch (e, st) {
          logger.logError('EncryptedStorageImpl: Failed to update entry', error: e, stackTrace: st);

          rethrow;
        } finally {
          masterKey?.erase();
        }
      });

  @override
  Future<Map<EntryId, EntryMeta>> readAllMeta({required CipherFunc cipherFunc}) => _sync(() async {
        ErasableByteArray? masterKey;

        try {
          final data = await _loadData();
          masterKey = await _getDecryptedMasterKey(data: data, cipherFunc: cipherFunc);

          final result = <EntryId, EntryMeta>{};

          for (final e in data.entries) {
            final decryptedMeta = await CryptographyUtils.decrypt(
              key: masterKey,
              data: e.encryptedMeta,
            );

            result[e.id] = EntryMeta.fromErasable(erasable: decryptedMeta);
          }

          return result;
        } on DecryptFailedException catch (_) {
          rethrow;
        } on BiometricException {
          rethrow;
        } catch (e, st) {
          logger.logError('EncryptedStorageImpl: Failed to read all meta', error: e, stackTrace: st);

          rethrow;
        } finally {
          masterKey?.erase();
        }
      });

  @override
  Future<EntryValue> readValue({
    required EntryId id,
    required CipherFunc cipherFunc,
  }) =>
      _sync(() async {
        ErasableByteArray? masterKey;

        try {
          final data = await _loadData();
          final entry = data.entries.firstWhereOrNull(
            (e) => e.id == id,
          );

          if (entry == null || entry.id.isEmpty) {
            throw StorageException.entryNotFound(entryId: id.value);
          }

          masterKey = await _getDecryptedMasterKey(data: data, cipherFunc: cipherFunc);
          final decryptedValue = await CryptographyUtils.decrypt(
            key: masterKey,
            data: entry.encryptedValue,
          );

          return EntryValue.fromErasable(erasable: decryptedValue);
        } on DecryptFailedException catch (_) {
          rethrow;
        } on BiometricException {
          rethrow;
        } catch (e, st) {
          logger.logError('EncryptedStorageImpl: Failed to read value', error: e, stackTrace: st);

          rethrow;
        } finally {
          masterKey?.erase();
        }
      });

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
        } on DecryptFailedException catch (_) {
          rethrow;
        } catch (e, st) {
          logger.logError('EncryptedStorageImpl: Failed to update lock timeout', error: e, stackTrace: st);

          rethrow;
        } finally {
          masterKey?.erase();
        }
      });

  @override
  Future<bool> erase() => _sync(() async {
        final isFileExists = await file.exists();

        if (!isFileExists) {
          logger.logInfo('Storage file does not exist, erasing skipped');
          return true;
        }

        try {
          await file.delete();
        } catch (e, st) {
          logger.logError('EncryptedStorageImpl: Failed to erase storage', error: e, stackTrace: st);

          return false;
        }

        return true;
      });

  @override
  Future<void> printDebugInfo() => _sync(() async {
        final exists = await file.exists();
        logger.logInfo('Storage file exists: $exists');

        if (exists) {
          final stat = await file.stat();
          logger.logInfo('Storage file size: ${stat.size} bytes');
          logger.logInfo('Storage last modified: ${stat.modified}');
        }
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
    } catch (e, st) {
      logger.logError('EncryptedStorageImpl: Failed parse storage data', error: e, stackTrace: st);

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
    } catch (e, st) {
      decryptedMasterKey?.erase();
      logger.logError('EncryptedStorageImpl: Failed to decrypt master key', error: e, stackTrace: st);

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
    } catch (e, st) {
      logger.logInfo(
        'EncryptedStorageImpl: Failed to restrict file permissions',
        error: e,
        stackTrace: st,
      );
    }
  }

  String _generateEntryId() => CryptographyUtils.generateUuid();
}
