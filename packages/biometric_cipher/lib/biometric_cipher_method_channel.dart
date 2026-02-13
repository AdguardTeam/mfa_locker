import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:biometric_cipher/data/biometric_status.dart';
import 'package:biometric_cipher/data/model/config_data.dart';
import 'package:biometric_cipher/data/biometric_cipher_exception.dart';
import 'package:biometric_cipher/data/biometric_cipher_exception_code.dart';
import 'package:biometric_cipher/data/tpm_status.dart';
import 'package:biometric_cipher/biometric_cipher_platform_interface.dart';

/// An implementation of [BiometricCipherPlatform] that uses method channels.
class MethodChannelBiometricCipher extends BiometricCipherPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel(BiometricCipherPlatform.channelName);

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
  Future<void> generateKey({required String tag}) async {
    try {
      await methodChannel.invokeMethod<void>(
        'generateKey',
        {
          'tag': tag,
        },
      );
    } on PlatformException catch (e) {
      throw _mapPlatformException(e);
    }
  }

  @override
  Future<String?> encrypt({required String tag, required String data}) async {
    try {
      return await methodChannel.invokeMethod<String?>(
        'encrypt',
        {
          'tag': tag,
          'data': data,
        },
      );
    } on PlatformException catch (e) {
      throw _mapPlatformException(e);
    }
  }

  @override
  Future<String?> decrypt({required String tag, required String data}) async {
    try {
      return await methodChannel.invokeMethod<String?>(
        'decrypt',
        {
          'tag': tag,
          'data': data,
        },
      );
    } on PlatformException catch (e) {
      throw _mapPlatformException(e);
    }
  }

  @override
  Future<void> deleteKey({required String tag}) async {
    try {
      await methodChannel.invokeMethod<void>(
        'deleteKey',
        {
          'tag': tag,
        },
      );
    } on PlatformException catch (e) {
      throw _mapPlatformException(e);
    }
  }

  BiometricCipherException _mapPlatformException(PlatformException e) {
    return BiometricCipherException(
      code: BiometricCipherExceptionCode.fromString(e.code),
      message: e.message ?? 'Unknown error',
      details: e.details,
    );
  }
}
