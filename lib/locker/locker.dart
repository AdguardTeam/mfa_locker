import 'dart:async';
import 'dart:typed_data';

import 'package:locker/locker/locker_transaction.dart';
import 'package:locker/locker/models/biometric_state.dart';
import 'package:locker/security/models/bio_cipher_func.dart';
import 'package:locker/security/models/biometric_config.dart';
import 'package:locker/security/models/cipher_func.dart';
import 'package:locker/security/models/password_cipher_func.dart';
import 'package:locker/storage/models/domain/entry_add_input.dart';
import 'package:locker/storage/models/domain/entry_id.dart';
import 'package:locker/storage/models/domain/entry_meta.dart';
import 'package:locker/storage/models/domain/entry_update_input.dart';
import 'package:locker/storage/models/domain/entry_value.dart';
import 'package:rxdart/rxdart.dart';

enum LockerState {
  locked,
  unlocked,
}

/// Encrypted key-value storage with lock/unlock, password rotation and
/// biometric support; locked methods unlock via the provided [CipherFunc].
abstract interface class Locker {
  ValueStream<LockerState> get stateStream;

  /// The storage salt; throws [StorageException] if not initialized.
  Future<Uint8List> get salt;

  Future<bool> get isStorageInitialized;

  Future<Duration> get lockTimeout;

  Future<bool> get isBiometricEnabled;

  /// All committed metadata (cleared on lock/dispose); an open `withTransaction`
  /// body appears here after it commits. Throws [LockerException] when not unlocked.
  Map<EntryId, EntryMeta> get allMeta;

  /// Initializes the storage with [passwordCipherFunc] and [initialEntries], then
  /// unlocks; throws [LockerException] on a bad timeout, [StorageException] if already initialized.
  Future<void> init({
    required PasswordCipherFunc passwordCipherFunc,
    required List<EntryAddInput> initialEntries,
    required Duration lockTimeout,
  });

  /// Unlocks (if locked) and loads all entry metadata; throws
  /// [StorageException] if the storage is not initialized.
  Future<void> loadAllMeta(CipherFunc cipherFunc);

  /// Runs [body] in one transaction: a single key unwrap, atomic persist on
  /// return, abort on throw. Use only [LockerTransaction] methods inside.
  Future<R> withTransaction<R>(
    CipherFunc cipherFunc,
    Future<R> Function(LockerTransaction txn) body,
  );

  /// Clears all cached data.
  void lock();

  /// Writes a new entry and returns its id; throws [StorageException] if
  /// [input.id] already exists.
  Future<EntryId> write({
    required EntryAddInput input,
    required CipherFunc cipherFunc,
  });

  /// Reads an entry value by id, unlocking if needed.
  Future<EntryValue> readValue({
    required EntryId id,
    required CipherFunc cipherFunc,
  });

  /// Deletes an entry by id (no-op if the entry does not exist).
  Future<void> delete({
    required EntryId id,
    required CipherFunc cipherFunc,
  });

  /// Updates an entry; at least one of [input.meta]/[input.value] is required.
  Future<void> update({
    required EntryUpdateInput input,
    required CipherFunc cipherFunc,
  });

  Future<void> changePassword({
    required PasswordCipherFunc newCipherFunc,
    required CipherFunc existingCipherFunc,
  });

  /// Call once at application startup.
  Future<void> configureBiometricCipher(BiometricConfig config);

  /// Enables biometric authentication (requires password confirmation).
  Future<void> setupBiometry({
    required BioCipherFunc bioCipherFunc,
    required PasswordCipherFunc passwordCipherFunc,
  });

  /// Disables biometrics; deletes the hardware key if [biometricKeyTag] is
  /// given (best-effort, errors suppressed).
  Future<void> teardownBiometry({
    required PasswordCipherFunc passwordCipherFunc,
    String? biometricKeyTag,
  });

  /// Updates the auto-lock timeout; throws [LockerException] if it is not positive.
  Future<void> updateLockTimeout({
    required Duration lockTimeout,
    required CipherFunc cipherFunc,
  });

  /// Determines the biometric state. With [biometricKeyTag] silently checks
  /// key validity and returns [BiometricState.keyInvalidated] (no prompt).
  Future<BiometricState> determineBiometricState({String? biometricKeyTag});

  /// Irreversibly erases all data and transitions to the locked state.
  Future<void> eraseStorage();

  /// Closes the state stream and clears cached data; no operations afterwards.
  void dispose();
}
