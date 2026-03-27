# QA Plan: AW-2160 Phase 7 — Example App: Detect and Display Biometric Key Invalidation

Status: REVIEWED
Date: 2026-03-17

---

## Phase Scope

Phase 7 wires the example app (`example/lib/`) to detect `BiometricExceptionType.keyInvalidated` at runtime and respond with clear UI feedback. No library-layer changes. Nine tasks across eight files plus one code-generation step.

Specifically, this phase delivers:

1. A new `isBiometricKeyInvalidated` runtime flag on `LockerState` (in-memory, resets on cold launch).
2. A new `biometricKeyInvalidated()` factory on `LockerAction`, distinct from `biometricAuthenticationFailed`.
3. Separation of `keyInvalidated` from the `failure` case in `LockerBloc._handleBiometricFailure` — sets the flag, emits the dedicated action, resets to idle, returns early.
4. Mapping of `biometricKeyInvalidated` action to `BiometricFailed('Biometrics have changed. Please use your password.')` in `LockerBlocBiometricStream`.
5. Hiding the biometric unlock button on the locked screen and in `BiometricUnlockButton` when the flag is set.
6. Informational error-colored description in Settings when the flag is set; biometric tile toggle remains enabled.
7. Specific `keyInvalidated` error message in `SettingsBloc._onAutoLockTimeoutSelectedWithBiometric`.
8. Clearing `isBiometricKeyInvalidated` on successful erase.

**Phase 8 boundary (not in scope):** `disableBiometricPasswordOnlyRequested` event, `_handleBiometricToggle` routing to password-only event, clearing the flag on successful `enableBiometric`.

---

## Implementation Status (observed)

All files were read directly from the repository.

### `example/lib/features/locker/bloc/locker_state.dart` — Task 7.1

`@Default(false) bool isBiometricKeyInvalidated` is present at line 14, placed after `enableBiometricAfterInit`. The field uses the correct `@Default(false)` annotation. Matches spec.

### `example/lib/features/locker/bloc/locker_action.dart` — Task 7.2

`const factory LockerAction.biometricKeyInvalidated() = BiometricKeyInvalidatedAction` is present at line 31, with the correct doc comment. Placed after `biometricNotAvailable`. Matches spec.

### Code generation — Task 7.3

Not directly verifiable from static files, but downstream code compiles (tasks 7.4–7.9 reference the generated factory and field). Analysis exit code is the definitive confirmation.

### `example/lib/features/locker/bloc/locker_bloc.dart` — Tasks 7.4 and 7.9

**Task 7.4** (`_handleBiometricFailure`): At lines 1082–1091, `BiometricExceptionType.keyInvalidated` has its own case. It emits `state.copyWith(isBiometricKeyInvalidated: true)`, calls `action(const LockerAction.biometricKeyInvalidated())`, adds `biometricOperationStateChanged(idle)`, and returns early. The `BiometricExceptionType.failure` case at line 1093 retains its original behavior (`_determineBiometricStateAndEmit`). The `keyInvalidated` case does NOT fall through to `biometricAuthenticationFailed`. Matches spec exactly.

**Task 7.9** (`_onEraseStorageRequested`): At line 891, `isBiometricKeyInvalidated: false` is included in the `state.copyWith(...)` call in the success path, alongside the other reset fields (`status`, `entries`, `loadState`). Matches spec.

### `example/lib/features/locker/views/widgets/locker_bloc_biometric_stream.dart` — Task 7.5

The `mapOrNull` call at lines 8–15 includes `biometricKeyInvalidated: (_) => const BiometricFailed('Biometrics have changed. Please use your password.')`. Copy matches the PRD-approved string exactly. Matches spec.

### `example/lib/features/locker/views/auth/locked_screen.dart` — Task 7.6

**`buildWhen`** (lines 20–23): Includes `previous.isBiometricKeyInvalidated != current.isBiometricKeyInvalidated`. Matches spec.

**`showBiometricButton` local variable** (line 68): `state.biometricState.isEnabled && !state.isBiometricKeyInvalidated`. Matches spec.

**Button label** (lines 52–54): Uses the same `state.biometricState.isEnabled && !state.isBiometricKeyInvalidated` condition to choose between `'Unlock Storage'` and `'Unlock with Password'`. This is functionally equivalent to the spec intent.

**`onBiometricPressed` guard** (lines 79–81): `onBiometricPressed: showBiometric ? () => bloc.add(...) : null`. Correctly gates on `showBiometric` (the same boolean). Matches spec.

### `example/lib/features/locker/views/widgets/biometric_unlock_button.dart` — Task 7.7

**`buildWhen`** (lines 10–13): Includes `previous.isBiometricKeyInvalidated != current.isBiometricKeyInvalidated`. Matches spec.

**Hide condition** (line 15): `if (!state.biometricState.isEnabled || state.isBiometricKeyInvalidated)` returns `SizedBox.shrink()`. Matches spec exactly.

### `example/lib/features/settings/views/settings_screen.dart` — Task 7.8

**Inner `BlocBuilder` `buildWhen`** (lines 77–79): Includes `previous.isBiometricKeyInvalidated != current.isBiometricKeyInvalidated`. Matches spec.

**`_canToggleBiometric`** (lines 124–126): `(state.biometricState.isAvailable || state.isBiometricKeyInvalidated) && state.loadState != LoadState.loading`. Matches spec.

**`_getBiometricStateDescription`** (lines 157–171): Accepts `{required bool isKeyInvalidated}`. When `isKeyInvalidated` is `true`, returns `'Biometrics changed. Disable and re-enable to use new biometrics.'`. Copy matches PRD-approved string exactly. Matches spec.

**Subtitle `Text` style** (lines 85–92): `style: innerLockerState.isBiometricKeyInvalidated ? TextStyle(color: Theme.of(context).colorScheme.error) : null`. Matches spec.

**Call site** (lines 86–89): Passes `isKeyInvalidated: innerLockerState.isBiometricKeyInvalidated`. Correct.

**`_AutoLockTimeoutTile._showTimeoutDialog`** (lines 217–218): `final isBiometricEnabled = lockerBloc.state.biometricState.isEnabled && !lockerBloc.state.isBiometricKeyInvalidated`. All downstream uses of `isBiometricEnabled` in the method correctly reflect invalidation. Matches spec.

**`_handleBiometricToggle`** (lines 128–155): Routes toggle-off to `disableBiometricRequested` without checking `isBiometricKeyInvalidated`. This is correct — the password-only routing is Phase 8 scope. No deviation from Phase 7 spec.

**Additional display detail** (lines 97–105): The `'Your biometric credentials can unlock the vault.'` hint text is guarded by `innerLockerState.biometricState.isEnabled && !innerLockerState.isBiometricKeyInvalidated`. This is a correct and reasonable defensive addition not explicitly in the spec but consistent with its intent.

### `example/lib/features/settings/bloc/settings_bloc.dart` — Task 7.8b

At lines 131–138, `BiometricExceptionType.keyInvalidated` has its own `case` in `_onAutoLockTimeoutSelectedWithBiometric`. It emits `SettingsAction.biometricAuthenticationFailed(message: 'Biometrics have changed. Please use your password.')` and returns early. The generic `'Failed to update timeout using biometric.'` error path at lines 145–150 is not reached for this case. Matches spec exactly.

---

## Positive Scenarios

### PS-1: Biometric key invalidation detected at runtime — inline message shown

**Setup:** Vault is locked. Biometrics are enabled. `isBiometricKeyInvalidated` is `false`. Platform returns `keyPermanentlyInvalidated` on biometric operation attempt.

**Steps:**
1. User taps unlock button. Auth bottom sheet opens with biometric button visible.
2. User taps biometric button. `unlockWithBiometricRequested` is added.
3. Repository calls `MFALocker` biometric operation. Platform throws `keyPermanentlyInvalidated`.
4. `BiometricExceptionType.keyInvalidated` reaches `_handleBiometricFailure`.
5. BLoC emits `state.copyWith(isBiometricKeyInvalidated: true)`.
6. BLoC emits `LockerAction.biometricKeyInvalidated()`.
7. BLoC adds `biometricOperationStateChanged(idle)` and returns early.

**Expected:**
- `LockerBlocBiometricStream` maps the action to `BiometricFailed('Biometrics have changed. Please use your password.')`.
- Auth bottom sheet displays the inline message.
- `biometricAuthenticationFailed` action is NOT emitted.

**Automated:** No. Requires device-level BLoC integration test or manual verification.

---

### PS-2: Biometric button hidden after invalidation flag is set

**Setup:** `isBiometricKeyInvalidated` is `true` (set in PS-1).

**Steps:**
1. Locked screen `BlocBuilder` rebuilds (triggered by `isBiometricKeyInvalidated` change in `buildWhen`).
2. Local variable `showBiometric = state.biometricState.isEnabled && !state.isBiometricKeyInvalidated` evaluates to `false`.
3. Button label reads `'Unlock with Password'`.
4. `AuthenticationBottomSheet` receives `showBiometricButton: false`.
5. `BiometricUnlockButton.build` evaluates `!state.biometricState.isEnabled || state.isBiometricKeyInvalidated` as `true`, returns `SizedBox.shrink()`.

**Expected:** No biometric button visible on locked screen or in the auth sheet.

**Automated:** No. Requires widget test or manual check.

---

### PS-3: User unlocks with password after invalidation

**Setup:** `isBiometricKeyInvalidated` is `true`. Biometric button is hidden.

**Steps:**
1. User taps `'Unlock with Password'` button. Auth sheet opens with password field only.
2. User enters correct password. `unlockPasswordSubmitted` is dispatched.
3. Vault unlocks normally.

**Expected:** Normal unlock flow completes. `isBiometricKeyInvalidated` remains `true` (not cleared by a successful password unlock — that is correct and by design; clearing only happens on erase or successful biometric enable, which is Phase 8).

**Automated:** No. Manual verification.

---

### PS-4: Settings screen shows invalidation description in error color

**Setup:** `isBiometricKeyInvalidated` is `true`. User navigates to Settings.

**Steps:**
1. Inner `BlocBuilder` rebuilds because `buildWhen` includes `isBiometricKeyInvalidated`.
2. `_getBiometricStateDescription(biometricState, isKeyInvalidated: true)` returns `'Biometrics changed. Disable and re-enable to use new biometrics.'`.
3. Subtitle `Text` widget applies `TextStyle(color: Theme.of(context).colorScheme.error)`.
4. `_canToggleBiometric` returns `true` because `state.isBiometricKeyInvalidated` is `true`.
5. The biometric tile switch is enabled.

**Expected:** The subtitle text renders in the theme's error color. The switch is not greyed out.

**Automated:** No. Requires widget test or manual check.

---

### PS-5: Settings auto-lock timeout update with invalidated key gives specific message

**Setup:** `isBiometricKeyInvalidated` is `true`. `_AutoLockTimeoutTile._showTimeoutDialog` evaluates `isBiometricEnabled` as `false` (due to `&& !lockerBloc.state.isBiometricKeyInvalidated`). Biometric button is not shown in the timeout dialog.

**Steps:**
1. If a biometric operation were triggered (e.g., via a code path that bypasses the guard), `SettingsBloc._onAutoLockTimeoutSelectedWithBiometric` would receive `BiometricExceptionType.keyInvalidated`.
2. The `case BiometricExceptionType.keyInvalidated:` branch emits `biometricAuthenticationFailed(message: 'Biometrics have changed. Please use your password.')`.
3. Returns early — does not reach `'Failed to update timeout using biometric.'`.

**Expected:** Specific message emitted; generic timeout failure message not shown.

**Automated:** No. Requires integration test.

Note: The `_AutoLockTimeoutTile` guard (`isBiometricEnabled` being `false`) prevents the biometric button from appearing when the key is invalidated, so this path is normally unreachable from normal UI interaction when the flag is set. The `SettingsBloc` case acts as a defensive backstop.

---

### PS-6: Erase clears the invalidation flag

**Setup:** `isBiometricKeyInvalidated` is `true`.

**Steps:**
1. User confirms storage erase.
2. `_onEraseStorageRequested` completes successfully.
3. `state.copyWith(status: notInitialized, isBiometricKeyInvalidated: false, entries: {}, loadState: none)` is emitted.

**Expected:** `isBiometricKeyInvalidated` is `false` in the new state. App returns to initial state with no stale invalidation knowledge.

**Automated:** No. Requires BLoC integration test or manual check.

---

### PS-7: Generic biometric failure (wrong fingerprint) — no regression

**Setup:** `isBiometricKeyInvalidated` is `false`. User attempts biometric with wrong fingerprint.

**Steps:**
1. `BiometricExceptionType.failure` reaches `_handleBiometricFailure`.
2. `case BiometricExceptionType.failure:` branch calls `_determineBiometricStateAndEmit(emit)`.
3. Falls through to `biometricAuthenticationFailed(message: fallbackMessage)`.

**Expected:** `isBiometricKeyInvalidated` remains `false`. `biometricKeyInvalidated` action is NOT emitted. Generic failure message shown.

**Automated:** No. Requires integration or manual test.

---

### PS-8: Cold launch resets the flag

**Setup:** App is relaunched after session where `isBiometricKeyInvalidated` was `true`.

**Steps:**
1. App cold-starts. `LockerState` is constructed with Freezed defaults.
2. `@Default(false) bool isBiometricKeyInvalidated` initializes to `false`.

**Expected:** Flag is `false` at startup. Biometric button is visible again if biometrics are still enrolled and the hardware key is still accessible (or will trigger another invalidation detection on first attempt).

**Automated:** No. Manual check or review of Freezed field defaults.

---

## Negative and Edge Cases

### NC-1: `biometricKeyInvalidated` action must NOT conflate with `biometricAuthenticationFailed`

**Concern:** If `biometricAuthenticationFailed` were emitted instead of `biometricKeyInvalidated`, the `LockerBlocBiometricStream` would not produce the approved inline message, and the `isBiometricKeyInvalidated` flag would never be set.

**Verification:** Code review of `_handleBiometricFailure` lines 1082–1091 confirms the `keyInvalidated` case returns early before the `biometricAuthenticationFailed` fallback at line 1102. The `LockerBlocBiometricStream` handles both actions distinctly at lines 11–13.

---

### NC-2: `_handleBiometricToggle` with invalidated key — Phase 8 routing not yet present

**Concern:** The Settings screen shows the toggle as enabled when `isBiometricKeyInvalidated` is `true`. If a user taps the toggle to disable biometrics, `_handleBiometricToggle` currently dispatches `disableBiometricRequested` (which requires a working biometric key for some internal flows) rather than the Phase 8 `disableBiometricPasswordOnlyRequested`.

**Current behavior:** `_handleBiometricToggle` (lines 128–155 of `settings_screen.dart`) dispatches `disableBiometricRequested` unconditionally for the `value == false` path. There is no `isBiometricKeyInvalidated` check. This is the intended Phase 7 state — the toggle is enabled (so the UI is correct) but the routing to password-only is Phase 8. The user can tap the toggle, but the disable operation will route through the standard path.

**Risk:** If `disableBiometricRequested` triggers a biometric prompt internally as part of the disable flow, and the key is already invalidated, that biometric prompt will fail and `_handleBiometricFailure` will be called again — re-setting `isBiometricKeyInvalidated: true` (which is already `true`). No data loss or crash, but the user cannot complete the disable flow until Phase 8. This is documented and accepted behavior for Phase 7.

**Verdict:** Acceptable per PRD. Phase 8 closes this gap.

---

### NC-3: `buildWhen` for `LockedScreen` — captures all relevant state changes

**Concern:** If `buildWhen` omits `isBiometricKeyInvalidated`, the locked screen will not rebuild when the flag is set, leaving the biometric button visible after invalidation.

**Verification:** Lines 20–23 of `locked_screen.dart` include `previous.isBiometricKeyInvalidated != current.isBiometricKeyInvalidated`. The three conditions cover `loadState`, `biometricState`, and `isBiometricKeyInvalidated`. No gap.

---

### NC-4: `buildWhen` for Settings inner `BlocBuilder` — correct conditions

**Concern:** If `isBiometricKeyInvalidated` is not in the Settings `buildWhen`, the error-colored subtitle and toggle state will not update when the flag changes mid-session (e.g., if the user left Settings open before triggering invalidation).

**Verification:** Lines 77–79 of `settings_screen.dart` include `previous.isBiometricKeyInvalidated != current.isBiometricKeyInvalidated`. Correct.

---

### NC-5: `SettingsBloc` `keyInvalidated` case must `return` without reaching `showError`

**Concern:** If the `return` is absent or if `SettingsAction.showError` is also emitted, the user will see a redundant snackbar in addition to the inline auth sheet error.

**Verification:** Lines 131–138 of `settings_bloc.dart` — the `case BiometricExceptionType.keyInvalidated:` block calls `action(biometricAuthenticationFailed(...))` then `return`. The `showError` action at line 150 is not reachable from this path. Correct.

---

### NC-6: Outer Settings `BlocBuilder` does not observe `isBiometricKeyInvalidated`

**Observation:** The outer `BlocBuilder<LockerBloc, LockerState>` at line 55 of `settings_screen.dart` does not have a `buildWhen` (it rebuilds on every `LockerState` change). This means the outer layout (which uses `lockerState.loadState` for the `LoadingOverlay`) rebuilds more than strictly necessary. This is not a bug — the outer builder does not use `isBiometricKeyInvalidated` directly. The inner `BlocBuilder` (with the correct `buildWhen`) handles the biometric card. No issue.

---

### NC-7: `_AutoLockTimeoutTile` biometric check prevents double-prompt when key is invalidated

**Concern:** If `lockerBloc.state.isBiometricKeyInvalidated` were not checked, the timeout dialog would show a biometric button even when the key is invalidated, leading to another guaranteed failure and another `keyInvalidated` emission (with `isBiometricKeyInvalidated` being set to `true` a second time — harmless but confusing).

**Verification:** Lines 217–218 of `settings_screen.dart` — `lockerBloc.state.biometricState.isEnabled && !lockerBloc.state.isBiometricKeyInvalidated`. The guard is correct.

---

### NC-8: Flag persistence — in-memory only, not persisted to disk

**Concern:** If the flag were persisted to `SharedPreferences` or the locker storage JSON, old stale flags could survive across reinstalls or storage clears.

**Verification:** The field is `@Default(false) bool isBiometricKeyInvalidated` on a Freezed class — a plain in-memory Dart object. No write to storage. Confirmed by searching `locker_state.dart` and `locker_bloc.dart` — no `SharedPreferences` or JSON serialization calls touch `isBiometricKeyInvalidated`. Correct.

---

### NC-9: Approved copy strings are exact

**Concern:** User-facing strings are copy-approved. Any deviation (including punctuation or capitalization) is a defect.

**Verification:**

- `LockerBlocBiometricStream` line 13: `'Biometrics have changed. Please use your password.'` — exact match.
- `_getBiometricStateDescription` line 159: `'Biometrics changed. Disable and re-enable to use new biometrics.'` — exact match.
- `SettingsBloc` line 134: `'Biometrics have changed. Please use your password.'` — exact match.

All three strings match the PRD-approved copy.

---

### NC-10: Multiple rapid taps on biometric button before flag is set

**Concern:** If the user taps the biometric button multiple times before the first `keyInvalidated` response arrives, each tap dispatches `unlockWithBiometricRequested`. Each invocation will independently fail with `keyInvalidated` and attempt to emit `state.copyWith(isBiometricKeyInvalidated: true)` and `biometricKeyInvalidated()`.

**Analysis:** `LockerBloc` uses `on<...>` with default `EventTransformer.sequential` behavior. Only one event handler runs at a time. Each `keyInvalidated` response will arrive sequentially and attempt `emit(state.copyWith(isBiometricKeyInvalidated: true))`. After the first, the flag is already `true`. The second emit is idempotent (same value). The second `biometricKeyInvalidated()` action will also be emitted, which causes `LockerBlocBiometricStream` to emit another `BiometricFailed` message — displaying the inline error again. This is not harmful but may show a repeated error in the auth sheet. Not a blocking issue given that the biometric button disappears after the first rebuild.

**Risk:** Low. No data corruption. Minor UX redundancy possible under rapid tapping.

---

## Automated Tests Coverage

Phase 7 adds no new automated unit or widget tests. All changes are in the example app layer (`example/lib/`), which has no test suite in this repository. The implementation is entirely verified by:

- Code review (all eight files read directly).
- Static analysis: `cd example && fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .`
- Format check: `cd example && fvm dart format . --line-length 120`

The library-layer tests from Phases 1–6 (in `lib/` and `packages/biometric_cipher/`) continue to cover the underlying exception propagation chain and `teardownBiometryPasswordOnly`. Running `fvm flutter test` from the root confirms no library regressions.

### Coverage gaps

| Scenario | Gap type |
|----------|----------|
| PS-1 through PS-7 (all runtime BLoC flows) | No automated BLoC integration tests for the example app |
| Widget rendering of error color subtitle | No widget tests |
| `BiometricUnlockButton` returns `SizedBox.shrink()` when flag is set | No widget test |
| `LockedScreen` button text change on flag | No widget test |
| `buildWhen` filtering correctness | No automated check |

These gaps are inherent to the example app's test structure and are not regressions introduced by Phase 7.

---

## Manual Checks Needed

### MC-1: Static analysis — example app

**Command:**
```
cd example && fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .
```

**Pass criterion:** Exits with code 0.

This validates:
- Freezed-generated code is present and consistent with the new `isBiometricKeyInvalidated` field and `biometricKeyInvalidated()` factory.
- `mapOrNull` call in `LockerBlocBiometricStream` includes the `biometricKeyInvalidated` parameter (only available after `make g`).
- All eight modified files compile without errors or warnings.
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

Phase 7 does not change any library file, so no library test should fail. This check is a safeguard against accidental changes.

---

### MC-4: Device/simulator — biometric key invalidation end-to-end

**Prerequisite:** Device or simulator that supports biometric enrollment changes. Android emulator with fingerprint simulation, or iOS Simulator with Touch ID. A vault with biometric wrap established.

**Procedure:**
1. Install the example app. Initialize vault with password + biometric unlock.
2. Simulate a biometric enrollment change:
   - Android: Add or remove a fingerprint via device settings.
   - iOS Simulator: `Device > Touch ID > Enrolled` (toggle off and on, or add new fingerprint via the menu).
3. Return to app. Vault should be in locked state.
4. Open the auth bottom sheet. Biometric button should be visible (flag is `false` — invalidation not yet detected).
5. Tap the biometric button.
6. Expected: System biometric prompt fires and immediately fails with `keyPermanentlyInvalidated`.
7. Expected: Auth sheet shows `'Biometrics have changed. Please use your password.'` inline.
8. Expected: Biometric button disappears from the auth sheet.
9. Navigate to locked screen (dismiss sheet). Expected: Locked screen button label changes to `'Unlock with Password'`.
10. Enter password. Vault unlocks normally.
11. Navigate to Settings. Expected: Biometric tile subtitle reads `'Biometrics changed. Disable and re-enable to use new biometrics.'` in red.
12. Expected: Biometric switch toggle is enabled (not greyed out).
13. Go back to locked screen. Tap Settings. Expected: Invalidation message persists in-session.
14. Close and relaunch app. Expected: Flag resets — biometric button visible again on locked screen.
15. Trigger invalidation again. Then erase storage.
16. Expected: App returns to `notInitialized` state. On restart, no invalidation state present.

**Pass criterion:** All expected outcomes in steps 6–16 match observed behavior.

**Status:** Not executed. Required before AW-2160 final release.

---

### MC-5: Regression — wrong fingerprint does not set `isBiometricKeyInvalidated`

**Procedure:**
1. Vault locked. Biometrics enabled and valid.
2. Present wrong fingerprint (or face) intentionally.
3. Auth sheet shows generic failure message (e.g., the `fallbackMessage` defined at each call site).
4. `isBiometricKeyInvalidated` must remain `false` — biometric button must still be visible.

**Pass criterion:** Biometric button visible after generic failure. Settings shows no invalidation message.

**Status:** Not executed. Manual check required.

---

### MC-6: Auto-lock timeout tile — biometric button absent when flag is set

**Procedure:**
1. With `isBiometricKeyInvalidated` set to `true` (from MC-4 step 7), navigate to Settings.
2. Tap the Auto-Lock Timeout tile.
3. Expected: The timeout dialog / bottom sheet does NOT show a biometric button (`isBiometricEnabled` evaluates to `false`).
4. User enters password to update timeout. Timeout updates normally.

**Pass criterion:** No biometric button in timeout dialog when key is invalidated.

**Status:** Not executed. Manual check required.

---

## Risk Zone

| Risk | Severity | Status |
|------|----------|--------|
| `_handleBiometricToggle` dispatches `disableBiometricRequested` even when `isBiometricKeyInvalidated` is `true` — toggle-off will attempt a normal disable flow that may internally require the invalidated key | Medium | Accepted per PRD. This is the documented Phase 8 boundary. The user cannot complete the disable flow in Phase 7. No crash or data loss, but the UX leaves the user unable to fix the stale biometric setup until Phase 8 ships. |
| No automated tests for any example app code path in this phase | Medium | Inherent to the example app's test structure. All nine tasks are pure code-review + manual verification items. Risk is mitigated by the clarity of each change and by static analysis. |
| End-to-end device test not yet performed (carry-over from all phases) | High | The full AW-2160 pipeline (Android `KeyPermanentlyInvalidatedException`, iOS `errSecAuthFailed`, Dart mapping, locker mapping, example app detection and display) has never been exercised end-to-end on a real device. All layers were verified individually via code review and unit tests. A single device-level regression could exist at any layer boundary. Must be run before production release. |
| One failed biometric attempt per session before flag is set | Low | Accepted per PRD. The flag is in-memory and starts `false` on each cold launch. The first `keyInvalidated` attempt sets the flag; subsequent attempts are blocked by the hidden button. One failed prompt per session is acceptable. |
| `make g` codegen not directly verifiable from static files | Low | If codegen was not run after Tasks 7.1 and 7.2, the `.freezed.dart` files would be stale and `fvm flutter analyze` would fail. The analyze check (MC-1) is the definitive gate. |
| `biometricKeyInvalidated` action emitted multiple times under rapid tapping (NC-10) | Low | Each `keyInvalidated` response emits one action. Under rapid tapping, multiple `BiometricFailed` messages may appear in the auth sheet. Not a blocking issue — the button hides after the first rebuild. |
| `_canToggleBiometric` allows toggle on simulator or device with no biometric hardware when flag is `true` | Very Low | Dev concern only. On a device with no biometric hardware, `biometricState` will be `hardwareUnavailable` or `notEnrolled`. If `isBiometricKeyInvalidated` were somehow set, the toggle would be enabled. The disable flow (Phase 8) will gate correctly on the repository layer. Accepted per PRD. |

---

## Final Verdict

**Release with reservations.**

All nine Phase 7 tasks are implemented correctly in the observed code. Each spec requirement — the Freezed field, the new action factory, the `_handleBiometricFailure` split, the stream mapping, the locked screen and button guards, the Settings tile description and toggle behavior, the `SettingsBloc` specific message, and the erase flag clear — is present with the exact copy strings, conditions, and return-early logic required by the PRD.

**Reservations:**

1. **`_handleBiometricToggle` does not route to `disableBiometricPasswordOnlyRequested`** when `isBiometricKeyInvalidated` is `true`. The Settings toggle is enabled (correct for Phase 7), but tapping it to disable biometrics will invoke the standard `disableBiometricRequested` path, which may fail when the key is invalidated. This is the documented Phase 8 boundary — not a Phase 7 defect — but it means the advertised remediation path ("Disable and re-enable to use new biometrics.") is not yet functional. Users will see the instruction but cannot follow it until Phase 8 ships. Phase 7 must not be communicated to users as delivering complete recovery capability.

2. **No end-to-end device test has been executed for any phase of AW-2160.** The full pipeline from native `KeyPermanentlyInvalidatedException` / `errSecAuthFailed` through all Dart layers to the example app display has only been verified by code review and unit tests. A device-level smoke test (MC-4) is mandatory before the complete AW-2160 feature reaches production.

3. **No automated tests for the example app.** All Phase 7 behavior is verified by code review alone. Regressions in the example app will not be caught by the CI test suite.

Phase 7 is safe to merge as an independent phase. It does not break any existing functionality, introduces no library changes, and delivers all specified detection and display behavior. The reservations above are preconditions for the full AW-2160 release, not blockers for this phase in isolation.
