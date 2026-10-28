import 'package:biometric_cipher/data/model/android_config.dart';

final class ConfigData {
  final String? biometricPromptTitle;
  final String? biometricPromptSubtitle;
  final AndroidConfig? androidConfig;

  const ConfigData({
    this.biometricPromptTitle,
    this.biometricPromptSubtitle,
    this.androidConfig,
  });

  factory ConfigData.fromMap(Map<String, dynamic> map) => ConfigData(
    biometricPromptTitle: map['biometricPromptTitle'],
    biometricPromptSubtitle: map['biometricPromptSubtitle'],
    androidConfig: AndroidConfig.fromMap(map['androidConfig']),
  );

  Map<String, dynamic> toMap() => {
    'biometricPromptTitle': biometricPromptTitle,
    'biometricPromptSubtitle': biometricPromptSubtitle,
    'androidConfig': androidConfig?.toMap(),
  };
}
