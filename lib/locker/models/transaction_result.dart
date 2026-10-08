import 'package:locker/storage/models/domain/entry_id.dart';
import 'package:locker/storage/models/domain/entry_meta.dart';

/// Uncommitted metadata of a transaction, published by the locker on commit.
class TransactionResult {
  final Map<EntryId, EntryMeta> pendingMeta;
  final Set<EntryId> deletedIds;

  const TransactionResult({required this.pendingMeta, required this.deletedIds});
}
