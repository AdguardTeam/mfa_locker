# Phase 15: Example App: Proactive Detection Integration

**Goal:** Use `BiometricState.keyInvalidated` from `determineBiometricState` to hide biometric UI at init time — eliminating the brief biometric button flash before a failed attempt hides it.

## Context

### Feature Motivation

Phase 13 added `BiometricState.keyInvalidated` and the proactive key validity check in `MFALocker.determineBiometricState(biometricKeyTag:)`. Phase 14 added tests. This phase wires up the example app to consume `keyInvalidated` from the initial state query, so the locked screen never shows the biometric button when the key is already invalidated — no flash, no failed attempt required.

Previously, invalidation was only detected at runtime (when the user tapped the biometric button and the prompt failed). This phase adds init-time detection via `determineBiometricState`, which eliminates the UX issue entirely.

The `isBiometricKeyInvalidated` runtime flag (from Phase 7) remains useful for in-session state changes where the user discovers invalidation mid-session via an explicit biometric attempt.

### Section G7 — Repository: pass `biometricKeyTag`

**File**: `example/lib/features/locker/data/repositories/locker_repository.dart`

```dart
Future<BiometricState> determineBiometricState() =>
    locker.determineBiometricState(biometricKeyTag: AppConstants.biometricKeyTag);
```

Passing `biometricKeyTag` automatically enables proactive detection for all callers. Without the tag, the existing behavior (no key validity check) is preserved for backwards compatibility.

### Section G8 — Example App Integration

With proactive detection, `determineBiometricState()` returns `keyInvalidated` directly at init time. The biometric button can be hidden based on `biometricState.isKeyInvalidated` from the initial state query, without waiting for a failed user-initiated operation.

**Updated locked screen flow:**

```
buildWhen: state.biometricState changes (or isBiometricKeyInvalidated changes)
if (state.biometricState.isEnabled
    && !state.biometricState.isKeyInvalidated
    && !state.isBiometricKeyInvalidated)
  → show biometric button
else
  → hide biometric button
```

The two checks serve different purposes:
- `biometricState.isKeyInvalidated` — init-time detection (from `determineBiometricState` at startup)
- `isBiometricKeyInvalidated` — runtime detection (from a failed biometric attempt mid-session)

### Proactive Detection Flow (Workflow 4)

```
App starts / lock screen mounts
  → LockerBloc calls determineBiometricState(biometricKeyTag: AppConstants.biometricKeyTag)
    → TPM check: supported
    → Biometry check: available, enrolled
    → App settings check: biometric enabled
    → Key validity check: isKeyValid(tag) — NO biometric prompt
      → Android: Cipher.init() → KeyPermanentlyInvalidatedException → false
      → iOS/macOS: keyExists() with kSecUseAuthenticationUISkip → false
      → Windows: OpenAsync() → NotFound → false
    → Returns BiometricState.keyInvalidated
  → LockerBloc sets isBiometricKeyInvalidated: true in state
  → Lock screen renders with biometricState.isKeyInvalidated == true → no biometric button
  → No button flash — UI is correct from the first frame
```

## Tasks

- [x] **15.1** Pass `biometricKeyTag` in repository's `determineBiometricState` call
  - File: `example/lib/features/locker/data/repositories/locker_repository.dart`
  - Update the `determineBiometricState()` call to pass `biometricKeyTag: AppConstants.biometricKeyTag`

- [x] **15.2** Handle `BiometricState.keyInvalidated` in `LockerBloc`
  - File: `example/lib/features/locker/bloc/locker_bloc.dart`
  - When `determineBiometricState` returns `keyInvalidated`: set `isBiometricKeyInvalidated: true` on state

- [x] **15.3** Update locked screen biometric button visibility to use `biometricState.isKeyInvalidated`
  - File: `example/lib/features/locker/views/auth/locked_screen.dart`
  - Update `showBiometricButton:` to also check `!state.biometricState.isKeyInvalidated`
  - This provides init-time hiding (no button flash) alongside the runtime flag

- [x] **15.4** Update `BiometricUnlockButton` to check `biometricState.isKeyInvalidated`
  - File: `example/lib/features/locker/views/widgets/biometric_unlock_button.dart`
  - Add `state.biometricState.isKeyInvalidated` check alongside existing `isBiometricKeyInvalidated` check

## Acceptance Criteria

**Test:** `cd example && fvm flutter analyze --fatal-warnings --fatal-infos --no-pub . && fvm dart format . --line-length 120`

- `LockerRepository.determineBiometricState()` passes `biometricKeyTag: AppConstants.biometricKeyTag`
- When `determineBiometricState` returns `BiometricState.keyInvalidated`, `LockerBloc` sets `isBiometricKeyInvalidated: true`
- `LockedScreen` hides biometric button when `state.biometricState.isKeyInvalidated` is true (init-time detection)
- `BiometricUnlockButton` hides when `state.biometricState.isKeyInvalidated` is true
- No biometric button flash on locked screen when key is invalidated (init-time, not just after failed attempt)
- Analyze and format pass with no errors

## Dependencies

- Phase 13 complete (`BiometricState.keyInvalidated`, `BiometricCipherProvider.isKeyValid`, `MFALocker.determineBiometricState` with `biometricKeyTag` all implemented)
- Phase 7 complete (`isBiometricKeyInvalidated` runtime flag in `LockerState`)
- Phase 8 complete (password-only biometric disable flow)

## Technical Details

### Task 15.1 — Repository call update

The `LockerRepository.determineBiometricState()` implementation in `LockerRepositoryImpl` currently calls `_locker.determineBiometricState()` with no arguments. Adding `biometricKeyTag: AppConstants.biometricKeyTag` activates the key validity check. The interface signature is unchanged (consumer calls `determineBiometricState()` without arguments).

### Task 15.2 — LockerBloc: handle `keyInvalidated` state

In `_refreshBiometricState` (or equivalent), when `determineBiometricState()` returns `keyInvalidated`:
- Set `isBiometricKeyInvalidated: true` in state (same flag used by runtime detection in Phase 7)
- The `biometricState` on the state object will carry `BiometricState.keyInvalidated` directly

Both flags are now set simultaneously on init, providing dual-layer hiding logic.

### Tasks 15.3 & 15.4 — UI: dual-layer hiding

Before this phase, `showBiometricButton` and `BiometricUnlockButton` only checked `isBiometricKeyInvalidated` (runtime flag). After:

```dart
// LockedScreen
showBiometricButton: state.biometricState.isEnabled
    && !state.biometricState.isKeyInvalidated  // NEW: init-time
    && !state.isBiometricKeyInvalidated,        // existing: runtime

// BiometricUnlockButton
if (state.biometricState.isKeyInvalidated      // NEW: init-time
    || state.isBiometricKeyInvalidated)         // existing: runtime
  return SizedBox.shrink();
```

`buildWhen` in both widgets should already include `biometricState` (it carries `isKeyInvalidated`), ensuring a rebuild when the state is set at init.

## Implementation Notes

- This phase is purely wiring — no new library changes, only example app
- The `biometricState.isKeyInvalidated` check is idempotent with the runtime `isBiometricKeyInvalidated` flag; both serving as safety nets for different detection paths
- `AppConstants.biometricKeyTag` is the shared constant for the biometric key tag used throughout the example app
