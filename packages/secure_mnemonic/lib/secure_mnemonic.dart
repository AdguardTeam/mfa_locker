import 'package:secure_mnemonic/data/biometric_status.dart';

import 'package:secure_mnemonic/data/model/config_data.dart';
import 'package:secure_mnemonic/data/secure_mnemonic_exception.dart';
import 'package:secure_mnemonic/data/secure_mnemonic_exception_code.dart';
import 'package:secure_mnemonic/data/tpm_status.dart';
import 'package:secure_mnemonic/secure_mnemonic_platform_interface.dart';

export 'package:secure_mnemonic/data/secure_mnemonic_exception.dart';
export 'package:secure_mnemonic/data/secure_mnemonic_exception_code.dart';

class SecureMnemonic {
  final SecureMnemonicPlatform _instance;

  SecureMnemonic([
    SecureMnemonicPlatform? instance,
  ]) : _instance = instance ?? SecureMnemonicPlatform.instance;

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
      throw const SecureMnemonicException(
        code: SecureMnemonicExceptionCode.invalidArgument,
        message: 'Tag cannot be empty',
      );
    }

    return _instance.generateKey(tag: tag);
  }

  Future<String?> encrypt({required String tag, required String data}) {
    if (tag.isEmpty) {
      throw const SecureMnemonicException(
        code: SecureMnemonicExceptionCode.invalidArgument,
        message: 'Tag cannot be empty',
      );
    }

    if (data.isEmpty) {
      throw const SecureMnemonicException(
        code: SecureMnemonicExceptionCode.invalidArgument,
        message: 'Data cannot be empty',
      );
    }

    return _instance.encrypt(tag: tag, data: data);
  }

  Future<String?> decrypt({required String tag, required String data}) {
    if (_configured == false) {
      throw const SecureMnemonicException(
        code: SecureMnemonicExceptionCode.configureError,
        message: 'Plugin is not configured',
      );
    }

    if (tag.isEmpty) {
      throw const SecureMnemonicException(
        code: SecureMnemonicExceptionCode.invalidArgument,
        message: 'Tag cannot be empty',
      );
    }

    if (data.isEmpty) {
      throw const SecureMnemonicException(
        code: SecureMnemonicExceptionCode.invalidArgument,
        message: 'Data cannot be empty',
      );
    }

    return _instance.decrypt(tag: tag, data: data);
  }

  Future<void> deleteKey({required String tag}) {
    if (tag.isEmpty) {
      throw const SecureMnemonicException(
        code: SecureMnemonicExceptionCode.invalidArgument,
        message: 'Tag cannot be empty',
      );
    }

    return _instance.deleteKey(tag: tag);
  }
}
