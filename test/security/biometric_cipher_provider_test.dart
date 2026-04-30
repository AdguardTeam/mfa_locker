import 'dart:typed_data';

import 'package:biometric_cipher/biometric_cipher.dart';
import 'package:biometric_cipher/data/model/config_data.dart';
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

      test('maps keyPermanentlyInvalidated to BiometricExceptionType.keyInvalidated', () async {
        when(() => mockCipher.isKeyValid(tag: any(named: 'tag'))).thenThrow(
          const BiometricCipherException(
            code: BiometricCipherExceptionCode.keyPermanentlyInvalidated,
            message: 'invalidated',
          ),
        );

        await expectLater(
          () => provider.isKeyValid(tag: 'my-key'),
          throwsA(
            isA<BiometricException>()
                .having((e) => e.type, 'type', BiometricExceptionType.keyInvalidated)
                .having((e) => e.message, 'message', 'invalidated'),
          ),
        );
      });
    });

    group('configure', () {
      late MockBiometricCipher mockCipher;
      late BiometricCipherProviderImpl provider;

      const config = BiometricConfig(
        promptTitle: 'Title',
        promptSubtitle: 'Subtitle',
        androidCancelButtonText: 'Cancel',
        androidPromptDescription: 'Description',
      );

      setUp(() {
        mockCipher = MockBiometricCipher();
        provider = BiometricCipherProviderImpl.forTesting(mockCipher);
      });

      test('maps configureError to BiometricExceptionType.notConfigured', () async {
        when(() => mockCipher.configure(config: any(named: 'config'))).thenThrow(
          const BiometricCipherException(
            code: BiometricCipherExceptionCode.configureError,
            message: 'configure failed',
          ),
        );

        await expectLater(
          () => provider.configure(config),
          throwsA(
            isA<BiometricException>()
                .having((e) => e.type, 'type', BiometricExceptionType.notConfigured)
                .having((e) => e.message, 'message', 'configure failed'),
          ),
        );
      });
    });

    group('getTPMStatus', () {
      late MockBiometricCipher mockCipher;
      late BiometricCipherProviderImpl provider;

      setUp(() {
        mockCipher = MockBiometricCipher();
        provider = BiometricCipherProviderImpl.forTesting(mockCipher);
      });

      test('maps tpmUnsupported to BiometricExceptionType.notAvailable', () async {
        when(() => mockCipher.getTPMStatus()).thenThrow(
          const BiometricCipherException(
            code: BiometricCipherExceptionCode.tpmUnsupported,
            message: 'tpm unsupported',
          ),
        );

        await expectLater(
          () => provider.getTPMStatus(),
          throwsA(
            isA<BiometricException>()
                .having((e) => e.type, 'type', BiometricExceptionType.notAvailable)
                .having((e) => e.message, 'message', 'tpm unsupported'),
          ),
        );
      });
    });

    group('getBiometryStatus', () {
      late MockBiometricCipher mockCipher;
      late BiometricCipherProviderImpl provider;

      setUp(() {
        mockCipher = MockBiometricCipher();
        provider = BiometricCipherProviderImpl.forTesting(mockCipher);
      });

      test('maps biometricNotSupported to BiometricExceptionType.notAvailable', () async {
        when(() => mockCipher.getBiometryStatus()).thenThrow(
          const BiometricCipherException(
            code: BiometricCipherExceptionCode.biometricNotSupported,
            message: 'not supported',
          ),
        );

        await expectLater(
          () => provider.getBiometryStatus(),
          throwsA(
            isA<BiometricException>()
                .having((e) => e.type, 'type', BiometricExceptionType.notAvailable)
                .having((e) => e.message, 'message', 'not supported'),
          ),
        );
      });
    });

    group('generateKey', () {
      late MockBiometricCipher mockCipher;
      late BiometricCipherProviderImpl provider;

      setUp(() {
        mockCipher = MockBiometricCipher();
        provider = BiometricCipherProviderImpl.forTesting(mockCipher);
      });

      test('maps keyAlreadyExists to BiometricExceptionType.keyAlreadyExists', () async {
        when(() => mockCipher.generateKey(tag: any(named: 'tag'))).thenThrow(
          const BiometricCipherException(
            code: BiometricCipherExceptionCode.keyAlreadyExists,
            message: 'exists',
          ),
        );

        await expectLater(
          () => provider.generateKey(tag: 'my-key'),
          throwsA(
            isA<BiometricException>()
                .having((e) => e.type, 'type', BiometricExceptionType.keyAlreadyExists)
                .having((e) => e.message, 'message', 'exists'),
          ),
        );
      });
    });

    group('deleteKey', () {
      late MockBiometricCipher mockCipher;
      late BiometricCipherProviderImpl provider;

      setUp(() {
        mockCipher = MockBiometricCipher();
        provider = BiometricCipherProviderImpl.forTesting(mockCipher);
      });

      test('maps keyNotFound to BiometricExceptionType.keyNotFound', () async {
        when(() => mockCipher.deleteKey(tag: any(named: 'tag'))).thenThrow(
          const BiometricCipherException(
            code: BiometricCipherExceptionCode.keyNotFound,
            message: 'missing',
          ),
        );

        await expectLater(
          () => provider.deleteKey(tag: 'my-key'),
          throwsA(
            isA<BiometricException>()
                .having((e) => e.type, 'type', BiometricExceptionType.keyNotFound)
                .having((e) => e.message, 'message', 'missing'),
          ),
        );
      });
    });
  });
}
