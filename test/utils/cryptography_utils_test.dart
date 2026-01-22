import 'dart:typed_data';

import 'package:locker/erasable/erasable_byte_array.dart';
import 'package:locker/storage/models/exceptions/decrypt_failed_exception.dart';
import 'package:locker/utils/cryptography_utils.dart';
import 'package:test/test.dart';

void main() {
  Uint8List buildData() => Uint8List.fromList('data'.codeUnits);
  ErasableByteArray buildPlaintext() => ErasableByteArray(buildData());

  group('test CryptographyUtils', () {
    group('generateAESKey', () {
      test('returns non-empty key', () async {
        final key = await CryptographyUtils.generateAESKey();

        expect(key.bytes, isNotEmpty);
      });

      test('key length is correct', () async {
        final key = await CryptographyUtils.generateAESKey();

        expect(key.bytes.length, equals(CryptographyUtils.aesKeySizeBytes));
      });
    });

    group('encrypt', () {
      test('returns non-empty output', () async {
        final key = await CryptographyUtils.generateAESKey();
        final plaintext = buildPlaintext();

        final encrypted = await CryptographyUtils.encrypt(key: key, data: plaintext);

        expect(encrypted, isNotEmpty);
      });

      test('returns different output for same data with different keys', () async {
        final key1 = await CryptographyUtils.generateAESKey();
        final key2 = await CryptographyUtils.generateAESKey();
        final plaintext = buildPlaintext();

        final encrypted1 = await CryptographyUtils.encrypt(key: key1, data: plaintext);
        final encrypted2 = await CryptographyUtils.encrypt(key: key2, data: plaintext);

        expect(encrypted1, isNot(orderedEquals(encrypted2)));
      });

      test('throws on invalid key length', () async {
        final invalidKey = ErasableByteArray(Uint8List(CryptographyUtils.aesKeySizeBytes - 1));
        final plaintext = buildPlaintext();

        expect(
          () => CryptographyUtils.encrypt(key: invalidKey, data: plaintext),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('throws when key is erased', () async {
        final key = await CryptographyUtils.generateAESKey();
        final plaintext = buildPlaintext();

        key.erase();

        expect(
          () => CryptographyUtils.encrypt(key: key, data: plaintext),
          throwsA(isA<StateError>()),
        );
      });

      test('throws when data is erased', () async {
        final key = await CryptographyUtils.generateAESKey();
        final plaintext = buildPlaintext();

        plaintext.erase();

        expect(
          () => CryptographyUtils.encrypt(key: key, data: plaintext),
          throwsA(isA<StateError>()),
        );
      });
    });

    group('decrypt', () {
      test('reproduces original plaintext', () async {
        final key = await CryptographyUtils.generateAESKey();
        final plaintext = buildPlaintext();

        final encrypted = await CryptographyUtils.encrypt(key: key, data: plaintext);
        final decrypted = await CryptographyUtils.decrypt(key: key, data: encrypted);

        expect(decrypted.bytes, plaintext.bytes);
      });

      test('throws when ciphertext too short', () async {
        final key = await CryptographyUtils.generateAESKey();
        final data = Uint8List(0);

        expect(
          () => CryptographyUtils.decrypt(key: key, data: data),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('throws when ciphertext missing content', () async {
        final key = await CryptographyUtils.generateAESKey();
        final data = Uint8List(CryptographyUtils.nonceSizeBytes + CryptographyUtils.macSizeBytes);

        expect(
          () => CryptographyUtils.decrypt(key: key, data: data),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('throws on invalid key length', () async {
        final goodKey = await CryptographyUtils.generateAESKey();
        final plaintext = buildPlaintext();

        final encrypted = await CryptographyUtils.encrypt(key: goodKey, data: plaintext);
        final badKey = ErasableByteArray(Uint8List(CryptographyUtils.aesKeySizeBytes - 1));

        expect(
          () => CryptographyUtils.decrypt(key: badKey, data: encrypted),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('throws when MAC/auth tag does not verify', () async {
        final key = await CryptographyUtils.generateAESKey();
        final plaintext = buildPlaintext();
        final encrypted = await CryptographyUtils.encrypt(key: key, data: plaintext);

        final tampered = Uint8List.fromList(encrypted);
        tampered[0] = 42;

        expect(
          () => CryptographyUtils.decrypt(key: key, data: tampered),
          throwsA(isA<DecryptFailedException>()),
        );
      });
    });

    group('authenticateHmac', () {
      test('returns non-empty mac', () async {
        final hmacKey = await CryptographyUtils.generateAESKey();
        final data = buildData();

        final mac = await CryptographyUtils.authenticateHmac(hmacKey: hmacKey, data: data);

        expect(mac, isNotEmpty);
      });

      test('same mac for same input', () async {
        final hmacKey = await CryptographyUtils.generateAESKey();
        final data = buildData();

        final mac1 = await CryptographyUtils.authenticateHmac(hmacKey: hmacKey, data: data);
        final mac2 = await CryptographyUtils.authenticateHmac(hmacKey: hmacKey, data: data);

        expect(mac1, orderedEquals(mac2));
      });

      test('throws when key is erased', () async {
        final hmacKey = await CryptographyUtils.generateAESKey();
        final data = buildData();

        hmacKey.erase();

        expect(
          () => CryptographyUtils.authenticateHmac(hmacKey: hmacKey, data: data),
          throwsA(isA<StateError>()),
        );
      });
    });

    group('generateSalt', () {
      test('salt length is correct', () {
        final salt = CryptographyUtils.generateSalt();

        expect(salt.length, equals(CryptographyUtils.saltSizeBytes));
      });

      test('produces different salts', () {
        final salt1 = CryptographyUtils.generateSalt();
        final salt2 = CryptographyUtils.generateSalt();

        expect(salt1, isNot(orderedEquals(salt2)));
      });
    });

    group('generateUuid', () {
      test('returns non-empty uuid', () {
        final id = CryptographyUtils.generateUuid();

        expect(id, isNotEmpty);
      });

      test('produces different values', () {
        final id1 = CryptographyUtils.generateUuid();
        final id2 = CryptographyUtils.generateUuid();

        expect(id1, isNot(equals(id2)));
      });
    });

    group('deriveKeyFromPassword', () {
      test('returns key with correct length', () async {
        final password = buildPlaintext();
        final salt = CryptographyUtils.generateSalt();

        final derived = await CryptographyUtils.deriveKeyFromPassword(password: password, salt: salt);

        expect(derived.bytes.length, equals(CryptographyUtils.aesKeySizeBytes));
      });

      test('returns same key with same password and salt', () async {
        final password = buildPlaintext();
        final salt = CryptographyUtils.generateSalt();

        final d1 = await CryptographyUtils.deriveKeyFromPassword(password: password, salt: salt);
        final d2 = await CryptographyUtils.deriveKeyFromPassword(password: password, salt: salt);

        expect(d1.bytes, orderedEquals(d2.bytes));
      });

      test('returns different key with different salt', () async {
        final password = buildPlaintext();
        final salt1 = CryptographyUtils.generateSalt();
        final salt2 = CryptographyUtils.generateSalt();

        final d1 = await CryptographyUtils.deriveKeyFromPassword(password: password, salt: salt1);
        final d2 = await CryptographyUtils.deriveKeyFromPassword(password: password, salt: salt2);

        expect(d1.bytes, isNot(orderedEquals(d2.bytes)));
      });

      test('throws when password is erased', () async {
        final password = buildPlaintext();
        final salt = CryptographyUtils.generateSalt();

        password.erase();

        expect(
          () => CryptographyUtils.deriveKeyFromPassword(password: password, salt: salt),
          throwsA(isA<StateError>()),
        );
      });
    });
  });
}
