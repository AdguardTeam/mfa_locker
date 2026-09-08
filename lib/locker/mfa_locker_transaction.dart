part of 'mfa_locker.dart';

/// Concrete [LockerTransaction] held by [MFALocker]. Buffers operations in a
/// [StorageChangeSet] and refreshes the metadata cache like the one-shot paths.
class _MfaLockerTransaction implements LockerTransaction {
  final MFALocker _locker;
  final StorageChangeSet _changeSet;
  bool _closed = false;

  _MfaLockerTransaction._(this._locker, this._changeSet);

  @override
  bool get isClosed => _closed;

  @override
  bool get isErased => _changeSet.isErased;

  void _ensureOpen() {
    if (_closed) {
      throw StateError('Transaction is closed');
    }
  }

  @override
  Future<EntryValue> readValue(EntryId id) async {
    _ensureOpen();

    return _changeSet.readValue(id);
  }

  @override
  Future<EntryId> write(EntryAddInput input) => _locker._executeWithCleanup<EntryId>(
        // dispose input.meta only on error because it is cached
        erasables: [input.value],
        erasablesOnError: [input.meta],
        callback: () async {
          _ensureOpen();

          final entryId = await _changeSet.addEntry(input);

          _locker._metaCache[entryId]?.erase();
          _locker._metaCache[entryId] = input.meta;

          return entryId;
        },
      );

  @override
  Future<void> update(EntryUpdateInput input) => _locker._executeWithCleanup(
        // dispose input.meta only on error because it is cached
        erasables: [if (input.value != null) input.value!],
        erasablesOnError: [if (input.meta != null) input.meta!],
        callback: () async {
          _ensureOpen();

          await _changeSet.updateEntry(input);

          final meta = input.meta;
          if (meta != null) {
            _locker._metaCache[input.id]?.erase();
            _locker._metaCache[input.id] = meta;
          }
        },
      );

  @override
  Future<void> delete(EntryId id) async {
    _ensureOpen();

    try {
      await _changeSet.deleteEntry(id);
    } on StorageException catch (error) {
      // The entry is already absent in storage - treat delete as an
      // idempotent success and fall through to reconcile the cache.
      if (error.type != StorageExceptionType.entryNotFound) {
        rethrow;
      }
    }

    final removedMeta = _locker._metaCache.remove(id);
    removedMeta?.erase();
  }

  @override
  Future<void> commit() async {
    _ensureOpen();

    try {
      await _locker._storage.commitChangeSet(_changeSet);
    } finally {
      _detachAndErase();
    }
  }

  @override
  Future<void> abort() async {
    _ensureOpen();
    _detachAndErase();
  }

  @override
  void erase() => _detachAndErase();

  /// Marks the transaction closed and erases the key, releasing the gate.
  void _detachAndErase() {
    if (_closed) {
      return;
    }

    _closed = true;
    _changeSet.erase();
    _locker._releaseTransactionGate();
    if (identical(_locker._activeTransaction, this)) {
      _locker._activeTransaction = null;
    }
  }
}
