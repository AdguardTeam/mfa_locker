# Phase 8: Example App — Password-Only Biometric Disable

**Goal:** Allow the user to disable biometrics using only their password when the biometric key has been invalidated.

## Context

### Feature Motivation

Phase 7 wires detection and display of key invalidation. Phase 8 completes the recovery loop: once the user sees the "Biometrics changed" message and navigates to Settings, they need a way to disable biometrics without triggering a biometric prompt (which would fail on an invalidated key).

The flow:
- User toggles biometric OFF in Settings while `isBiometricKeyInvalidated` is `true`
- Instead of dispatching `disableBiometricRequested` (which needs a live biometric key), dispatch `disableBiometricPasswordOnlyRequested`
- Repository calls `MFALocker.teardownBiometryPasswordOnly` — password auth only, no biometric prompt
- After success, `isBiometricKeyInvalidated` is cleared and biometric state refreshed
- User can then re-enable biometrics to register new enrollment

### Architecture: App-Level Flow

```
┌─────────────────────────────────────────────────────────────┐
│ UI Layer                                                     │
│                                                              │
│ SettingsScreen                                               │
│   └── Route toggle-off to password-only event               │
│       when isBiometricKeyInvalidated == true                 │
└──────────────────────────┬───────────────────────────────────┘
                           │
┌──────────────────────────▼───────────────────────────────────┐
│ BLoC Layer (LockerBloc)                                      │
│                                                              │
│ _onDisableBiometricPasswordOnlyRequested:                    │
│   password-only → repo.disableBiometricPasswordOnly          │
│                 → clear flag, refresh biometric state         │
│                                                              │
│ _onEnableBiometricRequested (existing):                      │
│   on success → clear isBiometricKeyInvalidated flag          │
└──────────────────────────┬───────────────────────────────────┘
                           │
┌──────────────────────────▼───────────────────────────────────┐
│ Repository Layer (LockerRepositoryImpl)                       │
│                                                              │
│ disableBiometricPasswordOnly(password):                      │
│   authenticatePassword → locker.teardownBiometryPasswordOnly │
└──────────────────────────┬───────────────────────────────────┘
                           │
┌──────────────────────────▼───────────────────────────────────┐
│ Library Layer (MFALocker)                                    │
│                                                              │
│ teardownBiometryPasswordOnly(passwordCipherFunc, keyTag):    │
│   deleteWrap(Origin.bio) + try deleteKey (suppress errors)   │
└─────────────────────────────────────────────────────────────┘
```

### Recovery Workflow (User-Visible)

```
User changes biometrics in device settings (e.g., enrolls new fingerprint)
  → Phase 7: app detects keyInvalidated, sets isBiometricKeyInvalidated = true
  → User enters password → vault unlocks normally
  → User navigates to Settings
  → Biometric tile shows "Biometrics changed. Disable and re-enable to use new biometrics." in error color
  → User toggles biometric OFF → password prompt appears
  → User enters password → LockerBloc dispatches disableBiometricPasswordOnlyRequested
  → Repository calls teardownBiometryPasswordOnly (no biometric prompt)
  → Origin.bio wrap removed, flag cleared
  → User toggles biometric ON → password + biometric prompts
  → Fresh key created, biometric re-enabled with new enrollment
```

### Flag Lifecycle (complete picture)

`isBiometricKeyInvalidated` flag:
- **Set** — `_handleBiometricFailure` receives `BiometricExceptionType.keyInvalidated` (Phase 7)
- **Cleared** — `_onEraseStorageRequested` on success (Phase 7, task 7.9)
- **Cleared** — `_onDisableBiometricPasswordOnlyRequested` on success (Phase 8, task 8.4)
- **Cleared** — `_onEnableBiometricRequested` on success (Phase 8, task 8.6)

## Tasks

- [ ] **8.1** Add `disableBiometricPasswordOnly` to repository
  - File: `example/lib/features/locker/data/repositories/locker_repository.dart`
  - Add `Future<void> disableBiometricPasswordOnly({required String password})` to `LockerRepository` interface
  - Implement in `LockerRepositoryImpl`: `_securityProvider.authenticatePassword` → `_locker.teardownBiometryPasswordOnly(passwordCipherFunc, AppConstants.biometricKeyTag)`

- [ ] **8.2** Add `disableBiometricPasswordOnlyRequested` event to `LockerEvent` (Freezed)
  - File: `example/lib/features/locker/bloc/locker_event.dart`
  - Add `const factory LockerEvent.disableBiometricPasswordOnlyRequested({required String password}) = _DisableBiometricPasswordOnlyRequested`

- [ ] **8.3** Run `make g` for code generation
  - Dir: `example/`
  - Regenerates `.freezed.dart` files for updated event class

- [ ] **8.4** Register handler + implement `_onDisableBiometricPasswordOnlyRequested` in `LockerBloc`
  - File: `example/lib/features/locker/bloc/locker_bloc.dart`
  - Register: `on<_DisableBiometricPasswordOnlyRequested>(_onDisableBiometricPasswordOnlyRequested)`
  - Implementation: set `loadState: loading` → call `repo.disableBiometricPasswordOnly` → `_refreshBiometricState` → clear `isBiometricKeyInvalidated` → show success
  - No `biometricOperationState` management (password-only, no system biometric dialog)
  - Error handling: `onDecryptFailed` for wrong password, `onError` for generic failure

- [ ] **8.5** Update `SettingsScreen._handleBiometricToggle` — route to password-only event when invalidated
  - File: `example/lib/features/settings/views/settings_screen.dart`
  - When `value == false` (disabling) and `lockerBloc.state.isBiometricKeyInvalidated == true`:
    dispatch `LockerEvent.disableBiometricPasswordOnlyRequested(password:)` instead of `disableBiometricRequested`

- [ ] **8.6** Clear `isBiometricKeyInvalidated` on successful enable
  - File: `example/lib/features/locker/bloc/locker_bloc.dart`
  - In `_onEnableBiometricRequested`, after successful `enableBiometric` and `_refreshBiometricState`:
    `emit(state.copyWith(isBiometricKeyInvalidated: false))`

## Acceptance Criteria

**Test:** `cd example && fvm flutter analyze --fatal-warnings --fatal-infos --no-pub . && fvm dart format . --line-length 120`

- `disableBiometricPasswordOnly` on the repository calls `teardownBiometryPasswordOnly` without creating a `BioCipherFunc`
- Toggling biometric OFF in Settings when `isBiometricKeyInvalidated` dispatches `disableBiometricPasswordOnlyRequested` (not `disableBiometricRequested`)
- After successful password-only disable: `isBiometricKeyInvalidated` is `false`, biometric state is refreshed
- After successful biometric re-enable: `isBiometricKeyInvalidated` is `false`
- Wrong password during disable emits a specific error (not a generic one)

## Dependencies

- Phase 7 complete — `isBiometricKeyInvalidated` flag in `LockerState`, `biometricKeyInvalidated` action, Settings screen invalidation display are all in place
- `MFALocker.teardownBiometryPasswordOnly` from Phase 5 is available
- `BiometricExceptionType.keyInvalidated` from Phase 4 is available

## Technical Details

### Task 8.1 — Repository method

```dart
/// Disable biometric authentication using password only.
///
/// Use when the biometric key has been permanently invalidated and the
/// normal [disableBiometric] flow (which requires a biometric prompt)
/// cannot succeed.
Future<void> disableBiometricPasswordOnly({required String password});
```

Implementation in `LockerRepositoryImpl`:

```dart
@override
Future<void> disableBiometricPasswordOnly({required String password}) async {
  await _ensureLockerInstance();
  final passwordCipherFunc = await _securityProvider.authenticatePassword(password: password);

  await _locker.teardownBiometryPasswordOnly(
    passwordCipherFunc: passwordCipherFunc,
    biometricKeyTag: AppConstants.biometricKeyTag,
  );
}
```

### Task 8.2 — New event

```dart
/// Request to disable biometric authentication using password only (key invalidated scenario)
const factory LockerEvent.disableBiometricPasswordOnlyRequested({
  required String password,
}) = _DisableBiometricPasswordOnlyRequested;
```

### Task 8.4 — BLoC handler

```dart
Future<void> _onDisableBiometricPasswordOnlyRequested(
  _DisableBiometricPasswordOnlyRequested event,
  Emitter<LockerState> emit,
) async {
  emit(state.copyWith(loadState: LoadState.loading));

  await _handleVaultOperation(
    operation: () async {
      await _lockerRepository.disableBiometricPasswordOnly(password: event.password);
      await _refreshBiometricState(emit, resetLoadState: true);

      if (!isClosed) {
        emit(state.copyWith(isBiometricKeyInvalidated: false));
      }

      action(const LockerAction.showSuccess(message: 'Biometric authentication disabled'));
    },
    onDecryptFailed: (error) => _handleDecryptFailure(
      emit,
      LockerAction.showError(message: 'Incorrect password: $error'),
    ),
    onError: (error) => _handleGenericFailure(
      emit,
      LockerAction.showError(message: 'Failed to disable biometric: $error'),
    ),
    operationDescription: 'disable biometric (password-only)',
  );
}
```

No `biometricOperationState` management — password-only operation, no system biometric dialog.

### Task 8.5 — Settings toggle routing

```dart
// In _handleBiometricToggle, before the normal disableBiometricRequested dispatch:
if (!value && lockerBloc.state.isBiometricKeyInvalidated) {
  lockerBloc.add(
    LockerEvent.disableBiometricPasswordOnlyRequested(password: result!.password!),
  );
  return;
}
```

### Task 8.6 — Clear flag on successful enable

In `_onEnableBiometricRequested`, after the successful enable + `_refreshBiometricState` call:

```dart
emit(state.copyWith(isBiometricKeyInvalidated: false));
```

## Implementation Notes

- Tasks 8.1 and 8.2 can be done in parallel. Task 8.3 (`make g`) must run after both.
- Task 8.4 must run after 8.3 (references generated `_DisableBiometricPasswordOnlyRequested`).
- Tasks 8.5 and 8.6 are independent of each other and can follow 8.4.
- The `_handleVaultOperation` helper is the standard wrapper — follow the exact same pattern used by `_onDisableBiometricRequested`.
- `_refreshBiometricState(emit, resetLoadState: true)` sets `loadState` back to `idle` as part of the state refresh. Don't manually reset `loadState` after the `operation` closure.
- The password prompt in `_handleBiometricToggle` (task 8.5) already exists for the normal disable flow — reuse it; just route the result to the new event type when `isBiometricKeyInvalidated` is true.
