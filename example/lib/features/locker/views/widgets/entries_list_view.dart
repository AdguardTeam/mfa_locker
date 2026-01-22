import 'package:flutter/material.dart';
import 'package:locker/storage/models/domain/entry_id.dart';

class EntriesListView extends StatelessWidget {
  const EntriesListView({
    required this.entries,
    required this.onDeleteEntry,
    required this.onViewEntry,
    super.key,
  });

  final Map<EntryId, String> entries;
  final Function(EntryId, String) onDeleteEntry;
  final Function(EntryId, String) onViewEntry;

  @override
  Widget build(BuildContext context) => ListView.builder(
    itemCount: entries.length,
    itemBuilder: (context, index) {
      final entry = entries.entries.elementAt(index);
      final entryId = entry.key;
      final entryName = entry.value;

      return ListTile(
        leading: const Icon(Icons.vpn_key, color: Colors.blue),
        title: Text(
          entryName,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: 'Delete entry',
              onPressed: () => onDeleteEntry(entryId, entryName),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.lock_open, color: Colors.grey),
              tooltip: 'View entry',
              onPressed: () => onViewEntry(entryId, entryName),
            ),
          ],
        ),
      );
    },
  );
}
