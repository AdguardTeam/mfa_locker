import 'package:flutter_test/flutter_test.dart';
import 'package:secure_mnemonic/data/model/config_data.dart';
import 'package:secure_mnemonic/secure_mnemonic.dart';
import 'package:secure_mnemonic/secure_mnemonic_platform_interface.dart';

import 'mock_secure_mnemonic_platform.dart';

/// Extended tests for [SecureMnemonic], ensuring:
/// 1) The same 'tag' is used for encryption and decryption.
/// 2) The original data matches the decrypted data after an encrypt-decrypt cycle.
void main() {
  group('SecureMnemonic tests', () {
    late SecureMnemonic secureMnemonic;
    late MockSecureMnemonicPlatform mockPlatform;

    setUp(() {
      // Arrange: set up the mock platform and create the tested instance.
      mockPlatform = MockSecureMnemonicPlatform();
      SecureMnemonicPlatform.instance = mockPlatform;
      secureMnemonic = SecureMnemonic(mockPlatform);
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
        await secureMnemonic.configure(config: config);

        // Assert
        expect(secureMnemonic.configured, isTrue);
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
        await secureMnemonic.configure(
          config: const ConfigData(
            biometricPromptTitle: 'Title',
            biometricPromptSubtitle: 'Subtitle',
            windowsDataToSign: 'DataToSign',
          ),
        );
        await secureMnemonic.generateKey(tag: tag);
      });

      test('encrypt and then decrypt returns the original data', () async {
        // Arrange (already done in setUp)
        // Act
        final encrypted = await secureMnemonic.encrypt(tag: tag, data: data);
        final decrypted = await secureMnemonic.decrypt(tag: tag, data: encrypted!);

        // Assert
        // After decryption, we expect to get the same 'data' we started with.
        expect(decrypted, equals(data));
      });

      test('throws SecureMnemonicException if trying to decrypt with different tag', () async {
        // Arrange
        final encrypted = await secureMnemonic.encrypt(tag: tag, data: data);
        const differentTag = 'another_tag';

        // Act & Assert
        expect(
          () => secureMnemonic.decrypt(tag: differentTag, data: encrypted!),
          throwsA(predicate((e) => e is SecureMnemonicException && e.code == SecureMnemonicExceptionCode.keyNotFound)),
        );
      });
    });

    group('generateKey', () {
      test('should throw Exception if tag is empty', () async {
        // Arrange, Act & Assert
        expect(() => secureMnemonic.generateKey(tag: ''), throwsA(isA<Exception>()));
      });
    });

    group('encrypt', () {
      test('throws Exception if tag is empty', () async {
        // Arrange
        await secureMnemonic.configure(
          config: const ConfigData(
            biometricPromptTitle: 'Title',
            biometricPromptSubtitle: 'Subtitle',
            windowsDataToSign: 'DataToSign',
          ),
        );

        // Act & Assert
        expect(() => secureMnemonic.encrypt(tag: '', data: 'some_data'), throwsA(isA<Exception>()));
      });

      test('throws Exception if data is empty', () async {
        // Arrange
        const tag = 'encrypt_tag';
        await secureMnemonic.configure(
          config: const ConfigData(
            biometricPromptTitle: 'Title',
            biometricPromptSubtitle: 'Subtitle',
            windowsDataToSign: 'DataToSign',
          ),
        );
        await secureMnemonic.generateKey(tag: tag);

        // Act & Assert
        expect(() => secureMnemonic.encrypt(tag: tag, data: ''), throwsA(isA<Exception>()));
      });
    });

    group('decrypt', () {
      test('throws SecureMnemonicException if plugin is not configured', () async {
        // Arrange
        // We do NOT call secureMnemonic.configure here
        const tag = 'unconfigured_tag';

        // In the current mock, generating a key does NOT require configure,
        // but decrypting will fail if configured == false
        await secureMnemonic.generateKey(tag: tag);

        // Act & Assert
        expect(
          () => secureMnemonic.decrypt(tag: tag, data: 'encrypted_data'),
          throwsA(
            predicate((e) => e is SecureMnemonicException && e.code == SecureMnemonicExceptionCode.configureError),
          ),
        );
      });

      test('throws Exception if data is empty', () async {
        // Arrange
        const tag = 'decrypt_tag';
        await secureMnemonic.configure(
          config: const ConfigData(
            biometricPromptTitle: 'Title',
            biometricPromptSubtitle: 'Subtitle',
            windowsDataToSign: 'DataToSign',
          ),
        );
        await secureMnemonic.generateKey(tag: tag);

        // Act & Assert
        expect(() => secureMnemonic.decrypt(tag: tag, data: ''), throwsA(isA<Exception>()));
      });
    });

    group('deleteKey', () {
      test('deleteKey removes existing key', () async {
        // Arrange
        const tag = 'delete_tag';
        await secureMnemonic.configure(
          config: const ConfigData(
            biometricPromptTitle: 'Title',
            biometricPromptSubtitle: 'Subtitle',
            windowsDataToSign: 'DataToSign',
          ),
        );
        await secureMnemonic.generateKey(tag: tag);
        expect(mockPlatform.keys.containsKey(tag), isTrue);

        // Act
        await secureMnemonic.deleteKey(tag: tag);

        // Assert
        expect(mockPlatform.keys.containsKey(tag), isFalse);
      });
    });
  });
}
