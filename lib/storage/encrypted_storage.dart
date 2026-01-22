import 'dart:core';
import 'dart:typed_data';

import 'package:locker/security/models/cipher_func.dart';
import 'package:locker/security/models/password_cipher_func.dart';
import 'package:locker/storage/models/data/origin.dart';
import 'package:locker/storage/models/domain/entry_id.dart';
import 'package:locker/storage/models/domain/entry_meta.dart';
import 'package:locker/storage/models/domain/entry_value.dart';
import 'package:locker/storage/models/exceptions/storage_exception.dart';
import 'package:meta/meta.dart';

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
  Future<bool> get isBiometricEnabled;

  /// The salt used for PBKDF2 key derivation.
  Future<Uint8List?> get salt;

  /// The lock timeout in milliseconds.
  Future<int?> get lockTimeout;

  /// Initializes the storage with a initial record.
  ///
  /// For storage initialization, only password authentication is supported.
  ///
  /// [passwordCipherFunc] - Cipher function to encrypt the master key.
  /// [initialEntryMeta] - Metadata for the initial entry.
  /// [initialEntryValue] - Value for the initial entry.
  /// [lockTimeout] - The auto-lock timeout in milliseconds. Must be greater than 0.
  ///
  /// Throws [StorageException] if the lock timeout is not greater than 0.
  /// Throws [StorageException] if the storage is already initialized.
  Future<void> init({
    required PasswordCipherFunc passwordCipherFunc,
    required EntryMeta initialEntryMeta,
    required EntryValue initialEntryValue,
    required int lockTimeout,
  });

  /// Adds an additional authentication method or replaces an existing one.
  ///
  /// Creates a new wrap for the master key using [newWrapFunc], allowing
  /// the storage to be unlocked with an additional authentication method
  /// (e.g., biometrics).
  ///
  /// [existingWrapFunc] - Existing wrap function to decrypt the master key.
  ///
  Future<void> addOrReplaceWrap({
    required CipherFunc newWrapFunc,
    required CipherFunc existingWrapFunc,
  });

  /// Removes an authentication method.
  ///
  /// [originToDelete] - The origin of the wrap to delete.
  /// [cipherFunc] - Cipher function to decrypt the master key.
  Future<bool> deleteWrap({
    required Origin originToDelete,
    required CipherFunc cipherFunc,
  });

  /// Deletes an entry by its id.
  ///
  /// [id] - The id of the entry to delete.
  /// [cipherFunc] - Cipher function to decrypt the master key.
  Future<bool> deleteEntry({
    required EntryId id,
    required CipherFunc cipherFunc,
  });

  /// Adds an entry to the storage.
  ///
  /// [entryMeta] - Metadata for the entry.
  /// [entryValue] - Value for the entry.
  /// [cipherFunc] - Cipher function to decrypt the master key.
  ///
  /// Returns the id of the added entry.
  Future<EntryId> addEntry({
    required EntryMeta entryMeta,
    required EntryValue entryValue,
    required CipherFunc cipherFunc,
  });

  /// Updates an entry by its id.
  ///
  /// [id] - The id of the entry to update.
  /// [cipherFunc] - The cipher function to decrypt the master key.
  /// [entryMeta] -  New metadata for the entry.
  /// [entryValue] - New value for the entry.
  ///
  /// At least one of [entryMeta] or [entryValue] must be provided, otherwise throws [StorageException].
  ///
  /// Throws [StorageException] if no entry was found.
  Future<void> updateEntry({
    required EntryId id,
    required CipherFunc cipherFunc,
    EntryMeta? entryMeta,
    EntryValue? entryValue,
  });

  /// Retrieves and decrypts all entries metadata and maps them to their ids.
  ///
  /// Requires [cipherFunc] to decrypt the master key.
  Future<Map<EntryId, EntryMeta>> readAllMeta({
    required CipherFunc cipherFunc,
  });

  /// Retrieves and decrypts an entry value by id.
  ///
  /// [id] - The id of the entry to retrieve.
  /// [cipherFunc] - Cipher function to decrypt the master key.
  ///
  /// Throws [StorageException] if the entry is not found.
  Future<EntryValue> readValue({
    required EntryId id,
    required CipherFunc cipherFunc,
  });

  /// Updates the storage lock timeout value.
  ///
  /// [lockTimeout] - The new lock timeout in milliseconds. Must be greater than 0.
  /// [cipherFunc] - Cipher function to decrypt the master key.
  ///
  Future<void> updateLockTimeout({
    required int lockTimeout,
    required CipherFunc cipherFunc,
  });

  /// Completely erases all storage data.
  ///
  /// Deletes the storage file.
  Future<bool> erase();

  /// Outputs diagnostic information about the storage.
  ///
  /// Logs information such as file existence, size, and modification time
  /// for debugging purposes.
  @visibleForTesting
  Future<void> printDebugInfo();
}
