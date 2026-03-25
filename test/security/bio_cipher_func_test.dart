import 'dart:typed_data';

import 'package:locker/erasable/erasable_byte_array.dart';
import 'package:locker/security/models/bio_cipher_func.dart';
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
          () => mockProvider.encrypt(tag: any(named: 'tag'), data: any(named: 'data')),
        );
      });

      // Note: BioCipherFunc.encrypt accesses data.bytes inside the ArgumentError.value
      // constructor even when data.isErased is true, causing a StateError instead of
      // ArgumentError. This test documents the current behavior.
      test('throws StateError when data is erased', () async {
        final data = ErasableByteArray(Uint8List.fromList([1, 2, 3]));
        data.erase();

        await expectLater(
          () => sut.encrypt(data),
          throwsA(isA<StateError>()),
        );

        verifyNever(
          () => mockProvider.encrypt(tag: any(named: 'tag'), data: any(named: 'data')),
        );
      });

      test('rethrows exception from provider', () async {
        final data = ErasableByteArray(Uint8List.fromList([1, 2, 3]));
        final exception = Exception('provider error');

        when(
          () => mockProvider.encrypt(tag: any(named: 'tag'), data: any(named: 'data')),
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
          () => mockProvider.decrypt(tag: any(named: 'tag'), data: any(named: 'data')),
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
          () => mockProvider.decrypt(tag: any(named: 'tag'), data: any(named: 'data')),
        );
      });

      test('rethrows exception from provider', () async {
        final exception = Exception('provider error');

        when(
          () => mockProvider.decrypt(tag: any(named: 'tag'), data: any(named: 'data')),
        ).thenThrow(exception);

        await expectLater(
          () => sut.decrypt(Uint8List.fromList([4, 5, 6])),
          throwsA(same(exception)),
        );
      });
    });
  });
}
