import 'package:secure_mnemonic/data/model/android_config.dart';

final class ConfigData {
  final String? biometricPromptTitle;
  final String? biometricPromptSubtitle;
  final String? windowsDataToSign;
  final AndroidConfig? androidConfig;

  const ConfigData({
    this.biometricPromptTitle,
    this.biometricPromptSubtitle,
    this.windowsDataToSign,
    this.androidConfig,
  });

  factory ConfigData.fromMap(Map<String, dynamic> map) => ConfigData(
    biometricPromptTitle: map['biometricPromptTitle'],
    biometricPromptSubtitle: map['biometricPromptSubtitle'],
    windowsDataToSign: map['windowsDataToSign'],
    androidConfig: AndroidConfig.fromMap(map['androidConfig']),
  );

  Map<String, dynamic> toMap() => {
    'biometricPromptTitle': biometricPromptTitle,
    'biometricPromptSubtitle': biometricPromptSubtitle,
    'windowsDataToSign': windowsDataToSign,
    'androidConfig': androidConfig?.toMap(),
  };
}
