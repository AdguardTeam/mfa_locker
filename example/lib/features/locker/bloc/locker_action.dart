part of 'locker_bloc.dart';

/// Actions (side effects) for the Locker BLoC
@freezed
sealed class LockerAction with _$LockerAction {
  /// Show error message
  const factory LockerAction.showError({
    required String message,
  }) = ShowError;

  /// Show success message
  const factory LockerAction.showSuccess({
    required String message,
  }) = ShowSuccess;

  /// Biometric authentication cancelled by user
  const factory LockerAction.biometricAuthenticationCancelled() = BiometricAuthenticationCancelledAction;

  /// Biometric authentication succeeded
  const factory LockerAction.biometricAuthenticationSucceeded() = BiometricAuthenticationSucceededAction;

  /// Biometric authentication failed with message
  const factory LockerAction.biometricAuthenticationFailed({
    required String message,
  }) = BiometricAuthenticationFailedAction;

  /// Biometric not available on device
  const factory LockerAction.biometricNotAvailable() = BiometricNotAvailableAction;

  /// Navigate back
  const factory LockerAction.navigateBack() = NavigateBack;

  const factory LockerAction.showEntryValue({
    required String name,
    required String value,
  }) = ShowEntryValue;
}
