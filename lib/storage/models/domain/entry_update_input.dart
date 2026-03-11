import 'package:locker/storage/models/domain/entry_id.dart';
import 'package:locker/storage/models/domain/entry_input.dart';

class EntryUpdateInput extends EntryInput {
  @override
  EntryId get id => super.id!;

  const EntryUpdateInput({
    required EntryId id,
    super.meta,
    super.value,
  }) : super(id: id);
}
