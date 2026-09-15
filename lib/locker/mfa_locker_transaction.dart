part of 'mfa_locker.dart';

/// Concrete [LockerTransaction] held by [MFALocker] for the duration of a
/// `withTransaction` body: operations go to a [StorageChangeSet]; metadata is
/// overlaid on the locker cache at commit.
class _MfaLockerTransaction implements LockerTransaction {
  final MFALocker _locker;
  final StorageChangeSet _changeSet;

  /// Locker generation captured when the transaction was opened; used to detect
  /// that the locker was locked/disposed before the commit is applied.
  final int _epochAtOpen;

  bool _closed = false;

  /// Metadata added or updated by this transaction.
  final Map<EntryId, EntryMeta> _pendingMeta = {};

  /// Ids deleted by this transaction.
  final Set<EntryId> _deletedIds = {};

  _MfaLockerTransaction._(this._locker, this._changeSet, this._epochAtOpen);

  /// Whether the transaction is already closed by `lock()`/`dispose()`.
  bool get isClosed => _closed;

  @override
  Map<EntryId, EntryMeta> get allMeta {
    _ensureOpen();

    return UnmodifiableMapView(mergedMeta(_locker._metaCache));
  }

  /// [committed] metadata merged with the uncommitted changes of this
  /// transaction. The values are not copied; the caller must not erase them.
  Map<EntryId, EntryMeta> mergedMeta(Map<EntryId, EntryMeta> committed) {
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

  @override
  Future<EntryValue> readValue(EntryId id) async {
    _ensureOpen();

    return _changeSet.readValue(id);
  }

  @override
  Future<EntryId> write(EntryAddInput input) => _locker._executeWithCleanup<EntryId>(
        // Erase meta on error only: on success the transaction owns it.
        erasables: [input.value],
        erasablesOnError: [input.meta],
        callback: () async {
          _ensureOpen();

          final entryId = await _changeSet.addEntry(input);

          _deletedIds.remove(entryId);
          _pendingMeta[entryId] = input.meta;

          return entryId;
        },
      );

  @override
  Future<void> update(EntryUpdateInput input) => _locker._executeWithCleanup(
        // Erase meta on error only: on success the transaction owns it.
        erasables: [if (input.value != null) input.value!],
        erasablesOnError: [if (input.meta != null) input.meta!],
        callback: () async {
          _ensureOpen();

          await _changeSet.updateEntry(input);

          final meta = input.meta;
          if (meta != null) {
            _pendingMeta.remove(input.id)?.erase();
            _pendingMeta[input.id] = meta;
            _deletedIds.remove(input.id);
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

    await _changeSet.updateLockTimeout(lockTimeout.inMilliseconds);
  }

  @override
  Future<void> addOrReplaceWrap({required CipherFunc newWrapFunc}) async {
    _ensureOpen();

    await _changeSet.addOrReplaceWrap(newWrapFunc: newWrapFunc);
  }

  @override
  Future<void> deleteWrap({required Origin originToDelete}) async {
    _ensureOpen();

    await _changeSet.deleteWrap(originToDelete: originToDelete);
  }

  /// Persists the buffered changes and closes the transaction; called by
  /// `withTransaction` when the body returns.
  Future<void> _commit() async {
    _ensureOpen();

    try {
      await _locker._storage.commitChangeSet(_changeSet);

      // Persisted, but the locker may have been locked meanwhile: do not
      // repopulate the cache of a locked locker.
      _locker._ensureFreshEpochOrErasePending(_epochAtOpen, this);
      _locker._applyCommittedMeta(this);
    } finally {
      _detachAndErase();
    }
  }

  /// Discards the buffered changes and closes the transaction; called by
  /// `withTransaction` when the body throws.
  Future<void> _abort() async {
    _ensureOpen();
    _detachAndErase();
  }

  /// Marks the transaction closed, erases the key material and the uncommitted
  /// metadata, and releases the lane.
  void _detachAndErase() {
    if (_closed) {
      return;
    }

    _closed = true;
    _discardPendingMeta();
    _changeSet.erase();
    _locker._lane.release();
    if (identical(_locker._activeTransaction, this)) {
      _locker._activeTransaction = null;
    }
  }

  /// Erases the uncommitted metadata: after a successful commit it was already
  /// moved into the locker cache, after an abort nothing references it.
  void _discardPendingMeta() {
    for (final meta in _pendingMeta.values) {
      meta.erase();
    }

    _pendingMeta.clear();
    _deletedIds.clear();
  }
}
