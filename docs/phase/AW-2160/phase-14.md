# Phase 14: Example App — Proactive Detection Integration

**Goal:** Use `BiometricState.keyInvalidated` from `determineBiometricState` to hide biometric UI at init time — eliminating the brief biometric button flash before a failed attempt hides it.

## Context

With proactive detection (Phase 12), `determineBiometricState(biometricKeyTag: tag)` now returns `BiometricState.keyInvalidated` directly at startup — before the user ever taps the biometric button. The example app needs to consume this new state so that the locked screen starts in password-only mode when the key is already invalid.

The runtime flag `isBiometricKeyInvalidated` (Phase 7) stays in place for in-session discovery (e.g., user taps biometric in an auth dialog and gets the invalidation error mid-session). Phase 14 adds a complementary init-time check via `biometricState.isKeyInvalidated`.

**From idea-2160.md Section G8 — updated locked screen flow:**

```
buildWhen: state.biometricState changes
if (state.biometricState.isEnabled && !state.biometricState.isKeyInvalidated)
  → show biometric button
else
  → hide biometric button
```

**From idea-2160.md Section G7 — repository change:**

```dart
Future<BiometricState> determineBiometricState() =>
    locker.determineBiometricState(biometricKeyTag: LockerConstants.biometricKeyTag);
```

This passes the key tag so the locker library can perform the silent `isKeyValid` probe.

## Tasks

- [x] 14.1 Pass `biometricKeyTag` in repository's `determineBiometricState` call
  - File: `example/lib/features/locker/data/repositories/locker_repository.dart`
  - Update the `determineBiometricState()` call to pass `biometricKeyTag: AppConstants.biometricKeyTag`

- [x] 14.2 Handle `BiometricState.keyInvalidated` in `LockerBloc`
  - File: `example/lib/features/locker/bloc/locker_bloc.dart`
  - When `determineBiometricState` returns `keyInvalidated`: set `isBiometricKeyInvalidated: true` on state

- [x] 14.3 Update locked screen biometric button visibility to use `biometricState.isKeyInvalidated`
  - File: `example/lib/features/locker/views/auth/locked_screen.dart`
  - Update `showBiometricButton:` to also check `!state.biometricState.isKeyInvalidated`
  - This provides init-time hiding (no button flash) alongside the runtime flag

- [x] 14.4 Update `BiometricUnlockButton` to check `biometricState.isKeyInvalidated`
  - File: `example/lib/features/locker/views/widgets/biometric_unlock_button.dart`
  - Add `state.biometricState.isKeyInvalidated` check alongside existing `isBiometricKeyInvalidated` check

## Acceptance Criteria

**Test:** `cd example && fvm flutter analyze --fatal-warnings --fatal-infos --no-pub . && fvm dart format . --line-length 120`

- Locked screen never shows biometric button when `determineBiometricState` returns `keyInvalidated` at init.
- No button flash: biometric button is hidden from first render, not revealed then hidden after a failed attempt.
- Runtime flag (`isBiometricKeyInvalidated`) remains effective for in-session invalidation discovery.
- `BiometricUnlockButton` hides on both `isBiometricKeyInvalidated` and `biometricState.isKeyInvalidated`.

## Dependencies

- Phase 12 complete (`BiometricState.keyInvalidated` enum + `determineBiometricState(biometricKeyTag:)` implemented)
- Phase 13 complete (tests for proactive detection passing)

## Technical Details

### Files changed

| File | Change |
|------|--------|
| `example/lib/features/locker/data/repositories/locker_repository.dart` | Pass `biometricKeyTag: AppConstants.biometricKeyTag` to `determineBiometricState` |
| `example/lib/features/locker/bloc/locker_bloc.dart` | Set `isBiometricKeyInvalidated: true` when state is `keyInvalidated` |
| `example/lib/features/locker/views/auth/locked_screen.dart` | Add `!state.biometricState.isKeyInvalidated` to `showBiometricButton` |
| `example/lib/features/locker/views/widgets/biometric_unlock_button.dart` | Add `state.biometricState.isKeyInvalidated` check |

### LockerBloc — handle `keyInvalidated` from `determineBiometricState`

In `_determineBiometricStateAndEmit` (or wherever `determineBiometricState` result is consumed):

```dart
case BiometricState.keyInvalidated:
  emit(state.copyWith(
    biometricState: BiometricState.keyInvalidated,
    isBiometricKeyInvalidated: true,
  ));
```

### LockedScreen — button visibility

```dart
showBiometricButton: state.biometricState.isEnabled &&
    !state.isBiometricKeyInvalidated &&
    !state.biometricState.isKeyInvalidated,
```

### BiometricUnlockButton — hide condition

```dart
if (state.isBiometricKeyInvalidated || state.biometricState.isKeyInvalidated) {
  return const SizedBox.shrink();
}
```

## Implementation Notes

The two checks (`isBiometricKeyInvalidated` and `biometricState.isKeyInvalidated`) are complementary:
- `biometricState.isKeyInvalidated` — detected at init time via silent key probe; no user interaction needed.
- `isBiometricKeyInvalidated` — detected at runtime when the user triggers a biometric operation and receives `BiometricExceptionType.keyInvalidated`.

Both must independently gate the biometric button to cover all cases.
