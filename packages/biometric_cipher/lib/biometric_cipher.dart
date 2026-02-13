import 'package:biometric_cipher/data/biometric_status.dart';

import 'package:biometric_cipher/data/model/config_data.dart';
import 'package:biometric_cipher/data/biometric_cipher_exception.dart';
import 'package:biometric_cipher/data/biometric_cipher_exception_code.dart';
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
}
