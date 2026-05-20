import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:biometric_cipher/data/biometric_status.dart';
import 'package:biometric_cipher/data/model/config_data.dart';
import 'package:biometric_cipher/data/tpm_status.dart';

import 'biometric_cipher_method_channel.dart';

abstract class BiometricCipherPlatform extends PlatformInterface {
  /// Constructs a BiometricCipherPlatform.
  BiometricCipherPlatform() : super(token: _token);

  static final Object _token = Object();

  static const channelName = 'biometric_cipher';

  static BiometricCipherPlatform _instance = MethodChannelBiometricCipher();

  /// The default instance of [BiometricCipherPlatform] to use.
  ///
  /// Defaults to [MethodChannelBiometricCipher].
  static BiometricCipherPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [BiometricCipherPlatform] when
  /// they register themselves.
  static set instance(BiometricCipherPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Configures the biometric cipher plugin with platform-specific settings.
  ///
  /// Must be called before [decrypt] can be used. The [configData] provides
  /// platform-specific configuration such as biometric prompt titles and
  /// Android-specific options.
  ///
  /// Throws [BiometricCipherException] with
  /// [BiometricCipherExceptionCode.configureError] if configuration fails.
  Future<void> configure({required ConfigData configData}) {
    throw UnimplementedError('configure({required ConfigData configData}) has not been implemented.');
  }

  /// Retrieves the Trusted Platform Module (TPM) status of the device.
  ///
  /// Returns a [TPMStatus] indicating whether the device TPM is supported,
  /// unsupported, or has an incompatible version.
  Future<TPMStatus> getTPMStatus() {
    throw UnimplementedError('getTPMStatus() has not been implemented.');
  }

  /// Retrieves the biometric authentication status of the device.
  ///
  /// Returns a [BiometricStatus] indicating whether biometric authentication
  /// is supported, unavailable, not configured, or otherwise restricted.
  Future<BiometricStatus> getBiometryStatus() {
    throw UnimplementedError('getBiometryStatus() has not been implemented.');
  }

  /// Generates a hardware-backed cryptographic key identified by [tag].
  ///
  /// The key is stored in the platform's secure element (Keystore, Secure
  /// Enclave, or TPM) and can be used for subsequent [encrypt] and [decrypt]
  /// operations.
  ///
  /// Throws [BiometricCipherException] with:
  /// - [BiometricCipherExceptionCode.keyAlreadyExists] if a key with the
  ///   given [tag] already exists.
  /// - [BiometricCipherExceptionCode.keyGenerationError] if key creation fails.
  Future<void> generateKey({required String tag}) {
    throw UnimplementedError('generateKey({required String tag}) has not been implemented.');
  }

  /// Encrypts [data] using the cryptographic key identified by [tag].
  ///
  /// Triggers a biometric authentication prompt. Returns the encrypted data
  /// as a Base64-encoded string, or `null` if encryption could not be
  /// completed.
  ///
  /// Throws [BiometricCipherException] with:
  /// - [BiometricCipherExceptionCode.keyNotFound] if no key exists for [tag].
  /// - [BiometricCipherExceptionCode.encryptionError] if encryption fails.
  /// - [BiometricCipherExceptionCode.authenticationUserCanceled] if the user
  ///   dismisses the biometric prompt.
  Future<String?> encrypt({required String tag, required String data}) {
    throw UnimplementedError('encrypt({required String tag, required String data}) has not been implemented.');
  }

  /// Decrypts [data] using the cryptographic key identified by [tag].
  ///
  /// Triggers a biometric authentication prompt. Returns the decrypted
  /// plaintext string, or `null` if decryption could not be completed.
  ///
  /// The plugin must be configured via [configure] before calling this method.
  ///
  /// Throws [BiometricCipherException] with:
  /// - [BiometricCipherExceptionCode.configureError] if the plugin has not
  ///   been configured.
  /// - [BiometricCipherExceptionCode.keyNotFound] if no key exists for [tag].
  /// - [BiometricCipherExceptionCode.decryptionError] if decryption fails.
  /// - [BiometricCipherExceptionCode.authenticationUserCanceled] if the user
  ///   dismisses the biometric prompt.
  Future<String?> decrypt({required String tag, required String data}) {
    throw UnimplementedError('decrypt({required String tag, required String data}) has not been implemented.');
  }

  /// Deletes the cryptographic key identified by [tag] from the platform's
  /// secure storage.
  ///
  /// After deletion, any data encrypted with this key can no longer be
  /// decrypted.
  ///
  /// Throws [BiometricCipherException] with
  /// [BiometricCipherExceptionCode.keyDeletionError] if deletion fails.
  Future<void> deleteKey({required String tag}) {
    throw UnimplementedError('deleteKey() has not been implemented.');
  }

  /// Checks whether the biometric key identified by [tag] exists and is still
  /// valid, without triggering a biometric prompt.
  ///
  /// Returns `true` if the key exists and is usable, `false` if it has been
  /// permanently invalidated (e.g. due to a biometric enrollment change) or
  /// deleted.
  Future<bool> isKeyValid({required String tag}) {
    throw UnimplementedError('isKeyValid({required String tag}) has not been implemented.');
  }
}
