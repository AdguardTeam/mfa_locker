# AW-2160-8: Example App — Password-Only Biometric Disable

Status: PRD_READY

## Context / Idea

This is Phase 8 of AW-2160. The ticket as a whole adds biometric key invalidation detection and a password-only teardown path across the full stack.

**Phases 1–7 status (all complete):**
- Phase 1: Android native emits `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")` for `KeyPermanentlyInvalidatedException`.
- Phase 2: iOS/macOS native emits `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")` when the Secure Enclave key is inaccessible after a biometric enrollment change.
- Phase 3: Dart plugin maps `'KEY_PERMANENTLY_INVALIDATED'` → `BiometricCipherExceptionCode.keyPermanentlyInvalidated`.
- Phase 4: Locker library maps `BiometricCipherExceptionCode.keyPermanentlyInvalidated` → `BiometricExceptionType.keyInvalidated`.
- Phase 5: `MFALocker.teardownBiometryPasswordOnly` is complete — removes the `Origin.bio` wrap using password auth only, with suppressed key deletion errors.
- Phase 6: Unit tests for all new Dart-layer code paths are complete.
- Phase 7: Example app detects `keyInvalidated` at runtime: `isBiometricKeyInvalidated` flag in `LockerState`, `biometricKeyInvalidated()` action in `LockerAction`, inline error in the auth sheet, biometric button hidden, Settings tile description in error color, toggle enabled when invalidated, `SettingsBloc` `keyInvalidated` case, flag cleared on erase.

**The problem this phase solves:** Phase 7 wires detection and display of key invalidation. The user now sees the "Biometrics changed. Disable and re-enable to use new biometrics." message in Settings and has an enabled toggle — but toggling OFF still dispatches `disableBiometricRequested`, which calls `teardownBiometry` with a live `BioCipherFunc`. This triggers a biometric prompt that will always fail on an invalidated key. The recovery loop is incomplete. Phase 8 closes the loop: when the user toggles biometric OFF while `isBiometricKeyInvalidated == true`, the app must dispatch a new `disableBiometricPasswordOnlyRequested` event, the repository calls `MFALocker.teardownBiometryPasswordOnly` (password auth, no biometric prompt), and on success the `isBiometricKeyInvalidated` flag is cleared. Additionally, a successful biometric re-enable (which follows the disable) must also clear the flag.

**Scope:** Example app only — `example/lib/` files. Five tasks across the repository layer (1), BLoC event (1), BLoC logic (2), and the Settings screen (1). One code-generation step (`make g`) is required after the Freezed event change.

**Dependencies from prior phases:**
- `isBiometricKeyInvalidated: bool` field in `LockerState` — Phase 7, task 7.1
- `biometricKeyInvalidated()` action in `LockerAction` — Phase 7, task 7.2
- Settings biometric toggle enabled when invalidated (`_canToggleBiometric`) — Phase 7, task 7.7
- `MFALocker.teardownBiometryPasswordOnly` — Phase 5

---

## Goals

1. Add `disableBiometricPasswordOnly({required String password})` to the `LockerRepository` interface and `LockerRepositoryImpl` — calls `teardownBiometryPasswordOnly` without creating a `BioCipherFunc`.
2. Add `disableBiometricPasswordOnlyRequested({required String password})` Freezed event to `LockerEvent`.
3. Run `make g` after tasks 8.1 and 8.2 to regenerate `.freezed.dart` files.
4. Register and implement `_onDisableBiometricPasswordOnlyRequested` in `LockerBloc`: set `loadState: loading`, call repo, call `_refreshBiometricState`, clear `isBiometricKeyInvalidated`, emit success action. No `biometricOperationState` management (no system dialog).
5. Update `SettingsScreen._handleBiometricToggle` to route to `disableBiometricPasswordOnlyRequested` (not `disableBiometricRequested`) when `value == false` and `lockerBloc.state.isBiometricKeyInvalidated == true`.
6. Clear `isBiometricKeyInvalidated` in `_onEnableBiometricRequested` after a successful enable + `_refreshBiometricState`, so that the flag does not persist after the user re-enrolls biometrics.

---

## User Stories

**US-1 — User can disable invalidated biometrics without being prompted for biometric**
As a user whose biometric key has been permanently invalidated, when I toggle biometrics OFF in Settings, I need the app to disable biometrics using only my password — without triggering a biometric prompt that would immediately fail — so that the recovery flow completes successfully.

**US-2 — After password-only disable, the invalidation state is resolved**
As a user who has completed the password-only disable, I need the `isBiometricKeyInvalidated` flag to be cleared and the biometric state to be refreshed, so that the Settings screen returns to its normal non-error state and I can re-enable biometrics.

**US-3 — Re-enabling biometrics after invalidation clears the stale flag**
As a user who has disabled biometrics via password-only and then re-enables them with the new enrollment, I need the `isBiometricKeyInvalidated` flag to be cleared on successful enable, so that no stale invalidation knowledge persists in the session after recovery is complete.

**US-4 — Wrong password during password-only disable gives a specific error**
As a user who enters the wrong password during the password-only disable flow, I need a specific error ("Incorrect password") rather than a generic failure, so that I understand what went wrong and can retry with the correct password.

---

## Main Scenarios

### Scenario 1: Full recovery — user disables and re-enables biometrics after invalidation

1. Phase 7 is complete: `isBiometricKeyInvalidated` is `true` (set when biometric prompt failed with `keyInvalidated`). Settings screen shows error description and enabled toggle.
2. User toggles biometric OFF. `_handleBiometricToggle` is called with `value == false`.
3. Because `lockerBloc.state.isBiometricKeyInvalidated == true`, the password prompt is shown (same prompt as normal disable).
4. User enters password. `_handleBiometricToggle` dispatches `LockerEvent.disableBiometricPasswordOnlyRequested(password: result!.password!)` instead of `disableBiometricRequested`. Returns early.
5. `LockerBloc._onDisableBiometricPasswordOnlyRequested` emits `state.copyWith(loadState: LoadState.loading)`.
6. `_lockerRepository.disableBiometricPasswordOnly(password: event.password)` is called.
7. Repository calls `_securityProvider.authenticatePassword` → `_locker.teardownBiometryPasswordOnly(passwordCipherFunc: ..., biometricKeyTag: AppConstants.biometricKeyTag)`. No biometric prompt fires.
8. On success: `_refreshBiometricState(emit, resetLoadState: true)` is called. `loadState` returns to `idle`.
9. BLoC emits `state.copyWith(isBiometricKeyInvalidated: false)`.
10. BLoC emits `LockerAction.showSuccess(message: 'Biometric authentication disabled')`.
11. Settings screen rebuilds: error description gone, normal state shown, toggle is now OFF.
12. User toggles biometric ON. Normal `enableBiometricRequested` flow fires (password + biometric prompt with new enrollment).
13. On successful enable + `_refreshBiometricState`: BLoC emits `state.copyWith(isBiometricKeyInvalidated: false)`.
14. Biometric is fully re-enabled with new enrollment. No stale state.

### Scenario 2: Wrong password during password-only disable

1. `isBiometricKeyInvalidated` is `true`. User toggles biometric OFF, enters wrong password.
2. `_onDisableBiometricPasswordOnlyRequested` runs.
3. Repository `disableBiometricPasswordOnly` throws `DecryptFailedException` (wrong password).
4. `_handleVaultOperation.onDecryptFailed` triggers `_handleDecryptFailure(emit, LockerAction.showError(message: 'Incorrect password: $error'))`.
5. `loadState` is reset. Error toast/snackbar is shown.
6. `isBiometricKeyInvalidated` remains `true`. User can retry.

### Scenario 3: Generic error during password-only disable

1. `isBiometricKeyInvalidated` is `true`. User toggles biometric OFF, enters correct password.
2. An unexpected error occurs (e.g., storage I/O failure) in `teardownBiometryPasswordOnly`.
3. `_handleVaultOperation.onError` triggers `_handleGenericFailure(emit, LockerAction.showError(message: 'Failed to disable biometric: $error'))`.
4. `loadState` is reset. Error is shown.
5. `isBiometricKeyInvalidated` remains `true`. User can retry.

### Scenario 4: Normal disable flow is NOT affected (no regression)

1. `isBiometricKeyInvalidated` is `false`. User toggles biometric OFF in Settings.
2. `_handleBiometricToggle` is called with `value == false`.
3. `lockerBloc.state.isBiometricKeyInvalidated` is `false` — the routing condition is not met.
4. The existing `disableBiometricRequested` event is dispatched as before. No change in behavior.

### Scenario 5: Successful biometric re-enable clears the flag

1. User has completed password-only disable (Scenario 1 steps 1–11). `isBiometricKeyInvalidated` is `false`.
2. User toggles biometric ON. Normal `enableBiometricRequested` flow fires.
3. On success, after `_refreshBiometricState`: `emit(state.copyWith(isBiometricKeyInvalidated: false))`.
4. Flag confirmed cleared. Even if the flag was somehow still `true`, this emit ensures cleanup.

---

## Success / Metrics

| Criterion | How to verify |
|-----------|--------------|
| `disableBiometricPasswordOnly` added to `LockerRepository` interface | Code review |
| `LockerRepositoryImpl.disableBiometricPasswordOnly` calls `teardownBiometryPasswordOnly` without creating `BioCipherFunc` | Code review |
| `disableBiometricPasswordOnlyRequested` Freezed event added to `LockerEvent` | Code review / Freezed codegen |
| `make g` produces updated `.freezed.dart` without errors | `cd example && make g` |
| `_onDisableBiometricPasswordOnlyRequested` handler registered in `LockerBloc` constructor | Code review |
| Handler emits `loadState: loading` before operation | Code review |
| Handler clears `isBiometricKeyInvalidated` on success | Code review |
| Handler calls `_refreshBiometricState(emit, resetLoadState: true)` — no manual `loadState` reset needed | Code review |
| Handler does NOT manage `biometricOperationState` | Code review |
| Wrong password emits `showError('Incorrect password: ...')` via `onDecryptFailed` | Code review |
| Generic failure emits `showError('Failed to disable biometric: ...')` via `onError` | Code review |
| `SettingsScreen._handleBiometricToggle` routes to `disableBiometricPasswordOnlyRequested` when `value == false && isBiometricKeyInvalidated == true` | Code review |
| `SettingsScreen._handleBiometricToggle` still routes to `disableBiometricRequested` when `isBiometricKeyInvalidated == false` (no regression) | Code review |
| `_onEnableBiometricRequested` clears `isBiometricKeyInvalidated` after successful enable + `_refreshBiometricState` | Code review |
| `cd example && fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` exits 0 | CI / local run |
| `cd example && fvm dart format . --line-length 120` produces no diffs | CI / local run |

---

## Constraints and Assumptions

- **Example app only.** No changes to library files under `lib/` or `packages/`. All five tasks (8.1–8.6, excluding 8.3 which is codegen) touch only `example/lib/` files.
- **Phase 7 must be complete.** This phase depends on `isBiometricKeyInvalidated` in `LockerState` (task 7.1), `biometricKeyInvalidated()` in `LockerAction` (task 7.2), the Settings toggle being enabled when invalidated (task 7.7 `_canToggleBiometric`), and `MFALocker.teardownBiometryPasswordOnly` (Phase 5).
- **No `biometricOperationState` management.** The password-only disable does not show a system biometric dialog. Do not wrap the operation in `biometricOperationState` management — follow the pattern of password-only operations (e.g., `_onDisableBiometricRequested` minus the bio parts, or closer to `_onUnlockPasswordSubmitted`).
- **`_refreshBiometricState(emit, resetLoadState: true)` resets `loadState` to idle.** Do not manually reset `loadState` after the `operation` closure — the flag `resetLoadState: true` handles it.
- **Password prompt in `_handleBiometricToggle` is reused.** The existing password prompt (used for normal disable) is already present. The routing change (dispatch new event vs. old event) is the only UI-side modification. No new dialog or screen is introduced.
- **`isBiometricKeyInvalidated: false` emit in `_onEnableBiometricRequested` is idempotent.** After a successful password-only disable (which already clears the flag), the flag will typically be `false` when `enableBiometricRequested` runs. The emit is still required as a safety measure to ensure the flag is cleared even if the session had unusual state.
- **Code generation required.** Task 8.2 modifies a Freezed model (`LockerEvent`). Task 8.3 (`make g`) must run after 8.2 and before 8.4 (which references the generated `_DisableBiometricPasswordOnlyRequested` class).
- **Task ordering constraints:** 8.1 and 8.2 are parallel. 8.3 must follow both. 8.4 must follow 8.3. 8.5 and 8.6 are independent of each other and can follow 8.4.
- **Dart code style applies.** Line length 120, single quotes, trailing commas on multi-line constructs.
- **`_handleVaultOperation` pattern is the standard wrapper.** Follow the exact same pattern used by `_onDisableBiometricRequested` minus the biometric cipher creation.
- **No new UI elements.** This phase adds no new screens, dialogs, or widgets. All changes are in BLoC, repository, and event routing.

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| `_refreshBiometricState` signature does not accept `resetLoadState` named parameter in current codebase | Low — referenced in phase-8.md implementation notes and used in Phase 7 | High — handler would need manual `loadState` reset | Read `_refreshBiometricState` signature before implementing task 8.4; confirm parameter name. |
| `_handleVaultOperation` helper has a different signature or name in the current codebase | Low — referenced consistently in idea-2160.md and phase-8.md | Medium — handler implementation requires adjustment | Read `_handleVaultOperation` definition before task 8.4. |
| `_handleBiometricToggle` in Settings screen does not have access to `lockerBloc.state` at the point of the routing check | Low — standard Flutter BLoC access pattern | Medium — routing check may need to capture state before async password prompt | Confirm state access pattern in `_handleBiometricToggle` before task 8.5; use `lockerBloc.state` (synchronous read of current state). |
| `_onEnableBiometricRequested` does not currently call `_refreshBiometricState` | Low — biometric enable is a complete flow that should refresh state | Medium — flag clear emit would be placed after wrong point | Read `_onEnableBiometricRequested` before task 8.6 to confirm the correct insertion point. |
| Password prompt in `_handleBiometricToggle` is triggered before `isBiometricKeyInvalidated` is read | Possible — prompt is async; state could change | Low — state flip from `true` to `false` mid-toggle is not a realistic scenario (only cleared on success of this very operation) | Accepted. Capture `isBiometricKeyInvalidated` before launching the prompt if needed. |
| Codegen (`make g`) fails after 8.2 changes | Low — standard Freezed pattern | Medium — blocks 8.4 | Run `make g` immediately after 8.2; confirm before proceeding. |

---

## Open Questions

None.
