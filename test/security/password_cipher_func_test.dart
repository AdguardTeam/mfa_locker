import 'dart:typed_data';

import 'package:locker/erasable/erasable_byte_array.dart';
import 'package:locker/security/models/password_cipher_func.dart';
import 'package:locker/storage/models/data/origin.dart';
import 'package:locker/storage/models/exceptions/decrypt_failed_exception.dart';
import 'package:test/test.dart';

void main() {
  final salt = Uint8List.fromList(List.generate(16, (i) => i));

  PasswordCipherFunc createCipher(String password) => PasswordCipherFunc(password: password, salt: salt);

  group('PasswordCipherFunc', () {
    test('exposes the pwd origin', () {
      expect(createCipher('secret').origin, Origin.pwd);
    });

    test('encrypt/decrypt round-trip with the same password and salt', () async {
      // Arrange: the key is derived per call, so a second instance must decrypt.
      final plaintext = Uint8List.fromList([1, 2, 3]);
      final encryptor = createCipher('correct horse battery staple');

      // Act
      final encrypted = await encryptor.encrypt(ErasableByteArray(plaintext));
      final decrypted = await createCipher('correct horse battery staple').decrypt(encrypted);

      // Assert
      expect(encrypted, isNotEmpty);
      expect(encrypted, isNot(orderedEquals(plaintext)));
      expect(decrypted.bytes, orderedEquals(plaintext));
    });

    test('decrypt fails with a different password', () async {
      // Arrange
      final encrypted = await createCipher('right password').encrypt(ErasableByteArray(Uint8List.fromList([1, 2, 3])));

      // Act & Assert
      await expectLater(
        createCipher('wrong password').decrypt(encrypted),
        throwsA(isA<DecryptFailedException>()),
      );
    });

    test('erase erases the password and isErased reflects it', () {
      // Arrange
      final cipher = createCipher('secret');
      expect(cipher.isErased, isFalse);

      // Act
      cipher.erase();

      // Assert
      expect(cipher.isErased, isTrue);
      expect(cipher.password.isErased, isTrue);
    });
  });
}
