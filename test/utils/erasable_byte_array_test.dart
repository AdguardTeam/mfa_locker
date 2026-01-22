import 'dart:typed_data';

import 'package:locker/erasable/erasable_byte_array.dart';
import 'package:test/test.dart';

void main() {
  group('ErasableByteArray', () {
    test('key erases successfully', () {
      final key = ErasableByteArray(Uint8List(32));

      key.erase();

      expect(key.isErased, isTrue);
      expect(() => key.bytes, throwsA(isA<StateError>()));
    });
  });
}
