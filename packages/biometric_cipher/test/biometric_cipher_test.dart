import 'package:flutter_test/flutter_test.dart';
import 'package:biometric_cipher/data/model/config_data.dart';
import 'package:biometric_cipher/biometric_cipher.dart';
import 'package:biometric_cipher/biometric_cipher_platform_interface.dart';

import 'mock_biometric_cipher_platform.dart';

/// Extended tests for [BiometricCipher], ensuring:
/// 1) The same 'tag' is used for encryption and decryption.
/// 2) The original data matches the decrypted data after an encrypt-decrypt cycle.
void main() {
  group('BiometricCipher tests', () {
    late BiometricCipher biometricCipher;
    late MockBiometricCipherPlatform mockPlatform;

    setUp(() {
      // Arrange: set up the mock platform and create the tested instance.
      mockPlatform = MockBiometricCipherPlatform();
      BiometricCipherPlatform.instance = mockPlatform;
      biometricCipher = BiometricCipher(mockPlatform);
    });

    group('configure', () {
      test('Successful configure', () async {
        // Arrange
        const config = ConfigData(
          biometricPromptTitle: 'Title',
          biometricPromptSubtitle: 'Subtitle',
          windowsDataToSign: 'DataToSign',
        );

        // Act
        await biometricCipher.configure(config: config);

        // Assert
        expect(biometricCipher.configured, isTrue);
        expect(mockPlatform.isConfigured, isTrue);
      });
    });

    group('encrypt-decrypt cycle', () {
      // We use the SAME tag and data for encryption and decryption.
      const tag = 'common_tag';
      const data = 'secret_data';

      setUp(() async {
        // Arrange
        // First, configure the plugin and generate the key with the SAME tag.
        await biometricCipher.configure(
          config: const ConfigData(
            biometricPromptTitle: 'Title',
            biometricPromptSubtitle: 'Subtitle',
            windowsDataToSign: 'DataToSign',
          ),
        );
        await biometricCipher.generateKey(tag: tag);
      });

      test('encrypt and then decrypt returns the original data', () async {
        // Arrange (already done in setUp)
        // Act
        final encrypted = await biometricCipher.encrypt(tag: tag, data: data);
        final decrypted = await biometricCipher.decrypt(tag: tag, data: encrypted!);

        // Assert
        // After decryption, we expect to get the same 'data' we started with.
        expect(decrypted, equals(data));
      });

      test('throws BiometricCipherException if trying to decrypt with different tag', () async {
        // Arrange
        final encrypted = await biometricCipher.encrypt(tag: tag, data: data);
        const differentTag = 'another_tag';

        // Act & Assert
        expect(
          () => biometricCipher.decrypt(tag: differentTag, data: encrypted!),
          throwsA(predicate((e) => e is BiometricCipherException && e.code == BiometricCipherExceptionCode.keyNotFound)),
        );
      });
    });

    group('generateKey', () {
      test('should throw Exception if tag is empty', () async {
        // Arrange, Act & Assert
        expect(() => biometricCipher.generateKey(tag: ''), throwsA(isA<Exception>()));
      });
    });

    group('encrypt', () {
      test('throws Exception if tag is empty', () async {
        // Arrange
        await biometricCipher.configure(
          config: const ConfigData(
            biometricPromptTitle: 'Title',
            biometricPromptSubtitle: 'Subtitle',
            windowsDataToSign: 'DataToSign',
          ),
        );

        // Act & Assert
        expect(() => biometricCipher.encrypt(tag: '', data: 'some_data'), throwsA(isA<Exception>()));
      });

      test('throws Exception if data is empty', () async {
        // Arrange
        const tag = 'encrypt_tag';
        await biometricCipher.configure(
          config: const ConfigData(
            biometricPromptTitle: 'Title',
            biometricPromptSubtitle: 'Subtitle',
            windowsDataToSign: 'DataToSign',
          ),
        );
        await biometricCipher.generateKey(tag: tag);

        // Act & Assert
        expect(() => biometricCipher.encrypt(tag: tag, data: ''), throwsA(isA<Exception>()));
      });
    });

    group('decrypt', () {
      test('throws BiometricCipherException if plugin is not configured', () async {
        // Arrange
        // We do NOT call biometricCipher.configure here
        const tag = 'unconfigured_tag';

        // In the current mock, generating a key does NOT require configure,
        // but decrypting will fail if configured == false
        await biometricCipher.generateKey(tag: tag);

        // Act & Assert
        expect(
          () => biometricCipher.decrypt(tag: tag, data: 'encrypted_data'),
          throwsA(
            predicate((e) => e is BiometricCipherException && e.code == BiometricCipherExceptionCode.configureError),
          ),
        );
      });

      test('throws Exception if data is empty', () async {
        // Arrange
        const tag = 'decrypt_tag';
        await biometricCipher.configure(
          config: const ConfigData(
            biometricPromptTitle: 'Title',
            biometricPromptSubtitle: 'Subtitle',
            windowsDataToSign: 'DataToSign',
          ),
        );
        await biometricCipher.generateKey(tag: tag);

        // Act & Assert
        expect(() => biometricCipher.decrypt(tag: tag, data: ''), throwsA(isA<Exception>()));
      });
    });

    group('deleteKey', () {
      test('deleteKey removes existing key', () async {
        // Arrange
        const tag = 'delete_tag';
        await biometricCipher.configure(
          config: const ConfigData(
            biometricPromptTitle: 'Title',
            biometricPromptSubtitle: 'Subtitle',
            windowsDataToSign: 'DataToSign',
          ),
        );
        await biometricCipher.generateKey(tag: tag);
        expect(mockPlatform.keys.containsKey(tag), isTrue);

        // Act
        await biometricCipher.deleteKey(tag: tag);

        // Assert
        expect(mockPlatform.keys.containsKey(tag), isFalse);
      });
    });
  });
}
