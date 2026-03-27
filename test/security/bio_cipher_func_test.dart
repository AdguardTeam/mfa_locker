import 'dart:typed_data';

import 'package:locker/erasable/erasable_byte_array.dart';
import 'package:locker/security/models/bio_cipher_func.dart';
import 'package:locker/security/models/exceptions/biometric_exception.dart';
import 'package:locker/storage/models/data/origin.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../mocks/mock_biometric_cipher_provider.dart';

void main() {
  late MockBiometricCipherProvider mockProvider;
  late BioCipherFunc sut;

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    mockProvider = MockBiometricCipherProvider();
    sut = BioCipherFunc(keyTag: 'test-key', secureProviderOverride: mockProvider);
  });

  group('BioCipherFunc', () {
    group('constructor and properties', () {
      test('throws AssertionError when keyTag is empty', () {
        expect(
          () => BioCipherFunc(keyTag: '', secureProviderOverride: mockProvider),
          throwsA(isA<AssertionError>()),
        );
      });

      test('origin returns Origin.bio', () {
        expect(sut.origin, Origin.bio);
      });

      test('isErased always returns false', () {
        expect(sut.isErased, false);
      });
    });

    group('encrypt', () {
      test('returns encrypted bytes from provider', () async {
        final inputBytes = Uint8List.fromList([1, 2, 3]);
        final encryptedBytes = Uint8List.fromList([4, 5, 6]);
        final data = ErasableByteArray(inputBytes);

        when(
          () => mockProvider.encrypt(tag: 'test-key', data: inputBytes),
        ).thenAnswer((_) async => encryptedBytes);

        final result = await sut.encrypt(data);

        expect(result, encryptedBytes);
        verify(() => mockProvider.encrypt(tag: 'test-key', data: inputBytes)).called(1);
      });

      test('throws ArgumentError when data is empty', () async {
        final data = ErasableByteArray(Uint8List(0));

        await expectLater(
          () => sut.encrypt(data),
          throwsA(isA<ArgumentError>()),
        );

        verifyNever(
          () => mockProvider.encrypt(
            tag: any(named: 'tag'),
            data: any(named: 'data'),
          ),
        );
      });

      test('throws ArgumentError when data is erased', () async {
        final data = ErasableByteArray(Uint8List.fromList([1, 2, 3]));
        data.erase();

        await expectLater(
          () => sut.encrypt(data),
          throwsA(isA<ArgumentError>()),
        );

        verifyNever(
          () => mockProvider.encrypt(
            tag: any(named: 'tag'),
            data: any(named: 'data'),
          ),
        );
      });

      test('rethrows exception from provider', () async {
        final data = ErasableByteArray(Uint8List.fromList([1, 2, 3]));
        final exception = Exception('provider error');

        when(
          () => mockProvider.encrypt(
            tag: any(named: 'tag'),
            data: any(named: 'data'),
          ),
        ).thenThrow(exception);

        await expectLater(
          () => sut.encrypt(data),
          throwsA(same(exception)),
        );
      });
    });

    group('decrypt', () {
      test('returns ErasableByteArray with decrypted bytes from provider', () async {
        final encryptedData = Uint8List.fromList([4, 5, 6]);
        final decryptedBytes = Uint8List.fromList([1, 2, 3]);

        when(
          () => mockProvider.decrypt(
            tag: any(named: 'tag'),
            data: any(named: 'data'),
          ),
        ).thenAnswer((_) async => decryptedBytes);

        final result = await sut.decrypt(encryptedData);

        expect(result, isA<ErasableByteArray>());
        expect(result.bytes, decryptedBytes);
        verify(() => mockProvider.decrypt(tag: 'test-key', data: encryptedData)).called(1);
      });

      test('throws ArgumentError when data is empty', () async {
        await expectLater(
          () => sut.decrypt(Uint8List(0)),
          throwsA(isA<ArgumentError>()),
        );

        verifyNever(
          () => mockProvider.decrypt(
            tag: any(named: 'tag'),
            data: any(named: 'data'),
          ),
        );
      });

      test('rethrows exception from provider', () async {
        final exception = Exception('provider error');

        when(
          () => mockProvider.decrypt(
            tag: any(named: 'tag'),
            data: any(named: 'data'),
          ),
        ).thenThrow(exception);

        await expectLater(
          () => sut.decrypt(Uint8List.fromList([4, 5, 6])),
          throwsA(same(exception)),
        );
      });

      test('rethrows as keyInvalidated when failure occurs and key is invalid', () async {
        when(
          () => mockProvider.decrypt(
            tag: any(named: 'tag'),
            data: any(named: 'data'),
          ),
        ).thenThrow(const BiometricException(BiometricExceptionType.failure));

        when(
          () => mockProvider.isKeyValid(tag: any(named: 'tag')),
        ).thenAnswer((_) async => false);

        await expectLater(
          () => sut.decrypt(Uint8List.fromList([4, 5, 6])),
          throwsA(
            isA<BiometricException>().having((e) => e.type, 'type', BiometricExceptionType.keyInvalidated),
          ),
        );

        verify(() => mockProvider.isKeyValid(tag: 'test-key')).called(1);
      });

      test('rethrows original failure when key is still valid', () async {
        const originalException = BiometricException(BiometricExceptionType.failure);

        when(
          () => mockProvider.decrypt(
            tag: any(named: 'tag'),
            data: any(named: 'data'),
          ),
        ).thenThrow(originalException);

        when(
          () => mockProvider.isKeyValid(tag: any(named: 'tag')),
        ).thenAnswer((_) async => true);

        await expectLater(
          () => sut.decrypt(Uint8List.fromList([4, 5, 6])),
          throwsA(same(originalException)),
        );
      });

      test('rethrows original failure when isKeyValid throws', () async {
        const originalException = BiometricException(BiometricExceptionType.failure);

        when(
          () => mockProvider.decrypt(
            tag: any(named: 'tag'),
            data: any(named: 'data'),
          ),
        ).thenThrow(originalException);

        when(
          () => mockProvider.isKeyValid(tag: any(named: 'tag')),
        ).thenThrow(Exception('isKeyValid failed'));

        await expectLater(
          () => sut.decrypt(Uint8List.fromList([4, 5, 6])),
          throwsA(same(originalException)),
        );
      });

      test('does not check key validity for non-failure BiometricExceptions', () async {
        when(
          () => mockProvider.decrypt(
            tag: any(named: 'tag'),
            data: any(named: 'data'),
          ),
        ).thenThrow(const BiometricException(BiometricExceptionType.cancel));

        await expectLater(
          () => sut.decrypt(Uint8List.fromList([4, 5, 6])),
          throwsA(
            isA<BiometricException>().having((e) => e.type, 'type', BiometricExceptionType.cancel),
          ),
        );

        verifyNever(() => mockProvider.isKeyValid(tag: any(named: 'tag')));
      });
    });
  });
}
