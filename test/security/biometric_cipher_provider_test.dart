import 'dart:convert';
import 'dart:typed_data';

import 'package:biometric_cipher/biometric_cipher.dart';
import 'package:biometric_cipher/data/biometric_status.dart';
import 'package:biometric_cipher/data/model/config_data.dart';
import 'package:biometric_cipher/data/tpm_status.dart';
import 'package:locker/security/biometric_cipher_provider.dart';
import 'package:locker/security/models/biometric_config.dart';
import 'package:locker/security/models/exceptions/biometric_exception.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../mocks/mock_biometric_cipher.dart';

void main() {
  setUpAll(() {
    registerFallbackValue(const ConfigData());
  });

  group('BiometricCipherProviderImpl', () {
    group('_mapExceptionToBiometricException', () {
      late MockBiometricCipher mockCipher;
      late BiometricCipherProviderImpl provider;

      setUp(() {
        mockCipher = MockBiometricCipher();
        provider = BiometricCipherProviderImpl.forTesting(mockCipher);
      });

      test('maps keyPermanentlyInvalidated to BiometricExceptionType.keyInvalidated', () async {
        // Arrange
        when(
          () => mockCipher.decrypt(
            tag: any(named: 'tag'),
            data: any(named: 'data'),
          ),
        ).thenThrow(
          const BiometricCipherException(
            code: BiometricCipherExceptionCode.keyPermanentlyInvalidated,
            message: 'test',
          ),
        );

        // Act & Assert
        await expectLater(
          () => provider.decrypt(tag: 'tag', data: Uint8List.fromList([1])),
          throwsA(
            isA<BiometricException>()
                .having((e) => e.type, 'type', BiometricExceptionType.keyInvalidated)
                .having((e) => e.message, 'message', 'test'),
          ),
        );
      });

      test('maps authenticationError to BiometricExceptionType.failure and preserves message', () async {
        // Arrange
        when(
          () => mockCipher.decrypt(
            tag: any(named: 'tag'),
            data: any(named: 'data'),
          ),
        ).thenThrow(
          const BiometricCipherException(
            code: BiometricCipherExceptionCode.authenticationError,
            message: 'Authentication failed',
          ),
        );

        // Act & Assert
        await expectLater(
          () => provider.decrypt(tag: 'tag', data: Uint8List.fromList([1])),
          throwsA(
            isA<BiometricException>()
                .having((e) => e.type, 'type', BiometricExceptionType.failure)
                .having((e) => e.message, 'message', 'Authentication failed'),
          ),
        );
      });

      test('maps authenticationUserCanceled to BiometricExceptionType.cancel', () async {
        // Arrange
        when(
          () => mockCipher.decrypt(
            tag: any(named: 'tag'),
            data: any(named: 'data'),
          ),
        ).thenThrow(
          const BiometricCipherException(
            code: BiometricCipherExceptionCode.authenticationUserCanceled,
            message: 'test',
          ),
        );

        // Act & Assert
        await expectLater(
          () => provider.decrypt(tag: 'tag', data: Uint8List.fromList([1])),
          throwsA(
            isA<BiometricException>()
                .having((e) => e.type, 'type', BiometricExceptionType.cancel)
                .having((e) => e.message, 'message', 'test'),
          ),
        );
      });

      final mappings = <BiometricCipherExceptionCode, BiometricExceptionType>{
        BiometricCipherExceptionCode.keyNotFound: BiometricExceptionType.keyNotFound,
        BiometricCipherExceptionCode.keyAlreadyExists: BiometricExceptionType.keyAlreadyExists,
        BiometricCipherExceptionCode.encryptionError: BiometricExceptionType.failure,
        BiometricCipherExceptionCode.decryptionError: BiometricExceptionType.failure,
        BiometricCipherExceptionCode.biometricNotSupported: BiometricExceptionType.notAvailable,
        BiometricCipherExceptionCode.secureEnclaveUnavailable: BiometricExceptionType.notAvailable,
        BiometricCipherExceptionCode.tpmUnsupported: BiometricExceptionType.notAvailable,
        BiometricCipherExceptionCode.configureError: BiometricExceptionType.notConfigured,
        BiometricCipherExceptionCode.invalidArgument: BiometricExceptionType.failure,
        BiometricCipherExceptionCode.keyGenerationError: BiometricExceptionType.failure,
        BiometricCipherExceptionCode.keyDeletionError: BiometricExceptionType.failure,
      };

      for (final mapping in mappings.entries) {
        test('maps ${mapping.key.name} to BiometricExceptionType.${mapping.value.name}', () async {
          // Arrange
          when(
            () => mockCipher.decrypt(
              tag: any(named: 'tag'),
              data: any(named: 'data'),
            ),
          ).thenThrow(
            BiometricCipherException(code: mapping.key, message: 'test'),
          );

          // Act & Assert
          await expectLater(
            () => provider.decrypt(tag: 'tag', data: Uint8List.fromList([1])),
            throwsA(
              isA<BiometricException>()
                  .having((e) => e.type, 'type', mapping.value)
                  .having((e) => e.message, 'message', 'test'),
            ),
          );
        });
      }

      test('preserves the original error for codes without a dedicated type', () async {
        // Arrange
        const originalError = BiometricCipherException(
          code: BiometricCipherExceptionCode.keyGenerationError,
          message: 'boom',
        );
        when(() => mockCipher.generateKey(tag: any(named: 'tag'))).thenThrow(originalError);

        // Act & Assert
        await expectLater(
          () => provider.generateKey(tag: 'tag'),
          throwsA(
            isA<BiometricException>()
                .having((e) => e.type, 'type', BiometricExceptionType.failure)
                .having((e) => e.originalError, 'originalError', same(originalError)),
          ),
        );
      });

      test('maps an encrypt failure to BiometricExceptionType.failure', () async {
        // Arrange
        when(
          () => mockCipher.encrypt(
            tag: any(named: 'tag'),
            data: any(named: 'data'),
          ),
        ).thenThrow(
          const BiometricCipherException(
            code: BiometricCipherExceptionCode.encryptionError,
            message: 'boom',
          ),
        );

        // Act & Assert
        await expectLater(
          () => provider.encrypt(tag: 'tag', data: Uint8List.fromList([1])),
          throwsA(
            isA<BiometricException>()
                .having((e) => e.type, 'type', BiometricExceptionType.failure)
                .having((e) => e.message, 'message', 'boom'),
          ),
        );
      });
    });

    group('null platform result', () {
      late MockBiometricCipher mockCipher;
      late BiometricCipherProviderImpl provider;

      setUp(() {
        mockCipher = MockBiometricCipher();
        provider = BiometricCipherProviderImpl.forTesting(mockCipher);
      });

      test('maps a null encrypt result to BiometricExceptionType.failure', () async {
        // Arrange
        when(() => mockCipher.encrypt(tag: any(named: 'tag'), data: any(named: 'data'))).thenAnswer((_) async => null);

        // Act & Assert
        await expectLater(
          () => provider.encrypt(tag: 'tag', data: Uint8List.fromList([1])),
          throwsA(isA<BiometricException>().having((e) => e.type, 'type', BiometricExceptionType.failure)),
        );
      });

      test('maps a null decrypt result to BiometricExceptionType.failure', () async {
        // Arrange
        when(() => mockCipher.decrypt(tag: any(named: 'tag'), data: any(named: 'data'))).thenAnswer((_) async => null);

        // Act & Assert
        await expectLater(
          () => provider.decrypt(tag: 'tag', data: Uint8List.fromList([1])),
          throwsA(isA<BiometricException>().having((e) => e.type, 'type', BiometricExceptionType.failure)),
        );
      });
    });

    group('isKeyValid', () {
      late MockBiometricCipher mockCipher;
      late BiometricCipherProviderImpl provider;

      setUp(() {
        mockCipher = MockBiometricCipher();
        provider = BiometricCipherProviderImpl.forTesting(mockCipher);
      });

      test('returns true when cipher returns true', () async {
        when(() => mockCipher.isKeyValid(tag: any(named: 'tag'))).thenAnswer((_) async => true);

        final result = await provider.isKeyValid(tag: 'my-key');

        expect(result, isTrue);
        verify(() => mockCipher.isKeyValid(tag: 'my-key')).called(1);
      });

      test('returns false when cipher returns false', () async {
        when(() => mockCipher.isKeyValid(tag: any(named: 'tag'))).thenAnswer((_) async => false);

        final result = await provider.isKeyValid(tag: 'my-key');

        expect(result, isFalse);
        verify(() => mockCipher.isKeyValid(tag: 'my-key')).called(1);
      });
    });

    group('base64 payloads', () {
      late MockBiometricCipher mockCipher;
      late BiometricCipherProviderImpl provider;

      setUp(() {
        mockCipher = MockBiometricCipher();
        provider = BiometricCipherProviderImpl.forTesting(mockCipher);
      });

      test('encrypt sends base64 and decodes the platform result', () async {
        // Arrange
        final data = Uint8List.fromList([1, 2, 3]);
        when(() => mockCipher.encrypt(tag: 'tag', data: base64Encode(data)))
            .thenAnswer((_) async => base64Encode([9, 8]));

        // Act
        final result = await provider.encrypt(tag: 'tag', data: data);

        // Assert
        expect(result, orderedEquals([9, 8]));
      });

      test('decrypt sends base64 and decodes the platform result', () async {
        // Arrange
        final data = Uint8List.fromList([4, 5, 6]);
        when(() => mockCipher.decrypt(tag: 'tag', data: base64Encode(data)))
            .thenAnswer((_) async => base64Encode([1, 2]));

        // Act
        final result = await provider.decrypt(tag: 'tag', data: data);

        // Assert
        expect(result, orderedEquals([1, 2]));
      });
    });

    group('passthrough operations', () {
      late MockBiometricCipher mockCipher;
      late BiometricCipherProviderImpl provider;

      setUp(() {
        mockCipher = MockBiometricCipher();
        provider = BiometricCipherProviderImpl.forTesting(mockCipher);
      });

      test('generateKey forwards the tag', () async {
        // Arrange
        when(() => mockCipher.generateKey(tag: any(named: 'tag'))).thenAnswer((_) async {});

        // Act
        await provider.generateKey(tag: 'my-key');

        // Assert
        verify(() => mockCipher.generateKey(tag: 'my-key')).called(1);
      });

      test('deleteKey forwards the tag', () async {
        // Arrange
        when(() => mockCipher.deleteKey(tag: any(named: 'tag'))).thenAnswer((_) async {});

        // Act
        await provider.deleteKey(tag: 'my-key');

        // Assert
        verify(() => mockCipher.deleteKey(tag: 'my-key')).called(1);
      });

      test('getTPMStatus returns the platform status', () async {
        // Arrange
        when(() => mockCipher.getTPMStatus()).thenAnswer((_) async => TPMStatus.supported);

        // Act & Assert
        expect(await provider.getTPMStatus(), TPMStatus.supported);
      });

      test('getBiometryStatus returns the platform status', () async {
        // Arrange
        when(() => mockCipher.getBiometryStatus()).thenAnswer((_) async => BiometricStatus.supported);

        // Act & Assert
        expect(await provider.getBiometryStatus(), BiometricStatus.supported);
      });
    });

    group('configure', () {
      late MockBiometricCipher mockCipher;
      late BiometricCipherProviderImpl provider;

      setUp(() {
        mockCipher = MockBiometricCipher();
        provider = BiometricCipherProviderImpl.forTesting(mockCipher);

        when(() => mockCipher.configure(config: any(named: 'config'))).thenAnswer((_) async {});
      });

      test('maps the locker config onto the plugin config', () async {
        // Arrange
        const config = BiometricConfig(
          promptTitle: 'Title',
          promptSubtitle: 'Subtitle',
          androidCancelButtonText: 'Cancel',
          androidPromptDescription: 'Description',
        );

        // Act
        await provider.configure(config);

        // Assert
        final captured =
            verify(() => mockCipher.configure(config: captureAny(named: 'config'))).captured.single as ConfigData;

        expect(captured.biometricPromptTitle, 'Title');
        expect(captured.biometricPromptSubtitle, 'Subtitle');
        expect(captured.windowsDataToSign, 'locker_authentication_request');
        expect(captured.androidConfig?.negativeButtonText, 'Cancel');
        expect(captured.androidConfig?.promptTitle, 'Title');
        expect(captured.androidConfig?.promptSubtitle, 'Subtitle');
        expect(captured.androidConfig?.promptDescription, 'Description');
      });

      test('forwards the Windows auth data when provided', () async {
        // Arrange
        const config = BiometricConfig(
          promptTitle: 'Title',
          promptSubtitle: 'Subtitle',
          androidCancelButtonText: 'Cancel',
          androidPromptDescription: 'Description',
          windowsAuthData: 'payload',
        );

        // Act
        await provider.configure(config);

        // Assert
        final captured =
            verify(() => mockCipher.configure(config: captureAny(named: 'config'))).captured.single as ConfigData;

        expect(captured.windowsDataToSign, 'payload');
      });
    });
  });
}
