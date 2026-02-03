import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:adguard_logger/adguard_logger.dart';
import 'package:locker/erasable/erasable.dart';
import 'package:locker/locker/locker.dart';
import 'package:locker/locker/models/biometric_state.dart';
import 'package:locker/security/models/bio_cipher_func.dart';
import 'package:locker/security/models/biometric_config.dart';
import 'package:locker/security/models/cipher_func.dart';
import 'package:locker/security/models/password_cipher_func.dart';
import 'package:locker/security/secure_mnemonic_provider.dart';
import 'package:locker/storage/encrypted_storage.dart';
import 'package:locker/storage/encrypted_storage_impl.dart';
import 'package:locker/storage/models/data/origin.dart';
import 'package:locker/storage/models/domain/entry_id.dart';
import 'package:locker/storage/models/domain/entry_meta.dart';
import 'package:locker/storage/models/domain/entry_value.dart';
import 'package:locker/utils/sync.dart';
import 'package:meta/meta.dart';
import 'package:rxdart/rxdart.dart';
import 'package:secure_mnemonic/data/biometric_status.dart';
import 'package:secure_mnemonic/data/tpm_status.dart';

class MFALocker implements Locker {
  final EncryptedStorage _storage;

  final BehaviorSubject<LockerState> _stateController = BehaviorSubject<LockerState>.seeded(LockerState.locked);

  MFALocker({
    required File file,
    @visibleForTesting EncryptedStorage? storage,
  }) : _storage = storage ?? EncryptedStorageImpl(file: file);

  Map<EntryId, EntryMeta> _metaCache = {};

  final _sync = Sync();

  SecureMnemonicProvider get _secureProvider => SecureMnemonicProviderImpl.instance;

  @override
  ValueStream<LockerState> get stateStream => _stateController.stream;

  @override
  Future<bool> get isStorageInitialized => _storage.isInitialized;

  @override
  Future<Uint8List?> get salt => _storage.salt;

  @override
  Future<Duration> get lockTimeout async {
    final storageLockTimeout = await _storage.lockTimeout;

    if (storageLockTimeout == null) {
      throw StateError('Lock timeout is not set in storage');
    }

    return Duration(milliseconds: storageLockTimeout);
  }

  @override
  // TODO: (d.seloustev) A test needs to be added
  Future<bool> get isBiometricEnabled => _storage.isBiometricEnabled;

  @override
  Map<EntryId, EntryMeta> get allMeta {
    if (_stateController.value != LockerState.unlocked) {
      throw StateError('Locker is not unlocked');
    }

    return UnmodifiableMapView(_metaCache);
  }

  @override
  Future<void> init({
    required PasswordCipherFunc passwordCipherFunc,
    required EntryMeta initialEntryMeta,
    required EntryValue initialEntryValue,
    required Duration lockTimeout,
  }) =>
      _sync(
        () => _executeWithCleanup(
          erasables: [passwordCipherFunc, initialEntryMeta, initialEntryValue],
          callback: () async {
            if (await isStorageInitialized) {
              throw StateError('Storage is already initialized');
            }

            await _storage.init(
              passwordCipherFunc: passwordCipherFunc,
              initialEntryMeta: initialEntryMeta,
              initialEntryValue: initialEntryValue,
              lockTimeout: lockTimeout.inMilliseconds,
            );

            await loadAllMetaIfLocked(passwordCipherFunc);
          },
        ),
      );

  @override
  Future<void> loadAllMeta(CipherFunc cipherFunc) => _sync(
        () => _executeWithCleanup(
          erasables: [cipherFunc],
          callback: () async => loadAllMetaIfLocked(cipherFunc),
        ),
      );

  @override
  void lock() {
    if (_stateController.value != LockerState.unlocked) {
      return;
    }

    _cleanupState();
    _stateController.add(LockerState.locked);
  }

  @override
  Future<EntryId> write({
    required EntryMeta entryMeta,
    required EntryValue entryValue,
    required CipherFunc cipherFunc,
  }) =>
      _sync(
        () => _executeWithCleanup<EntryId>(
          // dispose entryMeta only on error because it is cached
          erasables: [cipherFunc, entryValue],
          erasablesOnError: [entryMeta],
          callback: () async {
            await loadAllMetaIfLocked(cipherFunc);

            final id = await _storage.addEntry(
              entryMeta: entryMeta,
              entryValue: entryValue,
              cipherFunc: cipherFunc,
            );

            _metaCache[id]?.erase();
            _metaCache[id] = entryMeta;

            return id;
          },
        ),
      );

  @override
  Future<EntryValue> readValue({
    required EntryId id,
    required CipherFunc cipherFunc,
  }) =>
      _sync(
        () => _executeWithCleanup<EntryValue>(
          erasables: [cipherFunc],
          callback: () async {
            await loadAllMetaIfLocked(cipherFunc);

            return _storage.readValue(
              id: id,
              cipherFunc: cipherFunc,
            );
          },
        ),
      );

  @override
  Future<bool> delete({
    required EntryId id,
    required CipherFunc cipherFunc,
  }) =>
      _sync(
        () => _executeWithCleanup(
          erasables: [cipherFunc],
          callback: () async {
            await loadAllMetaIfLocked(cipherFunc);

            final isDeleted = await _storage.deleteEntry(
              id: id,
              cipherFunc: cipherFunc,
            );

            final removedMeta = _metaCache.remove(id);
            removedMeta?.erase();

            return isDeleted;
          },
        ),
      );

  @override
  Future<void> update({
    required EntryId id,
    required CipherFunc cipherFunc,
    EntryMeta? entryMeta,
    EntryValue? entryValue,
  }) =>
      _sync(
        () => _executeWithCleanup(
          erasables: [cipherFunc, if (entryValue != null) entryValue],
          erasablesOnError: [if (entryMeta != null) entryMeta],
          callback: () async {
            await loadAllMetaIfLocked(cipherFunc);

            await _storage.updateEntry(
              id: id,
              cipherFunc: cipherFunc,
              entryMeta: entryMeta,
              entryValue: entryValue,
            );

            if (entryMeta != null) {
              _metaCache[id]?.erase();
              _metaCache[id] = entryMeta;
            }
          },
        ),
      );

  @override
  Future<void> changePassword({
    required PasswordCipherFunc newCipherFunc,
    required PasswordCipherFunc oldCipherFunc,
  }) =>
      _sync(
        () => _executeWithCleanup(
          erasables: [newCipherFunc, oldCipherFunc],
          callback: () async {
            await loadAllMetaIfLocked(oldCipherFunc);
            await _storage.addOrReplaceWrap(newWrapFunc: newCipherFunc, existingWrapFunc: oldCipherFunc);
          },
        ),
      );

  @override
  Future<void> updateLockTimeout({
    required Duration lockTimeout,
    required CipherFunc cipherFunc,
  }) =>
      _sync(
        () => _executeWithCleanup(
          erasables: [cipherFunc],
          callback: () async {
            await loadAllMetaIfLocked(cipherFunc);
            await _storage.updateLockTimeout(
              lockTimeout: lockTimeout.inMilliseconds,
              cipherFunc: cipherFunc,
            );
          },
        ),
      );

  @override
  Future<void> eraseStorage() => _sync(() async {
        final isErased = await _storage.erase();

        if (!isErased) {
          throw StateError('Failed to erase storage');
        }

        _cleanupState();
        _stateController.add(LockerState.locked);
      });

  @override
  void dispose() {
    _cleanupState();
    _stateController.close();
  }

  @visibleForTesting
  Future<void> loadAllMetaIfLocked(CipherFunc cipherFunc) async {
    if (!(await isStorageInitialized)) {
      throw StateError('Storage is not initialized');
    }

    if (_stateController.value == LockerState.unlocked) {
      return;
    }

    // locker is locked, unlock it, cache keys and jump to unlocked state
    _metaCache = await _storage.readAllMeta(cipherFunc: cipherFunc);

    _stateController.add(LockerState.unlocked);
  }

  @visibleForTesting
  Future<void> enableBiometry({
    required BioCipherFunc bioCipherFunc,
    required PasswordCipherFunc passwordCipherFunc,
  }) =>
      _sync(
        () => _executeWithCleanup(
          erasables: [bioCipherFunc, passwordCipherFunc],
          callback: () async {
            await loadAllMetaIfLocked(passwordCipherFunc);
            await _storage.addOrReplaceWrap(newWrapFunc: bioCipherFunc, existingWrapFunc: passwordCipherFunc);
          },
        ),
      );

  @visibleForTesting
  Future<void> disableBiometry({
    required BioCipherFunc bioCipherFunc,
    required PasswordCipherFunc passwordCipherFunc,
  }) =>
      _sync(
        () => _executeWithCleanup(
          erasables: [bioCipherFunc, passwordCipherFunc],
          callback: () async {
            await loadAllMetaIfLocked(passwordCipherFunc);
            await _storage.deleteWrap(originToDelete: Origin.bio, cipherFunc: passwordCipherFunc);
          },
        ),
      );

  void _cleanupState() {
    for (final meta in _metaCache.values) {
      meta.erase();
    }

    _metaCache = {};
  }

  @override
  Future<void> configureSecureMnemonic(BiometricConfig config) => _secureProvider.configure(config);

  @override
  Future<BiometricState> determineBiometricState() async {
    final tpmStatus = await _secureProvider.getTPMStatus();
    // TPM checks first
    if (tpmStatus == TPMStatus.unsupported) {
      return BiometricState.tpmUnsupported;
    }
    if (tpmStatus == TPMStatus.tpmVersionUnsupported) {
      return BiometricState.tpmVersionIncompatible;
    }

    final biometryStatus = await _secureProvider.getBiometryStatus();

    // Then biometry checks
    if (biometryStatus == BiometricStatus.unsupported ||
        biometryStatus == BiometricStatus.deviceNotPresent ||
        biometryStatus == BiometricStatus.deviceBusy) {
      return BiometricState.hardwareUnavailable;
    }
    if (biometryStatus == BiometricStatus.notConfiguredForUser) {
      return BiometricState.notEnrolled;
    }
    if (biometryStatus == BiometricStatus.disabledByPolicy) {
      return BiometricState.disabledByPolicy;
    }
    if (biometryStatus == BiometricStatus.androidBiometricErrorSecurityUpdateRequired) {
      return BiometricState.securityUpdateRequired;
    }

    final isEnabledInSettings = await isBiometricEnabled;

    // Finally check app settings
    return isEnabledInSettings ? BiometricState.enabled : BiometricState.availableButDisabled;
  }

  /// Enable biometric authentication (requires password confirmation)
  /// This method handles key generation and storage update.
  @override
  Future<void> setupBiometry({
    required BioCipherFunc bioCipherFunc,
    required PasswordCipherFunc passwordCipherFunc,
  }) =>
      _executeWithCleanup(
        erasables: [bioCipherFunc, passwordCipherFunc],
        callback: () async {
          // Step 1: Check TPM status
          final tpmStatus = await _secureProvider.getTPMStatus();
          if (tpmStatus != TPMStatus.supported) {
            throw Exception('TPM not supported on this device');
          }

          // Step 2: Check biometry status
          final biometryStatus = await _secureProvider.getBiometryStatus();
          if (biometryStatus != BiometricStatus.supported) {
            throw Exception('Biometric authentication not available: $biometryStatus');
          }

          try {
            // Step 3: Defensive key management - delete before generate
            try {
              await _secureProvider.deleteKey(tag: bioCipherFunc.keyTag);
            } catch (e) {
              // Ignore errors - key might not exist yet
              logger.logInfo('Key might not exist yet: $e');
            }

            // Step 4: Generate new key
            await _secureProvider.generateKey(tag: bioCipherFunc.keyTag);

            // Step 5: Enable biometry in locker
            await enableBiometry(
              bioCipherFunc: bioCipherFunc,
              passwordCipherFunc: passwordCipherFunc,
            );
          } catch (error, stackTrace) {
            logger.logError(
              'MFALocker: Failed to enable biometric, cleaning up biometric key',
              error: error,
              stackTrace: stackTrace,
            );

            try {
              await _secureProvider.deleteKey(tag: bioCipherFunc.keyTag);
            } catch (cleanupError, cleanupStackTrace) {
              logger.logError(
                'MFALocker: Failed to cleanup biometric key after enableBiometric failure',
                error: cleanupError,
                stackTrace: cleanupStackTrace,
              );
            }

            rethrow;
          }
        },
      );

  /// Disable biometric authentication (requires password confirmation)
  /// This method handles storage update and key deletion.
  @override
  Future<void> teardownBiometry({
    required BioCipherFunc bioCipherFunc,
    required PasswordCipherFunc passwordCipherFunc,
  }) async {
    // Disable biometry in locker
    await disableBiometry(
      bioCipherFunc: bioCipherFunc,
      passwordCipherFunc: passwordCipherFunc,
    );

    // Delete biometric key from secure storage
    await _secureProvider.deleteKey(tag: bioCipherFunc.keyTag);
  }

  Future<T> _executeWithCleanup<T>({
    required List<Erasable> erasables,
    required Future<T> Function() callback,
    List<Erasable> erasablesOnError = const [],
  }) async {
    try {
      return await callback();
    } catch (e, st) {
      logger.logError('MFALocker: error occurred during operation with storage', error: e, stackTrace: st);
      for (final cipherFunc in erasablesOnError) {
        cipherFunc.erase();
      }

      rethrow;
    } finally {
      for (final cipherFunc in erasables) {
        cipherFunc.erase();
      }
    }
  }
}
