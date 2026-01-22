import 'dart:typed_data';

extension ListIntExtension on List<int> {
  Uint8List toUint8List() => this is Uint8List ? this as Uint8List : Uint8List.fromList(this);
}
