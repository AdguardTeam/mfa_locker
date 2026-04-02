import 'dart:typed_data';

import 'package:locker/erasable/erasable.dart';

class ErasableByteArray implements Erasable {
  final void Function()? _onEraseCallback;
  Uint8List? _bytes;
  bool _erased = false;

  ErasableByteArray(
    Uint8List bytes, {
    void Function()? onEraseCallback,
  })  : _bytes = bytes,
        _onEraseCallback = onEraseCallback;

  /// Returns the underlying bytes
  /// Throws a StateError if the data has been erased
  Uint8List get bytes {
    if (_erased) {
      throw StateError('ErasableByteArray is erased');
    }

    return _bytes ?? Uint8List.fromList([]);
  }

  @override
  bool get isErased => _erased;

  /// Overwrites by zeroes and nullifies the internal byte array
  @override
  void erase() {
    if (_erased) {
      return;
    }

    _erased = true;

    final bytes = _bytes;
    if (bytes == null) {
      return;
    }

    bytes.fillRange(0, bytes.length, 0);

    _bytes = null;
    _onEraseCallback?.call();
  }
}
