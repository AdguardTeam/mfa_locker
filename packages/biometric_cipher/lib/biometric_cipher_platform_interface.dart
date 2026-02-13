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
