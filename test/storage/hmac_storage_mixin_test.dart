import 'dart:typed_data';

import 'package:locker/storage/hmac_storage_mixin.dart';
import 'package:locker/storage/models/data/storage_data.dart';
import 'package:locker/storage/models/data/wrapped_key.dart';
import 'package:locker/storage/models/exceptions/storage_exception.dart';
import 'package:locker/utils/cryptography_utils.dart';
import 'package:test/test.dart';
import 'encrypted_storage_test_helpers.dart';

typedef _Helpers = EncryptedStorageTestHelpers;

class _HmacHost with HmacStorageMixin {}

void main() {
  group('HmacStorageMixin', () {
    late _HmacHost host;

    setUp(() {
      host = _HmacHost();
    });

    group('verifySignature', () {
      test('Returns true for valid signature', () async {
        // Arrange
        final masterKey = await CryptographyUtils.generateAESKey();
        final data = await _Helpers.createStorageData(masterKey: masterKey);

        final decryptedHmacKey = await CryptographyUtils.decrypt(
          key: masterKey,
          data: data.hmacKey!,
        );

        // Act
        final verificationResult = await host.verifySignature(data, decryptedHmacKey);

        // Assert
        expect(verificationResult, isTrue);
      });

      test('Throws when signature is missing', () async {
        // Arrange
        final masterKey = await CryptographyUtils.generateAESKey();
        final data = await EncryptedStorageTestHelpers.createStorageData(masterKey: masterKey);
        final dataWithoutSignature = data.withoutHmacSignature();

        final decryptedHmacKey = await CryptographyUtils.decrypt(
          key: masterKey,
          data: data.hmacKey!,
        );

        // Act & Assert
        await expectLater(
          () => host.verifySignature(
            dataWithoutSignature,
            decryptedHmacKey,
          ),
          throwsA(isA<StorageException>()),
        );
      });

      test('Returns false for invalid payload', () async {
        // Arrange
        final masterKey = await CryptographyUtils.generateAESKey();
        final data = await EncryptedStorageTestHelpers.createStorageData(masterKey: masterKey);

        // Corrupt payload by changing salt
        final tampered = data.copyWith(salt: Uint8List.fromList([3, 4, 6]));

        final decryptedHmacKey = await CryptographyUtils.decrypt(
          key: masterKey,
          data: data.hmacKey!,
        );

        // Act
        final verificationResult = await host.verifySignature(
          tampered,
          decryptedHmacKey,
        );

        // Assert
        expect(verificationResult, isFalse);
      });
    });

    group('signDataWithHmac', () {
      test('Signs data with valid signature', () async {
        // Arrange
        final masterKey = await CryptographyUtils.generateAESKey();
        final data = StorageData(
          entries: const [],
          masterKey: const WrappedKey(wraps: []),
          salt: Uint8List.fromList([0]),
          lockTimeout: 0,
        );

        // Act
        final signedData = await host.signDataWithHmac(
          data: data,
          masterKey: masterKey,
        );

        // Assert
        final hmacKey = await CryptographyUtils.decrypt(
          key: masterKey,
          data: signedData.hmacKey!,
        );
        final verificationResult = await host.verifySignature(
          signedData,
          hmacKey,
        );

        expect(verificationResult, isTrue);
      });
    });
  });
}
