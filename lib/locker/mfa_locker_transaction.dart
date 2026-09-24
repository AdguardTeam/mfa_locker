import 'package:locker/locker/locker_transaction.dart';
import 'package:locker/locker/models/exceptions/locker_exception.dart';
import 'package:locker/locker/models/transaction_result.dart';
import 'package:locker/locker/utils/mfa_locker_utils.dart';
import 'package:locker/security/models/cipher_func.dart';
import 'package:locker/storage/encrypted_storage.dart';
import 'package:locker/storage/models/data/origin.dart';
import 'package:locker/storage/models/domain/entry_add_input.dart';
import 'package:locker/storage/models/domain/entry_id.dart';
import 'package:locker/storage/models/domain/entry_meta.dart';
import 'package:locker/storage/models/domain/entry_update_input.dart';
import 'package:locker/storage/models/domain/entry_value.dart';
import 'package:locker/storage/models/exceptions/storage_exception.dart';
import 'package:locker/storage/storage_transaction.dart';

/// Buffers one `withTransaction` body (working copy + metadata overlay) and owns
/// the working copy lifecycle, so it can never outlive the transaction.
class MfaLockerTransaction implements LockerTransaction {
  static Future<MfaLockerTransaction> open({
    required EncryptedStorage storage,
    required CipherFunc cipherFunc,
    required Future<void> Function(StorageTransaction storageTransaction) initialize,
  }) async {
    final storageTransaction = await storage.openTransaction(cipherFunc: cipherFunc);

    try {
      await initialize(storageTransaction);

      return MfaLockerTransaction._(storage, storageTransaction);
    } catch (_) {
      storageTransaction.erase();

      rethrow;
    }
  }

  final EncryptedStorage _storage;
  final StorageTransaction _storageTransaction;

  MfaLockerTransaction._(
    this._storage,
    this._storageTransaction,
  );

  final Map<EntryId, EntryMeta> _pendingMeta = {};
  final Set<EntryId> _deletedIds = {};
  bool _closed = false;
  bool _committing = false;

  @override
  Future<EntryValue> readValue(EntryId id) async {
    _ensureOpen();

    return _storageTransaction.readValue(id);
  }

  @override
  Future<EntryId> write(EntryAddInput input) => MFALockerUtils.eraseAfter<EntryId>(
        erasables: [input.value],
        erasablesOnError: [input.meta],
        callback: () => writeBuffered(input),
      );

  @override
  Future<void> update(EntryUpdateInput input) => MFALockerUtils.eraseAfter(
        erasables: [if (input.value != null) input.value!],
        erasablesOnError: [if (input.meta != null) input.meta!],
        callback: () => updateBuffered(input),
      );

  @override
  Future<void> delete(EntryId id) async {
    _ensureOpen();

    try {
      await _storageTransaction.deleteEntry(id);
    } on StorageException catch (error) {
      // Already absent in storage: treat delete as an idempotent success.
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

    await _storageTransaction.updateLockTimeout(lockTimeout.inMilliseconds);
  }

  @override
  Future<void> addOrReplaceWrap({required CipherFunc newWrapFunc}) async {
    _ensureOpen();

    await _storageTransaction.addOrReplaceWrap(newWrapFunc: newWrapFunc);
  }

  @override
  Future<void> deleteWrap({required Origin originToDelete}) async {
    _ensureOpen();

    await _storageTransaction.deleteWrap(originToDelete: originToDelete);
  }

  bool get isClosed => _closed;

  /// True while the commit is writing the file: the buffer must survive it.
  bool get isCommitting => _committing;

  /// [write] without erasing the input: the caller owns the single erase.
  Future<EntryId> writeBuffered(EntryAddInput input) async {
    _ensureOpen();

    final entryId = await _storageTransaction.addEntry(input);

    _deletedIds.remove(entryId);
    _pendingMeta[entryId] = input.meta;

    return entryId;
  }

  /// [update] without erasing the input (single erase owned by the caller).
  Future<void> updateBuffered(EntryUpdateInput input) async {
    _ensureOpen();

    await _storageTransaction.updateEntry(input);

    final meta = input.meta;
    if (meta != null) {
      _pendingMeta.remove(input.id)?.erase();
      _pendingMeta[input.id] = meta;
      _deletedIds.remove(input.id);
    }
  }

  /// Persists the working copy and closes the transaction; a failed commit discards the buffer.
  Future<TransactionResult> commit() async {
    _ensureOpen();

    _committing = true;
    try {
      await _storage.closeTransaction(_storageTransaction);
    } catch (_) {
      _committing = false;
      abort();

      rethrow;
    }
    _committing = false;

    _closed = true;
    _storageTransaction.erase();

    return TransactionResult(
      pendingMeta: _pendingMeta,
      deletedIds: _deletedIds,
    );
  }

  void abort() {
    // While a commit is in flight the buffer belongs to it: erasing the master
    // key now would corrupt the write. [commit] erases the buffer when done.
    if (_closed || _committing) {
      return;
    }

    _erasePendingMeta();
    _storageTransaction.erase();
    _closed = true;
  }

  void _erasePendingMeta() {
    for (final meta in _pendingMeta.values) {
      meta.erase();
    }

    _pendingMeta.clear();
    _deletedIds.clear();
  }

  void _ensureOpen() {
    if (_closed) {
      throw LockerException.transactionClosed();
    }
  }
}
