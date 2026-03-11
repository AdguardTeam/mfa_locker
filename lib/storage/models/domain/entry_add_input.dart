import 'package:locker/storage/models/domain/entry_input.dart';
import 'package:locker/storage/models/domain/entry_meta.dart';
import 'package:locker/storage/models/domain/entry_value.dart';

class EntryAddInput extends EntryInput {
  @override
  EntryMeta get meta => super.meta!;

  @override
  EntryValue get value => super.value!;

  const EntryAddInput({
    required EntryMeta meta,
    required EntryValue value,
    super.id,
  }) : super(meta: meta, value: value);
}
