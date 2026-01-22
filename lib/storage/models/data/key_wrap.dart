import 'dart:convert';
import 'dart:typed_data';

import 'package:locker/storage/models/data/origin.dart';

const _originFieldName = 'origin';
const _encryptedKeyFieldName = 'data';

class KeyWrap {
  final Origin origin;
  final Uint8List encryptedKey;

  const KeyWrap({
    required this.origin,
    required this.encryptedKey,
  });

  factory KeyWrap.fromJson(Map<String, Object?> json) {
    final originStr = json[_originFieldName] as String;
    final origin = Origin.values.firstWhere((o) => o.name == originStr);

    final encryptedKeyStr = json[_encryptedKeyFieldName] as String;
    final encryptedKeyBytes = base64.decode(encryptedKeyStr);

    return KeyWrap(
      origin: origin,
      encryptedKey: encryptedKeyBytes,
    );
  }

  Map<String, Object?> toJson() => {
        _originFieldName: origin.name,
        _encryptedKeyFieldName: base64.encode(encryptedKey),
      };
}
