import 'dart:convert';
import 'dart:typed_data';

import 'package:locker/security/models/biometric_config.dart';
import 'package:locker/security/models/exceptions/biometric_exception.dart';
import 'package:secure_mnemonic/data/biometric_status.dart';
import 'package:secure_mnemonic/data/tpm_status.dart';
import 'package:secure_mnemonic/secure_mnemonic.dart';

/// Interface for secure mnemonic storage and cryptographic operations.
///
/// Provides methods to configure biometric access, manage cryptographic keys,
/// and perform encryption/decryption operations using hardware-backed security
/// (TPM/Secure Enclave) where available.
abstract class SecureMnemonicProvider {
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

/// Implementation of [SecureMnemonicProvider] using the `secure_mnemonic` package.
class SecureMnemonicProviderImpl implements SecureMnemonicProvider {
  SecureMnemonicProviderImpl._();

  static final SecureMnemonicProvider instance = SecureMnemonicProviderImpl._();

  final SecureMnemonic _secureMnemonic = SecureMnemonic();

  @override
  Future<void> configure(BiometricConfig config) => _secureMnemonic.configure(config: config.toConfigData());

  @override
  Future<TPMStatus> getTPMStatus() => _secureMnemonic.getTPMStatus();

  @override
  Future<BiometricStatus> getBiometryStatus() => _secureMnemonic.getBiometryStatus();

  @override
  Future<void> generateKey({required String tag}) => _secureMnemonic.generateKey(tag: tag);

  @override
  Future<Uint8List> encrypt({required String tag, required Uint8List data}) async {
    try {
      final base64Data = base64Encode(data);
      final encrypted = await _secureMnemonic.encrypt(tag: tag, data: base64Data);

      if (encrypted == null) {
        throw StateError('SecureMnemonic.encrypt returned null');
      }

      return base64Decode(encrypted);
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(_mapPluginError(error), stackTrace);
    }
  }

  @override
  Future<Uint8List> decrypt({required String tag, required Uint8List data}) async {
    try {
      final base64Data = base64Encode(data);
      final decrypted = await _secureMnemonic.decrypt(tag: tag, data: base64Data);

      if (decrypted == null) {
        throw StateError('SecureMnemonic.decrypt returned null');
      }

      return base64Decode(decrypted);
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(_mapPluginError(error), stackTrace);
    }
  }

  @override
  Future<void> deleteKey({required String tag}) => _secureMnemonic.deleteKey(tag: tag);

  Object _mapPluginError(Object error) {
    final message = error.toString().toLowerCase();

    if (_containsAny(message, const ['key_not_found', 'key not found'])) {
      return const BiometricException(BiometricExceptionType.keyNotFound);
    }

    if (_containsAny(message, const ['key_already_exists', 'key already exists'])) {
      return const BiometricException(BiometricExceptionType.keyAlreadyExists);
    }

    if (_containsAny(
      message,
      const ['authentication_user_canceled', 'authentication user canceled'],
    )) {
      return const BiometricException(BiometricExceptionType.cancel);
    }

    // Map authentication failures (wrong finger/face, decryption errors) to cancellation
    // This allows graceful retry without crashing
    if (_containsAny(
      message,
      const [
        'keychainserviceerror',
        'decryption_error',
        'authentication_failed',
        'authentication failed',
        'errsecinvalidpassword',
        'errsecauthfailed',
        'authentication error',
      ],
    )) {
      return const BiometricException(BiometricExceptionType.failure);
    }

    if (_containsAny(
      message,
      const ['biometric_not_supported', 'biometric not supported'],
    )) {
      return const BiometricException(BiometricExceptionType.notAvailable);
    }

    if (_containsAny(message, const ['not_configured', 'not configured'])) {
      return const BiometricException(BiometricExceptionType.notConfigured);
    }

    return Exception(message);
  }

  bool _containsAny(String message, List<String> values) => values.any((value) => message.contains(value));
}
