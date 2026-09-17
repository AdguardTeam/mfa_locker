import 'dart:typed_data';

import 'package:locker/security/models/cipher_func.dart';
import 'package:locker/security/models/password_cipher_func.dart';
import 'package:locker/storage/encrypted_storage.dart';
import 'package:locker/storage/models/data/origin.dart';
import 'package:locker/storage/models/domain/entry_add_input.dart';
import 'package:locker/storage/models/domain/entry_id.dart';
import 'package:locker/storage/models/domain/entry_meta.dart';
import 'package:locker/storage/models/domain/entry_update_input.dart';
import 'package:locker/storage/models/domain/entry_value.dart';
import 'package:locker/storage/storage_transaction.dart';

/// Test helper that performs a storage operation the way the locker does it for
/// a single public call: open a transaction, apply one operation and commit it
/// (open → mutate → commit). A commit without mutations writes nothing.
///
/// The storage itself no longer exposes one-shot methods: every mutation goes
/// through [StorageTransaction].
class OneShotStorage {
  final EncryptedStorage _storage;

  OneShotStorage(this._storage);

  Future<bool> get isInitialized => _storage.isInitialized;

  Future<bool> get isBiometricEnabled => _storage.isBiometricEnabled;

  Future<Uint8List> get salt => _storage.salt;

  Future<int> get lockTimeout => _storage.lockTimeout;

  Future<void> init({
    required PasswordCipherFunc passwordCipherFunc,
    required List<EntryAddInput> initialEntries,
    required int lockTimeout,
  }) =>
      _storage.init(
        passwordCipherFunc: passwordCipherFunc,
        initialEntries: initialEntries,
        lockTimeout: lockTimeout,
      );

  Future<void> erase() => _storage.erase();

  Future<StorageTransaction> openTransaction({required CipherFunc cipherFunc}) =>
      _storage.openTransaction(cipherFunc: cipherFunc);

  Future<void> closeTransaction(StorageTransaction transaction) => _storage.closeTransaction(transaction);

  /// Runs [operation] over a fresh transaction and closes it.
  Future<T> run<T>(CipherFunc cipherFunc, Future<T> Function(StorageTransaction transaction) operation) async {
    final transaction = await _storage.openTransaction(cipherFunc: cipherFunc);

    try {
      final result = await operation(transaction);
      await _storage.closeTransaction(transaction);

      return result;
    } finally {
      transaction.erase();
    }
  }

  Future<EntryId> addEntry({required EntryAddInput input, required CipherFunc cipherFunc}) =>
      run(cipherFunc, (transaction) => transaction.addEntry(input));

  Future<void> updateEntry({required EntryUpdateInput input, required CipherFunc cipherFunc}) =>
      run(cipherFunc, (transaction) => transaction.updateEntry(input));

  Future<void> deleteEntry({required EntryId id, required CipherFunc cipherFunc}) =>
      run(cipherFunc, (transaction) => transaction.deleteEntry(id));

  Future<EntryValue> readValue({required EntryId id, required CipherFunc cipherFunc}) =>
      run(cipherFunc, (transaction) => transaction.readValue(id));

  Future<Map<EntryId, EntryMeta>> readAllMeta({required CipherFunc cipherFunc}) =>
      run(cipherFunc, (transaction) => transaction.readAllMeta());

  Future<void> addOrReplaceWrap({
    required CipherFunc newWrapFunc,
    required CipherFunc existingWrapFunc,
  }) =>
      run(existingWrapFunc, (transaction) => transaction.addOrReplaceWrap(newWrapFunc: newWrapFunc));

  Future<void> deleteWrap({required Origin originToDelete, required CipherFunc cipherFunc}) =>
      run(cipherFunc, (transaction) => transaction.deleteWrap(originToDelete: originToDelete));

  Future<void> updateLockTimeout({required int lockTimeout, required CipherFunc cipherFunc}) =>
      run(cipherFunc, (transaction) => transaction.updateLockTimeout(lockTimeout));
}
