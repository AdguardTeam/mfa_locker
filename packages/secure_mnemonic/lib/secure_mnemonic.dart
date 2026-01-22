import 'package:secure_mnemonic/data/biometric_status.dart';
import 'package:secure_mnemonic/data/model/config_data.dart';
import 'package:secure_mnemonic/data/tpm_status.dart';
import 'package:secure_mnemonic/secure_mnemonic_platform_interface.dart';

class SecureMnemonic {
  bool configured = false;

  final SecureMnemonicPlatform _instance;

  SecureMnemonic([SecureMnemonicPlatform? instance]) : _instance = instance ?? SecureMnemonicPlatform.instance;

  Future<void> configure({required ConfigData config}) async {
    configured = false;
    await _instance.configure(configData: config);
    configured = true;
  }

  Future<TPMStatus> getTPMStatus() => _instance.getTPMStatus();

  Future<BiometricStatus> getBiometryStatus() => _instance.getBiometryStatus();

  Future<void> generateKey({required String tag}) {
    if (tag.isEmpty) {
      throw Exception('Tag cannot be empty');
    }

    return _instance.generateKey(tag: tag);
  }

  Future<String?> encrypt({required String tag, required String data}) {
    if (tag.isEmpty) {
      throw Exception('Tag cannot be empty');
    }

    if (data.isEmpty) {
      throw Exception('Data cannot be empty');
    }

    return _instance.encrypt(tag: tag, data: data);
  }

  Future<String?> decrypt({required String tag, required String data}) {
    if (configured == false) {
      throw Exception('Plugin is not configured');
    }

    if (tag.isEmpty) {
      throw Exception('Tag cannot be empty');
    }

    if (data.isEmpty) {
      throw Exception('Data cannot be empty');
    }

    return _instance.decrypt(tag: tag, data: data);
  }

  Future<void> deleteKey({required String tag}) {
    if (tag.isEmpty) {
      throw Exception('Tag cannot be empty');
    }

    return _instance.deleteKey(tag: tag);
  }
}
