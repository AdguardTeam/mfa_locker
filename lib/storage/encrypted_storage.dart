import 'dart:core';
import 'dart:typed_data';

import 'package:locker/security/models/cipher_func.dart';
import 'package:locker/security/models/password_cipher_func.dart';
import 'package:locker/storage/models/domain/entry_add_input.dart';
import 'package:locker/storage/storage_transaction.dart';

/// File-backed encrypted storage; all mutations go through a
/// [StorageTransaction] and are persisted atomically on close.
abstract interface class EncryptedStorage {
  /// Whether the storage file exists and contains valid data.
  Future<bool> get isInitialized;

  /// Whether biometric authentication is enabled (`false` when not initialized).
  Future<bool> get isBiometricEnabled;

  /// The salt used for key derivation.
  Future<Uint8List> get salt;

  /// The lock timeout in milliseconds.
  Future<int> get lockTimeout;

  /// Initializes the storage with the given password wrap and entries; only
  /// password authentication is supported here.
  ///
  /// Throws if already initialized or [lockTimeout] is not positive.
  Future<void> init({
    required PasswordCipherFunc passwordCipherFunc,
    required List<EntryAddInput> initialEntries,
    required int lockTimeout,
  });

  /// Opens a transaction: unwraps the master key via [cipherFunc] and snapshots
  /// the data for the compare-and-swap on close.
  Future<StorageTransaction> openTransaction({
    required CipherFunc cipherFunc,
  });

  /// Persists [transaction] atomically (nothing is written without mutations);
  /// throws [StorageException.conflict] if the file changed since it was opened.
  Future<void> closeTransaction(StorageTransaction transaction);

  /// Deletes the storage file.
  Future<void> erase();
}
