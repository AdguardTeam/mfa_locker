import 'dart:math';
import 'dart:typed_data';

import 'package:adguard_logger/adguard_logger.dart';
import 'package:cryptography/cryptography.dart';
import 'package:locker/erasable/erasable_byte_array.dart';
import 'package:locker/storage/models/exceptions/decrypt_failed_exception.dart';
import 'package:locker/utils/list_extensions.dart';
import 'package:uuid/uuid.dart';

class CryptographyUtils {
  static const int bitsPerByte = 8;
  static const int maxByteValue = 255;

  static const int exclusiveByteUpperBound = maxByteValue + 1;

  static const int aesKeySizeBits = 256;
  static const int aesKeySizeBytes = aesKeySizeBits ~/ bitsPerByte;

  static const int nonceSizeBytes = 12;
  static const int macSizeBytes = 16;
  static const int saltSizeBytes = 16;

  static const int pbkdf2Iterations = 600000;

  static const _uuid = Uuid();

  static final _algorithm = AesGcm.with256bits();
  static final _random = Random.secure();
  static final _hmacAlgorithm = Hmac.sha256();

  static final _pbkdf2 = Pbkdf2(
    macAlgorithm: _hmacAlgorithm,
    iterations: pbkdf2Iterations,
    bits: aesKeySizeBits,
  );

  static Future<ErasableByteArray> generateAESKey() async {
    final newKey = await _algorithm.newSecretKey();

    try {
      final keyBytes = await newKey.extractBytes();

      return ErasableByteArray(keyBytes.toUint8List());
    } finally {
      newKey.destroy();
    }
  }

  static Future<Uint8List> encrypt({
    required ErasableByteArray key,
    required ErasableByteArray data,
  }) async {
    final keyBytes = key.bytes;

    if (keyBytes.length != aesKeySizeBytes) {
      throw ArgumentError('AES key must be $aesKeySizeBits bits');
    }

    // Generate nonce
    final nonce = Uint8List(nonceSizeBytes);
    for (var i = 0; i < nonceSizeBytes; i++) {
      nonce[i] = _random.nextInt(exclusiveByteUpperBound);
    }

    final secretKey = SecretKey(keyBytes);
    try {
      final result = await _algorithm.encrypt(
        data.bytes,
        secretKey: secretKey,
        nonce: nonce,
      );

      // Prepend nonce to cipherText and append MAC
      final output = Uint8List(
        nonce.length + result.cipherText.length + result.mac.bytes.length,
      );
      output.setAll(0, nonce);
      output.setAll(nonce.length, result.cipherText);
      output.setAll(nonce.length + result.cipherText.length, result.mac.bytes);

      return output;
    } finally {
      secretKey.destroy();
    }
  }

  static Future<ErasableByteArray> decrypt({
    required ErasableByteArray key,
    required Uint8List data,
  }) async {
    if (data.length < nonceSizeBytes) {
      throw ArgumentError('Ciphertext too short: missing nonce');
    }

    final nonce = data.sublist(0, nonceSizeBytes);
    final cipherTextEnd = data.length - macSizeBytes;

    if (cipherTextEnd <= nonceSizeBytes) {
      throw ArgumentError('Ciphertext too short: missing content');
    }

    final cipherText = data.sublist(nonceSizeBytes, cipherTextEnd);
    final mac = Mac(data.sublist(cipherTextEnd));

    final keyBytes = key.bytes;

    if (keyBytes.length != aesKeySizeBytes) {
      throw ArgumentError('AES key must be $aesKeySizeBits bits');
    }

    final secretBox = SecretBox(
      cipherText,
      nonce: nonce,
      mac: mac,
    );

    final secretKey = SecretKey(keyBytes);

    try {
      final result = await _algorithm.decrypt(
        secretBox,
        secretKey: secretKey,
      );

      return ErasableByteArray(result.toUint8List());
    } catch (e, st) {
      logger.logError('CryptographyUtils: Failed to decrypt data', error: e, stackTrace: st);

      throw DecryptFailedException(message: 'Failed to decrypt data: $e', stackTrace: st);
    } finally {
      secretKey.destroy();
    }
  }

  static Future<Uint8List> authenticateHmac({
    required ErasableByteArray hmacKey,
    required Uint8List data,
  }) async {
    final secretKey = SecretKey(hmacKey.bytes);

    try {
      final mac = await _hmacAlgorithm.calculateMac(
        data,
        secretKey: secretKey,
      );

      return mac.bytes.toUint8List();
    } finally {
      secretKey.destroy();
    }
  }

  static Uint8List generateSalt() => Uint8List.fromList(
        List.generate(
          saltSizeBytes,
          (i) => _random.nextInt(exclusiveByteUpperBound),
        ),
      );

  static String generateUuid() => _uuid.v4();

  static Future<ErasableByteArray> deriveKeyFromPassword({
    required ErasableByteArray password,
    required Uint8List salt,
  }) async {
    final passwordKey = SecretKey(password.bytes);

    final derivedKey = await _pbkdf2.deriveKey(
      secretKey: passwordKey,
      nonce: salt,
    );

    try {
      final derivedKeyBytes = await derivedKey.extractBytes();

      return ErasableByteArray(derivedKeyBytes.toUint8List());
    } finally {
      derivedKey.destroy();
      passwordKey.destroy();
    }
  }
}
