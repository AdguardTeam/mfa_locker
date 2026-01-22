part of 'locker_bloc.dart';

/// Events for the Locker BLoC
@freezed
sealed class LockerEvent with _$LockerEvent {
  /// Request to initialize storage
  const factory LockerEvent.initializeRequested() = _InitializeRequested;

  /// Submit password during initialization
  const factory LockerEvent.passwordSubmitted({
    required String password,
  }) = _PasswordSubmitted;

  /// User accepted biometric setup during initialization
  const factory LockerEvent.biometricSetupAccepted() = _BiometricSetupAccepted;

  /// User skipped biometric setup during initialization
  const factory LockerEvent.biometricSetupSkipped() = _BiometricSetupSkipped;

  /// Submit initial entry during initialization
  const factory LockerEvent.initialEntrySubmitted({
    required String name,
    required String value,
    required Duration lockTimeout,
  }) = _InitialEntrySubmitted;

  /// Request to unlock storage
  const factory LockerEvent.unlockRequested() = _UnlockRequested;

  /// Submit password to unlock
  const factory LockerEvent.unlockPasswordSubmitted({
    required String password,
  }) = _UnlockPasswordSubmitted;

  /// Request to lock storage
  const factory LockerEvent.lockRequested() = _LockRequested;

  /// Request to add new entry
  const factory LockerEvent.addEntryRequested({
    required String name,
    required String value,
    required String password,
  }) = _AddEntryRequested;

  /// Request to check biometric availability and enabled status
  const factory LockerEvent.checkBiometricAvailabilityRequested() = _CheckBiometricAvailabilityRequested;

  /// Request to enable biometric authentication
  const factory LockerEvent.enableBiometricRequested({
    required String password,
  }) = _EnableBiometricRequested;

  /// Request to disable biometric authentication
  const factory LockerEvent.disableBiometricRequested({
    required String password,
  }) = _DisableBiometricRequested;

  /// Request to unlock using biometric authentication
  const factory LockerEvent.unlockWithBiometricRequested() = _UnlockWithBiometricRequested;

  /// Request to add entry using biometric authentication
  const factory LockerEvent.addEntryWithBiometricRequested({
    required String name,
    required String value,
  }) = _AddEntryWithBiometricRequested;

  /// Request to read entry using biometric authentication
  const factory LockerEvent.readEntryWithBiometricRequested({
    required EntryId id,
    required String name,
  }) = _ReadEntryWithBiometricRequested;

  /// Request to delete entry using biometric authentication
  const factory LockerEvent.deleteEntryWithBiometricRequested({
    required EntryId id,
  }) = _DeleteEntryWithBiometricRequested;

  /// Request to view entry
  const factory LockerEvent.viewEntryRequested({
    required EntryId id,
    required String name,
    required String password,
  }) = _ViewEntryRequested;

  /// Request to delete entry
  const factory LockerEvent.deleteEntryRequested({
    required EntryId id,
    required String password,
  }) = _DeleteEntryRequested;

  /// Submit new password for change
  const factory LockerEvent.changePasswordSubmitted({
    required String oldPassword,
    required String newPassword,
  }) = _ChangePasswordSubmitted;

  /// Check storage initialization status on startup
  const factory LockerEvent.checkInitializationStatus() = _CheckInitializationStatus;

  /// Request to erase all storage data
  const factory LockerEvent.eraseStorageRequested() = _EraseStorageRequested;

  /// Locker state update emitted by repository stream
  const factory LockerEvent.lockerStateChanged({
    required RepositoryLockerState repositoryState,
  }) = _LockerStateChanged;

  /// App lifecycle resumed event.
  const factory LockerEvent.appResumed() = _AppResumed;

  /// Internal event to change biometric operation state.
  const factory LockerEvent.biometricOperationStateChanged({
    required BiometricOperationState biometricOperationState,
  }) = _BiometricOperationStateChanged;

  /// User activity detected - reset auto-lock timer
  const factory LockerEvent.activityDetected() = _ActivityDetected;
}
