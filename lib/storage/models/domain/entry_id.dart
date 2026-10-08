import 'package:locker/utils/cryptography_utils.dart';

extension type EntryId(String value) {
  static EntryId generate() => EntryId(CryptographyUtils.generateUuid());

  bool get isEmpty => value.isEmpty;
}
