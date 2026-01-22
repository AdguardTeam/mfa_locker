import 'dart:convert';

import 'dart:typed_data';

import 'package:adguard_logger/adguard_logger.dart';
import 'package:locker/erasable/erasable_byte_array.dart';
import 'package:locker/storage/models/data/storage_data.dart';
import 'package:locker/storage/models/exceptions/storage_exception.dart';
import 'package:locker/utils/cryptography_utils.dart';
import 'package:locker/utils/list_extensions.dart';

/// Mixin responsible for HMAC key handling, signing, and verification.
mixin HmacStorageMixin {
  /// Verifies that the HMAC signature inside [data] matches the expected value
  /// computed over the same payload without the signature.
  Future<bool> verifySignature(
    StorageData data,
    ErasableByteArray hmacKey,
  ) async {
    final signature = data.hmacSignature;

    if (signature == null) {
      throw StorageException.invalidStorage(message: 'No hmacSignature in data!');
    }

    final nonAuthCopy = data.withoutHmacSignature();
    final nonAuthJson = jsonEncode(nonAuthCopy.toJson());

    final expectedSignature = await CryptographyUtils.authenticateHmac(
      hmacKey: hmacKey,
      data: nonAuthJson.codeUnits.toUint8List(),
    );

    return _constantTimeEquals(signature, expectedSignature);
  }

  /// Generates a fresh HMAC key, embeds its encrypted form into [data],
  /// computes the signature, and returns the updated copy.
  Future<StorageData> signDataWithHmac({
    required StorageData data,
    required ErasableByteArray masterKey,
  }) async {
    final hmacKey = await CryptographyUtils.generateAESKey();

    try {
      final encryptedHmacKey = await CryptographyUtils.encrypt(
        key: masterKey,
        data: hmacKey,
      );

      final updatedData = data.copyWith(hmacKey: encryptedHmacKey);
      final nonAuthCopy = updatedData.withoutHmacSignature();

      final nonAuthJson = jsonEncode(nonAuthCopy.toJson());

      final hmacSignature = await CryptographyUtils.authenticateHmac(
        hmacKey: hmacKey,
        data: nonAuthJson.codeUnits.toUint8List(),
      );

      return updatedData.copyWith(hmacSignature: hmacSignature);
    } catch (e, st) {
      logger.logError('HmacStorageMixin: Failed to sign data with hmac', error: e, stackTrace: st);

      rethrow;
    } finally {
      hmacKey.erase();
    }
  }

  /// Compares two byte lists in constant time to prevent timing attacks.
  ///
  /// This implementation examines every byte regardless of mismatches to avoid
  /// timing side-channels commonly associated with early-exit comparisons.
  bool _constantTimeEquals(Uint8List signature, Uint8List expectedSignature) {
    if (signature.length != expectedSignature.length) {
      return false;
    }

    int result = 0;
    for (int i = 0; i < signature.length; i++) {
      // XOR will be non-zero for any differing byte; OR accumulates all diffs.
      result |= signature[i] ^ expectedSignature[i];
    }

    return result == 0;
  }
}
