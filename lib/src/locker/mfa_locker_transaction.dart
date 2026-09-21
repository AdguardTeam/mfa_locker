import 'dart:collection';

import 'package:locker/locker/locker_transaction.dart';
import 'package:locker/security/models/cipher_func.dart';
import 'package:locker/src/locker/erase_after.dart';
import 'package:locker/src/locker/transaction_result.dart';
import 'package:locker/storage/models/data/origin.dart';
import 'package:locker/storage/models/domain/entry_add_input.dart';
import 'package:locker/storage/models/domain/entry_id.dart';
import 'package:locker/storage/models/domain/entry_meta.dart';
import 'package:locker/storage/models/domain/entry_update_input.dart';
import 'package:locker/storage/models/domain/entry_value.dart';
import 'package:locker/storage/models/exceptions/storage_exception.dart';
import 'package:locker/storage/storage_transaction.dart';

/// In-memory buffer for one `withTransaction` body: entry operations go to a
/// [StorageTransaction]; metadata changes accumulate in an overlay that the
/// locker publishes on commit via [finalize].
///
/// Holds **no** reference to the locker: the locker owns the lifecycle
/// (open/commit/abort/lane/cache), the transaction owns only the buffer.
class MfaLockerTransaction implements LockerTransaction {
  /// Working copy of the storage; committed atomically by the locker on close.
  final StorageTransaction storageTransaction;

  /// Snapshot of the committed metadata at open; stable for the whole body
  /// because the transaction holds the lane (nothing commits meanwhile).
  final Map<EntryId, EntryMeta> _committed;

  final Map<EntryId, EntryMeta> _pendingMeta = {};

  final Set<EntryId> _deletedIds = {};

  bool _closed = false;

  MfaLockerTransaction(this.storageTransaction, this._committed);

  bool get isClosed => _closed;

  void close() => _closed = true;

  @override
  Map<EntryId, EntryMeta> get allMeta {
    _ensureOpen();

    return UnmodifiableMapView(_mergedMeta(_committed));
  }

  @override
  Future<EntryValue> readValue(EntryId id) async {
    _ensureOpen();

    return storageTransaction.readValue(id);
  }

  @override
  Future<EntryId> write(EntryAddInput input) => eraseAfter<EntryId>(
        // Erase meta on error only: on success the overlay owns it.
        erasables: [input.value],
        erasablesOnError: [input.meta],
        callback: () => writeBuffered(input),
      );

  /// [write] without erasing the input: the caller (a one-shot method or the
  /// public [write] boundary) is responsible for the single erase.
  Future<EntryId> writeBuffered(EntryAddInput input) async {
    _ensureOpen();

    final entryId = await storageTransaction.addEntry(input);

    _deletedIds.remove(entryId);
    _pendingMeta[entryId] = input.meta;

    return entryId;
  }

  @override
  Future<void> update(EntryUpdateInput input) => eraseAfter(
        // Erase meta on error only: on success the overlay owns it.
        erasables: [if (input.value != null) input.value!],
        erasablesOnError: [if (input.meta != null) input.meta!],
        callback: () => updateBuffered(input),
      );

  /// [update] without erasing the input (single erase owned by the caller).
  Future<void> updateBuffered(EntryUpdateInput input) async {
    _ensureOpen();

    await storageTransaction.updateEntry(input);

    final meta = input.meta;
    if (meta != null) {
      _pendingMeta.remove(input.id)?.erase();
      _pendingMeta[input.id] = meta;
      _deletedIds.remove(input.id);
    }
  }

  @override
  Future<void> delete(EntryId id) async {
    _ensureOpen();

    try {
      await storageTransaction.deleteEntry(id);
    } on StorageException catch (error) {
      // The entry is already absent in storage - treat delete as an
      // idempotent success and fall through to reconcile the overlay.
      if (error.type != StorageExceptionType.entryNotFound) {
        rethrow;
      }
    }

    _pendingMeta.remove(id)?.erase();
    _deletedIds.add(id);
  }

  @override
  Future<void> updateLockTimeout(Duration lockTimeout) async {
    _ensureOpen();

    await storageTransaction.updateLockTimeout(lockTimeout.inMilliseconds);
  }

  @override
  Future<void> addOrReplaceWrap({required CipherFunc newWrapFunc}) async {
    _ensureOpen();

    await storageTransaction.addOrReplaceWrap(newWrapFunc: newWrapFunc);
  }

  @override
  Future<void> deleteWrap({required Origin originToDelete}) async {
    _ensureOpen();

    await storageTransaction.deleteWrap(originToDelete: originToDelete);
  }

  /// The uncommitted metadata for the locker to publish into its cache.
  TransactionResult finalize() => TransactionResult(pendingMeta: _pendingMeta, deletedIds: _deletedIds);

  /// Erases the uncommitted metadata on abort or a failed commit.
  void eraseOverlay() {
    for (final meta in _pendingMeta.values) {
      meta.erase();
    }

    _pendingMeta.clear();
    _deletedIds.clear();
  }

  /// [committed] metadata merged with the uncommitted changes of this
  /// transaction. The values are not copied; the caller must not erase them.
  Map<EntryId, EntryMeta> _mergedMeta(Map<EntryId, EntryMeta> committed) {
    final result = Map<EntryId, EntryMeta>.of(committed);
    for (final id in _deletedIds) {
      result.remove(id);
    }
    result.addAll(_pendingMeta);

    return result;
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('Transaction is closed');
    }
  }
}
