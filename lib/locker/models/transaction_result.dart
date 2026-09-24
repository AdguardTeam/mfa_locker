import 'package:locker/storage/models/domain/entry_id.dart';
import 'package:locker/storage/models/domain/entry_meta.dart';

/// Uncommitted metadata of a transaction, handed to the locker on commit so it
/// can publish the overlay into its cache.
class TransactionResult {
  final Map<EntryId, EntryMeta> pendingMeta;
  final Set<EntryId> deletedIds;

  const TransactionResult({required this.pendingMeta, required this.deletedIds});
}
