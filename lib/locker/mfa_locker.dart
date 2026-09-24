import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:biometric_cipher/data/biometric_status.dart';
import 'package:biometric_cipher/data/tpm_status.dart';
import 'package:locker/locker/locker.dart';
import 'package:locker/locker/locker_transaction.dart';
import 'package:locker/locker/mfa_locker_transaction.dart';
import 'package:locker/locker/models/biometric_state.dart';
import 'package:locker/locker/models/exceptions/locker_exception.dart';
import 'package:locker/locker/utils/mfa_locker_utils.dart';
import 'package:locker/locker/utils/operation_lane.dart';
import 'package:locker/locker/utils/transaction_zone.dart';
import 'package:locker/security/biometric_cipher_provider.dart';
import 'package:locker/security/models/bio_cipher_func.dart';
import 'package:locker/security/models/biometric_config.dart';
import 'package:locker/security/models/cipher_func.dart';
import 'package:locker/security/models/exceptions/biometric_exception.dart';
import 'package:locker/security/models/password_cipher_func.dart';
import 'package:locker/storage/encrypted_storage.dart';
import 'package:locker/storage/encrypted_storage_impl.dart';
import 'package:locker/storage/models/data/origin.dart';
import 'package:locker/storage/models/domain/entry_add_input.dart';
import 'package:locker/storage/models/domain/entry_id.dart';
import 'package:locker/storage/models/domain/entry_meta.dart';
import 'package:locker/storage/models/domain/entry_update_input.dart';
import 'package:locker/storage/models/domain/entry_value.dart';
import 'package:locker/storage/models/exceptions/storage_exception.dart';
import 'package:meta/meta.dart';
import 'package:rxdart/rxdart.dart';

class MFALocker implements Locker {
  final EncryptedStorage _storage;
  final BiometricCipherProvider _secureProvider;

  final BehaviorSubject<LockerState> _stateController = BehaviorSubject<LockerState>.seeded(LockerState.locked);

  MFALocker({
    required File file,
    @visibleForTesting EncryptedStorage? storage,
    @visibleForTesting BiometricCipherProvider? secureProvider,
  })  : _storage = storage ?? EncryptedStorageImpl(file: file),
        _secureProvider = secureProvider ?? BiometricCipherProviderImpl.instance;

  Map<EntryId, EntryMeta> _metaCache = {};

  final _lane = OperationLane();

  MfaLockerTransaction? _activeTransaction;

  @override
  ValueStream<LockerState> get stateStream => _stateController.stream;

  @override
  Future<bool> get isStorageInitialized => _storage.isInitialized;

  @override
  Future<Uint8List> get salt => _storage.salt;

  @override
  Future<Duration> get lockTimeout async => Duration(milliseconds: await _storage.lockTimeout);

  @override
  Future<bool> get isBiometricEnabled => _storage.isBiometricEnabled;

  @override
  Map<EntryId, EntryMeta> get allMeta {
    if (_stateController.isClosed || _stateController.value != LockerState.unlocked) {
      throw LockerException.notUnlocked();
    }

    return UnmodifiableMapView(_metaCache);
  }

  @override
  Future<void> init({
    required PasswordCipherFunc passwordCipherFunc,
    required List<EntryAddInput> initialEntries,
    required Duration lockTimeout,
  }) =>
      MFALockerUtils.eraseAfter(
        erasables: [passwordCipherFunc, ...initialEntries],
        callback: () {
          _ensureValidLockTimeout(lockTimeout);

          return _runOperation((epoch) async {
            if (await isStorageInitialized) {
              throw StorageException.alreadyInitialized();
            }

            await _storage.init(
              passwordCipherFunc: passwordCipherFunc,
              initialEntries: initialEntries,
              lockTimeout: lockTimeout.inMilliseconds,
            );

            // Never unlock a locker that was locked while the storage was written.
            _ensureFreshEpoch(epoch);

            await _unlockAndLoadMeta(passwordCipherFunc, epoch);
          });
        },
      );

  @override
  Future<void> loadAllMeta(CipherFunc cipherFunc) => MFALockerUtils.eraseAfter(
        erasables: [cipherFunc],
        callback: () => _runOperation((epoch) => _unlockAndLoadMeta(cipherFunc, epoch)),
      );

  @override
  Future<R> withTransaction<R>(
    CipherFunc cipherFunc,
    Future<R> Function(LockerTransaction txn) body,
  ) =>
      MFALockerUtils.eraseAfter(
        erasables: [cipherFunc],
        callback: () => _startTransaction(cipherFunc, body),
      );

  @override
  void lock() {
    _lane.invalidate(LockerException.locked());
    _abortActiveTransaction();

    if (_stateController.isClosed || _stateController.value != LockerState.unlocked) {
      return;
    }

    _cleanupMetaCache();
    _stateController.add(LockerState.locked);
  }

  @override
  Future<EntryId> write({
    required EntryAddInput input,
    required CipherFunc cipherFunc,
  }) =>
      MFALockerUtils.eraseAfter<EntryId>(
        erasables: [input.value, cipherFunc],
        erasablesOnError: [input.meta],
        callback: () => _startTransaction(cipherFunc, (txn) => txn.writeBuffered(input)),
      );

  @override
  Future<EntryValue> readValue({
    required EntryId id,
    required CipherFunc cipherFunc,
  }) =>
      withTransaction(cipherFunc, (txn) => txn.readValue(id));

  @override
  Future<void> delete({
    required EntryId id,
    required CipherFunc cipherFunc,
  }) =>
      withTransaction(cipherFunc, (txn) => txn.delete(id));

  @override
  Future<void> update({
    required EntryUpdateInput input,
    required CipherFunc cipherFunc,
  }) =>
      MFALockerUtils.eraseAfter(
        erasables: [if (input.value != null) input.value!, cipherFunc],
        erasablesOnError: [if (input.meta != null) input.meta!],
        callback: () => _startTransaction(cipherFunc, (txn) => txn.updateBuffered(input)),
      );

  @override
  Future<void> changePassword({
    required PasswordCipherFunc newCipherFunc,
    required CipherFunc existingCipherFunc,
  }) =>
      MFALockerUtils.eraseAfter(
        erasables: [newCipherFunc, existingCipherFunc],
        callback: () => _startTransaction(
          existingCipherFunc,
          (txn) => txn.addOrReplaceWrap(newWrapFunc: newCipherFunc),
        ),
      );

  @override
  Future<void> updateLockTimeout({
    required Duration lockTimeout,
    required CipherFunc cipherFunc,
  }) =>
      MFALockerUtils.eraseAfter(
        erasables: [cipherFunc],
        callback: () {
          _ensureNotInsideTransaction();
          _ensureValidLockTimeout(lockTimeout);

          return _startTransaction(cipherFunc, (txn) => txn.updateLockTimeout(lockTimeout));
        },
      );

  @override
  Future<void> eraseStorage() => _runOperation((_) async {
        _lane.invalidate(LockerException.locked());
        final epoch = _lane.generation;

        await _storage.erase();

        _cleanupMetaCache();
        if (_lane.isCurrent(epoch) && !_stateController.isClosed) {
          _stateController.add(LockerState.locked);
        }
      });

  @override
  void dispose() {
    _lane.invalidate(LockerException.locked());
    _abortActiveTransaction();
    _cleanupMetaCache();
    _stateController.close();
  }

  @override
  Future<void> configureBiometricCipher(BiometricConfig config) => _secureProvider.configure(config);

  @override
  Future<BiometricState> determineBiometricState({String? biometricKeyTag}) async {
    final tpmStatus = await _secureProvider.getTPMStatus();
    if (tpmStatus == TPMStatus.unsupported) {
      return BiometricState.tpmUnsupported;
    }
    if (tpmStatus == TPMStatus.tpmVersionUnsupported) {
      return BiometricState.tpmVersionIncompatible;
    }

    final biometryStatus = await _secureProvider.getBiometryStatus();

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

    if (!isEnabledInSettings) {
      return BiometricState.availableButDisabled;
    }

    // Proactive check: no biometric prompt is shown.
    if (biometricKeyTag != null) {
      final isValid = await _secureProvider.isKeyValid(tag: biometricKeyTag);
      if (!isValid) {
        return BiometricState.keyInvalidated;
      }
    }

    return BiometricState.enabled;
  }

  @override
  Future<void> setupBiometry({
    required BioCipherFunc bioCipherFunc,
    required PasswordCipherFunc passwordCipherFunc,
  }) {
    final epoch = _lane.generation;

    return MFALockerUtils.eraseAfter(
      erasables: [bioCipherFunc, passwordCipherFunc],
      callback: () async {
        _ensureNotInsideTransaction();

        final tpmStatus = await _secureProvider.getTPMStatus();
        if (tpmStatus != TPMStatus.supported) {
          throw const BiometricException(
            BiometricExceptionType.notAvailable,
            message: 'TPM not supported on this device',
          );
        }

        final biometryStatus = await _secureProvider.getBiometryStatus();
        if (biometryStatus != BiometricStatus.supported) {
          throw BiometricException(
            BiometricExceptionType.notAvailable,
            message: 'Biometric authentication not available: $biometryStatus',
          );
        }

        try {
          // Delete before generate: a stale key may exist.
          try {
            await _secureProvider.deleteKey(tag: bioCipherFunc.keyTag);
          } catch (_) {
            // The key might not exist yet.
          }

          await _secureProvider.generateKey(tag: bioCipherFunc.keyTag);

          // The locker could have been locked while the native key was created.
          _ensureFreshEpoch(epoch);

          await _startTransaction(
            passwordCipherFunc,
            (txn) => txn.addOrReplaceWrap(newWrapFunc: bioCipherFunc),
          );
        } catch (_) {
          // Best-effort cleanup; the original error is rethrown.
          try {
            await _secureProvider.deleteKey(tag: bioCipherFunc.keyTag);
          } catch (_) {
            // Best-effort.
          }

          rethrow;
        }
      },
    );
  }

  @override
  Future<void> teardownBiometry({
    required PasswordCipherFunc passwordCipherFunc,
    String? biometricKeyTag,
  }) =>
      MFALockerUtils.eraseAfter(
        erasables: [passwordCipherFunc],
        callback: () async {
          await _startTransaction(
            passwordCipherFunc,
            (txn) => txn.deleteWrap(originToDelete: Origin.bio),
          );

          if (biometricKeyTag != null) {
            try {
              await _secureProvider.deleteKey(tag: biometricKeyTag);
            } catch (_) {
              // Suppress: biometric key deletion is best-effort during teardown
            }
          }
        },
      );

  /// Unlocks by opening a transaction and discarding it; nothing is persisted.
  Future<void> _unlockAndLoadMeta(CipherFunc cipherFunc, int epoch) async {
    if (_stateController.value == LockerState.unlocked) {
      return;
    }

    final txn = await _openTransaction(cipherFunc, epoch);

    txn.abort();
  }

  Future<R> _startTransaction<R>(
    CipherFunc cipherFunc,
    Future<R> Function(MfaLockerTransaction txn) body,
  ) async {
    _ensureNotInsideTransaction();
    _ensureNotDisposed();

    final epoch = _lane.generation;

    await _lane.acquire();

    final MfaLockerTransaction txn;
    try {
      txn = await _openTransaction(cipherFunc, epoch);
      _activeTransaction = txn;
    } catch (_) {
      _lane.release();

      rethrow;
    }

    var succeeded = false;
    try {
      final result = await TransactionZone.run(this, () => body(txn));
      succeeded = true;

      return result;
    } finally {
      if (succeeded && txn.isClosed) {
        throw LockerException.locked();
      }

      await _finishTransaction(txn, commit: succeeded, epoch: epoch);
    }
  }

  /// Opens a transaction; the first open of a session unwraps the key, loads the
  /// metadata and unlocks, so every operation can rely on that invariant.
  Future<MfaLockerTransaction> _openTransaction(CipherFunc cipherFunc, int epoch) async {
    _ensureFreshEpoch(epoch);

    if (!(await isStorageInitialized)) {
      throw StorageException.notInitialized();
    }

    return MfaLockerTransaction.open(
      storage: _storage,
      cipherFunc: cipherFunc,
      initialize: (storageTransaction) async {
        if (_stateController.value != LockerState.unlocked) {
          final meta = await storageTransaction.readAllMeta();
          _ensureFreshEpoch(epoch, metas: meta.values);

          _metaCache = meta;
          _stateController.add(LockerState.unlocked);
        }

        // lock()/dispose() could have happened while the storage was opening.
        _ensureFreshEpoch(epoch);
      },
    );
  }

  Future<T> _runOperation<T>(Future<T> Function(int epoch) body) async {
    _ensureNotInsideTransaction();
    _ensureNotDisposed();

    final epoch = _lane.generation;

    await _lane.acquire();

    try {
      _ensureFreshEpoch(epoch);

      return await body(epoch);
    } finally {
      _lane.release();
    }
  }

  void _ensureNotInsideTransaction() {
    if (identical(TransactionZone.current, this)) {
      throw LockerException.insideTransaction();
    }
  }

  void _ensureNotDisposed() {
    if (_stateController.isClosed) {
      throw const LockerException(
        type: LockerExceptionType.locked,
        message: 'Locker is disposed',
      );
    }
  }

  /// Checked before any storage call, so an invalid value never prompts.
  void _ensureValidLockTimeout(Duration lockTimeout) {
    if (lockTimeout.inMilliseconds <= 0) {
      throw LockerException.invalidArgument('Lock timeout must be greater than 0');
    }
  }

  /// Erases [metas] when the session they belong to is gone.
  void _ensureFreshEpoch(
    int epoch, {
    Iterable<EntryMeta> metas = const [],
  }) {
    if (_lane.isCurrent(epoch)) {
      return;
    }

    _eraseMetas(metas);

    throw LockerException.locked();
  }

  void _cleanupMetaCache() {
    _eraseMetas(_metaCache.values);
    _metaCache = {};
  }

  void _eraseMetas(Iterable<EntryMeta> metas) {
    for (final meta in metas) {
      meta.erase();
    }
  }

  Future<void> _finishTransaction(
    MfaLockerTransaction txn, {
    required bool commit,
    required int epoch,
  }) async {
    try {
      if (txn.isClosed) {
        return;
      }

      if (!commit) {
        txn.abort();

        return;
      }

      final result = await txn.commit();

      // The file is written, but a lock during the commit must not resurrect the session.
      if (!_lane.isCurrent(epoch)) {
        _eraseMetas(result.pendingMeta.values);

        throw LockerException.locked();
      }

      for (final id in result.deletedIds) {
        _metaCache.remove(id)?.erase();
      }

      for (final entry in result.pendingMeta.entries) {
        _metaCache[entry.key]?.erase();
        _metaCache[entry.key] = entry.value;
      }
    } finally {
      _releaseTransaction(txn);
    }
  }

  /// A commit in flight is left to finish and discarded by [_finishTransaction].
  void _abortActiveTransaction() {
    final txn = _activeTransaction;
    if (txn == null || txn.isClosed || txn.isCommitting) {
      return;
    }

    txn.abort();
    _releaseTransaction(txn);
  }

  void _releaseTransaction(MfaLockerTransaction txn) {
    if (!identical(_activeTransaction, txn)) {
      return;
    }

    _activeTransaction = null;
    _lane.release();
  }
}
