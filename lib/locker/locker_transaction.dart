import 'package:locker/erasable/erasable.dart';
import 'package:locker/storage/models/domain/entry_add_input.dart';
import 'package:locker/storage/models/domain/entry_id.dart';
import 'package:locker/storage/models/domain/entry_update_input.dart';
import 'package:locker/storage/models/domain/entry_value.dart';

/// A scoped vault transaction: master key unwrapped once (single biometric
/// prompt), changes buffered and persisted atomically by [commit] or dropped
/// by [abort]. After closing every method throws a [StateError].
abstract interface class LockerTransaction implements Erasable {
  /// Whether the transaction has been closed.
  bool get isClosed;

  Future<EntryValue> readValue(EntryId id);

  Future<EntryId> write(EntryAddInput input);

  Future<void> update(EntryUpdateInput input);

  Future<void> delete(EntryId id);

  /// Persists all buffered changes atomically (one write) and closes the
  /// transaction, erasing the key material.
  Future<void> commit();

  /// Discards all buffered changes and closes the transaction, erasing the
  /// key material.
  Future<void> abort();
}
