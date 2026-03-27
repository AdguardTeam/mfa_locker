# AW-2160 Phase 7 Summary — Example App: Detect and Display Biometric Key Invalidation

## What Was Done

Phase 7 wires the example app to detect `BiometricExceptionType.keyInvalidated` at runtime and respond with clear, actionable UI feedback. No library-layer files were changed. All nine tasks touch only `example/lib/` files.

The problem addressed: the library layers (Phases 1–5) correctly surface `BiometricExceptionType.keyInvalidated` when the hardware key is gone, but the example app still treated it identically to a generic biometric failure. Users saw no actionable message and the biometric button remained visible, causing repeated failing prompts. This phase makes the first occurrence of an invalidated key detectable and immediately visible to the user, and propagates that knowledge to every piece of UI that shows or hides biometric controls.

---

## Files Changed

All files are under `example/lib/`.

| File | Task | Change |
|------|------|--------|
| `features/locker/bloc/locker_state.dart` | 7.1 | Added `@Default(false) bool isBiometricKeyInvalidated` to `LockerState` |
| `features/locker/bloc/locker_action.dart` | 7.2 | Added `LockerAction.biometricKeyInvalidated()` Freezed factory |
| (codegen) | 7.3 | `make g` regenerated `.freezed.dart` files for updated state and action classes |
| `features/locker/bloc/locker_bloc.dart` | 7.4 | Extracted `keyInvalidated` into its own case in `_handleBiometricFailure` — sets flag, emits action, resets to idle, returns early |
| `features/locker/views/widgets/locker_bloc_biometric_stream.dart` | 7.5 | Added `biometricKeyInvalidated` mapping to `BiometricFailed('Biometrics have changed. Please use your password.')` |
| `features/locker/views/auth/locked_screen.dart` | 7.6 | Added `isBiometricKeyInvalidated` to `buildWhen`; updated `showBiometricButton` and button label condition |
| `features/locker/views/widgets/biometric_unlock_button.dart` | 7.7 | Added `isBiometricKeyInvalidated` to `buildWhen`; returns `SizedBox.shrink()` when flag is set |
| `features/settings/views/settings_screen.dart` | 7.8 | Updated `buildWhen`, `_canToggleBiometric`, `_getBiometricStateDescription`, subtitle error color, and `_AutoLockTimeoutTile` biometric check |
| `features/settings/bloc/settings_bloc.dart` | 7.8b | Added `case BiometricExceptionType.keyInvalidated:` in `_onAutoLockTimeoutSelectedWithBiometric` with specific message and early return |
| `features/locker/bloc/locker_bloc.dart` | 7.9 | Added `isBiometricKeyInvalidated: false` to the `state.copyWith(...)` call in `_onEraseStorageRequested` success path |

Zero new files were created. All changes are additive modifications to existing files.

---

## What Was Added

### Task 7.1 — `isBiometricKeyInvalidated` flag on `LockerState`

A new `@Default(false) bool isBiometricKeyInvalidated` Freezed field on `LockerState`. This flag is in-memory only — it is not persisted to any storage, has no `SharedPreferences` writes, and initializes to `false` on every cold launch. It represents runtime knowledge that the current session has detected a permanently invalidated biometric key. One failed biometric prompt per session before the flag is set is accepted behavior.

### Task 7.2 — `LockerAction.biometricKeyInvalidated()` factory

A new no-parameter Freezed factory on `LockerAction`, placed after `biometricNotAvailable`. This action is deliberately distinct from `biometricAuthenticationFailed` — the UI must handle both separately and must not conflate them.

### Task 7.3 — Code generation

`make g` regenerated `locker_bloc.freezed.dart` with the new field and factory. Tasks 7.4 onward depend on the generated `biometricKeyInvalidated()` factory being available for `mapOrNull`.

### Task 7.4 — `keyInvalidated` handling in `_handleBiometricFailure`

Previously, `BiometricExceptionType.keyInvalidated` shared a fall-through case with `BiometricExceptionType.failure`, both calling `_determineBiometricStateAndEmit` and ultimately emitting the generic `biometricAuthenticationFailed` action.

After the change, `keyInvalidated` has its own case that:
1. Emits `state.copyWith(isBiometricKeyInvalidated: true)`.
2. Emits `LockerAction.biometricKeyInvalidated()` via `action(...)`.
3. Adds `LockerEvent.biometricOperationStateChanged(biometricOperationState: BiometricOperationState.idle)`.
4. Returns early — does not fall through to `biometricAuthenticationFailed`.

The `failure` case retains its original behavior unchanged. This is the central dispatch point for all downstream UI changes in this phase.

### Task 7.5 — Biometric stream extension mapping

`LockerBlocBiometricStream` adds a `biometricKeyInvalidated` arm to the `mapOrNull` call, mapping to `const BiometricFailed('Biometrics have changed. Please use your password.')`. The auth bottom sheet receives this as an inline error result. The approved copy string is used exactly as written.

### Task 7.6 — `LockedScreen` biometric button guard

Three changes:
- `buildWhen` now includes `previous.isBiometricKeyInvalidated != current.isBiometricKeyInvalidated`, ensuring the screen rebuilds immediately when the flag is set.
- The `showBiometric` local variable is `state.biometricState.isEnabled && !state.isBiometricKeyInvalidated`, so the biometric path is gated on both conditions.
- The button label (`'Unlock Storage'` vs. `'Unlock with Password'`) uses the same boolean, so the label switches to password-only mode as soon as the flag is set.
- The `onBiometricPressed` callback is `null` when `showBiometric` is `false`, preventing biometric dispatch through the `AuthenticationBottomSheet` when the key is invalid.

### Task 7.7 — `BiometricUnlockButton` hide condition

`buildWhen` and the early-return guard both include `isBiometricKeyInvalidated`. The widget returns `SizedBox.shrink()` when either `!state.biometricState.isEnabled` or `state.isBiometricKeyInvalidated` is true.

### Task 7.8 — `SettingsScreen` invalidation display

Five changes to `settings_screen.dart`:
- Inner `BlocBuilder` `buildWhen` includes `isBiometricKeyInvalidated` so the biometric tile card rebuilds on flag changes.
- `_canToggleBiometric` condition is `(state.biometricState.isAvailable || state.isBiometricKeyInvalidated) && state.loadState != LoadState.loading`. The `|| state.isBiometricKeyInvalidated` clause ensures the toggle remains enabled when the key is invalidated, so the user can initiate the disable flow.
- `_getBiometricStateDescription` accepts a new required named parameter `{required bool isKeyInvalidated}`. When `true`, it returns `'Biometrics changed. Disable and re-enable to use new biometrics.'` before the switch statement, short-circuiting all other cases. The approved copy string is used exactly as written.
- The subtitle `Text` widget applies `TextStyle(color: Theme.of(context).colorScheme.error)` when `innerLockerState.isBiometricKeyInvalidated` is `true`.
- The `'Your biometric credentials can unlock the vault.'` hint text is guarded by `biometricState.isEnabled && !isBiometricKeyInvalidated`, preventing it from appearing alongside the error message.
- `_AutoLockTimeoutTile._showTimeoutDialog` computes `isBiometricEnabled` as `lockerBloc.state.biometricState.isEnabled && !lockerBloc.state.isBiometricKeyInvalidated`, preventing the biometric button from appearing in the timeout dialog when the key is invalidated.

### Task 7.8b — `SettingsBloc` specific `keyInvalidated` case

In `_onAutoLockTimeoutSelectedWithBiometric`, `BiometricExceptionType.keyInvalidated` previously fell through to the `failure`/`notConfigured` group that ended in the generic `'Failed to update timeout using biometric.'` message plus a `showError` snackbar.

After the change, `keyInvalidated` has its own case that emits `SettingsAction.biometricAuthenticationFailed(message: 'Biometrics have changed. Please use your password.')` and returns early, without emitting a separate `showError` action. The `_AutoLockTimeoutTile` guard (Task 7.8) makes this case normally unreachable from normal UI interaction — the `SettingsBloc` case acts as a defensive backstop.

### Task 7.9 — Erase clears the flag

`_onEraseStorageRequested` includes `isBiometricKeyInvalidated: false` in the `state.copyWith(...)` call in its success path, alongside the resets for `status`, `entries`, and `loadState`. This ensures no stale invalidation knowledge is carried over after a storage erase.

---

## Decisions Made

**Flag is in-memory only.** `isBiometricKeyInvalidated` is a plain Freezed field with no persistence. Resetting to `false` on each cold launch (meaning one failed biometric prompt per session before the flag is set) is accepted behavior per the PRD. The flag lifetime within a session is: set on first `keyInvalidated` detection, cleared on erase. Clearing on successful `enableBiometric` or `disableBiometricPasswordOnly` is Phase 8.

**Dedicated `biometricKeyInvalidated` action, not reuse of `biometricAuthenticationFailed`.** Keeping the two actions distinct allows the stream extension and any future consumer to handle them differently without inspecting message strings. The `LockerBlocBiometricStream` handles both on separate arms of `mapOrNull`.

**`_handleBiometricToggle` still dispatches `disableBiometricRequested` when the key is invalidated.** The toggle is enabled in Phase 7 so the Settings UI is correct, but the routing to `disableBiometricPasswordOnlyRequested` is Phase 8. If a user taps the toggle with an invalidated key in Phase 7, the normal disable flow will attempt a biometric prompt, fail, and re-set the already-true flag. No crash or data loss; the user simply cannot complete the disable flow until Phase 8 ships.

**`_canToggleBiometric` uses `|| state.isBiometricKeyInvalidated`.** The condition intentionally allows the toggle to be enabled when the key is invalidated (and `biometricState` would otherwise be `enabled` but non-operable). The actual routing to the password-only event is Phase 8, task 8.5.

**`SettingsBloc` `keyInvalidated` case does not emit `showError`.** Emitting both `biometricAuthenticationFailed` (surfaced inline in the auth sheet) and a `showError` snackbar would result in a redundant snackbar. The `keyInvalidated` case returns after the inline action only.

---

## Open Issues Carried Forward

**Phase 7 does not complete the recovery workflow.** The Settings tile correctly tells the user "Disable and re-enable to use new biometrics", and the toggle is enabled, but tapping the toggle does not yet route to the password-only disable path. The complete recovery flow (user disables biometrics without a biometric prompt, flag is cleared, user can re-enable with fresh enrollment) requires Phase 8.

**No end-to-end device test has been performed for any phase of AW-2160.** The full pipeline from native `KeyPermanentlyInvalidatedException` / `errSecAuthFailed` through all Dart layers to the example app display has only been verified by code review and unit tests. A device-level smoke test is mandatory before the complete AW-2160 feature reaches production.

**No automated tests for example app code.** All Phase 7 changes are verified by code review and static analysis only. The example app has no test suite in this repository.

---

## How Phase 7 Fits in the Full AW-2160 Flow

```
Android: KeyPermanentlyInvalidatedException → FlutterError("KEY_PERMANENTLY_INVALIDATED")   [Phase 1]
iOS/macOS: Secure Enclave key inaccessible → FlutterError("KEY_PERMANENTLY_INVALIDATED")    [Phase 2]
  → Dart plugin: BiometricCipherExceptionCode.keyPermanentlyInvalidated                     [Phase 3]
  → Locker: BiometricExceptionType.keyInvalidated                                           [Phase 4]
  → MFALocker.teardownBiometryPasswordOnly available for cleanup                            [Phase 5]
  → Unit tests for Phases 3–5 Dart layer                                                    [Phase 6]
  → Example app detects keyInvalidated at runtime:                                          [Phase 7]
      → Sets isBiometricKeyInvalidated flag in LockerState
      → Emits LockerAction.biometricKeyInvalidated()
      → Auth sheet shows inline "Biometrics have changed. Please use your password."
      → Biometric button hidden on locked screen and in BiometricUnlockButton
      → Settings tile shows error-colored invalidation description
      → Settings toggle remains enabled for upcoming disable flow
  → Password-only disable flow wired in Settings toggle                                     [Phase 8 — pending]
```

---

## Phase Dependencies

| Phase | Status | Relevance |
|-------|--------|-----------|
| Phase 1 (Android native) | Complete | Emits `"KEY_PERMANENTLY_INVALIDATED"` from Android KeyStore |
| Phase 2 (iOS/macOS native) | Complete | Emits `"KEY_PERMANENTLY_INVALIDATED"` from Secure Enclave |
| Phase 3 (Dart plugin) | Complete | `BiometricCipherExceptionCode.keyPermanentlyInvalidated` |
| Phase 4 (Locker library) | Complete | `BiometricExceptionType.keyInvalidated`; provider mapping |
| Phase 5 (Locker library) | Complete | `teardownBiometryPasswordOnly` on `Locker` and `MFALocker` |
| Phase 6 (Unit tests) | Complete | Unit tests for Dart-layer additions from Phases 3–5 |
| Phase 7 (this phase) | Complete | Example app detection and display of biometric key invalidation |
| Phase 8 (password-only disable) | Pending | `disableBiometricPasswordOnlyRequested` event, `_handleBiometricToggle` routing, flag clear on successful enable |
