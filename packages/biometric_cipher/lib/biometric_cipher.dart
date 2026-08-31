import 'package:biometric_cipher/data/biometric_status.dart';

import 'package:biometric_cipher/data/model/config_data.dart';
import 'package:biometric_cipher/data/biometric_cipher_exception.dart';
import 'package:biometric_cipher/data/biometric_cipher_exception_code.dart';
import 'package:biometric_cipher/data/tpm_key_info.dart';
import 'package:biometric_cipher/data/tpm_status.dart';
import 'package:biometric_cipher/biometric_cipher_platform_interface.dart';

export 'package:biometric_cipher/data/biometric_cipher_exception.dart';
export 'package:biometric_cipher/data/biometric_cipher_exception_code.dart';

class BiometricCipher {
  final BiometricCipherPlatform _instance;

  BiometricCipher([
    BiometricCipherPlatform? instance,
  ]) : _instance = instance ?? BiometricCipherPlatform.instance;

  bool _configured = false;

  bool get configured => _configured;

  Future<void> configure({required ConfigData config}) async {
    _configured = false;
    await _instance.configure(configData: config);
    _configured = true;
  }

  Future<TPMStatus> getTPMStatus() => _instance.getTPMStatus();

  /// Returns the major TPM version of the device, e.g. `2` for TPM 2.0.
  Future<int> getTpmVersion() => _instance.getTPMVersion();

  /// Returns all TPM-resident keys stored by the platform crypto provider.
  ///
  /// The list is diagnostic: it includes keys created by other applications
  /// and the OS itself, and entries cannot be mapped to this plugin's tags.
  Future<List<TpmKeyInfo>> listKeys() => _instance.listKeys();

  Future<BiometricStatus> getBiometryStatus() => _instance.getBiometryStatus();

  Future<void> generateKey({required String tag}) {
    if (tag.isEmpty) {
      throw const BiometricCipherException(
        code: BiometricCipherExceptionCode.invalidArgument,
        message: 'Tag cannot be empty',
      );
    }

    return _instance.generateKey(tag: tag);
  }

  Future<String?> encrypt({required String tag, required String data}) {
    if (tag.isEmpty) {
      throw const BiometricCipherException(
        code: BiometricCipherExceptionCode.invalidArgument,
        message: 'Tag cannot be empty',
      );
    }

    if (data.isEmpty) {
      throw const BiometricCipherException(
        code: BiometricCipherExceptionCode.invalidArgument,
        message: 'Data cannot be empty',
      );
    }

    return _instance.encrypt(tag: tag, data: data);
  }

  Future<String?> decrypt({required String tag, required String data}) {
    if (_configured == false) {
      throw const BiometricCipherException(
        code: BiometricCipherExceptionCode.configureError,
        message: 'Plugin is not configured',
      );
    }

    if (tag.isEmpty) {
      throw const BiometricCipherException(
        code: BiometricCipherExceptionCode.invalidArgument,
        message: 'Tag cannot be empty',
      );
    }

    if (data.isEmpty) {
      throw const BiometricCipherException(
        code: BiometricCipherExceptionCode.invalidArgument,
        message: 'Data cannot be empty',
      );
    }

    return _instance.decrypt(tag: tag, data: data);
  }

  Future<void> deleteKey({required String tag}) {
    if (tag.isEmpty) {
      throw const BiometricCipherException(
        code: BiometricCipherExceptionCode.invalidArgument,
        message: 'Tag cannot be empty',
      );
    }

    return _instance.deleteKey(tag: tag);
  }

  Future<bool> isKeyValid({required String tag}) {
    if (tag.isEmpty) {
      throw const BiometricCipherException(
        code: BiometricCipherExceptionCode.invalidArgument,
        message: 'Tag cannot be empty',
      );
    }

    return _instance.isKeyValid(tag: tag);
  }

  /// Encrypts [data] with the key identified by [tag], handling TPM checks
  /// and key creation automatically.
  ///
  /// Checks that the TPM is present and supported, generates the key for
  /// [tag] if it does not exist yet, encrypts [data], and returns it as a
  /// Base64-encoded string.
  ///
  /// The plugin must be configured via [configure] before calling this method.
  ///
  /// Throws [BiometricCipherException] with:
  /// - [BiometricCipherExceptionCode.invalidArgument] if [tag] or [data] is empty.
  /// - [BiometricCipherExceptionCode.tpmUnsupported] if the TPM is not
  ///   present or its version is incompatible.
  /// - [BiometricCipherExceptionCode.encryptionError] if encryption fails.
  Future<String> encryptString({required String tag, required String data}) async {
    if (tag.isEmpty) {
      throw const BiometricCipherException(
        code: BiometricCipherExceptionCode.invalidArgument,
        message: 'Tag cannot be empty',
      );
    }

    if (data.isEmpty) {
      throw const BiometricCipherException(
        code: BiometricCipherExceptionCode.invalidArgument,
        message: 'Data cannot be empty',
      );
    }

    final status = await getTPMStatus();

    if (status != TPMStatus.supported) {
      throw const BiometricCipherException(
        code: BiometricCipherExceptionCode.tpmUnsupported,
        message: 'TPM is unsupported or has an incompatible version',
      );
    }

    if (!await isKeyValid(tag: tag)) {
      await generateKey(tag: tag);
    }

    final encryptedData = await encrypt(tag: tag, data: data);

    if (encryptedData == null) {
      throw const BiometricCipherException(
        code: BiometricCipherExceptionCode.encryptionError,
        message: 'Encryption failed',
      );
    }

    return encryptedData;
  }

  /// Decrypts the Base64-encoded [data] with the key identified by [tag].
  ///
  /// Checks that the TPM is present and supported, then decrypts [data] and
  /// returns the plaintext string. Unlike [encryptString], the key for [tag]
  /// is never created implicitly: decryption fails if the key is missing.
  ///
  /// The plugin must be configured via [configure] before calling this method.
  ///
  /// Throws [BiometricCipherException] with:
  /// - [BiometricCipherExceptionCode.invalidArgument] if [tag] or [data] is empty.
  /// - [BiometricCipherExceptionCode.tpmUnsupported] if the TPM is not
  ///   present or its version is incompatible.
  /// - [BiometricCipherExceptionCode.keyNotFound] if no key exists for [tag].
  /// - [BiometricCipherExceptionCode.decryptionError] if decryption fails.
  Future<String> decryptString({required String tag, required String data}) async {
    if (tag.isEmpty) {
      throw const BiometricCipherException(
        code: BiometricCipherExceptionCode.invalidArgument,
        message: 'Tag cannot be empty',
      );
    }

    if (data.isEmpty) {
      throw const BiometricCipherException(
        code: BiometricCipherExceptionCode.invalidArgument,
        message: 'Data cannot be empty',
      );
    }

    final status = await getTPMStatus();

    if (status != TPMStatus.supported) {
      throw const BiometricCipherException(
        code: BiometricCipherExceptionCode.tpmUnsupported,
        message: 'TPM is unsupported or has an incompatible version',
      );
    }

    if (!await isKeyValid(tag: tag)) {
      throw BiometricCipherException(
        code: BiometricCipherExceptionCode.keyNotFound,
        message: 'Key not found for tag $tag',
      );
    }

    final decryptedData = await decrypt(tag: tag, data: data);

    if (decryptedData == null) {
      throw const BiometricCipherException(
        code: BiometricCipherExceptionCode.decryptionError,
        message: 'Decryption failed',
      );
    }

    return decryptedData;
  }
}
