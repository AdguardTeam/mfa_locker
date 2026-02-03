import 'dart:async';
import 'dart:typed_data';

import 'package:locker/locker/models/biometric_state.dart';
import 'package:locker/security/models/bio_cipher_func.dart';
import 'package:locker/security/models/biometric_config.dart';
import 'package:locker/security/models/cipher_func.dart';
import 'package:locker/security/models/password_cipher_func.dart';
import 'package:locker/storage/models/domain/entry_id.dart';
import 'package:locker/storage/models/domain/entry_meta.dart';
import 'package:locker/storage/models/domain/entry_value.dart';
import 'package:rxdart/rxdart.dart';

/// Represents the current state of the locker.
enum LockerState {
  /// The locker is locked and requires authentication to access.
  locked,

  /// The locker is unlocked and ready for operations.
  unlocked,
}

/// A secure storage abstraction that manages encrypted key-value pairs.
///
/// The locker provides a high-level interface for storing and retrieving
/// encrypted data with automatic lock/unlock, password rotation and
/// biometric support. When the locker is locked, methods that require access
/// to encrypted data will attempt to unlock using the provided `CipherFunc`
/// and transition to the unlocked state on success.
abstract interface class Locker {
  /// Returns the current state of the locker.
  ValueStream<LockerState> get stateStream;

  /// Returns the storage salt or `null` if storage is not initialized yet.
  Future<Uint8List?> get salt;

  /// Indicates whether the underlying storage has been initialized.
  Future<bool> get isStorageInitialized;

  /// Returns the auto-lock timeout.
  Future<Duration> get lockTimeout;

  /// Whether biometric authentication is enabled.
  Future<bool> get isBiometricEnabled;

  /// Returns a list of all entry metadata currently stored in the locker.
  /// The locker must be unlocked before calling this method.
  ///
  /// Note: Metadata is cached in-memory while unlocked and is cleared on lock
  /// or dispose. Holding references beyond the unlocked session is discouraged.
  Map<EntryId, EntryMeta> get allMeta;

  /// Initializes the storage and creates the first entry using the provided
  /// password-derived cipher function.
  ///
  /// On success the locker transitions to the unlocked state, metadata is cached.
  ///
  /// Throws [StateError] if storage is already initialized.
  Future<void> init({
    required PasswordCipherFunc passwordCipherFunc,
    required EntryMeta initialEntryMeta,
    required EntryValue initialEntryValue,
    required Duration lockTimeout,
  });

  /// Ensures all entry metadata is loaded and the locker is unlocked.
  ///
  /// If the locker is locked, attempts to unlock and load metadata using the
  /// provided [cipherFunc].
  ///
  /// Throws [StateError] if storage is not initialized.
  Future<void> loadAllMeta(CipherFunc cipherFunc);

  /// Locks the locker and clears all cached data.
  ///
  /// After locking, authentication will be required to access the data.
  void lock();

  /// Writes a new entry to storage.
  ///
  /// [entryMeta] - The metadata for the entry to store.
  /// [entryValue] - The value to store.
  ///
  /// Returns the id of the stored entry.
  ///
  /// Throws [StateError] if storage is not initialized.
  Future<EntryId> write({
    required EntryMeta entryMeta,
    required EntryValue entryValue,
    required CipherFunc cipherFunc,
  });

  /// Reads an entry value by id.
  ///
  /// If the locker is locked, attempts to unlock using [cipherFunc].
  /// Returns the entry value if found.
  ///
  /// Throws [StateError] if storage is not initialized.
  Future<EntryValue> readValue({
    required EntryId id,
    required CipherFunc cipherFunc,
  });

  /// Deletes an entry by id.
  ///
  /// If the locker is locked, attempts to unlock using [cipherFunc]. On
  /// success, deletes the entry and removes its metadata from the cache.
  ///
  /// Completes when deletion finishes. If the entry does not exist, the
  /// operation succeeds without effect.
  ///
  /// Throws [StateError] if storage is not initialized.
  Future<bool> delete({
    required EntryId id,
    required CipherFunc cipherFunc,
  });

  /// Updates an entry by id.
  ///
  /// If the locker is locked, attempts to unlock using [cipherFunc].
  /// At least one of [entryMeta] or [entryValue] must be provided.
  ///
  /// Throws [StateError] if storage is not initialized.
  Future<void> update({
    required EntryId id,
    required CipherFunc cipherFunc,
    EntryMeta? entryMeta,
    EntryValue? entryValue,
  });

  /// Adds a new password and re-wraps access using the old password.
  ///
  /// Uses [oldCipherFunc] to authorize and add [newCipherFunc] as a new
  /// password-based wrap. If the locker is locked, it will be unlocked using
  /// [oldCipherFunc].
  Future<void> changePassword({
    required PasswordCipherFunc newCipherFunc,
    required PasswordCipherFunc oldCipherFunc,
  });

  /// Configures the secure mnemonic provider with biometric settings.
  ///
  /// This must be called once at application startup before any biometric
  /// operations. Sets up prompts and platform-specific biometric configuration.
  Future<void> configureSecureMnemonic(BiometricConfig config);

  /// Enable biometric authentication (requires password confirmation)
  /// This method handles key generation and storage update.
  Future<void> setupBiometry({
    required BioCipherFunc bioCipherFunc,
    required PasswordCipherFunc passwordCipherFunc,
  });

  /// Disable biometric authentication (requires password confirmation)
  /// This method handles storage update and key deletion.
  Future<void> teardownBiometry({
    required BioCipherFunc bioCipherFunc,
    required PasswordCipherFunc passwordCipherFunc,
  });

  /// Updates the lock timeout.
  ///
  /// Requires a [cipherFunc] to authorize.
  Future<void> updateLockTimeout({
    required Duration lockTimeout,
    required CipherFunc cipherFunc,
  });

  /// Determines the biometric state.
  ///
  /// Returns the [BiometricState] state.
  Future<BiometricState> determineBiometricState();

  /// Completely erases all data from the storage.
  ///
  /// This operation is irreversible: it deletes all entries,
  /// clears cached metadata, and transitions the locker to the locked state.
  ///
  /// Throws [StateError] if erasure fails.
  Future<void> eraseStorage();

  /// Closes the locker state stream controller and clears all cached data.
  ///
  /// After calling this, no further operations should be performed.
  void dispose();
}
