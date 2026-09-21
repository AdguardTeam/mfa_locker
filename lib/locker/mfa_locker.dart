import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:biometric_cipher/data/biometric_status.dart';
import 'package:biometric_cipher/data/tpm_status.dart';
import 'package:locker/locker/locker.dart';
import 'package:locker/locker/locker_transaction.dart';
import 'package:locker/locker/models/biometric_state.dart';
import 'package:locker/locker/models/exceptions/inside_transaction_exception.dart';
import 'package:locker/locker/models/exceptions/locker_locked_exception.dart';
import 'package:locker/locker/utils/operation_lane.dart';
import 'package:locker/security/biometric_cipher_provider.dart';
import 'package:locker/security/models/bio_cipher_func.dart';
import 'package:locker/security/models/biometric_config.dart';
import 'package:locker/security/models/cipher_func.dart';
import 'package:locker/security/models/exceptions/biometric_exception.dart';
import 'package:locker/security/models/password_cipher_func.dart';
import 'package:locker/src/locker/erase_after.dart';
import 'package:locker/src/locker/mfa_locker_transaction.dart';
import 'package:locker/src/locker/transaction_result.dart';
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

/// Marks the `withTransaction` body zone with the owning locker so its methods
/// refuse to run inside it (instead of deadlocking on the lane).
class _TransactionZone {
  static final Object _key = Object();

  /// Runs [body] in a child zone marked with [locker]; the marker propagates
  /// through its async continuations.
  static Future<R> run<R>(MFALocker locker, Future<R> Function() body) async =>
      runZoned<Future<R>>(body, zoneValues: {_key: locker});

  static MFALocker? get current => Zone.current[_key] as MFALocker?;
}

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

  /// Serializes locker operations and owns the session generation:
  /// [OperationLane.invalidate] makes waiting/running operations fail on
  /// `lock()`/`dispose()`/`eraseStorage()`.
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
  // TODO(d.seloustev): A test needs to be added
  Future<bool> get isBiometricEnabled => _storage.isBiometricEnabled;

  @override
  Map<EntryId, EntryMeta> get allMeta {
    if (_stateController.value != LockerState.unlocked) {
      throw StateError('Locker is not unlocked');
    }

    // Committed-only: uncommitted changes are visible via LockerTransaction.allMeta.
    return UnmodifiableMapView(_metaCache);
  }

  @override
  Future<void> init({
    required PasswordCipherFunc passwordCipherFunc,
    required List<EntryAddInput> initialEntries,
    required Duration lockTimeout,
  }) =>
      // Erase the inputs even if the call never runs (cancelled while queued).
      eraseAfter(
        erasables: [passwordCipherFunc, ...initialEntries],
        callback: () => _runOperation(() async {
          final epoch = _lane.generation;

          if (await isStorageInitialized) {
            throw StateError('Storage is already initialized');
          }

          await _storage.init(
            passwordCipherFunc: passwordCipherFunc,
            initialEntries: initialEntries,
            lockTimeout: lockTimeout.inMilliseconds,
          );

          // Never unlock a locker that was locked while the storage was written.
          _ensureFreshEpoch(epoch);

          await loadAllMetaIfLocked(passwordCipherFunc, epoch: epoch);
        }),
      );

  @override
  Future<void> loadAllMeta(CipherFunc cipherFunc) async {
    _assertNotInsideTransaction();

    // Metadata is already loaded: do not unwrap the master key for nothing.
    if (_stateController.value == LockerState.unlocked) {
      cipherFunc.erase();

      return;
    }

    // Opening a transaction loads the metadata; an empty body persists nothing.
    await withTransaction(cipherFunc, (_) async {});
  }

  /// Enters the serialized transaction slot: asserts non-reentrancy, acquires
  /// the lane and captures the epoch, then delegates to [_unlockTransaction].
  /// Does not erase [cipherFunc] — the calling boundary owns the single erase.
  Future<MfaLockerTransaction> _enterTransaction(CipherFunc cipherFunc) async {
    _assertNotInsideTransaction();

    final epoch = _lane.generation;

    // The transaction holds the lane until the body finishes, so a second one waits.
    await _lane.acquire();

    try {
      _ensureFreshEpoch(epoch);

      return await _unlockTransaction(cipherFunc, epoch);
    } catch (_) {
      _lane.release();

      rethrow;
    }
  }

  /// Unwraps the master key (the single native call), loads metadata, transitions
  /// to unlocked and builds the transaction. Runs with the lane held.
  Future<MfaLockerTransaction> _unlockTransaction(CipherFunc cipherFunc, int epoch) async {
    if (!(await isStorageInitialized)) {
      throw StateError('Storage is not initialized');
    }

    final storageTransaction = await _storage.openTransaction(cipherFunc: cipherFunc);

    try {
      // Reuse the already-unwrapped master key to load metadata and transition
      // to unlocked instead of a second authentication.
      if (_stateController.value != LockerState.unlocked) {
        final meta = await storageTransaction.readAllMeta();
        _ensureFreshEpochErasing(epoch, meta.values);

        _metaCache = meta;
        _stateController.add(LockerState.unlocked);
      }
    } catch (_) {
      storageTransaction.erase();

      rethrow;
    }

    final transaction = MfaLockerTransaction(storageTransaction, _metaCache);
    _activeTransaction = transaction;

    return transaction;
  }

  @override
  Future<R> withTransaction<R>(
    CipherFunc cipherFunc,
    Future<R> Function(LockerTransaction txn) body,
  ) =>
      // Erase the cipher once here, at the public boundary that received it
      // (even if the transaction never opens); the internal path does not erase.
      eraseAfter(
        erasables: [cipherFunc],
        callback: () => _withTransaction(cipherFunc, body),
      );

  /// Internal typed variant: passes the concrete [MfaLockerTransaction] so
  /// one-shot methods can call `writeBuffered`/`updateBuffered` without a cast.
  Future<R> _withTransaction<R>(
    CipherFunc cipherFunc,
    Future<R> Function(MfaLockerTransaction txn) body,
  ) async {
    final txn = await _enterTransaction(cipherFunc);
    var succeeded = false;
    try {
      // Run the body in a child zone so [allMeta] exposes the uncommitted
      // metadata of this transaction (and one-shot methods can detect misuse).
      final result = await _TransactionZone.run(this, () => body(txn));
      succeeded = true;

      return result;
    } finally {
      if (succeeded && txn.isClosed) {
        // Closed by lock()/dispose() while the body was running: the buffer was
        // discarded, report the lock instead of returning as if committed.
        throw const LockerLockedException();
      }

      await _finishTransaction(txn, commit: succeeded);
    }
  }

  @override
  void lock() {
    _lane.invalidate(const LockerLockedException());
    _abortActiveTransaction();

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
      // The public call owns the input and cipher: even when the transaction
      // cannot be opened, the value/cipher are erased and the meta on error.
      eraseAfter<EntryId>(
        erasables: [input.value, cipherFunc],
        erasablesOnError: [input.meta],
        callback: () => _withTransaction(cipherFunc, (txn) => txn.writeBuffered(input)),
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
      // The public call owns the input and cipher: even when the transaction
      // cannot be opened, the value/cipher are erased and the meta on error.
      eraseAfter(
        erasables: [if (input.value != null) input.value!, cipherFunc],
        erasablesOnError: [if (input.meta != null) input.meta!],
        callback: () => _withTransaction(cipherFunc, (txn) => txn.updateBuffered(input)),
      );

  @override
  Future<void> changePassword({
    required PasswordCipherFunc newCipherFunc,
    required CipherFunc existingCipherFunc,
  }) {
    final epoch = _lane.generation;

    return eraseAfter(
      erasables: [newCipherFunc, existingCipherFunc],
      callback: () async {
        _assertNotInsideTransaction();
        _ensureFreshEpoch(epoch);

        await _withTransaction(
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
    final epoch = _lane.generation;

    return eraseAfter(
      erasables: [cipherFunc],
      callback: () async {
        _assertNotInsideTransaction();
        _ensureFreshEpoch(epoch);

        // Validate before unwrapping (no prompt for a bad value); the storage
        // stores whole milliseconds, so anything below 1 ms is invalid too.
        if (lockTimeout.inMilliseconds <= 0) {
          throw StorageException.other('Lock timeout must be greater than 0');
        }

        await _withTransaction(cipherFunc, (txn) => txn.updateLockTimeout(lockTimeout));
      },
    );
  }

  @override
  Future<void> eraseStorage() => _runOperation(() async {
        // Everything queued behind erase must fail, not resurrect the locker.
        _lane.invalidate(const LockerLockedException());
        final epoch = _lane.generation;

        await _storage.erase();

        // A concurrent lock()/dispose() must not turn a completed erase into an error.
        _cleanupState();
        if (_lane.isCurrent(epoch) && !_stateController.isClosed) {
          _stateController.add(LockerState.locked);
        }
      });

  @override
  void dispose() {
    _lane.invalidate(const LockerLockedException());
    _abortActiveTransaction();
    _cleanupState();
    _stateController.close();
  }

  /// Unlocks the locker and caches metadata if it is locked. [epoch] is the
  /// generation captured by the caller before its own awaits (defaults to now).
  @visibleForTesting
  Future<void> loadAllMetaIfLocked(CipherFunc cipherFunc, {int? epoch}) async {
    final epochAtStart = epoch ?? _lane.generation;

    if (!(await isStorageInitialized)) {
      throw StateError('Storage is not initialized');
    }

    if (_stateController.value == LockerState.unlocked) {
      return;
    }

    final transaction = await _storage.openTransaction(cipherFunc: cipherFunc);

    try {
      final meta = await transaction.readAllMeta();
      _ensureFreshEpochErasing(epochAtStart, meta.values);

      _metaCache = meta;
      _stateController.add(LockerState.unlocked);
    } finally {
      transaction.erase();
    }
  }

  /// Runs [body] exclusively on the FIFO lane, failing if the locker was locked meanwhile.
  Future<T> _runOperation<T>(Future<T> Function() body) async {
    _assertNotInsideTransaction();

    final epoch = _lane.generation;

    await _lane.acquire();

    try {
      _ensureFreshEpoch(epoch);

      return await body();
    } finally {
      _lane.release();
    }
  }

  /// Throws if the caller is inside a transaction of this locker, which would
  /// deadlock on its lane. Transactions of other lockers are fine.
  void _assertNotInsideTransaction() {
    if (identical(_TransactionZone.current, this)) {
      throw const InsideTransactionException();
    }
  }

  /// Throws if the locker was locked/disposed after [epoch] was captured.
  void _ensureFreshEpoch(int epoch) {
    if (!_lane.isCurrent(epoch)) {
      throw const LockerLockedException();
    }
  }

  /// Same as [_ensureFreshEpoch] but also erases [metas] when the result is
  /// discarded because the locker was locked while they were being read.
  void _ensureFreshEpochErasing(int epoch, Iterable<EntryMeta> metas) {
    if (_lane.isCurrent(epoch)) {
      return;
    }

    for (final meta in metas) {
      meta.erase();
    }

    throw const LockerLockedException();
  }

  void _cleanupState() {
    for (final meta in _metaCache.values) {
      meta.erase();
    }

    _metaCache = {};
  }

  /// Finishes a transaction: on commit persists and publishes the overlay; on
  /// abort (or a failed commit) erases the overlay. Always erases the working
  /// copy, releases the lane and clears the active marker. Idempotent.
  Future<void> _finishTransaction(MfaLockerTransaction txn, {required bool commit}) async {
    if (txn.isClosed) {
      return;
    }

    try {
      if (commit) {
        await _storage.closeTransaction(txn.storageTransaction);
        _applyResult(txn.finalize());
      } else {
        txn.eraseOverlay();
      }
    } catch (_) {
      // Commit failed (e.g. conflict): the overlay was not published, erase it.
      txn.eraseOverlay();

      rethrow;
    } finally {
      _closeTransaction(txn);
    }
  }

  /// Synchronous abort of the active transaction for `lock()`/`dispose()`.
  void _abortActiveTransaction() {
    final txn = _activeTransaction;
    if (txn == null || txn.isClosed) {
      return;
    }

    txn.eraseOverlay();
    _closeTransaction(txn);
  }

  void _closeTransaction(MfaLockerTransaction txn) {
    txn.close();
    txn.storageTransaction.erase();
    _lane.release();
    if (identical(_activeTransaction, txn)) {
      _activeTransaction = null;
    }
  }

  /// Publishes a committed transaction's overlay into the cache, erasing the
  /// metadata it replaced or deleted.
  void _applyResult(TransactionResult result) {
    for (final id in result.deletedIds) {
      _metaCache.remove(id)?.erase();
    }

    for (final entry in result.pendingMeta.entries) {
      _metaCache[entry.key]?.erase();
      _metaCache[entry.key] = entry.value;
    }
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

  /// Enable biometric authentication (requires password confirmation).
  @override
  Future<void> setupBiometry({
    required BioCipherFunc bioCipherFunc,
    required PasswordCipherFunc passwordCipherFunc,
  }) {
    final epoch = _lane.generation;

    return eraseAfter(
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
          await _withTransaction(
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
    final epoch = _lane.generation;

    return eraseAfter(
      erasables: [passwordCipherFunc],
      callback: () async {
        _assertNotInsideTransaction();
        _ensureFreshEpoch(epoch);

        await _withTransaction(
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
}
