import 'package:locker/storage/models/data/key_wrap.dart';
import 'package:locker/storage/models/data/origin.dart';

const _wrapsFieldName = 'wraps';

class WrappedKey {
  final List<KeyWrap> wraps;

  const WrappedKey({
    required this.wraps,
  });

  KeyWrap getWrapForOrigin(Origin origin) => wraps.firstWhere(
        (w) => w.origin == origin,
        orElse: () => throw StateError('Wrap for origin $origin not found'),
      );

  factory WrappedKey.fromJson(Map<String, Object?> json) => WrappedKey(
        wraps: (json[_wrapsFieldName] as List).map((w) => KeyWrap.fromJson(w as Map<String, Object?>)).toList(),
      );

  Map<String, Object?> toJson() => {
        _wrapsFieldName: wraps.map((x) => x.toJson()).toList(),
      };
}
