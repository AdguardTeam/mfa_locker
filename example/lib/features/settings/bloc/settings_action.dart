part of 'settings_bloc.dart';

@freezed
sealed class SettingsAction with _$SettingsAction {
  const factory SettingsAction.showError(String message) = ShowError;
  const factory SettingsAction.showSuccess(String message) = ShowSuccess;
  const factory SettingsAction.biometricAuthenticationSucceeded() = BiometricAuthenticationSucceeded;
  const factory SettingsAction.biometricAuthenticationFailed({required String message}) = BiometricAuthenticationFailed;
  const factory SettingsAction.biometricAuthenticationCancelled() = BiometricAuthenticationCancelled;
  const factory SettingsAction.biometricNotAvailable() = BiometricNotAvailable;
}
