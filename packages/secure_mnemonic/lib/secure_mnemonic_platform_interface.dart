import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:secure_mnemonic/data/biometric_status.dart';
import 'package:secure_mnemonic/data/model/config_data.dart';
import 'package:secure_mnemonic/data/tpm_status.dart';

import 'secure_mnemonic_method_channel.dart';

abstract class SecureMnemonicPlatform extends PlatformInterface {
  /// Constructs a SecureMnemonicPlatform.
  SecureMnemonicPlatform() : super(token: _token);

  static final Object _token = Object();

  static const channelName = 'secure_mnemonic';

  static SecureMnemonicPlatform _instance = MethodChannelSecureMnemonic();

  /// The default instance of [SecureMnemonicPlatform] to use.
  ///
  /// Defaults to [MethodChannelSecureMnemonic].
  static SecureMnemonicPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [SecureMnemonicPlatform] when
  /// they register themselves.
  static set instance(SecureMnemonicPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<void> configure({required ConfigData configData}) {
    throw UnimplementedError('configure({required ConfigData configData}) has not been implemented.');
  }

  Future<TPMStatus> getTPMStatus() {
    throw UnimplementedError('getTPMStatus() has not been implemented.');
  }

  Future<BiometricStatus> getBiometryStatus() {
    throw UnimplementedError('getBiometryStatus() has not been implemented.');
  }

  Future<void> generateKey({required String tag}) {
    throw UnimplementedError('generateKey({required String tag}) has not been implemented.');
  }

  Future<String?> encrypt({required String tag, required String data}) {
    throw UnimplementedError('encrypt({required String tag, required String data}) has not been implemented.');
  }

  Future<String?> decrypt({required String tag, required String data}) {
    throw UnimplementedError('decrypt({required String tag, required String data}) has not been implemented.');
  }

  Future<void> deleteKey({required String tag}) {
    throw UnimplementedError('deleteKey() has not been implemented.');
  }
}
