import 'package:locker/erasable/erasable.dart';
import 'package:locker/storage/models/domain/entry_add_input.dart';
import 'package:locker/storage/models/domain/entry_id.dart';
import 'package:locker/storage/models/domain/entry_update_input.dart';
import 'package:locker/storage/models/domain/entry_value.dart';

/// A handle to a scoped vault transaction.
///
/// Created by `Locker.beginTransaction`. The underlying master key is unwrapped
/// exactly once at creation (for biometrics this is the single system prompt)
/// and reused by all operations, so any number of [readValue] / [write] /
/// [update] / [delete] calls run without further authentication.
///
/// The transaction MUST be closed via [close] (preferably in a `finally`
/// block) to erase the key material. After [close] every method throws a
/// [StateError].
abstract interface class LockerTransaction implements Erasable {
  /// Whether the transaction has been closed (or its keys erased).
  bool get isClosed;

  /// Reads the value of the entry identified by [id].
  ///
  /// Throws StorageException if the entry does not exist.
  Future<EntryValue> readValue(EntryId id);

  /// Adds a new entry and returns its id.
  ///
  /// Throws StorageException if [input.id] is provided and already exists.
  Future<EntryId> write(EntryAddInput input);

  /// Updates an existing entry by id.
  ///
  /// Throws StorageException if the entry does not exist or both [input.meta]
  /// and [input.value] are null.
  Future<void> update(EntryUpdateInput input);

  /// Deletes the entry identified by [id]. Has no effect if it does not exist.
  Future<void> delete(EntryId id);

  /// Erases the key material and releases the transaction.
  ///
  /// Safe to call multiple times. After this call the transaction is closed.
  Future<void> close();
}
