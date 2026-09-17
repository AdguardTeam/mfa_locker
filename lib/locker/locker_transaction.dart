import 'package:locker/security/models/cipher_func.dart';
import 'package:locker/storage/models/data/origin.dart';
import 'package:locker/storage/models/domain/entry_add_input.dart';
import 'package:locker/storage/models/domain/entry_id.dart';
import 'package:locker/storage/models/domain/entry_meta.dart';
import 'package:locker/storage/models/domain/entry_update_input.dart';
import 'package:locker/storage/models/domain/entry_value.dart';

/// Vault operations available inside a `withTransaction` body. The transaction
/// lives strictly within the body (commits on return, aborts on throw); after
/// the body every method throws a [StateError].
abstract interface class LockerTransaction {
  /// Committed metadata merged with this transaction's uncommitted changes;
  /// the returned values are owned by the locker, do not erase.
  Map<EntryId, EntryMeta> get allMeta;

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
