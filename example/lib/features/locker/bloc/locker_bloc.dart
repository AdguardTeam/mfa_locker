import 'dart:async';

import 'package:action_bloc/action_bloc.dart';
import 'package:adguard_logger/adguard_logger.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:locker/locker/models/biometric_state.dart';
import 'package:locker/security/models/exceptions/biometric_exception.dart';
import 'package:locker/storage/models/domain/entry_id.dart';
import 'package:locker/storage/models/exceptions/decrypt_failed_exception.dart';
import 'package:mfa_demo/core/services/timer_service.dart';
import 'package:mfa_demo/features/locker/data/models/repository_locker_state.dart';
import 'package:mfa_demo/features/locker/data/repositories/locker_repository.dart';

part 'locker_action.dart';
part 'locker_bloc.freezed.dart';
part 'locker_event.dart';
part 'locker_state.dart';

/// BLoC for managing locker state and operations
class LockerBloc extends ActionBloc<LockerEvent, LockerState, LockerAction> {
  final LockerRepository _lockerRepository;
  final TimerService _timerService;

  LockerBloc({
    required LockerRepository lockerRepository,
    required TimerService timerService,
  }) : _lockerRepository = lockerRepository,
       _timerService = timerService,
       super(const LockerState()) {
    on<_InitializeRequested>(_onInitializeRequested);
    on<_PasswordSubmitted>(_onPasswordSubmitted);
    on<_BiometricSetupAccepted>(_onBiometricSetupAccepted);
    on<_BiometricSetupSkipped>(_onBiometricSetupSkipped);
    on<_InitialEntrySubmitted>(_onInitialEntrySubmitted);
    on<_UnlockRequested>(_onUnlockRequested);
    on<_UnlockPasswordSubmitted>(_onUnlockPasswordSubmitted);
    on<_LockRequested>(_onLockRequested);
    on<_AddEntryRequested>(_onAddEntryRequested);
    on<_CheckBiometricAvailabilityRequested>(_onCheckBiometricAvailabilityRequested);
    on<_EnableBiometricRequested>(_onEnableBiometricRequested);
    on<_DisableBiometricRequested>(_onDisableBiometricRequested);
    on<_UnlockWithBiometricRequested>(_onUnlockWithBiometricRequested);
    on<_AddEntryWithBiometricRequested>(_onAddEntryWithBiometricRequested);
    on<_ReadEntryWithBiometricRequested>(_onReadEntryWithBiometricRequested);
    on<_DeleteEntryWithBiometricRequested>(_onDeleteEntryWithBiometricRequested);
    on<_ViewEntryRequested>(_onViewEntryRequested);
    on<_DeleteEntryRequested>(_onDeleteEntryRequested);
    on<_ChangePasswordSubmitted>(_onChangePasswordSubmitted);
    on<_CheckInitializationStatus>(_onCheckInitializationStatus);
    on<_EraseStorageRequested>(_onEraseStorageRequested);
    on<_LockerStateChanged>(_onLockerStateChanged);
    on<_AppResumed>(_onAppResumed);
    on<_BiometricOperationStateChanged>(_onBiometricOperationStateChanged);
    on<_ActivityDetected>(_onActivityDetected);

    _timerService.onLockCallback = _onTimerExpired;
    _createSub();
  }

  StreamSubscription<RepositoryLockerState>? _lockerStateSubscription;

  @override
  Future<void> close() async {
    await _lockerStateSubscription?.cancel();

    return super.close();
  }

  void _onInitializeRequested(
    _InitializeRequested event,
    Emitter<LockerState> emit,
  ) => emit(state.copyWith(status: LockerStatus.settingPassword));

  Future<void> _onPasswordSubmitted(
    _PasswordSubmitted event,
    Emitter<LockerState> emit,
  ) async {
    // Store password temporarily
    emit(state.copyWith(tempPassword: event.password));

    // Check if biometric is available for optional setup
    try {
      final biometricState = await _lockerRepository.determineBiometricState();

      if (isClosed) {
        return;
      }

      // Offer biometric setup if available but not enabled
      if (biometricState == BiometricState.availableButDisabled) {
        emit(
          state.copyWith(
            status: LockerStatus.offeringBiometric,
            biometricState: biometricState,
          ),
        );
      } else {
        // Skip biometric setup if not available
        emit(state.copyWith(status: LockerStatus.settingInitialEntry));
      }
    } catch (error, stackTrace) {
      logger.logError(
        'LockerBloc: Failed to check biometric availability during initialization',
        error: error,
        stackTrace: stackTrace,
      );

      if (isClosed) {
        return;
      }

      // On error, skip biometric setup and proceed
      emit(state.copyWith(status: LockerStatus.settingInitialEntry));
    }
  }

  void _onBiometricSetupAccepted(
    _BiometricSetupAccepted event,
    Emitter<LockerState> emit,
  ) => emit(
    state.copyWith(
      status: LockerStatus.settingInitialEntry,
      enableBiometricAfterInit: true,
    ),
  );

  void _onBiometricSetupSkipped(
    _BiometricSetupSkipped event,
    Emitter<LockerState> emit,
  ) => emit(
    state.copyWith(
      status: LockerStatus.settingInitialEntry,
      enableBiometricAfterInit: false,
    ),
  );

  Future<void> _onInitialEntrySubmitted(
    _InitialEntrySubmitted event,
    Emitter<LockerState> emit,
  ) async {
    emit(state.copyWith(loadState: LoadState.loading));

    await _handleVaultOperation(
      operation: () async {
        await _lockerRepository.init(
          password: state.tempPassword,
          firstEntryName: event.name,
          firstEntryValue: event.value,
          lockTimeout: event.lockTimeout,
        );

        // Enable biometric if user opted in during setup
        if (state.enableBiometricAfterInit) {
          try {
            await _lockerRepository.enableBiometric(password: state.tempPassword);
            await _refreshBiometricState(emit);
          } catch (error, stackTrace) {
            logger.logError(
              'LockerBloc: Failed to enable biometric after initialization',
              error: error,
              stackTrace: stackTrace,
            );
            // Don't block initialization on biometric failure
            if (!isClosed) {
              action(
                const LockerAction.showError(
                  message: 'Biometric setup failed. You can enable it later in Settings.',
                ),
              );
            }
          }
        }

        final entries = await _lockerRepository.getAllEntries();
        await _timerService.startTimer();

        if (isClosed) {
          return;
        }

        emit(
          state.copyWith(
            status: LockerStatus.unlocked,
            entries: entries,
            tempPassword: '',
            enableBiometricAfterInit: false,
            loadState: LoadState.none,
          ),
        );
        action(
          const LockerAction.showSuccess(
            message: 'Storage initialized successfully',
          ),
        );
      },
      onError: (error) {
        if (isClosed) {
          return;
        }
        emit(state.copyWith(loadState: LoadState.none));
        action(
          LockerAction.showError(
            message: 'Failed to initialize: $error',
          ),
        );
      },
      operationDescription: 'initialize storage',
    );
  }

  void _onUnlockRequested(
    _UnlockRequested event,
    Emitter<LockerState> emit,
  ) => emit(state.copyWith(status: LockerStatus.locked));

  Future<void> _onUnlockPasswordSubmitted(
    _UnlockPasswordSubmitted event,
    Emitter<LockerState> emit,
  ) async {
    emit(state.copyWith(loadState: LoadState.loading));

    await _handleVaultOperation(
      operation: () async {
        await _lockerRepository.unlock(password: event.password);
        action(
          const LockerAction.showSuccess(
            message: 'Unlocked successfully',
          ),
        );
      },
      onDecryptFailed: (error) => _handleDecryptFailure(
        emit,
        LockerAction.showError(message: 'Incorrect password: $error'),
      ),
      onError: (error) => _handleGenericFailure(
        emit,
        LockerAction.showError(message: 'Failed to unlock: $error'),
      ),
      operationDescription: 'unlock locker',
    );
  }

  Future<void> _onLockRequested(
    _LockRequested event,
    Emitter<LockerState> emit,
  ) async {
    // Prevent locking if biometric operation is in progress or awaiting resume.
    // This handles the case where system biometric dialog causes app lifecycle changes.
    // We only allow locking when biometricOperationState is idle.
    if (state.biometricOperationState != BiometricOperationState.idle) {
      return;
    }
    await _lockerRepository.lock();
  }

  Future<void> _onAddEntryRequested(
    _AddEntryRequested event,
    Emitter<LockerState> emit,
  ) async {
    emit(state.copyWith(loadState: LoadState.loading));

    await _handleVaultOperation(
      operation: () async {
        await _lockerRepository.addEntry(
          password: event.password,
          name: event.name,
          value: event.value,
        );

        final entries = await _lockerRepository.getAllEntries();
        if (isClosed) {
          return;
        }

        emit(
          state.copyWith(
            entries: entries,
            loadState: LoadState.none,
          ),
        );

        action(
          const LockerAction.showSuccess(
            message: 'Entry added successfully',
          ),
        );
        action(const LockerAction.navigateBack());
      },
      onDecryptFailed: (error) => _handleDecryptFailure(
        emit,
        LockerAction.showError(
          message: 'Incorrect password: $error',
        ),
      ),
      onError: (error) => _handleGenericFailure(
        emit,
        LockerAction.showError(
          message: 'Failed to add entry: $error',
        ),
      ),
      operationDescription: 'add entry',
    );
  }

  Future<void> _onCheckBiometricAvailabilityRequested(
    _CheckBiometricAvailabilityRequested event,
    Emitter<LockerState> emit,
  ) => _determineBiometricStateAndEmit(emit);

  Future<void> _onEnableBiometricRequested(
    _EnableBiometricRequested event,
    Emitter<LockerState> emit,
  ) async {
    emit(
      state.copyWith(
        loadState: LoadState.loading,
        biometricOperationState: BiometricOperationState.inProgress,
      ),
    );

    try {
      // Step 1: Determine biometric state
      final biometricState = await _lockerRepository.determineBiometricState();

      if (isClosed) {
        return;
      }

      // Step 2: Validate state is appropriate for enabling
      if (biometricState != BiometricState.availableButDisabled) {
        emit(
          state.copyWith(
            loadState: LoadState.none,
            biometricOperationState: BiometricOperationState.idle,
          ),
        );
        action(
          LockerAction.showError(
            message: 'Biometric not available for enabling: $biometricState',
          ),
        );

        return;
      }

      // Step 3: Enable biometric with vault operation
      await _handleVaultOperation(
        operation: () async {
          await _lockerRepository.enableBiometric(password: event.password);
          await _refreshBiometricState(emit, resetLoadState: true);
          action(
            const LockerAction.showSuccess(
              message: 'Biometric authentication enabled',
            ),
          );
          // Reset biometric operation state after success (processed after finally block)
          if (!isClosed) {
            add(
              const LockerEvent.biometricOperationStateChanged(
                biometricOperationState: BiometricOperationState.idle,
              ),
            );
          }
        },
        onDecryptFailed: (error) => _handleDecryptFailure(
          emit,
          LockerAction.showError(
            message: 'Incorrect password: $error',
          ),
        ),
        onError: (error) => _handleBiometricFailure(
          emit,
          error,
          fallbackMessage: 'Failed to enable biometric: $error',
        ),
        operationDescription: 'enable biometric authentication',
      );
    } catch (error, stackTrace) {
      logger.logError(
        'LockerBloc: Failed to check biometric status before enabling',
        error: error,
        stackTrace: stackTrace,
      );

      if (isClosed) {
        return;
      }

      emit(state.copyWith(loadState: LoadState.none));
      action(
        LockerAction.showError(
          message: 'Failed to check biometric status: $error',
        ),
      );
    } finally {
      if (!isClosed) {
        emit(
          state.copyWith(
            loadState: LoadState.none,
            biometricOperationState: BiometricOperationState.awaitingResume,
          ),
        );
      }
    }
  }

  Future<void> _onDisableBiometricRequested(
    _DisableBiometricRequested event,
    Emitter<LockerState> emit,
  ) async {
    emit(
      state.copyWith(
        loadState: LoadState.loading,
        biometricOperationState: BiometricOperationState.inProgress,
      ),
    );

    try {
      await _handleVaultOperation(
        operation: () async {
          await _lockerRepository.disableBiometric(password: event.password);
          await _refreshBiometricState(emit, resetLoadState: true);
          action(
            const LockerAction.showSuccess(
              message: 'Biometric authentication disabled',
            ),
          );
          // Reset biometric operation state after success (processed after finally block)
          if (!isClosed) {
            add(
              const LockerEvent.biometricOperationStateChanged(
                biometricOperationState: BiometricOperationState.idle,
              ),
            );
          }
        },
        onDecryptFailed: (error) => _handleDecryptFailure(
          emit,
          LockerAction.showError(
            message: 'Incorrect password: $error',
          ),
        ),
        onError: (error) => _handleBiometricFailure(
          emit,
          error,
          fallbackMessage: 'Failed to disable biometric: $error',
        ),
        operationDescription: 'disable biometric authentication',
      );
    } finally {
      if (!isClosed) {
        emit(
          state.copyWith(
            loadState: LoadState.none,
            biometricOperationState: BiometricOperationState.awaitingResume,
          ),
        );
      }
    }
  }

  Future<void> _onUnlockWithBiometricRequested(
    _UnlockWithBiometricRequested event,
    Emitter<LockerState> emit,
  ) async {
    emit(
      state.copyWith(
        loadState: LoadState.loading,
        biometricOperationState: BiometricOperationState.inProgress,
      ),
    );

    try {
      await _handleVaultOperation(
        operation: () async {
          await _lockerRepository.unlockWithBiometric();
          action(const LockerAction.biometricAuthenticationSucceeded());
          action(const LockerAction.showSuccess(message: 'Unlocked with biometric'));
          // Reset biometric operation state after success (processed after finally block)
          if (!isClosed) {
            add(
              const LockerEvent.biometricOperationStateChanged(
                biometricOperationState: BiometricOperationState.idle,
              ),
            );
          }
        },
        onError: (error) => _handleBiometricFailure(
          emit,
          error,
          fallbackMessage: 'Failed to unlock with biometric: $error',
        ),
        operationDescription: 'unlock locker with biometric',
      );
    } finally {
      if (!isClosed) {
        emit(
          state.copyWith(
            loadState: LoadState.none,
            biometricOperationState: BiometricOperationState.awaitingResume,
          ),
        );
      }
    }
  }

  Future<void> _onAddEntryWithBiometricRequested(
    _AddEntryWithBiometricRequested event,
    Emitter<LockerState> emit,
  ) async {
    emit(
      state.copyWith(
        loadState: LoadState.loading,
        biometricOperationState: BiometricOperationState.inProgress,
      ),
    );

    try {
      await _handleVaultOperation(
        operation: () async {
          await _lockerRepository.addEntryWithBiometric(
            name: event.name,
            value: event.value,
          );

          final entries = await _lockerRepository.getAllEntries();
          if (isClosed) {
            return;
          }
          emit(
            state.copyWith(
              entries: entries,
              loadState: LoadState.none,
            ),
          );
          action(const LockerAction.biometricAuthenticationSucceeded());
          action(const LockerAction.showSuccess(message: 'Entry added successfully'));
          action(const LockerAction.navigateBack());
          // Reset biometric operation state after success (processed after finally block)
          if (!isClosed) {
            add(
              const LockerEvent.biometricOperationStateChanged(
                biometricOperationState: BiometricOperationState.idle,
              ),
            );
          }
        },
        onError: (error) => _handleBiometricFailure(
          emit,
          error,
          fallbackMessage: 'Failed to add entry: $error',
        ),
        operationDescription: 'add entry with biometric',
      );
    } finally {
      if (!isClosed) {
        emit(
          state.copyWith(
            loadState: LoadState.none,
            biometricOperationState: BiometricOperationState.awaitingResume,
          ),
        );
      }
    }
  }

  Future<void> _onReadEntryWithBiometricRequested(
    _ReadEntryWithBiometricRequested event,
    Emitter<LockerState> emit,
  ) async {
    emit(
      state.copyWith(
        loadState: LoadState.loading,
        biometricOperationState: BiometricOperationState.inProgress,
      ),
    );

    try {
      await _handleVaultOperation(
        operation: () async {
          final value = await _lockerRepository.readEntryWithBiometric(
            id: event.id,
          );

          if (isClosed) {
            return;
          }
          emit(
            state.copyWith(
              loadState: LoadState.none,
            ),
          );
          action(const LockerAction.biometricAuthenticationSucceeded());

          action(
            LockerAction.showEntryValue(
              name: event.name,
              value: value,
            ),
          );
          // Reset biometric operation state after success (processed after finally block)
          if (!isClosed) {
            add(
              const LockerEvent.biometricOperationStateChanged(
                biometricOperationState: BiometricOperationState.idle,
              ),
            );
          }
        },
        onDecryptFailed: (error) => _handleBiometricFailure(
          emit,
          error,
          fallbackMessage: 'Failed to read entry: $error',
        ),
        onError: (error) => _handleBiometricFailure(
          emit,
          error,
          fallbackMessage: 'Failed to read entry: $error',
        ),
        operationDescription: 'read entry with biometric',
      );
    } finally {
      if (!isClosed) {
        emit(
          state.copyWith(
            loadState: LoadState.none,
            biometricOperationState: BiometricOperationState.awaitingResume,
          ),
        );
      }
    }
  }

  /// Deletes an entry using biometric authentication.
  ///
  /// If the last entry is deleted, the storage will be erased automatically.
  Future<void> _onDeleteEntryWithBiometricRequested(
    _DeleteEntryWithBiometricRequested event,
    Emitter<LockerState> emit,
  ) async {
    emit(
      state.copyWith(
        loadState: LoadState.loading,
        biometricOperationState: BiometricOperationState.inProgress,
      ),
    );

    try {
      await _handleVaultOperation(
        operation: () async {
          final result = await _lockerRepository.deleteEntryWithBiometric(id: event.id);

          if (isClosed) {
            return;
          }

          if (!result) {
            throw Exception('Failed to delete entry');
          }

          final entries = await _lockerRepository.getAllEntries();

          if (entries.isEmpty) {
            await _lockerRepository.eraseStorage();
            action(const LockerAction.biometricAuthenticationSucceeded());

            return;
          }

          if (isClosed) {
            return;
          }

          emit(
            state.copyWith(
              entries: entries,
              loadState: LoadState.none,
            ),
          );
          action(const LockerAction.biometricAuthenticationSucceeded());
          action(const LockerAction.showSuccess(message: 'Entry deleted successfully'));
          // Reset biometric operation state after success (processed after finally block)
          if (!isClosed) {
            add(
              const LockerEvent.biometricOperationStateChanged(
                biometricOperationState: BiometricOperationState.idle,
              ),
            );
          }
        },
        onError: (error) => _handleBiometricFailure(
          emit,
          error,
          fallbackMessage: 'Failed to delete entry: $error',
        ),
        operationDescription: 'delete entry with biometric',
      );
    } finally {
      if (!isClosed) {
        emit(
          state.copyWith(
            loadState: LoadState.none,
            biometricOperationState: BiometricOperationState.awaitingResume,
          ),
        );
      }
    }
  }

  Future<void> _onViewEntryRequested(
    _ViewEntryRequested event,
    Emitter<LockerState> emit,
  ) async {
    emit(state.copyWith(loadState: LoadState.loading));

    await _handleVaultOperation(
      operation: () async {
        final value = await _lockerRepository.readEntry(
          password: event.password,
          id: event.id,
        );

        if (isClosed) {
          return;
        }
        emit(
          state.copyWith(
            loadState: LoadState.none,
          ),
        );

        action(
          LockerAction.showEntryValue(
            name: event.name,
            value: value,
          ),
        );
      },
      onDecryptFailed: (error) => _handleDecryptFailure(
        emit,
        LockerAction.showError(
          message: 'Incorrect password: $error',
        ),
      ),
      onError: (error) => _handleGenericFailure(
        emit,
        LockerAction.showError(
          message: 'Failed to read entry: $error',
        ),
      ),
      operationDescription: 'read entry',
    );
  }

  /// Deletes an entry using password authentication.
  ///
  /// If the last entry is deleted, the storage will be erased automatically.
  Future<void> _onDeleteEntryRequested(
    _DeleteEntryRequested event,
    Emitter<LockerState> emit,
  ) async {
    emit(state.copyWith(loadState: LoadState.loading));

    await _handleVaultOperation(
      operation: () async {
        await _lockerRepository.deleteEntry(
          password: event.password,
          id: event.id,
        );

        final entries = await _lockerRepository.getAllEntries();

        if (entries.isEmpty) {
          await _lockerRepository.eraseStorage();

          return;
        }

        if (isClosed) {
          return;
        }

        emit(
          state.copyWith(
            entries: entries,
            loadState: LoadState.none,
          ),
        );
        action(const LockerAction.showSuccess(message: 'Entry deleted successfully'));
      },
      onDecryptFailed: (error) {
        if (isClosed) {
          return;
        }
        emit(state.copyWith(loadState: LoadState.none));
        action(LockerAction.showError(message: 'Incorrect password: $error'));
      },
      onError: (error) {
        if (isClosed) {
          return;
        }
        emit(state.copyWith(loadState: LoadState.none));
        action(LockerAction.showError(message: 'Failed to delete entry: $error'));
      },
      operationDescription: 'delete entry',
    );
  }

  Future<void> _onChangePasswordSubmitted(
    _ChangePasswordSubmitted event,
    Emitter<LockerState> emit,
  ) async {
    emit(state.copyWith(loadState: LoadState.loading));

    await _handleVaultOperation(
      operation: () async {
        await _lockerRepository.changePassword(
          oldPassword: event.oldPassword,
          newPassword: event.newPassword,
        );

        if (isClosed) {
          return;
        }

        emit(state.copyWith(loadState: LoadState.none));
        action(const LockerAction.showSuccess(message: 'Password changed successfully'));
        action(const LockerAction.navigateBack());
      },
      onDecryptFailed: (error) {
        if (isClosed) {
          return;
        }
        emit(state.copyWith(loadState: LoadState.none));
        action(LockerAction.showError(message: 'Incorrect password: $error'));
      },
      onError: (error) {
        if (isClosed) {
          return;
        }
        emit(state.copyWith(loadState: LoadState.none));
        action(LockerAction.showError(message: 'Failed to change password: $error'));
      },
      operationDescription: 'change password',
    );
  }

  Future<void> _onCheckInitializationStatus(
    _CheckInitializationStatus event,
    Emitter<LockerState> emit,
  ) async {
    final isInitialized = await _lockerRepository.isInitialized();
    if (isClosed) {
      return;
    }
    if (isInitialized) {
      emit(
        state.copyWith(
          status: LockerStatus.locked,
          loadState: LoadState.none,
        ),
      );
    } else {
      emit(
        state.copyWith(
          status: LockerStatus.notInitialized,
          loadState: LoadState.none,
        ),
      );
    }
  }

  Future<void> _onEraseStorageRequested(
    _EraseStorageRequested event,
    Emitter<LockerState> emit,
  ) async {
    emit(state.copyWith(loadState: LoadState.loading));

    await _handleVaultOperation(
      operation: () async {
        await _lockerRepository.eraseStorage();

        if (isClosed) {
          return;
        }

        emit(
          state.copyWith(
            status: LockerStatus.notInitialized,
            entries: {},
            loadState: LoadState.none,
          ),
        );

        action(const LockerAction.showSuccess(message: 'All data cleared successfully'));
      },
      onDecryptFailed: (error) {
        if (isClosed) {
          return;
        }
        emit(state.copyWith(loadState: LoadState.none));
        action(LockerAction.showError(message: 'Incorrect password: $error'));
      },
      onError: (error) {
        if (isClosed) {
          return;
        }
        emit(state.copyWith(loadState: LoadState.none));
        action(LockerAction.showError(message: 'Failed to clear data: $error'));
      },
      operationDescription: 'erase storage',
    );
  }

  Future<void> _handleVaultOperation({
    required Future<void> Function() operation,
    FutureOr<void> Function(Object error)? onError,
    void Function(Object error)? onDecryptFailed,
    String? operationDescription,
  }) async {
    final description = operationDescription != null ? ' while attempting to $operationDescription' : '';

    try {
      await operation();
    } on DecryptFailedException catch (error, stackTrace) {
      logger.logWarning(
        'LockerBloc: Decrypt failed$description',
        error: error,
        stackTrace: stackTrace,
      );
      if (isClosed) {
        return;
      }
      onDecryptFailed?.call(error);
    } catch (error, stackTrace) {
      logger.logError(
        'LockerBloc: Operation failed$description',
        error: error,
        stackTrace: stackTrace,
      );
      if (isClosed) {
        return;
      }
      await onError?.call(error);
    }
  }

  void _handleDecryptFailure(
    Emitter<LockerState> emit,
    LockerAction actionToEmit,
  ) {
    if (isClosed) {
      return;
    }

    emit(state.copyWith(loadState: LoadState.none));
    action(actionToEmit);
  }

  void _handleGenericFailure(
    Emitter<LockerState> emit,
    LockerAction actionToEmit,
  ) {
    if (isClosed) {
      return;
    }

    emit(state.copyWith(loadState: LoadState.none));
    action(actionToEmit);
  }

  /// Helper method to determine and emit biometric state
  /// Gets TPM status, biometry status, and maps to BiometricState
  Future<void> _determineBiometricStateAndEmit(
    Emitter<LockerState> emit, {
    bool resetLoadState = false,
  }) async {
    try {
      // Step 1: Determine biometric state
      final biometricState = await _lockerRepository.determineBiometricState();

      if (isClosed) {
        return;
      }

      // Step 2: Emit state
      emit(
        state.copyWith(
          biometricState: biometricState,
          loadState: resetLoadState ? LoadState.none : state.loadState,
        ),
      );
    } catch (error, stackTrace) {
      logger.logError(
        'LockerBloc: Failed to determine biometric state',
        error: error,
        stackTrace: stackTrace,
      );
      if (resetLoadState && !isClosed) {
        emit(state.copyWith(loadState: LoadState.none));
      }
    }
  }

  Future<void> _refreshBiometricState(
    Emitter<LockerState> emit, {
    bool resetLoadState = false,
  }) => _determineBiometricStateAndEmit(emit, resetLoadState: resetLoadState);

  Future<void> _handleBiometricFailure(
    Emitter<LockerState> emit,
    Object error, {
    required String fallbackMessage,
  }) async {
    if (isClosed) {
      return;
    }

    emit(state.copyWith(loadState: LoadState.none));

    if (error is BiometricException) {
      switch (error.type) {
        case BiometricExceptionType.cancel:
          action(const LockerAction.biometricAuthenticationCancelled());
          // Deterministically clear biometric operation state to idle.
          // This event is processed after the finally block, overriding awaitingResume.
          // Cancel doesn't require waiting for app resume since no system dialog persists.
          add(
            const LockerEvent.biometricOperationStateChanged(
              biometricOperationState: BiometricOperationState.idle,
            ),
          );

          return;

        case BiometricExceptionType.notAvailable:
          action(const LockerAction.biometricNotAvailable());
          add(const LockerEvent.checkBiometricAvailabilityRequested());
          // Deterministically clear biometric operation state to idle.
          // notAvailable means no system dialog was shown, so no need to await resume.
          add(
            const LockerEvent.biometricOperationStateChanged(
              biometricOperationState: BiometricOperationState.idle,
            ),
          );

          return;

        case BiometricExceptionType.keyNotFound:
          action(
            const LockerAction.biometricAuthenticationFailed(
              message: 'Biometric key not found. Please enable biometric again.',
            ),
          );
          add(const LockerEvent.checkBiometricAvailabilityRequested());
          // Reset to idle - keyNotFound means system dialog was not shown or already dismissed.
          add(
            const LockerEvent.biometricOperationStateChanged(
              biometricOperationState: BiometricOperationState.idle,
            ),
          );

          return;

        case BiometricExceptionType.keyAlreadyExists:
          action(
            const LockerAction.biometricAuthenticationFailed(
              message: 'Biometric key already exists.',
            ),
          );
          // Reset to idle - keyAlreadyExists means no system dialog was shown.
          add(
            const LockerEvent.biometricOperationStateChanged(
              biometricOperationState: BiometricOperationState.idle,
            ),
          );

          return;

        case BiometricExceptionType.failure:
          await _determineBiometricStateAndEmit(emit);

        case BiometricExceptionType.notConfigured:
          // Fall through to generic error handling
          break;
      }
    }

    action(
      LockerAction.biometricAuthenticationFailed(
        message: fallbackMessage,
      ),
    );

    // Reset to idle for all error paths that reach this point (failure, notConfigured, non-biometric errors).
    // This ensures auto-lock is not blocked after any biometric error.
    add(
      const LockerEvent.biometricOperationStateChanged(
        biometricOperationState: BiometricOperationState.idle,
      ),
    );
  }

  void _createSub() {
    logger.logInfo('Creating subscription to locker state stream');
    _lockerStateSubscription = _lockerRepository.lockerStateStream.listen(
      (repositoryState) => add(
        LockerEvent.lockerStateChanged(repositoryState: repositoryState),
      ),
    );
  }

  void _onBiometricOperationStateChanged(
    _BiometricOperationStateChanged event,
    Emitter<LockerState> emit,
  ) {
    emit(state.copyWith(biometricOperationState: event.biometricOperationState));
    logger.logInfo('LockerBloc: Biometric operation state changed to ${event.biometricOperationState}');
  }

  Future<void> _onLockerStateChanged(
    _LockerStateChanged event,
    Emitter<LockerState> emit,
  ) async {
    final repositoryState = event.repositoryState;
    final previousStatus = state.status;

    logger.logInfo('Locker state changed: $repositoryState');

    switch (repositoryState) {
      case RepositoryLockerState.uninitialized when previousStatus != LockerStatus.notInitialized:
        emit(
          state.copyWith(
            status: LockerStatus.notInitialized,
            entries: const {},
            tempPassword: '',
            loadState: LoadState.none,
          ),
        );

      case RepositoryLockerState.locked when previousStatus != LockerStatus.locked:
        _timerService.stopTimer();
        emit(
          state.copyWith(
            status: LockerStatus.locked,
            entries: const {},
            tempPassword: '',
            loadState: LoadState.none,
          ),
        );

        // Check biometric availability when entering locked state
        // This ensures the UI shows the correct unlock method (biometric vs password)
        await _determineBiometricStateAndEmit(emit);

        if (!isClosed && previousStatus == LockerStatus.unlocked) {
          action(const LockerAction.showSuccess(message: 'Storage locked'));
        }

      case RepositoryLockerState.unlocked
          when previousStatus != LockerStatus.unlocked && previousStatus != LockerStatus.settingInitialEntry:
        await _refreshUnlockedState(emit);

      default:
    }
  }

  Future<void> _refreshUnlockedState(Emitter<LockerState> emit) async {
    try {
      final entries = await _lockerRepository.getAllEntries();
      await _timerService.startTimer();

      if (isClosed) {
        return;
      }

      emit(
        state.copyWith(
          status: LockerStatus.unlocked,
          entries: entries,
          loadState: LoadState.none,
        ),
      );
    } catch (error, stackTrace) {
      logger.logError(
        'LockerBloc: Failed to refresh entries after unlock',
        error: error,
        stackTrace: stackTrace,
      );

      if (isClosed) {
        return;
      }

      emit(
        state.copyWith(
          status: LockerStatus.unlocked,
          loadState: LoadState.none,
        ),
      );
    }
  }

  void _onAppResumed(
    _AppResumed event,
    Emitter<LockerState> emit,
  ) {
    if (_timerService.shouldLockOnResume &&
        state.status == LockerStatus.unlocked &&
        state.biometricOperationState == BiometricOperationState.idle) {
      add(const LockerEvent.lockRequested());
    }

    // Clear biometric operation state when app resumes after biometric operation.
    // This is the primary mechanism for clearing the state after the system biometric
    // dialog dismisses and the app returns to the foreground.
    if (state.biometricOperationState == BiometricOperationState.awaitingResume) {
      emit(state.copyWith(biometricOperationState: BiometricOperationState.idle));
      logger.logInfo('LockerBloc: Biometric operation state cleared on app resume');
    }
  }

  void _onActivityDetected(
    _ActivityDetected event,
    Emitter<LockerState> emit,
  ) {
    if (state.status == LockerStatus.unlocked) {
      _timerService.touch();
    }

    // Fallback: Clear biometric operation state on user activity.
    // This handles edge cases where biometric was cancelled without app going to background,
    // so no appResumed event would be received.
    if (state.biometricOperationState == BiometricOperationState.awaitingResume) {
      emit(state.copyWith(biometricOperationState: BiometricOperationState.idle));
    }
  }

  void _onTimerExpired() {
    if (!isClosed && state.status == LockerStatus.unlocked) {
      add(const LockerEvent.lockRequested());
    }
  }
}
