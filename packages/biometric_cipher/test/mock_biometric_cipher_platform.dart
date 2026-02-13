import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:biometric_cipher/data/biometric_status.dart';
import 'package:biometric_cipher/data/model/config_data.dart';
import 'package:biometric_cipher/data/biometric_cipher_exception.dart';
import 'package:biometric_cipher/data/biometric_cipher_exception_code.dart';
import 'package:biometric_cipher/data/tpm_status.dart';
import 'package:biometric_cipher/biometric_cipher_platform_interface.dart';

/// A mock implementation of [BiometricCipherPlatform] for testing purposes.
///
/// This mock simulates the behavior of the actual platform-specific
/// implementation, allowing for isolated and controlled testing of
/// [BiometricCipher].
class MockBiometricCipherPlatform with MockPlatformInterfaceMixin implements BiometricCipherPlatform {
  /// Indicates whether the plugin has been configured.
  bool isConfigured = false;

  /// A map to store generated keys associated with their tags.
  final Map<String, String> _storedKeys = {};

  /// Provides read-only access to the stored keys (for test verifications).
  Map<String, String> get keys => Map.unmodifiable(_storedKeys);

  /// Configures the mock platform with the provided [configData].
  ///
  /// Sets [isConfigured] to `true` to simulate successful configuration.
  @override
  Future<void> configure({required ConfigData configData}) async {
    // Simulate successful configuration
    isConfigured = true;
  }

  /// Retrieves the current TPM status.
  ///
  /// Always returns [TPMStatus.supported] in this mock.
  @override
  Future<TPMStatus> getTPMStatus() async => TPMStatus.supported;

  /// Retrieves the biometry status.
  ///
  /// Always returns `BiometricStatus.supported` in this mock.
  @override
  Future<BiometricStatus> getBiometryStatus() async => BiometricStatus.supported;

  /// Generates a cryptographic key associated with the given [tag].
  ///
  /// Stores the key in the [_storedKeys] map.
  ///
  /// Throws an [Exception] if [tag] is empty.
  @override
  Future<void> generateKey({required String tag}) async {
    if (tag.isEmpty) {
      throw const BiometricCipherException(
        code: BiometricCipherExceptionCode.invalidArgument,
        message: 'Tag cannot be empty (Mock)',
      );
    }

    if (_storedKeys.containsKey(tag)) {
      throw const BiometricCipherException(
        code: BiometricCipherExceptionCode.keyAlreadyExists,
        message: 'Key already exists (Mock)',
      );
    }

    _storedKeys[tag] = 'key_for_$tag';
  }

  /// Encrypts the provided [data] using the key associated with [tag].
  ///
  /// Returns the encrypted data prefixed with `'encrypted_'`.
  ///
  /// Throws an [Exception] if the key for [tag] does not exist or if [data] is empty.
  @override
  Future<String?> encrypt({required String tag, required String data}) async {
    if (!_storedKeys.containsKey(tag)) {
      throw BiometricCipherException(
        code: BiometricCipherExceptionCode.keyNotFound,
        message: 'Key not found for tag $tag (Mock)',
      );
    }
    if (data.isEmpty) {
      throw const BiometricCipherException(
        code: BiometricCipherExceptionCode.invalidArgument,
        message: 'Data cannot be empty (Mock)',
      );
    }
    return 'encrypted_$data';
  }

  /// Decrypts the provided [data] using the key associated with [tag].
  ///
  /// Removes the `'encrypted_'` prefix from [data].
  ///
  /// Throws an [Exception] if the plugin is not configured,
  /// if the key for [tag] does not exist, if [data] is empty,
  /// or if [data] does not start with `'encrypted_'`.
  @override
  Future<String?> decrypt({required String tag, required String data}) async {
    if (!isConfigured) {
      throw const BiometricCipherException(
        code: BiometricCipherExceptionCode.configureError,
        message: 'Plugin is not configured (Mock)',
      );
    }
    if (!_storedKeys.containsKey(tag)) {
      throw BiometricCipherException(
        code: BiometricCipherExceptionCode.keyNotFound,
        message: 'Key not found for tag $tag (Mock)',
      );
    }
    if (data.isEmpty) {
      throw const BiometricCipherException(
        code: BiometricCipherExceptionCode.invalidArgument,
        message: 'Data cannot be empty (Mock)',
      );
    }
    if (!data.startsWith('encrypted_')) {
      throw const BiometricCipherException(
        code: BiometricCipherExceptionCode.decryptionError,
        message: 'Invalid encrypted data (Mock)',
      );
    }
    return data.replaceFirst('encrypted_', '');
  }

  /// Deletes the cryptographic key associated with the given [tag].
  ///
  /// Removes the key from the [_storedKeys] map.
  ///
  /// Throws an [Exception] if [tag] is empty.
  @override
  Future<void> deleteKey({required String tag}) async {
    if (tag.isEmpty) {
      throw const BiometricCipherException(
        code: BiometricCipherExceptionCode.invalidArgument,
        message: 'Tag cannot be empty (Mock)',
      );
    }
    _storedKeys.remove(tag);
  }
}
