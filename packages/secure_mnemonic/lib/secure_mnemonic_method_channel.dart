import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:secure_mnemonic/data/biometric_status.dart';
import 'package:secure_mnemonic/data/model/config_data.dart';
import 'package:secure_mnemonic/data/tpm_status.dart';
import 'package:secure_mnemonic/secure_mnemonic_platform_interface.dart';

/// An implementation of [SecureMnemonicPlatform] that uses method channels.
class MethodChannelSecureMnemonic extends SecureMnemonicPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel(SecureMnemonicPlatform.channelName);

  @override
  Future<void> configure({required ConfigData configData}) =>
      methodChannel.invokeMethod<void>('configure', configData.toMap());

  @override
  Future<TPMStatus> getTPMStatus() async {
    final statusValue = await methodChannel.invokeMethod<int>('getTPMStatus');
    if (statusValue == null) {
      throw Exception('Failed to get TPM status');
    }

    return TPMStatus.fromValue(statusValue);
  }

  @override
  Future<BiometricStatus> getBiometryStatus() async {
    final statusValue = await methodChannel.invokeMethod<int>('getBiometryStatus');
    if (statusValue == null) {
      throw Exception('Failed to get biometry status');
    }

    return BiometricStatus.fromValue(statusValue);
  }

  @override
  Future<void> generateKey({required String tag}) => methodChannel.invokeMethod<void>('generateKey', {'tag': tag});

  @override
  Future<String?> encrypt({required String tag, required String data}) =>
      methodChannel.invokeMethod<String?>('encrypt', {'tag': tag, 'data': data});

  @override
  Future<String?> decrypt({required String tag, required String data}) =>
      methodChannel.invokeMethod<String?>('decrypt', {'tag': tag, 'data': data});

  @override
  Future<void> deleteKey({required String tag}) => methodChannel.invokeMethod<void>('deleteKey', {'tag': tag});
}
