import 'dart:async';

import 'package:action_bloc/action_bloc.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:locker/security/models/exceptions/biometric_exception.dart';
import 'package:mfa_demo/core/constants/app_constants.dart';
import 'package:mfa_demo/core/services/timer_service.dart';
import 'package:mfa_demo/features/locker/data/repositories/locker_repository.dart';

part 'settings_action.dart';
part 'settings_bloc.freezed.dart';
part 'settings_event.dart';
part 'settings_state.dart';

class SettingsBloc extends ActionBloc<SettingsEvent, SettingsState, SettingsAction> {
  final TimerService _timerService;
  final LockerRepository _lockerRepository;

  SettingsBloc({
    required TimerService timerService,
    required LockerRepository lockerRepository,
  }) : _timerService = timerService,
       _lockerRepository = lockerRepository,
       super(const SettingsState()) {
    on<_LoadSettingsRequested>(_onLoadSettingsRequested);
    on<_AutoLockTimeoutSelected>(_onAutoLockTimeoutSelected);
    on<_AutoLockTimeoutUpdated>(_onAutoLockTimeoutUpdated);
    on<_AutoLockTimeoutSelectedWithBiometric>(_onAutoLockTimeoutSelectedWithBiometric);
  }

  void _onLoadSettingsRequested(
    _LoadSettingsRequested event,
    Emitter<SettingsState> emit,
  ) {
    emit(state.copyWith(loadingState: LoadingState.loading));

    try {
      final timeout = _timerService.timeout;

      emit(state.copyWith(autoLockTimeout: timeout));
    } catch (error) {
      action(SettingsAction.showError('Failed to load settings: $error'));
    } finally {
      emit(state.copyWith(loadingState: LoadingState.none));
    }
  }

  Future<void> _onAutoLockTimeoutSelected(
    _AutoLockTimeoutSelected event,
    Emitter<SettingsState> emit,
  ) async {
    emit(state.copyWith(loadingState: LoadingState.loading));

    try {
      await _lockerRepository.updateLockTimeout(
        timeout: event.timeout,
        password: event.password,
      );
      await _timerService.updateLockTimeout();

      if (!isClosed) {
        add(SettingsEvent.autoLockTimeoutUpdated(event.timeout));
      }

      action(const SettingsAction.showSuccess('Auto-lock timeout updated'));
    } catch (error) {
      action(SettingsAction.showError('Failed to update timeout: $error'));
    } finally {
      if (!isClosed) {
        emit(state.copyWith(loadingState: LoadingState.none));
      }
    }
  }

  void _onAutoLockTimeoutUpdated(
    _AutoLockTimeoutUpdated event,
    Emitter<SettingsState> emit,
  ) {
    emit(
      state.copyWith(
        autoLockTimeout: event.timeout,
        loadingState: LoadingState.none,
      ),
    );
  }

  Future<void> _onAutoLockTimeoutSelectedWithBiometric(
    _AutoLockTimeoutSelectedWithBiometric event,
    Emitter<SettingsState> emit,
  ) async {
    emit(state.copyWith(loadingState: LoadingState.loading));

    try {
      await _lockerRepository.updateLockTimeoutWithBiometric(timeout: event.timeout);
      await _timerService.updateLockTimeout();

      if (!isClosed) {
        add(SettingsEvent.autoLockTimeoutUpdated(event.timeout));
      }

      action(const SettingsAction.biometricAuthenticationSucceeded());
      action(const SettingsAction.showSuccess('Auto-lock timeout updated'));
    } catch (error) {
      if (error is BiometricException) {
        switch (error.type) {
          case BiometricExceptionType.cancel:
            action(const SettingsAction.biometricAuthenticationCancelled());

            return;
          case BiometricExceptionType.notAvailable:
            action(const SettingsAction.biometricNotAvailable());

            return;
          case BiometricExceptionType.keyNotFound:
            action(
              const SettingsAction.biometricAuthenticationFailed(
                message: 'Biometric key not found. Please enable biometric again.',
              ),
            );

            return;
          case BiometricExceptionType.keyAlreadyExists:
            action(
              const SettingsAction.biometricAuthenticationFailed(
                message: 'Biometric key already exists.',
              ),
            );

            return;
          case BiometricExceptionType.failure:
          case BiometricExceptionType.notConfigured:
            break;
        }
      }

      action(
        const SettingsAction.biometricAuthenticationFailed(
          message: 'Failed to update timeout using biometric.',
        ),
      );
      action(const SettingsAction.showError('Failed to update timeout using biometric.'));
    } finally {
      if (!isClosed) {
        emit(state.copyWith(loadingState: LoadingState.none));
      }
    }
  }
}
