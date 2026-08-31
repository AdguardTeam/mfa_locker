part of 'mfa_locker.dart';

/// Concrete [LockerTransaction] held by [MFALocker].
///
/// Runs all operations under the owning locker's reentrant lock so they
/// serialize with regular one-shot methods, and refreshes the metadata cache
/// exactly like the one-shot paths.
class _MfaLockerTransaction implements LockerTransaction {
  final MFALocker _locker;
  final UnlockedKeys _keys;
  bool _closed = false;

  _MfaLockerTransaction._(this._locker, this._keys);

  @override
  bool get isClosed => _closed;

  @override
  bool get isErased => _keys.isErased;

  void _ensureOpen() {
    if (_closed) {
      throw StateError('Transaction is closed');
    }
  }

  @override
  Future<EntryValue> readValue(EntryId id) => _locker._sync(() async {
        _ensureOpen();

        return _locker._storage.readValueWithKeys(id: id, keys: _keys);
      });

  @override
  Future<EntryId> write(EntryAddInput input) => _locker._sync(() async {
        _ensureOpen();

        final entryId = await _locker._storage.addEntryWithKeys(
          input: input,
          keys: _keys,
        );

        _locker._metaCache[entryId]?.erase();
        _locker._metaCache[entryId] = input.meta;

        return entryId;
      });

  @override
  Future<void> update(EntryUpdateInput input) => _locker._sync(() async {
        _ensureOpen();

        await _locker._storage.updateEntryWithKeys(
          input: input,
          keys: _keys,
        );

        final meta = input.meta;
        if (meta != null) {
          _locker._metaCache[input.id]?.erase();
          _locker._metaCache[input.id] = meta;
        }
      });

  @override
  Future<void> delete(EntryId id) => _locker._sync(() async {
        _ensureOpen();

        try {
          await _locker._storage.deleteEntryWithKeys(id: id, keys: _keys);
        } on StorageException catch (error) {
          // The entry is already absent in storage - treat delete as an
          // idempotent success and fall through to reconcile the cache.
          if (error.type != StorageExceptionType.entryNotFound) {
            rethrow;
          }
        }

        final removedMeta = _locker._metaCache.remove(id);
        removedMeta?.erase();
      });

  @override
  Future<void> close() => _locker._sync(() async => _detachAndErase());

  @override
  void erase() => _detachAndErase();

  /// Marks the transaction closed and erases the key material in place,
  /// without awaiting the locker lock (used by [MFALocker.lock]/[dispose]).
  void _detachAndErase() {
    if (_closed) {
      return;
    }

    _closed = true;
    _keys.erase();
    if (identical(_locker._activeTransaction, this)) {
      _locker._activeTransaction = null;
    }
  }
}
