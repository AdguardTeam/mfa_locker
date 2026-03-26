# QA Plan: AW-2160 Phase 8 — Example App: Password-Only Biometric Disable

Status: REVIEWED
Date: 2026-03-18

---

## Phase Scope

Phase 8 closes the biometric key-invalidation recovery loop established in Phase 7. When `isBiometricKeyInvalidated` is `true`, the user previously saw the "Biometrics changed. Disable and re-enable to use new biometrics." message in Settings and had an enabled toggle, but toggling OFF dispatched `disableBiometricRequested` — a path that internally creates a `BioCipherFunc` and triggers a biometric prompt that always fails on an invalidated key. Phase 8 plugs that gap.

All changes are scoped to the example app (`example/lib/`). No library files under `lib/` or `packages/` are modified.

Specifically, this phase delivers:

1. A new `disableBiometricPasswordOnly({required String password})` method on the `LockerRepository` interface and `LockerRepositoryImpl`, calling `MFALocker.teardownBiometryPasswordOnly` without creating a `BioCipherFunc`.
2. A new `disableBiometricPasswordOnlyRequested({required String password})` Freezed event on `LockerEvent`.
3. Codegen (`make g`) to regenerate `.freezed.dart` after the event change.
4. A new `_onDisableBiometricPasswordOnlyRequested` handler in `LockerBloc` — password-only pattern (no `biometricOperationState` management), sets `loadState: loading`, calls repo, calls `_refreshBiometricState(emit, resetLoadState: true)`, clears `isBiometricKeyInvalidated`, emits success action.
5. Routing in `SettingsScreen._handleBiometricToggle`: when `value == false` and `lockerBloc.state.isBiometricKeyInvalidated == true`, dispatch `disableBiometricPasswordOnlyRequested` instead of `disableBiometricRequested`.
6. Clearing `isBiometricKeyInvalidated` in `_onEnableBiometricRequested` on success, as an idempotent safety measure.

**Phase 7 boundary (prerequisite, complete):** `isBiometricKeyInvalidated` in `LockerState`, `biometricKeyInvalidated()` in `LockerAction`, Settings toggle enabled when invalidated (`_canToggleBiometric`), `_handleBiometricFailure` setting the flag on `keyInvalidated`.

---

## Implementation Status (observed)

All files were read directly from the repository.

### `example/lib/features/locker/data/repositories/locker_repository.dart` — Task 8.1

**Interface** (lines 98–103): `Future<void> disableBiometricPasswordOnly({required String password})` is declared with the correct doc comment: "Use when the biometric key has been permanently invalidated and the normal `disableBiometric` flow (which requires a biometric prompt) cannot succeed." Matches spec.

**Implementation** (lines 372–381): `disableBiometricPasswordOnly` calls `_ensureLockerInstance()`, then `_securityProvider.authenticatePassword(password: password)` to obtain a `PasswordCipherFunc`, then `_locker.teardownBiometryPasswordOnly(passwordCipherFunc: ..., biometricKeyTag: AppConstants.biometricKeyTag)`. No `BioCipherFunc` is created. No `_securityProvider.authenticateBiometric()` call is present. This is the critical correctness property — the method must not trigger a system biometric dialog. Matches spec exactly.

### `example/lib/features/locker/bloc/locker_event.dart` — Task 8.2

`const factory LockerEvent.disableBiometricPasswordOnlyRequested({required String password}) = _DisableBiometricPasswordOnlyRequested` is present at lines 58–61. Doc comment: "Request to disable biometric authentication using password only (key invalidated scenario)." Placed after `disableBiometricRequested`. Matches spec.

### Code generation — Task 8.3

Not directly verifiable from static file content alone, but `locker_bloc.dart` references `_DisableBiometricPasswordOnlyRequested` (the generated private class) directly at lines 43 and 467 without compile errors visible in the file. The definitive gate is `fvm flutter analyze` (MC-1).

### `example/lib/features/locker/bloc/locker_bloc.dart` — Tasks 8.4 and 8.6

**Task 8.4 — Handler registration** (line 43): `on<_DisableBiometricPasswordOnlyRequested>(_onDisableBiometricPasswordOnlyRequested)` is registered in the constructor, positioned between `_onDisableBiometricRequested` and `_onUnlockWithBiometricRequested`. Matches spec.

**Task 8.4 — Handler implementation** (lines 467–494): `_onDisableBiometricPasswordOnlyRequested` follows the password-only pattern:
- Emits `state.copyWith(loadState: LoadState.loading)` immediately (line 471). Correct.
- Calls `_handleVaultOperation` with no `try/finally` wrapper and no `biometricOperationState` management. Correct — this is the password-only pattern, not the biometric operation pattern.
- Inside `operation`: calls `_lockerRepository.disableBiometricPasswordOnly(password: event.password)`, then `_refreshBiometricState(emit, resetLoadState: true)` (which sets `loadState` back to `none`), then guards `!isClosed` before emitting `state.copyWith(isBiometricKeyInvalidated: false)`, then emits `LockerAction.showSuccess(message: 'Biometric authentication disabled')`. Sequence is correct.
- `onDecryptFailed` maps to `_handleDecryptFailure(emit, LockerAction.showError(message: 'Incorrect password: $error'))`. Correct per spec.
- `onError` maps to `_handleGenericFailure(emit, LockerAction.showError(message: 'Failed to disable biometric: $error'))`. Correct per spec.
- `operationDescription` is `'disable biometric (password-only)'`. Correct.

**Critically absent (correct):** No `biometricOperationState` management (`inProgress`/`awaitingResume`), no `try/finally` block wrapping the handler. This ensures the auto-lock timer is not blocked during a password-only operation. Matches NFR.

**Task 8.6 — Clear flag on successful enable** (lines 352–355): Inside `_onEnableBiometricRequested`, within the `_handleVaultOperation.operation` closure, after `await _refreshBiometricState(emit, resetLoadState: true)` and guarded by `if (!isClosed)`, the handler emits `emit(state.copyWith(isBiometricKeyInvalidated: false))`. This is placed before `action(const LockerAction.showSuccess(...))`. Matches spec exactly.

**Verify the `finally` block does not override the cleared flag:** The `finally` block of `_onEnableBiometricRequested` (lines 400–409) emits `state.copyWith(loadState: LoadState.none, biometricOperationState: BiometricOperationState.awaitingResume)`. This `copyWith` does not include `isBiometricKeyInvalidated`, so the cleared value set in the `operation` closure is preserved in subsequent state. Correct.

### `example/lib/features/settings/views/settings_screen.dart` — Task 8.5

**`_handleBiometricToggle`** (lines 127–162): The `else` branch (disable path, `value == false`) now has the routing check at lines 150–156:

```
if (lockerBloc.state.isBiometricKeyInvalidated) {
  lockerBloc.add(
    LockerEvent.disableBiometricPasswordOnlyRequested(password: result!.password!),
  );
  return;
}
```

When `isBiometricKeyInvalidated` is `true`, the new event is dispatched and the method returns early. When `isBiometricKeyInvalidated` is `false`, execution falls through to `lockerBloc.add(LockerEvent.disableBiometricRequested(...))` at lines 158–160. The normal disable path is unchanged. Matches spec. Regression risk: none — the routing check is additive.

**State capture timing:** `lockerBloc.state.isBiometricKeyInvalidated` is read after the `await showModalBottomSheet` call (line 143, which assigns `lockerBloc`). The state is read synchronously from `lockerBloc.state` at line 150, after the async password prompt has completed. This is safe — the flag can only be set to `false` from this same handler's successful completion (or from erase), so reading it after the password prompt cannot produce a false negative.

---

## Positive Scenarios

### PS-1: Password-only disable — correct password, key invalidated

**Setup:** Phase 7 preconditions in place. Vault is unlocked. `isBiometricKeyInvalidated` is `true` (set during a prior biometric attempt). User navigates to Settings. Biometric tile shows error-colored description. Toggle is ON and enabled.

**Steps:**
1. User toggles biometric OFF.
2. `_handleBiometricToggle(false)` is called. Password prompt (modal bottom sheet) is shown.
3. User enters correct password. Sheet dismisses with a valid `AuthenticationResult`.
4. `lockerBloc.state.isBiometricKeyInvalidated` is `true` — routing check passes.
5. `LockerEvent.disableBiometricPasswordOnlyRequested(password: ...)` is dispatched. Method returns early.
6. `_onDisableBiometricPasswordOnlyRequested` emits `loadState: loading`. `LoadingOverlay` appears on screen.
7. `repo.disableBiometricPasswordOnly` is called. `_securityProvider.authenticatePassword` creates `PasswordCipherFunc`. `_locker.teardownBiometryPasswordOnly` removes the `Origin.bio` wrap and attempts key deletion (suppressed errors).
8. No system biometric dialog fires at any point.
9. `_refreshBiometricState(emit, resetLoadState: true)` emits updated `biometricState` and sets `loadState: none`.
10. `emit(state.copyWith(isBiometricKeyInvalidated: false))` clears the flag.
11. `LockerAction.showSuccess(message: 'Biometric authentication disabled')` is emitted. Success snackbar shown.
12. Settings screen rebuilds: subtitle returns to the standard description, toggle is now OFF, no error color, no extra hint text.

**Expected:** Full recovery step one completes. No biometric prompt at any point. `isBiometricKeyInvalidated` is `false` after success.

**Automated:** No. Requires device-level integration test or manual verification.

---

### PS-2: User re-enables biometrics after password-only disable

**Setup:** PS-1 complete. `isBiometricKeyInvalidated` is `false`. Biometric toggle is OFF in Settings.

**Steps:**
1. User toggles biometric ON.
2. `_handleBiometricToggle(true)` dispatches `enableBiometricRequested(password: ...)`.
3. Normal `_onEnableBiometricRequested` flow: password + biometric prompt with new enrollment.
4. `enableBiometric` succeeds. `_refreshBiometricState(emit, resetLoadState: true)` runs.
5. `emit(state.copyWith(isBiometricKeyInvalidated: false))` runs (Phase 8, task 8.6) — idempotent here since the flag is already `false`.
6. `LockerAction.showSuccess(message: 'Biometric authentication enabled')` emitted.

**Expected:** Biometric re-enabled with new enrollment. `isBiometricKeyInvalidated` remains `false`. Settings shows the normal enabled state.

**Automated:** No. Manual verification.

---

### PS-3: Full end-to-end recovery workflow

**Setup:** Physical device or simulator with biometric hardware. Vault initialized with password + biometric. User changes biometric enrollment in device settings.

**Steps:**
1. User returns to app. Vault is locked.
2. User taps biometric button. Biometric prompt fires. `keyPermanentlyInvalidated` is returned by the platform.
3. `isBiometricKeyInvalidated` is set to `true` (Phase 7). Auth sheet shows inline error. Biometric button hidden.
4. User enters password. Vault unlocks.
5. User navigates to Settings. Error description shown in red. Toggle is ON and enabled.
6. User toggles OFF. Password prompt appears.
7. User enters correct password. `disableBiometricPasswordOnlyRequested` is dispatched.
8. `teardownBiometryPasswordOnly` runs. No biometric prompt fires. Success.
9. `isBiometricKeyInvalidated` cleared. Settings returns to normal state (toggle OFF).
10. User toggles ON. New biometric enrollment prompt fires. Succeeds.
11. Biometric unlock works from now on with new enrollment.

**Expected:** Full recovery completes without any failed or unexpected biometric prompts after step 2.

**Automated:** No. Requires real device or simulator end-to-end test.

---

### PS-4: Normal biometric disable — no regression when key is valid

**Setup:** `isBiometricKeyInvalidated` is `false`. Biometrics are enabled and valid.

**Steps:**
1. User navigates to Settings. Normal enabled state shown.
2. User toggles biometric OFF.
3. `_handleBiometricToggle(false)` runs. Password prompt appears.
4. User enters password.
5. `lockerBloc.state.isBiometricKeyInvalidated` is `false` — routing check does NOT trigger.
6. `LockerEvent.disableBiometricRequested(password: ...)` is dispatched (existing path).
7. `_onDisableBiometricRequested` runs: sets `biometricOperationState: inProgress`, biometric prompt fires (the existing normal disable flow).
8. Biometric confirmation succeeds. `teardownBiometry` called. Biometric wrap removed. Toggle goes OFF.

**Expected:** Existing normal disable flow is completely unaffected by Phase 8 changes. `disableBiometricPasswordOnlyRequested` is NOT dispatched.

**Automated:** No. Manual regression check required.

---

### PS-5: `isBiometricKeyInvalidated` cleared on successful biometric re-enable (safety measure)

**Setup:** `isBiometricKeyInvalidated` is `true` (simulated — set manually or via Phase 7 trigger). Biometrics are in an enabled state from the locker's perspective, but the key is known-invalidated. User somehow triggers enable (e.g., after Phase 8 password-only disable, which sets the flag to `false`, but as a safety test: force the flag to `true` then enable).

**Steps:**
1. `isBiometricKeyInvalidated` is `true`.
2. `enableBiometricRequested` is dispatched (either through the toggle flow or programmatically).
3. `_onEnableBiometricRequested` succeeds: `_refreshBiometricState` runs, then `emit(state.copyWith(isBiometricKeyInvalidated: false))` runs.

**Expected:** `isBiometricKeyInvalidated` is `false` in the state after success, regardless of its prior value. Idempotent safety clear works.

**Automated:** No. Code-review verified (line 354 in `locker_bloc.dart`).

---

### PS-6: Loading overlay visible during password-only disable

**Setup:** `isBiometricKeyInvalidated` is `true`. User initiates the password-only disable.

**Steps:**
1. `disableBiometricPasswordOnlyRequested` is dispatched.
2. `emit(state.copyWith(loadState: LoadState.loading))` fires first.
3. `LoadingOverlay(message: 'Processing...')` is rendered (Settings screen line 117: `if (lockerState.loadState == LoadState.loading) const LoadingOverlay(...)`).
4. Operation completes. `_refreshBiometricState(emit, resetLoadState: true)` sets `loadState: none`. Overlay disappears.

**Expected:** Loading overlay visible during the operation, then disappears on completion.

**Automated:** No. Manual visual check.

---

## Negative and Edge Cases

### NC-1: Wrong password during password-only disable — specific error message

**Setup:** `isBiometricKeyInvalidated` is `true`. User toggles biometric OFF, enters wrong password.

**Steps:**
1. `disableBiometricPasswordOnlyRequested` dispatched with incorrect password.
2. `repo.disableBiometricPasswordOnly` calls `_securityProvider.authenticatePassword(password: wrongPassword)`.
3. `_locker.teardownBiometryPasswordOnly` throws `DecryptFailedException` (wrong password unwraps incorrectly).
4. `_handleVaultOperation` catches `DecryptFailedException`, calls `onDecryptFailed`.
5. `_handleDecryptFailure(emit, LockerAction.showError(message: 'Incorrect password: $error'))` runs.
6. `loadState` is reset to `none`. Error snackbar shown.

**Expected:**
- Error message begins with `'Incorrect password: '` — specific, not the generic `'Failed to disable biometric: '`.
- `isBiometricKeyInvalidated` remains `true`.
- Toggle remains ON in Settings (biometric still technically configured from storage perspective — just the session disable attempt failed).
- User can retry.

**Code verified:** `onDecryptFailed` at lines 484–487 in `locker_bloc.dart`.

**Automated:** No. Requires integration test or manual check with wrong password.

---

### NC-2: Generic I/O failure during password-only disable

**Setup:** `isBiometricKeyInvalidated` is `true`. User enters correct password. An unexpected storage I/O error occurs in `teardownBiometryPasswordOnly`.

**Steps:**
1. `disableBiometricPasswordOnlyRequested` dispatched.
2. Repository call throws a generic error (not `DecryptFailedException`).
3. `_handleVaultOperation` catches it in the generic `catch` block, calls `onError`.
4. `_handleGenericFailure(emit, LockerAction.showError(message: 'Failed to disable biometric: $error'))` runs.
5. `loadState` reset. Error shown.

**Expected:**
- Error message begins with `'Failed to disable biometric: '`.
- `isBiometricKeyInvalidated` remains `true`. User can retry.
- No crash. No state corruption.

**Code verified:** `onError` at lines 488–491 in `locker_bloc.dart`.

**Automated:** No. Requires simulated I/O failure or manual injection.

---

### NC-3: No biometric prompt fires during password-only disable

**Verification focus:** `LockerRepositoryImpl.disableBiometricPasswordOnly` (lines 372–381) must never call `_securityProvider.authenticateBiometric()` and must never call `_locker.teardownBiometry` (the version that requires a `BioCipherFunc`).

**Code verified:**
- Only `_securityProvider.authenticatePassword` is called (line 375).
- `_locker.teardownBiometryPasswordOnly` is called (line 377) — not `_locker.teardownBiometry`.
- No `BioCipherFunc` variable is created or used in this method.
- The BLoC handler has no `biometricOperationState` management (no `inProgress`/`awaitingResume` emits), confirming the design intent is respected end-to-end.

**Risk:** None — code matches spec. However, this is the most critical correctness property of Phase 8 and warrants confirmation by running the full flow on a device with an invalidated key.

**Automated:** No. Must be manually confirmed on device.

---

### NC-4: `disableBiometricRequested` still routed correctly when `isBiometricKeyInvalidated` is `false`

**Concern:** The Phase 8 routing check must be additive — it must not break the existing normal disable path.

**Code verified:** `_handleBiometricToggle` lines 150–160. The `if (lockerBloc.state.isBiometricKeyInvalidated)` block `return`s early only when the flag is `true`. When `false`, execution proceeds to the original `lockerBloc.add(LockerEvent.disableBiometricRequested(...))` at lines 158–160. No change to the existing dispatch.

**Automated:** No. Manual regression check (PS-4 above).

---

### NC-5: `_refreshBiometricState` failure does not block `isBiometricKeyInvalidated: false` emit

**Concern:** If `_refreshBiometricState` internally threw an exception, the `isBiometricKeyInvalidated: false` emit that follows it would be skipped, leaving the flag stale.

**Analysis:** `_refreshBiometricState` delegates to `_determineBiometricStateAndEmit` (line 1043 in `locker_bloc.dart`). That method wraps its body in a `try/catch` (lines 1013–1037) and never rethrows — on error it only logs and optionally resets `loadState`. It always returns normally. Therefore, the `emit(state.copyWith(isBiometricKeyInvalidated: false))` at line 479 will always execute after `_refreshBiometricState` returns, regardless of whether `determineBiometricState` internally fails.

**Risk:** None. Confirmed by reading `_determineBiometricStateAndEmit` implementation.

---

### NC-6: `_onEnableBiometricRequested` `finally` block does not override the cleared flag

**Concern:** If the `finally` block of `_onEnableBiometricRequested` emitted a `copyWith` that included `isBiometricKeyInvalidated: true` or reset it to the old value, the task 8.6 safety clear would be undone.

**Code verified:** The `finally` block (lines 400–409) emits `state.copyWith(loadState: LoadState.none, biometricOperationState: BiometricOperationState.awaitingResume)`. Only `loadState` and `biometricOperationState` are set — `isBiometricKeyInvalidated` is not touched. The cleared value from the `operation` closure is preserved.

**Risk:** None.

---

### NC-7: BLoC is closed before `isBiometricKeyInvalidated: false` emit — guard correct

**Concern:** If the BLoC is closed while the password-only disable operation is in progress (e.g., the user navigates away and the widget tree disposes the BLoC), the `emit(state.copyWith(isBiometricKeyInvalidated: false))` call would throw.

**Code verified:** Line 478: `if (!isClosed) { emit(state.copyWith(isBiometricKeyInvalidated: false)); }`. The guard is present. Matches the pattern used throughout the BLoC.

**Risk:** None.

---

### NC-8: `disableBiometricPasswordOnlyRequested` event does not manage `biometricOperationState`

**Concern:** If `biometricOperationState` were set to `inProgress` during the password-only disable, the auto-lock timer would be blocked, and the `_onLockRequested` handler (line 252: `if (state.biometricOperationState != BiometricOperationState.idle) return`) would silently swallow lock requests during the operation.

**Code verified:** `_onDisableBiometricPasswordOnlyRequested` (lines 467–494) contains no reference to `BiometricOperationState`. No `inProgress`, no `awaitingResume`, no `try/finally` wrapping the handler. The handler begins with `emit(state.copyWith(loadState: LoadState.loading))` only. The auto-lock timer is not blocked.

**Contrast with `_onDisableBiometricRequested`:** That handler explicitly wraps its body in a `try/finally` with `biometricOperationState: inProgress` and `biometricOperationState: awaitingResume`. The password-only handler deliberately omits this. Correct.

**Risk:** None — code matches spec.

---

### NC-9: Password-only disable event not accessible when `isBiometricKeyInvalidated` is `false` via normal UI

**Concern:** A user should not be able to dispatch `disableBiometricPasswordOnlyRequested` through the normal Settings UI when the key is valid (i.e., the event should only be reachable via the routing check).

**Code verified:** The only UI dispatch site is `_handleBiometricToggle` in `settings_screen.dart` line 152. The dispatch is behind `if (lockerBloc.state.isBiometricKeyInvalidated)`. When the flag is `false`, this branch is never reached from normal UI interaction. An adversarial caller could dispatch the event directly, but the operation itself is safe — it calls `teardownBiometryPasswordOnly` which only removes the bio wrap, leaving the password wrap intact, so the vault remains accessible.

**Risk:** None.

---

### NC-10: State capture timing — `isBiometricKeyInvalidated` read after async password prompt

**Concern:** `lockerBloc.state.isBiometricKeyInvalidated` is read at line 150, after `await showModalBottomSheet` (line 128). If the flag could change from `true` to `false` between showing the password prompt and reading the flag, the wrong event would be dispatched.

**Analysis:** `isBiometricKeyInvalidated` can only transition `true → false` via: (1) successful `disableBiometricPasswordOnlyRequested` completion, (2) successful `enableBiometricRequested` completion, or (3) storage erase. None of these can happen while the password bottom sheet is open (no concurrent BLoC events can complete this operation during `showModalBottomSheet`). The only direction that could cause a missed routing is `false → true`, which would be the flag being set during the sheet interaction — this would mean an independent biometric operation ran concurrently, which cannot happen because the Settings screen password prompt blocks the UI. The state read is safe.

**Risk:** Very low. Accepted per PRD.

---

### NC-11: `disableBiometricPasswordOnly` called before locker is initialized

**Setup:** Edge case — `disableBiometricPasswordOnly` called when `_mfaLocker` is `null`.

**Code verified:** Line 374: `await _ensureLockerInstance()` is the first call. If the locker is not initialized, `_ensureLockerInstance` creates it. This is the same pattern used by all other repository methods. If `_mfaLocker` creation itself fails (e.g., storage file inaccessible), the error propagates as a generic exception, is caught by `_handleVaultOperation.onError`, and the user sees `'Failed to disable biometric: ...'`. No crash.

**Risk:** None.

---

### NC-12: Phase 7 reservation resolved — `_handleBiometricToggle` no longer routes to `disableBiometricRequested` when key is invalidated

Phase 7 QA (NC-2) noted that the Settings toggle dispatched `disableBiometricRequested` unconditionally for the `value == false` path, even when `isBiometricKeyInvalidated` was `true`. This was the documented Phase 7 limitation and the primary motivation for Phase 8.

**Code verified:** Lines 150–156 of `settings_screen.dart` now contain the routing check. The Phase 7 reservation is fully resolved by this change.

---

## Automated Tests Coverage

Phase 8 adds no new automated unit or widget tests. All changes are in the example app layer (`example/lib/`), which has no test suite in this repository. Implementation is verified by:

- Code review of all five task files, read directly from the repository.
- Static analysis: `cd example && fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .`
- Format check: `cd example && fvm dart format . --line-length 120`
- Root library test suite: `fvm flutter test` from the project root, confirming no library regressions (Phase 8 does not touch any library file).

### Coverage gaps

| Scenario | Gap type |
|----------|----------|
| PS-1: Password-only disable — correct password | No automated BLoC integration test |
| PS-2: Re-enable after password-only disable | No automated test |
| PS-3: Full end-to-end recovery | No automated test — requires real device |
| PS-4: Normal disable regression | No automated regression test |
| NC-1: Wrong password error message specificity | No automated BLoC integration test |
| NC-2: Generic failure error message | No automated test |
| NC-3: No biometric prompt fires (verified by code review) | No runtime assertion or test |
| NC-8: `biometricOperationState` not managed | No automated test; code review only |
| Loading overlay visibility during operation | No widget test |

These gaps are inherent to the example app's test structure and are not regressions introduced by Phase 8. The library-level tests from Phases 1–6 continue to cover `teardownBiometryPasswordOnly` and the underlying exception propagation chain.

---

## Manual Checks Needed

### MC-1: Static analysis — example app

**Command:**
```
cd example && fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .
```

**Pass criterion:** Exits with code 0.

This validates:
- Freezed-generated code is consistent with the new `disableBiometricPasswordOnlyRequested` event.
- `_DisableBiometricPasswordOnlyRequested` generated class is referenced correctly in `locker_bloc.dart`.
- All five modified files compile without errors, warnings, or infos.
- Line length 120, single quotes, trailing commas satisfied throughout.

---

### MC-2: Format check — example app

**Command:**
```
cd example && fvm dart format . --line-length 120
```

**Pass criterion:** No output (no diffs).

---

### MC-3: Root library test suite — no regressions

**Command:**
```
fvm flutter test
```

**Pass criterion:** All tests pass. Count should remain at the Phase 6 total (146+).

Phase 8 does not change any library file, so no library test should fail. This check is a safeguard against accidental changes.

---

### MC-4: Device/simulator — password-only disable end-to-end

**Prerequisite:** Device or simulator that supports biometric enrollment changes (Android emulator with fingerprint simulation, iOS Simulator with Touch ID). A vault with biometric wrap established and `isBiometricKeyInvalidated` triggered via Phase 7 detection.

**Procedure:**
1. Install the example app. Initialize vault with password + biometric unlock.
2. Simulate a biometric enrollment change (Android: add/remove fingerprint in device settings; iOS Simulator: `Device > Touch ID`).
3. Return to app. Vault should be locked.
4. Tap biometric button. System prompt fires. `keyPermanentlyInvalidated` is returned.
5. Auth sheet shows `'Biometrics have changed. Please use your password.'`. Biometric button hidden.
6. Enter password. Vault unlocks. Navigate to Settings.
7. Biometric tile shows error-colored description. Toggle is ON and enabled.
8. Toggle biometric OFF. Password prompt appears.
9. Enter correct password. Expected: NO system biometric prompt fires.
10. Expected: Success snackbar `'Biometric authentication disabled'` appears.
11. Expected: Settings biometric tile shows normal (non-error) description. Toggle is OFF.
12. Expected: `isBiometricKeyInvalidated` is `false` (verified by observing UI — no error color).
13. Toggle biometric ON. Enter password. System biometric prompt fires with new enrollment.
14. Expected: Biometric re-enabled successfully.
15. Lock vault. Attempt biometric unlock. Expected: Succeeds with new enrollment.

**Pass criterion:** All expected outcomes in steps 9–15 match observed behavior. Specifically: no biometric prompt fires in step 9; error state cleared in steps 10–12; fresh biometric works in steps 14–15.

**Status:** Not executed. Required before AW-2160 final release.

---

### MC-5: Wrong password during password-only disable

**Procedure:**
1. With `isBiometricKeyInvalidated` set to `true` (from MC-4 step 4), navigate to Settings.
2. Toggle biometric OFF. Password prompt appears.
3. Enter an incorrect password.
4. Expected: Error snackbar begins with `'Incorrect password: '` (not `'Failed to disable biometric: '`).
5. Expected: Loading overlay disappears. Settings still shows error-colored description and enabled toggle.
6. Expected: No biometric prompt fires.
7. Retry with correct password. Expected: Disable succeeds as in MC-4.

**Pass criterion:** Specific error message displayed; `isBiometricKeyInvalidated` remains `true` after wrong password; user can retry.

**Status:** Not executed. Manual check required.

---

### MC-6: Normal disable regression — no biometric routing change when key is valid

**Procedure:**
1. Fresh vault with biometrics enabled and valid (no `keyPermanentlyInvalidated` error triggered).
2. Navigate to Settings. Biometric tile shows normal enabled state.
3. Toggle biometric OFF. Password prompt appears.
4. Enter correct password.
5. Expected: System biometric prompt fires (standard disable flow using `_onDisableBiometricRequested`).
6. Confirm biometric. Expected: Biometric disabled. Toggle goes OFF. Normal success snackbar.

**Pass criterion:** Standard disable flow is completely unchanged. `disableBiometricPasswordOnlyRequested` is never dispatched in this flow.

**Status:** Not executed. Manual regression check required.

---

### MC-7: Re-enable after password-only disable clears flag on success

**Procedure (continuation of MC-4 steps 10–15):**
1. After successful password-only disable, `isBiometricKeyInvalidated` is confirmed `false` (step 12 of MC-4).
2. Toggle biometric ON. Normal enable flow: password + biometric prompt.
3. Enable succeeds.
4. Verify `emit(state.copyWith(isBiometricKeyInvalidated: false))` from task 8.6 runs (idempotent — flag already `false`, but the emit should not cause any observable issue).
5. Expected: Settings shows normal enabled state, no error color, no error description.

**Pass criterion:** Enable succeeds cleanly. No stale invalidation state visible.

**Status:** Not executed. Manual check required.

---

### MC-8: Loading overlay during password-only disable

**Procedure:**
1. `isBiometricKeyInvalidated` is `true`. Toggle biometric OFF, enter correct password.
2. Observe the Settings screen immediately after password submission.
3. Expected: `LoadingOverlay(message: 'Processing...')` is visible while the operation runs.
4. After success: overlay disappears, success snackbar appears.

**Pass criterion:** Loading overlay is visible during the async operation and disappears on completion.

**Status:** Not executed. Manual visual check required. (Operation may be fast enough that the overlay is only briefly visible.)

---

## Risk Zone

| Risk | Severity | Status |
|------|----------|--------|
| `disableBiometricPasswordOnly` accidentally creating a `BioCipherFunc` — would trigger a biometric prompt on an invalidated key, defeating the purpose of Phase 8 | Critical | Verified absent by code review of `LockerRepositoryImpl.disableBiometricPasswordOnly` (lines 372–381). No `authenticateBiometric()` call. Must be confirmed by device test (MC-4 step 9). |
| `_onDisableBiometricPasswordOnlyRequested` accidentally managing `biometricOperationState` — would block auto-lock during password-only operation | High | Verified absent by code review (lines 467–494 have no `BiometricOperationState` references). |
| End-to-end device test not yet performed for Phase 8 (and all prior phases) | High | The full AW-2160 pipeline has never been exercised on a real device. MC-4 is mandatory before production release. |
| `_refreshBiometricState` failing silently and leaving `isBiometricKeyInvalidated: false` emit unreachable | Low | Confirmed safe: `_determineBiometricStateAndEmit` never rethrows; `isBiometricKeyInvalidated: false` emit always executes (NC-5). |
| `finally` block in `_onEnableBiometricRequested` overriding the task 8.6 flag clear | Low | Confirmed safe: `finally` block does not include `isBiometricKeyInvalidated` in its `copyWith` (NC-6). |
| Codegen (`make g`) not run after task 8.2 — stale `.freezed.dart` would fail analysis | Low | MC-1 (static analysis) is the definitive gate. If the `.freezed.dart` is stale, analyze exits non-zero. |
| State timing: `isBiometricKeyInvalidated` read after async password prompt could be stale | Very Low | Analyzed in NC-10. The flag can only transition `true → false` by completing the very operation being set up. No realistic concurrent path. Accepted. |
| No automated tests for the example app | Medium | Inherent to the example app's test structure. All Phase 8 behavior is verified by code review and manual checks. Regressions in the example app will not be caught by CI. |
| `biometricKeyInvalidated` flag persists in-session after Phase 8 password-only disable only if the handler fails before the flag-clear emit | Low | `_handleVaultOperation` resets `loadState` on all error paths. The flag-clear emit is only in the success path — correct by design. On failure, the flag stays `true` and the user can retry. |

---

## Final Verdict

**Release with reservations.**

All five Phase 8 implementation tasks are correctly implemented in the observed code. The critical correctness property — that `disableBiometricPasswordOnly` calls `teardownBiometryPasswordOnly` without creating a `BioCipherFunc` — is verified by code review. The routing check in `_handleBiometricToggle`, the new BLoC handler, the event definition, the flag-clear on both the password-only disable and the re-enable success paths, and the absence of `biometricOperationState` management in the new handler all match the specification exactly.

Phase 7 QA reservation NC-2 (the toggle routing the invalid key disable to the wrong event) is fully resolved by Phase 8.

**Reservations:**

1. **No end-to-end device test has been executed for Phase 8 (or any prior phase of AW-2160).** The full pipeline from native `keyPermanentlyInvalidated`, through Dart layers, to the password-only disable in the example app has never been exercised on a real device or simulator. MC-4 (device/simulator end-to-end) and MC-5 (wrong password on device) are mandatory before the complete AW-2160 feature reaches production. Code review can confirm structural correctness but cannot confirm that `teardownBiometryPasswordOnly` actually suppresses the biometric prompt at the platform layer.

2. **No automated tests for the example app.** All Phase 8 behavior is verified by code review alone. Any regression in `LockerRepository`, `LockerBloc`, or `SettingsScreen` will not be caught by the CI test suite.

3. **The full AW-2160 recovery UX is now code-complete with Phase 8, but has not been smoke-tested end-to-end across all eight phases on a single device.** Before communicating the feature as production-ready, a single continuous test run covering Phases 1–8 (native exception → Dart mapping → library → example app detection → password-only disable → re-enable) must be executed.

Phase 8 is safe to merge as a phase. It resolves the last known UX gap in the biometric key invalidation recovery flow and introduces no library changes or breaking modifications. The reservations above are preconditions for the full AW-2160 production release, not blockers for this phase in isolation.
