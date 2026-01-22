part of 'locker_bloc.dart';

/// State for the Locker BLoC
@freezed
abstract class LockerState with _$LockerState {
  const factory LockerState({
    @Default(LockerStatus.initializing) LockerStatus status,
    @Default({}) Map<EntryId, String> entries,
    @Default(LoadState.none) LoadState loadState,
    @Default('') String tempPassword,
    @Default(BiometricState.hardwareUnavailable) BiometricState biometricState,
    @Default(BiometricOperationState.idle) BiometricOperationState biometricOperationState,
    @Default(false) bool enableBiometricAfterInit,
  }) = _LockerState;
}

/// Status of the locker
enum LockerStatus {
  /// Checking storage initialization status
  initializing,

  /// Storage not yet initialized
  notInitialized,

  /// User is setting initial password
  settingPassword,

  /// Offering optional biometric setup during initialization
  offeringBiometric,

  /// User is adding the first entry
  settingInitialEntry,

  /// Storage is locked
  locked,

  /// Storage is unlocked
  unlocked,
}

enum LoadState {
  none,
  loading,
}

/// State of biometric operation for lock prevention.
enum BiometricOperationState {
  /// No biometric operation in progress. Locking is allowed.
  idle,

  /// Biometric operation is in progress (system dialog may be showing).
  /// Locking is blocked.
  inProgress,

  /// Biometric operation completed, waiting for app lifecycle to return to resumed.
  /// Locking is still blocked until we receive the resumed lifecycle event.
  /// This prevents race conditions between operation completion and lifecycle callbacks.
  awaitingResume,
}
