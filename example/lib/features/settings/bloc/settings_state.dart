part of 'settings_bloc.dart';

@freezed
abstract class SettingsState with _$SettingsState {
  const factory SettingsState({
    @Default(AppConstants.lockTimeoutDuration) Duration autoLockTimeout,
    @Default(LoadingState.none) LoadingState loadingState,
  }) = _SettingsState;
}

enum LoadingState {
  none,
  loading,
}
