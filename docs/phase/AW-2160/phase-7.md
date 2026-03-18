# Phase 7: Example App — Detect and Display Key Invalidation

**Goal:** Wire the example app to detect `keyInvalidated` at runtime, display an inline message, and hide biometric UI when the key is invalidated.

## Context

### Feature Motivation

When a user changes biometrics in device settings (e.g. enrolls a new fingerprint), the hardware key becomes permanently inaccessible. Previously, this manifested as a generic failure. Iterations 1–5 added the dedicated `keyInvalidated` exception type through all library layers. This iteration wires the **example app** to:
1. Detect the invalidation at decrypt time and set a runtime flag
2. Display "Biometrics have changed. Please use your password." inline in the auth sheet
3. Hide the biometric unlock button so users can't keep tapping a broken button

### What "Permanently Invalidated" Means to the App

`determineBiometricState()` still returns `BiometricState.enabled` because the hardware is fine and the `Origin.bio` wrap exists in storage. The invalidation is only discoverable at **decrypt time** when the platform throws `keyInvalidated`. The `isBiometricKeyInvalidated` flag captures this runtime knowledge.

**Flag lifecycle:**
- **Set** when `_handleBiometricFailure` receives `BiometricExceptionType.keyInvalidated`
- **Cleared** on: successful `enableBiometric`, `eraseStorage`, or `disableBiometricPasswordOnly`

### App-Level Flow

```
┌─────────────────────────────────────────────────────────────┐
│ UI Layer                                                     │
│                                                              │
│ LockedScreen / BiometricUnlockButton                         │
│   └── Hide biometric button when isBiometricKeyInvalidated   │
│                                                              │
│ AuthenticationBottomSheet (via biometric stream)              │
│   └── Show "Biometrics have changed" inline message          │
│                                                              │
│ SettingsScreen                                               │
│   └── Show invalidation description in error color           │
│   └── Route toggle-off to password-only event (phase 8)      │
└──────────────────────────┬───────────────────────────────────┘
                           │
┌──────────────────────────▼───────────────────────────────────┐
│ BLoC Layer (LockerBloc)                                      │
│                                                              │
│ _handleBiometricFailure:                                     │
│   keyInvalidated → set flag, emit biometricKeyInvalidated    │
│                    action, reset to idle, return early        │
└──────────────────────────────────────────────────────────────┘
```

### Recovery Workflow (User-Visible)

```
User changes biometrics in device settings
  → User opens app → vault is locked
  → User taps "Unlock Storage" → auth bottom sheet opens with biometric button
  → Biometric prompt triggers → platform throws keyPermanentlyInvalidated
  → BLoC sets isBiometricKeyInvalidated = true
  → BLoC emits biometricKeyInvalidated action
  → Biometric stream maps to BiometricFailed("Biometrics have changed. Please use your password.")
  → Auth bottom sheet shows inline error message
  → Biometric button hides (sheet + locked screen)
  → User enters password → vault unlocks normally
  → User navigates to Settings
  → Biometric tile shows "Biometrics changed. Disable and re-enable to use new biometrics." in error color
  → User toggles OFF → password-only disable path (phase 8)
```

## Tasks

- [x] 7.1 Add `isBiometricKeyInvalidated` flag to `LockerState` (Freezed)
  - File: `example/lib/features/locker/bloc/locker_state.dart`
  - Add `@Default(false) bool isBiometricKeyInvalidated` to `LockerState`

- [x] 7.2 Add `biometricKeyInvalidated()` action to `LockerAction` (Freezed)
  - File: `example/lib/features/locker/bloc/locker_action.dart`
  - Add `const factory LockerAction.biometricKeyInvalidated() = BiometricKeyInvalidatedAction`

- [x] 7.3 Run `make g` for code generation
  - Dir: `example/`
  - Regenerates `.freezed.dart` files for updated state, event, and action classes

- [x] 7.4 Separate `keyInvalidated` from `failure` in `_handleBiometricFailure`
  - File: `example/lib/features/locker/bloc/locker_bloc.dart`
  - Split the `case BiometricExceptionType.failure: case BiometricExceptionType.keyInvalidated:` block
  - `keyInvalidated`: set `isBiometricKeyInvalidated: true`, emit `biometricKeyInvalidated()` action, reset to `BiometricOperationState.idle`, return early
  - `failure`: keep existing behavior (call `_determineBiometricStateAndEmit`, fall through)

- [x] 7.5 Map `biometricKeyInvalidated` action in biometric stream extension
  - File: `example/lib/features/locker/views/widgets/locker_bloc_biometric_stream.dart`
  - Add `biometricKeyInvalidated: (_) => const BiometricFailed('Biometrics have changed. Please use your password.')` to the `mapOrNull` call

- [x] 7.6 Hide biometric button when `isBiometricKeyInvalidated` is true
  - File: `example/lib/features/locker/views/auth/locked_screen.dart`
    - Update `buildWhen` to include `isBiometricKeyInvalidated`
    - Update `showBiometricButton:` to `state.biometricState.isEnabled && !state.isBiometricKeyInvalidated`
    - Update biometric `onPressed` guard similarly
  - File: `example/lib/features/locker/views/widgets/biometric_unlock_button.dart`
    - Update `buildWhen` to include `isBiometricKeyInvalidated`
    - Return `SizedBox.shrink()` when `state.isBiometricKeyInvalidated` is true

- [x] 7.7 Update `SettingsScreen` for invalidation display
  - File: `example/lib/features/settings/views/settings_screen.dart`
  - Update `_getBiometricStateDescription` to accept `isKeyInvalidated` parameter
  - When invalidated: return `'Biometrics changed. Disable and re-enable to use new biometrics.'`
  - Style subtitle text in `Theme.of(context).colorScheme.error` when invalidated
  - Update `_canToggleBiometric` to allow toggle when `isBiometricKeyInvalidated` is true
  - Update `buildWhen` to include `isBiometricKeyInvalidated`
  - Account for invalidation in `_AutoLockTimeoutTile` biometric check: `state.biometricState.isEnabled && !lockerBloc.state.isBiometricKeyInvalidated`

- [x] 7.8 Update `SettingsBloc` — specific `keyInvalidated` case in timeout-with-biometric handler
  - File: `example/lib/features/settings/bloc/settings_bloc.dart`
  - In `_onAutoLockTimeoutSelectedWithBiometric` catch block: add `case BiometricExceptionType.keyInvalidated:` with message `'Biometrics have changed. Please use your password.'`, return early

- [x] 7.9 Clear `isBiometricKeyInvalidated` flag on erase
  - File: `example/lib/features/locker/bloc/locker_bloc.dart`
  - In `_onEraseStorageRequested`, after successful erase: `emit(state.copyWith(isBiometricKeyInvalidated: false))`

## Acceptance Criteria

**Test:** `cd example && fvm flutter analyze --fatal-warnings --fatal-infos --no-pub . && fvm dart format . --line-length 120`

- When `BiometricExceptionType.keyInvalidated` is received, `isBiometricKeyInvalidated` is set to `true` and `biometricKeyInvalidated` action is emitted
- Auth bottom sheet shows "Biometrics have changed. Please use your password." inline
- Biometric button is hidden on locked screen and in `BiometricUnlockButton` when flag is set
- Settings screen shows error-colored description and allows biometric toggle when invalidated
- `isBiometricKeyInvalidated` is cleared on erase

## Dependencies

- Phase 6 (Tests) should be complete, but this iteration can proceed in parallel since it touches different files
- `BiometricExceptionType.keyInvalidated` from Phase 4 is available
- `teardownBiometryPasswordOnly` from Phase 5 is available (used in Phase 8)

## Technical Details

### Task 7.4 — `_handleBiometricFailure` change

```dart
// Before:
case BiometricExceptionType.failure:
case BiometricExceptionType.keyInvalidated:
  await _determineBiometricStateAndEmit(emit);

// After:
case BiometricExceptionType.keyInvalidated:
  emit(state.copyWith(isBiometricKeyInvalidated: true));
  action(const LockerAction.biometricKeyInvalidated());
  add(
    const LockerEvent.biometricOperationStateChanged(
      biometricOperationState: BiometricOperationState.idle,
    ),
  );
  return;

case BiometricExceptionType.failure:
  await _determineBiometricStateAndEmit(emit);
```

### Task 7.5 — Biometric stream extension

```dart
extension LockerBlocBiometricStream on LockerBloc {
  Stream<BiometricAuthResult> get biometricResultStream => actions
      .map(
        (action) => action.mapOrNull(
          biometricAuthenticationSucceeded: (_) => const BiometricSuccess(),
          biometricAuthenticationCancelled: (_) => const BiometricCancelled(),
          biometricAuthenticationFailed: (a) => BiometricFailed(a.message),
          biometricKeyInvalidated: (_) =>
              const BiometricFailed('Biometrics have changed. Please use your password.'),
          biometricNotAvailable: (_) => const BiometricNotAvailable(),
        ),
      )
      .where((result) => result != null)
      .cast<BiometricAuthResult>();
}
```

### Task 7.6 — Locked screen / biometric button changes

```dart
// locked_screen.dart — buildWhen:
buildWhen: (previous, current) =>
    previous.loadState != current.loadState ||
    previous.biometricState != current.biometricState ||
    previous.isBiometricKeyInvalidated != current.isBiometricKeyInvalidated,

// locked_screen.dart — showBiometricButton:
showBiometricButton: state.biometricState.isEnabled && !state.isBiometricKeyInvalidated,

// biometric_unlock_button.dart — early return:
if (!state.biometricState.isEnabled || state.isBiometricKeyInvalidated) {
  return const SizedBox.shrink();
}
```

### Task 7.7 — Settings screen changes

```dart
String _getBiometricStateDescription(BiometricState biometricState, {required bool isKeyInvalidated}) {
  if (isKeyInvalidated) {
    return 'Biometrics changed. Disable and re-enable to use new biometrics.';
  }
  return switch (biometricState) {
    // ... existing cases unchanged ...
  };
}

bool _canToggleBiometric(LockerState state) =>
    (state.biometricState.isAvailable || state.isBiometricKeyInvalidated) &&
    state.loadState != LoadState.loading;

// _AutoLockTimeoutTile biometric check:
final isBiometricEnabled =
    lockerBloc.state.biometricState.isEnabled && !lockerBloc.state.isBiometricKeyInvalidated;
```

### Task 7.8 — SettingsBloc timeout handler

```dart
case BiometricExceptionType.keyInvalidated:
  action(
    const SettingsAction.biometricAuthenticationFailed(
      message: 'Biometrics have changed. Please use your password.',
    ),
  );
  return;
```

## Implementation Notes

- The `biometricKeyInvalidated` action is distinct from `biometricAuthenticationFailed` — don't conflate them. The UI must handle both.
- Task 7.3 (`make g`) must run after 7.1 and 7.2, but before 7.4 (which references generated code).
- The `isBiometricKeyInvalidated` flag is only cleared in two places in this phase: task 7.9 (on erase). Clearing on successful `enableBiometric` is covered in Phase 8, task 8.6.
- The `_handleBiometricToggle` routing to the password-only event (when `isBiometricKeyInvalidated` is true) is Phase 8, task 8.5 — not part of this phase.
