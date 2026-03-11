import 'package:locker/erasable/erasable.dart';
import 'package:locker/storage/models/domain/entry_id.dart';
import 'package:locker/storage/models/domain/entry_meta.dart';
import 'package:locker/storage/models/domain/entry_value.dart';

abstract class EntryInput implements Erasable {
  final EntryId? id;
  final EntryMeta? meta;
  final EntryValue? value;

  const EntryInput({this.id, this.meta, this.value});

  @override
  bool get isErased => (meta?.isErased ?? true) && (value?.isErased ?? true);

  @override
  void erase() {
    meta?.erase();
    value?.erase();
  }
}
