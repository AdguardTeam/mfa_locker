import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:locker/erasable/erasable_byte_array.dart';
import 'package:locker/locker/locker.dart' as locker;
import 'package:locker/locker/mfa_locker.dart';
import 'package:locker/locker/models/biometric_state.dart';
import 'package:locker/security/models/biometric_config.dart';
import 'package:locker/security/security_provider.dart';
import 'package:locker/storage/models/domain/entry_id.dart';
import 'package:locker/storage/models/domain/entry_meta.dart';
import 'package:locker/storage/models/domain/entry_value.dart';
import 'package:mfa_demo/core/constants/app_constants.dart';
import 'package:mfa_demo/features/locker/data/models/repository_locker_state.dart';
import 'package:rxdart/rxdart.dart';

/// Repository interface for locker operations
abstract class LockerRepository {
  /// Stream of repository state updates that stay stable across MFALocker recreation.
  ValueStream<RepositoryLockerState> get lockerStateStream;

  /// Get auto-lock timeout
  Future<Duration> get autoLockTimeout;

  /// Initialize storage with password and first entry
  Future<void> init({
    required String password,
    required String firstEntryName,
    required String firstEntryValue,
    required Duration lockTimeout,
  });

  /// Update auto-lock timeout
  Future<void> updateLockTimeout({
    required Duration timeout,
    required String password,
  });

  /// Update auto-lock timeout using biometric authentication
  Future<void> updateLockTimeoutWithBiometric({required Duration timeout});

  /// Unlock storage with password
  Future<void> unlock({required String password});

  /// Lock storage
  Future<void> lock();

  /// Add new entry
  Future<void> addEntry({
    required String password,
    required String name,
    required String value,
  });

  /// Read entry value
  Future<String> readEntry({
    required String password,
    required EntryId id,
  });

  /// Delete entry
  Future<bool> deleteEntry({
    required String password,
    required EntryId id,
  });

  /// Get all entries with their IDs
  Future<Map<EntryId, String>> getAllEntries();

  /// Change master password
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  });

  /// Check if storage is initialized
  Future<bool> isInitialized();

  /// Erase all data from storage (irreversible)
  Future<void> eraseStorage();

  /// Map TPM status, biometry status, and settings to BiometricState
  Future<BiometricState> determineBiometricState();

  /// Configure biometric cipher provider with custom settings
  /// This must be called before any biometric operations
  Future<void> configureBiometricCipher(BiometricConfig config);

  /// Enable biometric authentication (requires password confirmation)
  Future<void> enableBiometric({required String password});

  /// Disable biometric authentication (requires password confirmation)
  Future<void> disableBiometric({required String password});

  /// Unlock storage with biometric
  Future<void> unlockWithBiometric();

  /// Add new entry using biometric authentication
  Future<void> addEntryWithBiometric({
    required String name,
    required String value,
  });

  /// Read entry value using biometric authentication
  Future<String> readEntryWithBiometric({required EntryId id});

  /// Delete entry using biometric authentication
  Future<bool> deleteEntryWithBiometric({required EntryId id});

  /// Dispose of resources
  Future<void> dispose();
}

/// Implementation of LockerRepository using MFALocker
class LockerRepositoryImpl implements LockerRepository {
  final String _storageFilePath;

  LockerRepositoryImpl({
    required String storageFilePath,
  }) : _storageFilePath = storageFilePath;

  final BehaviorSubject<RepositoryLockerState> _stateController = BehaviorSubject<RepositoryLockerState>.seeded(
    RepositoryLockerState.unknown,
  );
  bool _isStorageInitialized = false;

  Completer<void>? _initCompleter;
  MFALocker? _mfaLocker;
  SecurityProviderImpl? _cachedProvider;
  StreamSubscription<locker.LockerState>? _lockerStateSubscription;

  @override
  ValueStream<RepositoryLockerState> get lockerStateStream {
    _ensureLockerInstance();

    return _stateController;
  }

  @override
  Future<Duration> get autoLockTimeout => _locker.lockTimeout;

  MFALocker get _locker {
    final locker = _mfaLocker;
    if (locker == null) {
      throw StateError('Locker not initialized');
    }

    return locker;
  }

  SecurityProvider get _securityProvider {
    final locker = _locker;
    if (_cachedProvider?.locker != locker) {
      _cachedProvider = SecurityProviderImpl(
        locker: locker,
        biometricKeyTag: AppConstants.biometricKeyTag,
      );
    }

    return _cachedProvider!;
  }

  @override
  Future<void> init({
    required String password,
    required String firstEntryName,
    required String firstEntryValue,
    required Duration lockTimeout,
  }) async {
    await _ensureLockerInstance();
    await _runInitOnce(() async {
      final passwordCipherFunc = await _securityProvider.authenticatePassword(password: password);

      final entryMeta = _createEntryMeta(firstEntryName);
      final entryValue = _createEntryValue(firstEntryValue);

      await _locker.init(
        passwordCipherFunc: passwordCipherFunc,
        initialEntryMeta: entryMeta,
        initialEntryValue: entryValue,
        lockTimeout: lockTimeout,
      );

      _isStorageInitialized = true;
      _emitRepositoryState(RepositoryLockerState.unlocked);
    });
  }

  @override
  Future<void> updateLockTimeout({
    required Duration timeout,
    required String password,
  }) async {
    await _ensureLockerInstance();
    final passwordCipherFunc = await _securityProvider.authenticatePassword(password: password);

    await _locker.updateLockTimeout(
      lockTimeout: timeout,
      cipherFunc: passwordCipherFunc,
    );
  }

  @override
  Future<void> updateLockTimeoutWithBiometric({required Duration timeout}) async {
    await _ensureLockerInstance();
    final bioCipherFunc = await _securityProvider.authenticateBiometric();

    await _locker.updateLockTimeout(
      lockTimeout: timeout,
      cipherFunc: bioCipherFunc,
    );
  }

  @override
  Future<void> unlock({required String password}) async {
    await _ensureLockerInstance();
    final passwordCipherFunc = await _securityProvider.authenticatePassword(password: password);

    await _locker.loadAllMeta(passwordCipherFunc);
  }

  @override
  Future<void> lock() async {
    await _ensureLockerInstance();
    _locker.lock();
  }

  @override
  Future<void> addEntry({
    required String password,
    required String name,
    required String value,
  }) async {
    await _ensureLockerInstance();
    final passwordCipherFunc = await _securityProvider.authenticatePassword(password: password);

    final entryMeta = _createEntryMeta(name);
    final entryValue = _createEntryValue(value);

    await _locker.write(
      entryMeta: entryMeta,
      entryValue: entryValue,
      cipherFunc: passwordCipherFunc,
    );
  }

  @override
  Future<String> readEntry({
    required String password,
    required EntryId id,
  }) async {
    await _ensureLockerInstance();
    final passwordCipherFunc = await _securityProvider.authenticatePassword(password: password);

    // Read the entry value
    final entryValue = await _locker.readValue(
      id: id,
      cipherFunc: passwordCipherFunc,
    );

    return _entryValueToString(entryValue);
  }

  @override
  Future<bool> deleteEntry({
    required String password,
    required EntryId id,
  }) async {
    await _ensureLockerInstance();
    final passwordCipherFunc = await _securityProvider.authenticatePassword(password: password);

    // Delete the entry
    final result = await _locker.delete(
      id: id,
      cipherFunc: passwordCipherFunc,
    );

    return result;
  }

  @override
  Future<Map<EntryId, String>> getAllEntries() async {
    await _ensureLockerInstance();
    final allMeta = _locker.allMeta;

    return allMeta.map((id, meta) => MapEntry(id, _entryMetaToString(meta)));
  }

  @override
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    await _ensureLockerInstance();
    final oldCipherFunc = await _securityProvider.authenticatePassword(password: oldPassword);
    final newCipherFunc = await _securityProvider.authenticatePassword(password: newPassword, forceNewSalt: true);

    await _locker.changePassword(
      oldCipherFunc: oldCipherFunc,
      newCipherFunc: newCipherFunc,
    );
  }

  @override
  Future<bool> isInitialized() async {
    await _ensureLockerInstance();

    return _locker.isStorageInitialized;
  }

  @override
  Future<void> eraseStorage() async {
    await _ensureLockerInstance();
    await _locker.eraseStorage();

    _isStorageInitialized = false;
    _initCompleter = null;
    _emitRepositoryState(RepositoryLockerState.uninitialized);
  }

  @override
  Future<BiometricState> determineBiometricState() async {
    await _ensureLockerInstance();

    return _locker.determineBiometricState();
  }

  @override
  Future<void> configureBiometricCipher(BiometricConfig config) async {
    await _ensureLockerInstance();
    await _locker.configureBiometricCipher(config);
  }

  @override
  Future<void> enableBiometric({required String password}) async {
    await _ensureLockerInstance();

    // Create cipher functions
    final passwordCipherFunc = await _securityProvider.authenticatePassword(password: password);
    final bioCipherFunc = await _securityProvider.authenticateBiometric();

    // Setup biometry in locker (handles key generation and storage update)
    await _locker.setupBiometry(
      bioCipherFunc: bioCipherFunc,
      passwordCipherFunc: passwordCipherFunc,
    );
  }

  @override
  Future<void> disableBiometric({required String password}) async {
    await _ensureLockerInstance();

    // Create cipher functions
    final passwordCipherFunc = await _securityProvider.authenticatePassword(password: password);
    final bioCipherFunc = await _securityProvider.authenticateBiometric();

    // Teardown biometry in locker (handles storage update and key deletion)
    await _locker.teardownBiometry(
      bioCipherFunc: bioCipherFunc,
      passwordCipherFunc: passwordCipherFunc,
    );
  }

  @override
  Future<void> unlockWithBiometric() async {
    await _ensureLockerInstance();
    final bioCipherFunc = await _securityProvider.authenticateBiometric();

    await _locker.loadAllMeta(bioCipherFunc);
  }

  @override
  Future<void> addEntryWithBiometric({
    required String name,
    required String value,
  }) async {
    await _ensureLockerInstance();
    final bioCipherFunc = await _securityProvider.authenticateBiometric();

    final entryMeta = _createEntryMeta(name);
    final entryValue = _createEntryValue(value);

    await _locker.write(
      entryMeta: entryMeta,
      entryValue: entryValue,
      cipherFunc: bioCipherFunc,
    );
  }

  @override
  Future<String> readEntryWithBiometric({required EntryId id}) async {
    await _ensureLockerInstance();
    final bioCipherFunc = await _securityProvider.authenticateBiometric();

    // Read the entry value
    final entryValue = await _locker.readValue(
      id: id,
      cipherFunc: bioCipherFunc,
    );

    return _entryValueToString(entryValue);
  }

  @override
  Future<bool> deleteEntryWithBiometric({required EntryId id}) async {
    await _ensureLockerInstance();
    final bioCipherFunc = await _securityProvider.authenticateBiometric();

    // Delete the entry
    final result = await _locker.delete(
      id: id,
      cipherFunc: bioCipherFunc,
    );

    return result;
  }

  @override
  Future<void> dispose() async {
    await _lockerStateSubscription?.cancel();
    _lockerStateSubscription = null;
    if (!_stateController.isClosed) {
      await _stateController.close();
    }
    _mfaLocker?.dispose();
  }

  // Helper methods
  void _emitRepositoryState(RepositoryLockerState state) {
    if (_stateController.isClosed || _stateController.value == state) {
      return;
    }

    _stateController.add(state);
  }

  Future<void> _subscribeToLockerStream() async {
    final locker = _mfaLocker;
    if (locker == null) {
      return;
    }

    await _lockerStateSubscription?.cancel();
    _lockerStateSubscription = locker.stateStream.listen((libraryState) {
      final repositoryState = _mapLibraryStateToRepositoryState(libraryState);
      _emitRepositoryState(repositoryState);
    });
  }

  Future<void> _refreshInitializationStatus() async {
    final locker = _mfaLocker;
    if (locker == null) {
      return;
    }

    final isInitialized = await locker.isStorageInitialized;
    _isStorageInitialized = isInitialized;

    if (!isInitialized) {
      _emitRepositoryState(RepositoryLockerState.uninitialized);

      return;
    }

    final currentLibraryState = locker.stateStream.value;
    _emitRepositoryState(_mapLibraryStateToRepositoryState(currentLibraryState));
  }

  RepositoryLockerState _mapLibraryStateToRepositoryState(locker.LockerState libraryState) => switch (libraryState) {
    locker.LockerState.locked =>
      _isStorageInitialized ? RepositoryLockerState.locked : RepositoryLockerState.uninitialized,
    locker.LockerState.unlocked => RepositoryLockerState.unlocked,
  };

  Future<void> _runInitOnce(Future<void> Function() body) async {
    if (_isStorageInitialized) {
      return;
    }

    final existingCompleter = _initCompleter;
    if (existingCompleter != null) {
      return existingCompleter.future;
    }

    final completer = Completer<void>();
    _initCompleter = completer;

    try {
      await body();
      if (!completer.isCompleted) {
        completer.complete();
      }
    } catch (error, stackTrace) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
      _initCompleter = null;
      rethrow;
    } finally {
      if (completer.isCompleted) {
        _initCompleter = null;
      }
    }

    return completer.future;
  }

  Future<void> _ensureLockerInstance() async {
    if (_mfaLocker != null) {
      return;
    }

    final file = File(_storageFilePath);
    _mfaLocker = MFALocker(file: file);

    await _subscribeToLockerStream();
    await _refreshInitializationStatus();
  }

  EntryMeta _createEntryMeta(String key) {
    final bytes = Uint8List.fromList(utf8.encode(key));
    final erasable = ErasableByteArray(bytes);

    return EntryMeta.fromErasable(erasable: erasable);
  }

  EntryValue _createEntryValue(String value) {
    final bytes = Uint8List.fromList(utf8.encode(value));
    final erasable = ErasableByteArray(bytes);

    return EntryValue.fromErasable(erasable: erasable);
  }

  String _entryValueToString(EntryValue value) => utf8.decode(value.bytes);

  String _entryMetaToString(EntryMeta meta) => utf8.decode(meta.bytes);
}
