import 'dart:core';
import 'dart:typed_data';

import 'package:locker/security/models/cipher_func.dart';
import 'package:locker/security/models/password_cipher_func.dart';
import 'package:locker/storage/models/domain/entry_add_input.dart';
import 'package:locker/storage/storage_change_set.dart';

/// Interface for encrypted storage that manages secure data.
///
/// Provides methods for initializing storage, managing authentication methods,
/// and performing CRUD operations on encrypted entries.
abstract interface class EncryptedStorage {
  /// Whether the storage has been initialized.
  ///
  /// Storage is considered initialized when the storage file exists and contains valid data.
  Future<bool> get isInitialized;

  /// Whether biometric authentication is enabled.
  ///
  /// Returns `false` if the storage is not yet initialized.
  /// Throws [StorageException] for any other storage failure (e.g. a corrupted file).
  Future<bool> get isBiometricEnabled;

  /// The salt used for key derivation.
  ///
  /// Throws [StorageException] if the storage is not initialized.
  Future<Uint8List> get salt;

  /// The lock timeout in milliseconds.
  ///
  /// Throws [StorageException] if the storage is not initialized.
  Future<int> get lockTimeout;

  /// Initializes the storage with optional initial entries.
  ///
  /// For storage initialization, only password authentication is supported.
  ///
  /// [passwordCipherFunc] - Cipher function to encrypt the master key.
  /// [initialEntries] - Entries to store during initialization. May be empty.
  /// [lockTimeout] - The auto-lock timeout in milliseconds. Must be greater than 0.
  ///
  /// Throws [StorageException] if the lock timeout is not greater than 0.
  /// Throws [StorageException] if the storage is already initialized.
  /// Throws [StorageException] if duplicate explicit IDs are found in [initialEntries].
  Future<void> init({
    required PasswordCipherFunc passwordCipherFunc,
    required List<EntryAddInput> initialEntries,
    required int lockTimeout,
  });

  /// Opens a change set: reads the storage, unwraps the master key via
  /// [cipherFunc] and snapshots the data for the compare-and-swap on commit.
  Future<StorageChangeSet> openChangeSet({
    required CipherFunc cipherFunc,
  });

  /// Persists [changeSet] atomically (nothing is written without mutations);
  /// throws [StorageException.conflict] if the file changed since it was opened.
  Future<void> commitChangeSet(StorageChangeSet changeSet);

  /// Completely erases all storage data.
  ///
  /// Deletes the storage file. Throws if file deletion fails.
  Future<void> erase();
}
