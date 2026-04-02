import 'package:locker/erasable/erasable_byte_array.dart';

class EntryValue extends ErasableByteArray {
  EntryValue._(
    super.bytes, {
    required super.onEraseCallback,
  });

  static EntryValue fromErasable({
    required ErasableByteArray erasable,
  }) =>
      EntryValue._(
        erasable.bytes,
        onEraseCallback: erasable.erase,
      );
}
