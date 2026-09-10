import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:biometric_cipher/data/biometric_status.dart';
import 'package:biometric_cipher/data/tpm_status.dart';
import 'package:locker/erasable/erasable.dart';
import 'package:locker/locker/locker.dart';
import 'package:locker/locker/locker_transaction.dart';
import 'package:locker/locker/models/biometric_state.dart';
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
import 'package:locker/storage/storage_change_set.dart';
import 'package:locker/utils/operation_lane.dart';
import 'package:locker/utils/sync.dart';
import 'package:meta/meta.dart';
import 'package:rxdart/rxdart.dart';

part 'mfa_locker_transaction.dart';

/// Zone marker set by [MFALocker.withTransaction] for the duration of the
/// transaction body. Lets [MFALocker.allMeta] expose the uncommitted metadata
/// of the active transaction to its own body only.
final Object _transactionZoneKey = Object();

/// Error raised when the locker was locked (or disposed) while an operation was
/// waiting in the queue or running.
const _lockedWhileWaitingMessage = 'Locker was locked while the operation was waiting';

/// Error raised when a locker method is called from the body of a transaction.
const _insideTransactionMessage =
    'MFALocker methods cannot be used inside a transaction; use LockerTransaction instead';

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

  final _sync = Sync();

  /// Serializes all locker operations (transactions and standalone ones).
  final _lane = OperationLane();

  _MfaLockerTransaction? _activeTransaction;

  /// Unlocked-session generation: incremented by [lock], [eraseStorage] and
  /// [dispose], so that operations which waited (or were running) can detect
  /// that the locker was locked and must not apply their result.
  int _epoch = 0;

  @override
  ValueStream<LockerState> get stateStream => _stateController.stream;

  @override
  Future<bool> get isStorageInitialized => _storage.isInitialized;

  @override
  Future<Uint8List> get salt => _storage.salt;

  @override
  Future<Duration> get lockTimeout async => Duration(milliseconds: await _storage.lockTimeout);

  @override
  // TODO(d.seloustev): A test needs to be added
  Future<bool> get isBiometricEnabled => _storage.isBiometricEnabled;

  @override
  Map<EntryId, EntryMeta> get allMeta {
    if (_stateController.value != LockerState.unlocked) {
      throw StateError('Locker is not unlocked');
    }

    final activeTransaction = _activeTransaction;
    final zoneTransaction = Zone.current[_transactionZoneKey];
    if (activeTransaction != null &&
        zoneTransaction is _MfaLockerTransaction &&
        identical(zoneTransaction, activeTransaction) &&
        !activeTransaction.isClosed) {
      // Inside the transaction body: expose its uncommitted changes.
      return UnmodifiableMapView(activeTransaction.mergedMeta(_metaCache));
    }

    return UnmodifiableMapView(_metaCache);
  }

  @override
  Future<void> init({
    required PasswordCipherFunc passwordCipherFunc,
    required List<EntryAddInput> initialEntries,
    required Duration lockTimeout,
  }) =>
      _runOperation(
        () => _executeWithCleanup(
          erasables: [passwordCipherFunc, ...initialEntries],
          callback: () async {
            if (await isStorageInitialized) {
              throw StateError('Storage is already initialized');
            }

            await _storage.init(
              passwordCipherFunc: passwordCipherFunc,
              initialEntries: initialEntries,
              lockTimeout: lockTimeout.inMilliseconds,
            );

            await loadAllMetaIfLocked(passwordCipherFunc);
          },
        ),
      );

  @override
  Future<void> loadAllMeta(CipherFunc cipherFunc) async {
    _assertNotInsideTransaction();

    // Metadata is already loaded: do not unwrap the master key for nothing.
    if (_stateController.value == LockerState.unlocked) {
      cipherFunc.erase();

      return;
    }

    // Opening a transaction loads the metadata, an empty commit persists nothing.
    await withTransaction(cipherFunc, (_) async {});
  }

  @override
  Future<LockerTransaction> beginTransaction(CipherFunc cipherFunc) async {
    _assertNotInsideTransaction();

    final epoch = _epoch;

    // The transaction holds the lane until commit/abort, so a second one waits.
    await _lane.acquire();

    try {
      _ensureFreshEpoch(epoch);

      return await _executeWithCleanup(
        erasables: [cipherFunc],
        callback: () => _sync(() => _openTransaction(cipherFunc, epoch)),
      );
    } catch (_) {
      _lane.release();

      rethrow;
    }
  }

  /// Opens the change set (the single key unwrap) and transitions to unlocked
  /// using the already-unwrapped key. Runs under `_sync` with the lane held.
  Future<_MfaLockerTransaction> _openTransaction(CipherFunc cipherFunc, int epoch) async {
    if (!(await isStorageInitialized)) {
      throw StateError('Storage is not initialized');
    }

    final changeSet = await _storage.openChangeSet(cipherFunc: cipherFunc);

    try {
      // Reuse the already-unwrapped master key to load metadata and transition
      // to unlocked instead of a second authentication.
      if (_stateController.value != LockerState.unlocked) {
        final meta = await changeSet.readAllMeta();
        _ensureFreshEpochOrErase(epoch, meta);

        _metaCache = meta;
        _stateController.add(LockerState.unlocked);
      }
    } catch (_) {
      changeSet.erase();

      rethrow;
    }

    final transaction = _MfaLockerTransaction._(this, changeSet, epoch);
    _activeTransaction = transaction;

    return transaction;
  }

  @override
  Future<R> withTransaction<R>(
    CipherFunc cipherFunc,
    Future<R> Function(LockerTransaction txn) body,
  ) async {
    final txn = await beginTransaction(cipherFunc);
    var succeeded = false;
    try {
      // Run the body in a child zone so [allMeta] exposes the uncommitted
      // metadata of this transaction (and one-shot methods can detect misuse).
      final result = await runZoned(() => body(txn), zoneValues: {_transactionZoneKey: txn});
      succeeded = true;

      return result;
    } finally {
      if (succeeded) {
        await txn.commit();
      } else {
        await txn.abort();
      }
    }
  }

  @override
  void lock() {
    _epoch++;
    _lane.failPending(StateError(_lockedWhileWaitingMessage));
    _activeTransaction?._abortAndErase();

    if (_stateController.value != LockerState.unlocked) {
      return;
    }

    _cleanupState();
    _stateController.add(LockerState.locked);
  }

  @override
  Future<EntryId> write({
    required EntryAddInput input,
    required CipherFunc cipherFunc,
  }) =>
      // The public call owns the input: even when the transaction cannot be
      // opened, the value is erased and the meta is erased on error.
      _executeWithCleanup<EntryId>(
        erasables: [input.value],
        erasablesOnError: [input.meta],
        callback: () => withTransaction(cipherFunc, (txn) => txn.write(input)),
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
      // The public call owns the input: even when the transaction cannot be
      // opened, the value is erased and the meta is erased on error.
      _executeWithCleanup(
        erasables: [if (input.value != null) input.value!],
        erasablesOnError: [if (input.meta != null) input.meta!],
        callback: () => withTransaction(cipherFunc, (txn) => txn.update(input)),
      );

  @override
  Future<void> changePassword({
    required PasswordCipherFunc newCipherFunc,
    required CipherFunc existingCipherFunc,
  }) {
    final epoch = _epoch;

    return _executeWithCleanup(
      erasables: [newCipherFunc, existingCipherFunc],
      callback: () async {
        _assertNotInsideTransaction();
        _ensureFreshEpoch(epoch);

        await withTransaction(
          existingCipherFunc,
          (txn) => txn.addOrReplaceWrap(newWrapFunc: newCipherFunc),
        );
      },
    );
  }

  @override
  Future<void> updateLockTimeout({
    required Duration lockTimeout,
    required CipherFunc cipherFunc,
  }) {
    final epoch = _epoch;

    return _executeWithCleanup(
      erasables: [cipherFunc],
      callback: () async {
        _assertNotInsideTransaction();
        _ensureFreshEpoch(epoch);

        // Validate before unwrapping: an invalid value must not trigger an
        // authentication prompt.
        if (lockTimeout <= Duration.zero) {
          throw StorageException.other('Lock timeout must be greater than 0');
        }

        await withTransaction(cipherFunc, (txn) => txn.updateLockTimeout(lockTimeout));
      },
    );
  }

  @override
  Future<void> eraseStorage() => _runOperation(() async {
        _epoch++;
        final epoch = _epoch;

        // Everything queued behind erase must fail, not resurrect the locker.
        _lane.failPending(StateError(_lockedWhileWaitingMessage));

        await _storage.erase();

        _ensureFreshEpoch(epoch);
        _cleanupState();
        _stateController.add(LockerState.locked);
      });

  @override
  void dispose() {
    _epoch++;
    _lane.failPending(StateError(_lockedWhileWaitingMessage));
    _activeTransaction?._abortAndErase();
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

    final epoch = _epoch;
    final changeSet = await _storage.openChangeSet(cipherFunc: cipherFunc);

    try {
      // locker is locked, unlock it, cache keys and jump to unlocked state
      final meta = await changeSet.readAllMeta();
      _ensureFreshEpochOrErase(epoch, meta);

      _metaCache = meta;
      _stateController.add(LockerState.unlocked);
    } finally {
      changeSet.erase();
    }
  }

  /// Runs [body] as an exclusive operation: takes the FIFO lane, fails if the
  /// locker was locked while waiting, then runs [body] under `_sync`.
  Future<T> _runOperation<T>(Future<T> Function() body) async {
    _assertNotInsideTransaction();

    final epoch = _epoch;

    await _lane.acquire();

    try {
      _ensureFreshEpoch(epoch);

      return await _sync(body);
    } finally {
      _lane.release();
    }
  }

  /// Throws when the caller is inside a [withTransaction] body, where only the
  /// transaction itself may touch the storage (otherwise it would deadlock on
  /// the lane held by its own transaction).
  void _assertNotInsideTransaction() {
    if (Zone.current[_transactionZoneKey] != null) {
      throw StateError(_insideTransactionMessage);
    }
  }

  /// Throws if the locker was locked/disposed after [epoch] was captured.
  void _ensureFreshEpoch(int epoch) {
    if (epoch != _epoch) {
      throw StateError(_lockedWhileWaitingMessage);
    }
  }

  /// Same as [_ensureFreshEpoch] but also erases [meta] when the result is
  /// discarded because the locker was locked while it was being read.
  void _ensureFreshEpochOrErase(int epoch, Map<EntryId, EntryMeta> meta) {
    if (epoch == _epoch) {
      return;
    }

    for (final entryMeta in meta.values) {
      entryMeta.erase();
    }

    throw StateError(_lockedWhileWaitingMessage);
  }

  void _cleanupState() {
    for (final meta in _metaCache.values) {
      meta.erase();
    }

    _metaCache = {};
  }

  /// Same as [_ensureFreshEpoch] but also erases the uncommitted metadata of a
  /// transaction whose commit result must not be applied.
  void _ensureFreshEpochOrErasePending(int epoch, _MfaLockerTransaction txn) {
    if (epoch == _epoch) {
      return;
    }

    // Never leave uncommitted metadata behind on a locked locker.
    for (final meta in txn._pendingMeta.values) {
      meta.erase();
    }

    txn._pendingMeta.clear();
    txn._deletedIds.clear();

    throw StateError(_lockedWhileWaitingMessage);
  }

  /// Applies the metadata overlay of a committed [txn] to the cache, erasing
  /// the metadata it replaced or deleted.
  void _applyCommittedMeta(_MfaLockerTransaction txn) {
    for (final id in txn._deletedIds) {
      _metaCache.remove(id)?.erase();
    }

    for (final entry in txn._pendingMeta.entries) {
      _metaCache[entry.key]?.erase();
      _metaCache[entry.key] = entry.value;
    }

    // Ownership moved to the cache: nothing left to erase on detach.
    txn._pendingMeta.clear();
    txn._deletedIds.clear();
  }

  @override
  Future<void> configureBiometricCipher(BiometricConfig config) => _secureProvider.configure(config);

  @override
  Future<BiometricState> determineBiometricState({String? biometricKeyTag}) async {
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
    if (!isEnabledInSettings) {
      return BiometricState.availableButDisabled;
    }

    // Proactive key validity check — no biometric prompt shown.
    if (biometricKeyTag != null) {
      final isValid = await _secureProvider.isKeyValid(tag: biometricKeyTag);
      if (!isValid) {
        return BiometricState.keyInvalidated;
      }
    }

    return BiometricState.enabled;
  }

  /// Enable biometric authentication (requires password confirmation)
  /// This method handles key generation and storage update.
  @override
  Future<void> setupBiometry({
    required BioCipherFunc bioCipherFunc,
    required PasswordCipherFunc passwordCipherFunc,
  }) {
    final epoch = _epoch;

    return _executeWithCleanup(
      erasables: [bioCipherFunc, passwordCipherFunc],
      callback: () async {
        _assertNotInsideTransaction();
        _ensureFreshEpoch(epoch);

        // Step 1: Check TPM status
        final tpmStatus = await _secureProvider.getTPMStatus();
        if (tpmStatus != TPMStatus.supported) {
          throw const BiometricException(
            BiometricExceptionType.notAvailable,
            message: 'TPM not supported on this device',
          );
        }

        // Step 2: Check biometry status
        final biometryStatus = await _secureProvider.getBiometryStatus();
        if (biometryStatus != BiometricStatus.supported) {
          throw BiometricException(
            BiometricExceptionType.notAvailable,
            message: 'Biometric authentication not available: $biometryStatus',
          );
        }

        try {
          // Step 3: Defensive key management - delete before generate
          try {
            await _secureProvider.deleteKey(tag: bioCipherFunc.keyTag);
          } catch (_) {
            // Ignore errors - key might not exist yet
          }

          // Step 4: Generate new key
          await _secureProvider.generateKey(tag: bioCipherFunc.keyTag);

          // The locker could have been locked while the native key was created.
          _ensureFreshEpoch(epoch);

          // Step 5: Enable biometry in locker (one atomic write)
          await withTransaction(
            passwordCipherFunc,
            (txn) => txn.addOrReplaceWrap(newWrapFunc: bioCipherFunc),
          );
        } catch (_) {
          // Best-effort cleanup after enableBiometric failure; original error is rethrown below
          try {
            await _secureProvider.deleteKey(tag: bioCipherFunc.keyTag);
          } catch (_) {
            // Suppress cleanup error; original failure is rethrown
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
  }) {
    final epoch = _epoch;

    return _executeWithCleanup(
      erasables: [passwordCipherFunc],
      callback: () async {
        _assertNotInsideTransaction();
        _ensureFreshEpoch(epoch);

        await withTransaction(
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
  }

  Future<T> _executeWithCleanup<T>({
    required List<Erasable> erasables,
    required Future<T> Function() callback,
    List<Erasable> erasablesOnError = const [],
  }) async {
    try {
      return await callback();
    } catch (_) {
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
