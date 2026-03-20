import 'dart:typed_data';

import 'package:biometric_cipher/biometric_cipher.dart';
import 'package:locker/security/biometric_cipher_provider.dart';
import 'package:locker/security/models/exceptions/biometric_exception.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../mocks/mock_biometric_cipher.dart';

void main() {
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
            isA<BiometricException>().having((e) => e.type, 'type', BiometricExceptionType.keyInvalidated),
          ),
        );
      });

      test('maps authenticationError to BiometricExceptionType.failure', () async {
        // Arrange
        when(
          () => mockCipher.decrypt(
            tag: any(named: 'tag'),
            data: any(named: 'data'),
          ),
        ).thenThrow(
          const BiometricCipherException(
            code: BiometricCipherExceptionCode.authenticationError,
            message: 'test',
          ),
        );

        // Act & Assert
        await expectLater(
          () => provider.decrypt(tag: 'tag', data: Uint8List.fromList([1])),
          throwsA(
            isA<BiometricException>().having((e) => e.type, 'type', BiometricExceptionType.failure),
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
            isA<BiometricException>().having((e) => e.type, 'type', BiometricExceptionType.cancel),
          ),
        );
      });
    });
  });
}
