import 'package:locker/security/models/cipher_func.dart';
import 'package:locker/storage/models/data/origin.dart';
import 'package:locker/storage/models/domain/entry_add_input.dart';
import 'package:locker/storage/models/domain/entry_id.dart';
import 'package:locker/storage/models/domain/entry_update_input.dart';
import 'package:locker/storage/models/domain/entry_value.dart';

/// Vault operations available inside a `withTransaction` body; after the body
/// every method throws [LockerException.transactionClosed].
abstract interface class LockerTransaction {
  Future<EntryValue> readValue(EntryId id);

  Future<EntryId> write(EntryAddInput input);

  Future<void> update(EntryUpdateInput input);

  Future<void> delete(EntryId id);

  /// Updates the auto-lock timeout of the storage.
  Future<void> updateLockTimeout(Duration lockTimeout);

  /// Adds a new wrap for the master key or replaces the existing wrap of the
  /// same origin (password change, enabling biometrics).
  Future<void> addOrReplaceWrap({required CipherFunc newWrapFunc});

  /// Removes the wrap of [originToDelete] (disabling biometrics).
  Future<void> deleteWrap({required Origin originToDelete});
}
