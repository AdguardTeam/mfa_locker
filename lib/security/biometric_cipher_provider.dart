import 'dart:convert';
import 'dart:typed_data';

import 'package:biometric_cipher/biometric_cipher.dart';
import 'package:biometric_cipher/data/biometric_status.dart';
import 'package:biometric_cipher/data/tpm_status.dart';
import 'package:locker/security/models/biometric_config.dart';
import 'package:locker/security/models/exceptions/biometric_exception.dart';
import 'package:meta/meta.dart';

/// Hardware-backed (TPM/Secure Enclave) key operations used by the locker.
abstract class BiometricCipherProvider {
  /// Applies [config] to the underlying plugin; call once at startup.
  Future<void> configure(BiometricConfig config);

  /// The TPM availability status of the device.
  Future<TPMStatus> getTPMStatus();

  /// The biometric availability status of the device.
  Future<BiometricStatus> getBiometryStatus();

  /// Generates a key for [tag]; an existing key may be overwritten or throw.
  Future<void> generateKey({required String tag});

  /// Encrypts [data] with the key of [tag]; the payload crosses the platform
  /// channel as base64.
  Future<Uint8List> encrypt({required String tag, required Uint8List data});

  /// Decrypts [data] with the key of [tag]; the payload crosses the platform
  /// channel as base64.
  Future<Uint8List> decrypt({required String tag, required Uint8List data});

  /// Deletes the key of [tag]; a missing key is not an error.
  Future<void> deleteKey({required String tag});

  /// Whether the key of [tag] exists and is still valid; never prompts.
  Future<bool> isKeyValid({required String tag});
}

/// Implementation of [BiometricCipherProvider] using the `biometric_cipher` package.
class BiometricCipherProviderImpl implements BiometricCipherProvider {
  static final BiometricCipherProvider instance = BiometricCipherProviderImpl._();

  final BiometricCipher _biometricCipher;

  BiometricCipherProviderImpl._() : _biometricCipher = BiometricCipher();

  @visibleForTesting
  BiometricCipherProviderImpl.forTesting(this._biometricCipher);

  @override
  Future<void> configure(BiometricConfig config) => _biometricCipher.configure(config: config.toConfigData());

  @override
  Future<TPMStatus> getTPMStatus() => _biometricCipher.getTPMStatus();

  @override
  Future<BiometricStatus> getBiometryStatus() => _biometricCipher.getBiometryStatus();

  @override
  Future<void> generateKey({required String tag}) async {
    try {
      await _biometricCipher.generateKey(tag: tag);
    } on BiometricCipherException catch (e, stackTrace) {
      Error.throwWithStackTrace(_mapExceptionToBiometricException(e), stackTrace);
    }
  }

  @override
  Future<Uint8List> encrypt({required String tag, required Uint8List data}) async {
    try {
      final base64Data = base64Encode(data);
      final encrypted = await _biometricCipher.encrypt(tag: tag, data: base64Data);

      if (encrypted == null) {
        throw const BiometricException(
          BiometricExceptionType.failure,
          message: 'BiometricCipher.encrypt returned null',
        );
      }

      return base64Decode(encrypted);
    } on BiometricCipherException catch (e, stackTrace) {
      Error.throwWithStackTrace(_mapExceptionToBiometricException(e), stackTrace);
    }
  }

  @override
  Future<Uint8List> decrypt({required String tag, required Uint8List data}) async {
    try {
      final base64Data = base64Encode(data);
      final decrypted = await _biometricCipher.decrypt(tag: tag, data: base64Data);

      if (decrypted == null) {
        throw const BiometricException(
          BiometricExceptionType.failure,
          message: 'BiometricCipher.decrypt returned null',
        );
      }

      return base64Decode(decrypted);
    } on BiometricCipherException catch (e, stackTrace) {
      Error.throwWithStackTrace(_mapExceptionToBiometricException(e), stackTrace);
    }
  }

  @override
  Future<void> deleteKey({required String tag}) => _biometricCipher.deleteKey(tag: tag);

  @override
  Future<bool> isKeyValid({required String tag}) => _biometricCipher.isKeyValid(tag: tag);

  BiometricException _mapExceptionToBiometricException(BiometricCipherException e) => switch (e.code) {
        BiometricCipherExceptionCode.keyNotFound => BiometricException(
            BiometricExceptionType.keyNotFound,
            message: e.message,
          ),
        BiometricCipherExceptionCode.keyAlreadyExists => BiometricException(
            BiometricExceptionType.keyAlreadyExists,
            message: e.message,
          ),
        BiometricCipherExceptionCode.keyPermanentlyInvalidated => BiometricException(
            BiometricExceptionType.keyInvalidated,
            message: e.message,
          ),
        BiometricCipherExceptionCode.authenticationUserCanceled => BiometricException(
            BiometricExceptionType.cancel,
            message: e.message,
          ),
        BiometricCipherExceptionCode.authenticationError ||
        BiometricCipherExceptionCode.encryptionError ||
        BiometricCipherExceptionCode.decryptionError =>
          BiometricException(
            BiometricExceptionType.failure,
            message: e.message,
          ),
        BiometricCipherExceptionCode.biometricNotSupported ||
        BiometricCipherExceptionCode.secureEnclaveUnavailable ||
        BiometricCipherExceptionCode.tpmUnsupported =>
          BiometricException(
            BiometricExceptionType.notAvailable,
            message: e.message,
          ),
        BiometricCipherExceptionCode.configureError => BiometricException(
            BiometricExceptionType.notConfigured,
            message: e.message,
          ),
        _ => BiometricException(BiometricExceptionType.failure, message: e.message, originalError: e),
      };
}
