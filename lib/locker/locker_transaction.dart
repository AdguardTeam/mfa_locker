import 'package:locker/erasable/erasable.dart';
import 'package:locker/security/models/cipher_func.dart';
import 'package:locker/storage/models/data/origin.dart';
import 'package:locker/storage/models/domain/entry_add_input.dart';
import 'package:locker/storage/models/domain/entry_id.dart';
import 'package:locker/storage/models/domain/entry_meta.dart';
import 'package:locker/storage/models/domain/entry_update_input.dart';
import 'package:locker/storage/models/domain/entry_value.dart';

/// A scoped vault transaction: master key unwrapped once (single biometric
/// prompt), changes buffered and persisted atomically by [commit] or dropped
/// by [abort]. After closing every method throws a [StateError].
abstract interface class LockerTransaction implements Erasable {
  /// Whether the transaction has been closed.
  bool get isClosed;

  /// Committed entry metadata merged with the uncommitted changes of this
  /// transaction. Valid while the transaction is open; the returned maps and
  /// their metadata are owned by the locker and must not be erased by callers.
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

  /// Persists all buffered changes atomically (one write) and closes the
  /// transaction, erasing the key material.
  Future<void> commit();

  /// Discards all buffered changes and closes the transaction, erasing the
  /// key material.
  Future<void> abort();
}
