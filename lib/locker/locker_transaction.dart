import 'package:locker/erasable/erasable.dart';
import 'package:locker/storage/models/domain/entry_add_input.dart';
import 'package:locker/storage/models/domain/entry_id.dart';
import 'package:locker/storage/models/domain/entry_update_input.dart';
import 'package:locker/storage/models/domain/entry_value.dart';

/// A scoped vault transaction: the master key is unwrapped once (a single
/// biometric prompt) and reused by every operation. Must be closed via
/// [close]; after that every method throws a [StateError].
abstract interface class LockerTransaction implements Erasable {
  /// Whether the transaction has been closed.
  bool get isClosed;

  Future<EntryValue> readValue(EntryId id);

  Future<EntryId> write(EntryAddInput input);

  Future<void> update(EntryUpdateInput input);

  Future<void> delete(EntryId id);

  /// Erases the key material and releases the transaction.
  Future<void> close();
}
