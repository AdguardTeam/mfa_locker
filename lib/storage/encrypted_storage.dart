import 'dart:core';
import 'dart:typed_data';

import 'package:locker/security/models/cipher_func.dart';
import 'package:locker/security/models/password_cipher_func.dart';
import 'package:locker/storage/models/data/origin.dart';
import 'package:locker/storage/models/domain/entry_add_input.dart';
import 'package:locker/storage/models/domain/entry_id.dart';
import 'package:locker/storage/models/domain/entry_meta.dart';
import 'package:locker/storage/models/domain/entry_update_input.dart';
import 'package:locker/storage/models/domain/entry_value.dart';
import 'package:locker/storage/models/exceptions/storage_exception.dart';
import 'package:locker/storage/models/unlocked_keys.dart';

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

  /// Unwraps the master key using [cipherFunc].
  ///
  /// This is the single authentication point of the storage: for biometrics it
  /// triggers exactly one system prompt. The returned [UnlockedKeys] is reused
  /// by the `*WithKeys` methods so a sequence of operations performs a single
  /// authentication.
  ///
  /// The caller is responsible for erasing the returned [UnlockedKeys] when no
  /// longer needed.
  ///
  /// Throws [StorageException] if the storage is not initialized, the HMAC is
  /// invalid, or authentication fails.
  Future<UnlockedKeys> unlockKeys({
    required CipherFunc cipherFunc,
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
  Future<void> deleteWrap({
    required Origin originToDelete,
    required CipherFunc cipherFunc,
  });

  /// Deletes an entry by its id.
  ///
  /// [id] - The id of the entry to delete.
  /// [cipherFunc] - Cipher function to decrypt the master key.
  Future<void> deleteEntry({
    required EntryId id,
    required CipherFunc cipherFunc,
  });

  /// Like [deleteEntry] but reuses an already-unwrapped master key ([keys]).
  ///
  /// Requires [keys] returned by [unlockKeys]; no authentication is performed.
  Future<void> deleteEntryWithKeys({
    required EntryId id,
    required UnlockedKeys keys,
  });

  /// Adds an entry to the storage.
  ///
  /// [input] - Entry data (meta, value, optional fixed ID). When [input.id] is
  /// provided, a duplicate check is performed.
  /// [cipherFunc] - Cipher function to decrypt the master key.
  ///
  /// Returns the id of the added entry.
  ///
  /// Throws [StorageException] if [input.id] is provided and already exists.
  Future<EntryId> addEntry({
    required EntryAddInput input,
    required CipherFunc cipherFunc,
  });

  /// Like [addEntry] but reuses an already-unwrapped master key ([keys]).
  ///
  /// Requires [keys] returned by [unlockKeys]; no authentication is performed.
  Future<EntryId> addEntryWithKeys({
    required EntryAddInput input,
    required UnlockedKeys keys,
  });

  /// Updates an entry by its id.
  ///
  /// [input] - Update data (id, optional meta, optional value). At least one of
  /// [input.meta] or [input.value] must be non-null, otherwise throws [StorageException].
  /// [cipherFunc] - The cipher function to decrypt the master key.
  ///
  /// Throws [StorageException] if no entry was found.
  Future<void> updateEntry({
    required EntryUpdateInput input,
    required CipherFunc cipherFunc,
  });

  /// Like [updateEntry] but reuses an already-unwrapped master key ([keys]).
  ///
  /// Requires [keys] returned by [unlockKeys]; no authentication is performed.
  Future<void> updateEntryWithKeys({
    required EntryUpdateInput input,
    required UnlockedKeys keys,
  });

  /// Retrieves and decrypts all entries metadata and maps them to their ids.
  ///
  /// Requires [cipherFunc] to decrypt the master key.
  Future<Map<EntryId, EntryMeta>> readAllMeta({
    required CipherFunc cipherFunc,
  });

  /// Like [readAllMeta] but reuses an already-unwrapped master key ([keys]).
  ///
  /// Requires [keys] returned by [unlockKeys]; no authentication is performed.
  Future<Map<EntryId, EntryMeta>> readAllMetaWithKeys(UnlockedKeys keys);

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

  /// Like [readValue] but reuses an already-unwrapped master key ([keys]).
  ///
  /// Requires [keys] returned by [unlockKeys]; no authentication is performed.
  Future<EntryValue> readValueWithKeys({
    required EntryId id,
    required UnlockedKeys keys,
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
  /// Deletes the storage file. Throws if file deletion fails.
  Future<void> erase();
}
