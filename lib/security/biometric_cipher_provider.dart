import 'dart:convert';
import 'dart:typed_data';

import 'package:biometric_cipher/biometric_cipher.dart';
import 'package:biometric_cipher/data/biometric_status.dart';
import 'package:biometric_cipher/data/tpm_status.dart';
import 'package:locker/security/models/biometric_config.dart';
import 'package:locker/security/models/exceptions/biometric_exception.dart';

/// Interface for biometric cipher storage and cryptographic operations.
///
/// Provides methods to configure biometric access, manage cryptographic keys,
/// and perform encryption/decryption operations using hardware-backed security
/// (TPM/Secure Enclave) where available.
abstract class BiometricCipherProvider {
  /// Configures the biometric settings for the provider.
  ///
  /// [config] contains the biometric configuration parameters.
  Future<void> configure(BiometricConfig config);

  /// Retrieves the current status of the Trusted Platform Module (TPM) or equivalent.
  ///
  /// Returns a [TPMStatus] indicating availability and readiness.
  Future<TPMStatus> getTPMStatus();

  /// Retrieves the current status of biometric authentication availability.
  ///
  /// Returns a [BiometricStatus] indicating if biometrics are supported, enrolled, etc.
  Future<BiometricStatus> getBiometryStatus();

  /// Generates a new cryptographic key pair identified by [tag].
  ///
  /// If a key with the specified [tag] already exists, it may be overwritten or
  /// throw an error depending on the underlying implementation.
  Future<void> generateKey({required String tag});

  /// Encrypts data and returns encrypted bytes.
  /// Input data is converted to base64 before encryption.
  /// Output is base64-decoded from provider result.
  Future<Uint8List> encrypt({required String tag, required Uint8List data});

  /// Decrypts data and returns decrypted bytes.
  /// Input data is converted to base64 before decryption.
  /// Output is base64-decoded from provider result.
  Future<Uint8List> decrypt({required String tag, required Uint8List data});

  /// Deletes the cryptographic key identified by [tag].
  ///
  /// If the key does not exist, this operation should complete without error.
  Future<void> deleteKey({required String tag});
}

/// Implementation of [BiometricCipherProvider] using the `biometric_cipher` package.
class BiometricCipherProviderImpl implements BiometricCipherProvider {
  BiometricCipherProviderImpl._();

  static final BiometricCipherProvider instance = BiometricCipherProviderImpl._();

  final BiometricCipher _biometricCipher = BiometricCipher();

  @override
  Future<void> configure(BiometricConfig config) => _biometricCipher.configure(config: config.toConfigData());

  @override
  Future<TPMStatus> getTPMStatus() => _biometricCipher.getTPMStatus();

  @override
  Future<BiometricStatus> getBiometryStatus() => _biometricCipher.getBiometryStatus();

  @override
  Future<void> generateKey({required String tag}) => _biometricCipher.generateKey(tag: tag);

  @override
  Future<Uint8List> encrypt({required String tag, required Uint8List data}) async {
    try {
      final base64Data = base64Encode(data);
      final encrypted = await _biometricCipher.encrypt(tag: tag, data: base64Data);

      if (encrypted == null) {
        throw StateError('BiometricCipher.encrypt returned null');
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
        throw StateError('BiometricCipher.decrypt returned null');
      }

      return base64Decode(decrypted);
    } on BiometricCipherException catch (e, stackTrace) {
      Error.throwWithStackTrace(_mapExceptionToBiometricException(e), stackTrace);
    }
  }

  @override
  Future<void> deleteKey({required String tag}) => _biometricCipher.deleteKey(tag: tag);

  BiometricException _mapExceptionToBiometricException(BiometricCipherException e) => switch (e.code) {
        BiometricCipherExceptionCode.keyNotFound => const BiometricException(BiometricExceptionType.keyNotFound),
        BiometricCipherExceptionCode.keyAlreadyExists =>
          const BiometricException(BiometricExceptionType.keyAlreadyExists),
        BiometricCipherExceptionCode.authenticationUserCanceled =>
          const BiometricException(BiometricExceptionType.cancel),
        BiometricCipherExceptionCode.authenticationError ||
        BiometricCipherExceptionCode.encryptionError ||
        BiometricCipherExceptionCode.decryptionError =>
          const BiometricException(BiometricExceptionType.failure),
        BiometricCipherExceptionCode.biometricNotSupported ||
        BiometricCipherExceptionCode.secureEnclaveUnavailable ||
        BiometricCipherExceptionCode.tpmUnsupported =>
          const BiometricException(BiometricExceptionType.notAvailable),
        BiometricCipherExceptionCode.configureError => const BiometricException(BiometricExceptionType.notConfigured),
        _ => BiometricException(BiometricExceptionType.failure, originalError: e),
      };
}
