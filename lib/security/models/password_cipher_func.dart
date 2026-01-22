import 'dart:typed_data';

import 'package:locker/erasable/erasable_byte_array.dart';
import 'package:locker/security/models/cipher_func.dart';
import 'package:locker/storage/models/data/origin.dart';
import 'package:locker/utils/cryptography_utils.dart';
import 'package:locker/utils/list_extensions.dart';

class PasswordCipherFunc extends CipherFunc {
  final ErasableByteArray password;
  final Uint8List salt;

  PasswordCipherFunc({
    required String password,
    required this.salt,
  })  : password = ErasableByteArray(password.codeUnits.toUint8List()),
        super(origin: Origin.pwd);

  @override
  bool get isErased => password.isErased;

  // Intentionally derive the key for every encrypt/decrypt call to minimize
  // the lifetime of the derived key material in memory. This is a security-first
  // trade-off (perf vs. memory exposure).
  @override
  Future<ErasableByteArray> decrypt(Uint8List data) async {
    final passwordKey = await CryptographyUtils.deriveKeyFromPassword(
      password: password,
      salt: salt,
    );

    try {
      final decrypted = await CryptographyUtils.decrypt(key: passwordKey, data: data);

      return decrypted;
    } finally {
      passwordKey.erase();
    }
  }

  // Intentionally derive the key for every encrypt/decrypt call to minimize
  // the lifetime of the derived key material in memory. This is a security-first
  // trade-off (perf vs. memory exposure).
  @override
  Future<Uint8List> encrypt(ErasableByteArray data) async {
    final passwordKey = await CryptographyUtils.deriveKeyFromPassword(password: password, salt: salt);

    try {
      final encrypted = await CryptographyUtils.encrypt(key: passwordKey, data: data);

      return encrypted;
    } finally {
      passwordKey.erase();
    }
  }

  @override
  void erase() => password.erase();
}
