part of 'settings_bloc.dart';

@freezed
class SettingsEvent with _$SettingsEvent {
  const factory SettingsEvent.loadSettingsRequested() = _LoadSettingsRequested;

  const factory SettingsEvent.autoLockTimeoutSelected(
    Duration timeout,
    String password,
  ) = _AutoLockTimeoutSelected;

  const factory SettingsEvent.autoLockTimeoutUpdated(Duration timeout) = _AutoLockTimeoutUpdated;

  const factory SettingsEvent.autoLockTimeoutSelectedWithBiometric(Duration timeout) =
      _AutoLockTimeoutSelectedWithBiometric;
}
