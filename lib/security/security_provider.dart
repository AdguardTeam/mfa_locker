import 'dart:async';
import 'dart:typed_data';

import 'package:locker/locker/locker.dart';
import 'package:locker/security/models/bio_cipher_func.dart';
import 'package:locker/security/models/password_cipher_func.dart';
import 'package:locker/storage/models/exceptions/storage_exception.dart';
import 'package:locker/utils/cryptography_utils.dart';

/// Handles authentication requests to obtain cipher functions.
abstract class SecurityProvider {
  Future<PasswordCipherFunc> authenticatePassword({
    required String password,
    bool forceNewSalt = false,
  });

  Future<BioCipherFunc> authenticateBiometric();
}

class SecurityProviderImpl implements SecurityProvider {
  final Locker locker;
  final String biometricKeyTag;

  SecurityProviderImpl({
    required this.locker,
    this.biometricKeyTag = 'biometric',
  });

  @override
  Future<PasswordCipherFunc> authenticatePassword({
    required String password,
    bool forceNewSalt = false,
  }) async {
    Uint8List salt;

    final isInitialized = await locker.isStorageInitialized;

    if (forceNewSalt || !isInitialized) {
      salt = CryptographyUtils.generateSalt();
    } else {
      try {
        salt = await locker.salt;
      } on StorageException catch (e) {
        if (e.type == StorageExceptionType.notInitialized) {
          salt = CryptographyUtils.generateSalt();
        } else {
          rethrow;
        }
      }
    }

    return PasswordCipherFunc(password: password, salt: salt);
  }

  @override
  Future<BioCipherFunc> authenticateBiometric() async => BioCipherFunc(keyTag: biometricKeyTag);
}
