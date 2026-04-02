import 'package:locker/erasable/erasable_byte_array.dart';

class EntryMeta extends ErasableByteArray {
  EntryMeta._(
    super.bytes, {
    required super.onEraseCallback,
  });

  static EntryMeta fromErasable({
    required ErasableByteArray erasable,
  }) =>
      EntryMeta._(
        erasable.bytes,
        onEraseCallback: erasable.erase,
      );
}
