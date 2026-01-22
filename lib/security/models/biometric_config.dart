import 'package:secure_mnemonic/data/model/android_config.dart';
import 'package:secure_mnemonic/data/model/config_data.dart';

/// Configuration for biometric authentication prompts shown by the
/// [secure_mnemonic] plugin.
///
/// This wrapper keeps locker APIs free from third-party types while allowing
/// callers to supply localized strings and platform specific overrides.
class BiometricConfig {
  /// Main title shown in the biometric prompt.
  final String promptTitle;

  /// Subtitle displayed under the main biometric prompt title.
  final String promptSubtitle;

  /// Label for the cancel button on Android biometric prompts.
  final String androidCancelButtonText;

  /// Description displayed under the main biometric prompt subtitle (Android only).
  final String androidPromptDescription;

  /// Optional payload used on Windows to authenticate the request.
  final String? windowsAuthData;

  const BiometricConfig({
    required this.promptTitle,
    required this.promptSubtitle,
    required this.androidCancelButtonText,
    required this.androidPromptDescription,
    this.windowsAuthData,
  });

  /// Converts the wrapper into the plugin's [ConfigData] representation.
  ConfigData toConfigData() {
    final androidConfig = AndroidConfig(
      negativeButtonText: androidCancelButtonText,
      promptTitle: promptTitle,
      promptSubtitle: promptSubtitle,
      promptDescription: androidPromptDescription,
    );
    final windowsDataToSign = windowsAuthData ?? 'locker_authentication_request';

    return ConfigData(
      biometricPromptTitle: promptTitle,
      biometricPromptSubtitle: promptSubtitle,
      androidConfig: androidConfig,
      windowsDataToSign: windowsDataToSign,
    );
  }
}
