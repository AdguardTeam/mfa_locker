# AW-2160-7: Example App — Detect and Display Biometric Key Invalidation

Status: PRD_READY

## Context / Idea

This is Phase 7 of AW-2160. The ticket as a whole adds biometric key invalidation detection and a password-only teardown path across the full stack.

**Phases 1–6 status (all complete):**
- Phase 1: Android native emits `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")` for `KeyPermanentlyInvalidatedException`.
- Phase 2: iOS/macOS native emits `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")` when the Secure Enclave key is inaccessible after a biometric enrollment change.
- Phase 3: Dart plugin maps `'KEY_PERMANENTLY_INVALIDATED'` → `BiometricCipherExceptionCode.keyPermanentlyInvalidated`.
- Phase 4: Locker library maps `BiometricCipherExceptionCode.keyPermanentlyInvalidated` → `BiometricExceptionType.keyInvalidated`.
- Phase 5: `MFALocker.teardownBiometryPasswordOnly` is complete — removes the `Origin.bio` wrap using password auth only, with suppressed key deletion errors.
- Phase 6: Unit tests for all new Dart-layer code paths (fromString mapping, provider mapping, teardownBiometryPasswordOnly) are complete.

**The problem this phase solves:** The library layers (Phases 1–5) correctly surface `BiometricExceptionType.keyInvalidated` when the hardware key is gone, but the example app still treats this case identically to a generic `failure` — it falls through to the existing `biometricAuthenticationFailed` action and re-evaluates biometric state. The user sees no actionable message and the biometric button remains visible, causing repeated failing prompts. This phase wires the example app to detect `keyInvalidated` at runtime, display a clear inline message, hide the broken biometric UI, and show an informational message in Settings.

**Scope:** Example app only — `example/lib/` files. No library-layer changes. Nine tasks across five BLoC/state files, two view files, one widget file, and one stream extension file. One code-generation step (`make g`) is required after the Freezed model changes.

**Phase 8 boundary:** The password-only disable flow (`disableBiometricPasswordOnlyRequested` event, `_handleBiometricToggle` routing, clearing the flag on successful enable) is Phase 8. Phase 7 ends at detection and display. Phase 7 ships independently.

---

## Goals

1. Add `isBiometricKeyInvalidated: false` runtime flag to `LockerState` (Freezed) so the BLoC can propagate invalidation knowledge to the UI.
2. Add a dedicated `biometricKeyInvalidated()` action to `LockerAction` (Freezed) so the biometric stream extension can map it to an inline `BiometricFailed` result.
3. Separate `keyInvalidated` from `failure` in `LockerBloc._handleBiometricFailure`: set the flag, emit the action, reset to idle, and return early — no fall-through to the generic `biometricAuthenticationFailed` path.
4. Map `biometricKeyInvalidated` action to `BiometricFailed('Biometrics have changed. Please use your password.')` in `LockerBlocBiometricStream`, so the auth bottom sheet shows the message inline.
5. Hide the biometric unlock button on the locked screen and in `BiometricUnlockButton` when the flag is set.
6. Update `SettingsScreen` to display `'Biometrics changed. Disable and re-enable to use new biometrics.'` in error color when the flag is set, and allow the biometric tile toggle when invalidated.
7. Update `SettingsBloc._onAutoLockTimeoutSelectedWithBiometric` to handle `keyInvalidated` with the message `'Biometrics have changed. Please use your password.'` via the existing `biometricAuthenticationFailed` action — not the generic timeout-failure message.
8. Clear `isBiometricKeyInvalidated` on successful erase (in `_onEraseStorageRequested`).

---

## User Stories

**US-1 — User receives a clear inline message when the biometric key is invalidated**
As a user whose biometric enrollment has changed, when the app tries to use the invalidated hardware key, I need to see "Biometrics have changed. Please use your password." inline in the auth sheet — not a generic error — so that I immediately understand what happened and what to do next.

**US-2 — The broken biometric button no longer appears after invalidation**
As a user who has received the invalidation message, I need the biometric unlock button to disappear from the auth sheet and the locked screen, so that I am not tempted to tap it again when I know it will always fail.

**US-3 — Settings screen informs me of the degraded state**
As a user navigating to Settings after detecting invalidation, I need the biometric tile to display "Biometrics changed. Disable and re-enable to use new biometrics." in red, so that I understand the biometric setup is stale and know the remediation path.

**US-4 — The Settings biometric toggle remains operable when the key is invalidated**
As a user with an invalidated key, I need the biometric tile toggle to be enabled (not greyed out), so that I can initiate the disable flow to clean up the stale setup.

**US-5 — Auto-lock timeout biometric operation gives a specific error on invalidation**
As a user who triggers a biometric-authenticated auto-lock timeout change when the key is already invalidated, I need a specific message "Biometrics have changed. Please use your password." rather than "Failed to update timeout", so that I understand the root cause.

**US-6 — Erase clears the invalidation flag**
As a user who erases storage, I need the invalidation flag to be cleared so that the fresh state does not carry stale knowledge from before the erase.

---

## Main Scenarios

### Scenario 1: User with invalidated key taps the biometric unlock button

1. User changes biometrics in device settings (e.g., enrolls a new fingerprint). Vault remains locked.
2. User opens the app. The locked screen is shown with a biometric button (flag is `false` — invalidation is not yet detected).
3. User taps the biometric button. The auth bottom sheet opens. The system biometric prompt fires.
4. The platform detects the key is permanently invalidated. `BiometricExceptionType.keyInvalidated` reaches `LockerBloc._handleBiometricFailure`.
5. BLoC emits `state.copyWith(isBiometricKeyInvalidated: true)`.
6. BLoC emits `LockerAction.biometricKeyInvalidated()`.
7. BLoC adds `LockerEvent.biometricOperationStateChanged(biometricOperationState: BiometricOperationState.idle)` and returns early.
8. `LockerBlocBiometricStream` maps `biometricKeyInvalidated` → `BiometricFailed('Biometrics have changed. Please use your password.')`.
9. The auth bottom sheet displays the inline error message.
10. The biometric button in the sheet disappears (because `isBiometricKeyInvalidated` is now `true`).
11. User enters password. Vault unlocks normally.

**Note:** The flag is in-memory only (no SharedPreferences). It is `false` on each cold launch. One failed attempt per session before the flag is set is acceptable.

### Scenario 2: User navigates to Settings after invalidation is detected

1. `isBiometricKeyInvalidated` is `true` (set in Scenario 1).
2. Settings screen opens. `buildWhen` rebuilds because the flag is included in the comparison.
3. `_getBiometricStateDescription` receives `isKeyInvalidated: true` and returns `'Biometrics changed. Disable and re-enable to use new biometrics.'`
4. The subtitle text is rendered in `Theme.of(context).colorScheme.error`.
5. `_canToggleBiometric` returns `true` because `state.isBiometricKeyInvalidated` is `true` (condition: `state.biometricState.isAvailable || state.isBiometricKeyInvalidated`).
6. The biometric tile toggle is enabled. (Toggle-off routing to the password-only event is Phase 8.)

### Scenario 3: Locked screen shown after invalidation flag is set

1. `isBiometricKeyInvalidated` is `true`.
2. Locked screen `BlocBuilder` rebuilds (because `isBiometricKeyInvalidated` is in `buildWhen`).
3. `showBiometricButton: state.biometricState.isEnabled && !state.isBiometricKeyInvalidated` evaluates to `false`.
4. The biometric unlock button in the auth sheet is not shown.
5. `BiometricUnlockButton` returns `SizedBox.shrink()` because `state.isBiometricKeyInvalidated` is `true`.

### Scenario 4: Auto-lock timeout update fails due to invalidated key

1. `isBiometricKeyInvalidated` is `true`. User attempts to update auto-lock timeout (which requires biometric in `_onAutoLockTimeoutSelectedWithBiometric`).
2. The biometric operation throws `BiometricExceptionType.keyInvalidated`.
3. `SettingsBloc._onAutoLockTimeoutSelectedWithBiometric` catch block matches `case BiometricExceptionType.keyInvalidated:`.
4. Emits `SettingsAction.biometricAuthenticationFailed(message: 'Biometrics have changed. Please use your password.')`.
5. Returns early — does not reach the generic `'Failed to update timeout'` message.

### Scenario 5: User erases storage — flag is cleared

1. `isBiometricKeyInvalidated` is `true`.
2. User confirms erase.
3. `_onEraseStorageRequested` completes successfully.
4. BLoC emits `state.copyWith(isBiometricKeyInvalidated: false)`.
5. App returns to initial state; no stale invalidation knowledge carried over.

### Scenario 6: Generic biometric failure (wrong fingerprint) — no regression

1. `isBiometricKeyInvalidated` is `false`.
2. User attempts biometric unlock with wrong fingerprint.
3. `BiometricExceptionType.failure` reaches `_handleBiometricFailure`.
4. The `case BiometricExceptionType.failure:` branch is unchanged — calls `_determineBiometricStateAndEmit`.
5. `isBiometricKeyInvalidated` remains `false`. No `biometricKeyInvalidated` action is emitted.

---

## Success / Metrics

| Criterion | How to verify |
|-----------|--------------|
| `isBiometricKeyInvalidated` field added to `LockerState` with `@Default(false)` | Code review / Freezed codegen |
| `biometricKeyInvalidated()` factory added to `LockerAction` | Code review / Freezed codegen |
| `make g` produces updated `.freezed.dart` files without errors | `cd example && make g` |
| `keyInvalidated` branch in `_handleBiometricFailure` sets flag, emits action, resets to idle, returns early | Code review |
| `biometricKeyInvalidated` → `BiometricFailed('Biometrics have changed. Please use your password.')` in stream extension | Code review; copy is final as written |
| Biometric button hidden on locked screen when flag is `true` | Code review of `buildWhen` + `showBiometricButton` condition |
| `BiometricUnlockButton` returns `SizedBox.shrink()` when flag is `true` | Code review |
| Settings tile shows `'Biometrics changed. Disable and re-enable to use new biometrics.'` in error color when flag is `true` | Code review; copy is final as written |
| `_canToggleBiometric` allows toggle when `isBiometricKeyInvalidated` is `true` | Code review |
| `_AutoLockTimeoutTile` biometric check excludes invalidated key | Code review |
| `SettingsBloc` emits `biometricAuthenticationFailed` (not a new action) with specific message on `keyInvalidated` | Code review |
| Flag cleared on erase | Code review of `_onEraseStorageRequested` |
| `cd example && fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` exits 0 | CI / local run |
| `cd example && fvm dart format . --line-length 120` produces no diffs | CI / local run |
| Generic failure (`BiometricExceptionType.failure`) still calls `_determineBiometricStateAndEmit` — no regression | Code review |

---

## Constraints and Assumptions

- **Example app only.** No changes to library files under `lib/` or `packages/`. All nine tasks touch only `example/lib/` files.
- **Flag is in-memory only.** `isBiometricKeyInvalidated` is a Freezed field with `@Default(false)` — no persistence to SharedPreferences or any storage. The flag resets on each cold launch. One failed attempt before the flag is set per session is acceptable behavior.
- **Phase 7 ships independently.** Phase 8 (password-only disable flow, flag clearing on successful enable) is a separate phase. Phase 7 does not block on Phase 8.
- **Copy is final.** The two user-facing strings are approved as written:
  - Inline auth sheet: `'Biometrics have changed. Please use your password.'`
  - Settings tile description: `'Biometrics changed. Disable and re-enable to use new biometrics.'`
- **`SettingsBloc` reuses existing `biometricAuthenticationFailed` action** for the `keyInvalidated` case in `_onAutoLockTimeoutSelectedWithBiometric`. No new dedicated settings action is introduced.
- **`_canToggleBiometric` condition is intentional.** The condition `(state.biometricState.isAvailable || state.isBiometricKeyInvalidated)` is the specified behavior — the toggle is enabled when the key is invalidated so the user can initiate the disable flow.
- **Code generation required.** Tasks 7.1 and 7.2 modify Freezed models. Task 7.3 (`make g`) must run after them and before 7.4 (which references the generated `biometricKeyInvalidated()` factory).
- **Dart code style applies.** Line length 120, single quotes, trailing commas on multi-line constructs, `buildWhen` pattern consistent with existing BLoC widgets.
- **`BiometricExceptionType.keyInvalidated` is available** from Phase 4. Tasks in this phase reference it at runtime in `_handleBiometricFailure` and in `SettingsBloc`.
- **`biometricKeyInvalidated` action is distinct from `biometricAuthenticationFailed`.** The stream extension must handle both. Do not conflate them.
- **Flag clearing on successful `enableBiometric` is Phase 8** (task 8.6). This phase only clears the flag on erase (task 7.9).
- **`_handleBiometricToggle` routing to password-only event is Phase 8** (task 8.5). The toggle in Settings is enabled in this phase but the routing logic is deferred.

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| `make g` fails or produces non-compiling code after Freezed changes in 7.1 and 7.2 | Low — standard Freezed pattern, same as other `LockerAction` and `LockerState` changes | Medium — blocks tasks 7.4–7.9 | Run `make g` immediately after 7.1 + 7.2 and confirm no codegen errors before proceeding. |
| `LockerBlocBiometricStream` `mapOrNull` does not have a `biometricKeyInvalidated` parameter until codegen completes | Low — deterministic; blocked until task 7.3 | Low — resolved by completing 7.3 before 7.5 | Task ordering: 7.1 → 7.2 → 7.3 → 7.4+ |
| Existing `_handleBiometricFailure` switch may not be exhaustive or may use `default:` instead of separate cases | Low — source is readable before editing | Low — adjust split accordingly | Read `_handleBiometricFailure` before editing to confirm the current switch structure. |
| `SettingsBloc._onAutoLockTimeoutSelectedWithBiometric` already has a `keyInvalidated` branch from earlier work | Low — no prior task was scoped to SettingsBloc | Low — if it exists, confirm message matches spec and skip writing | Read the method before editing. |
| `buildWhen` for Settings screen already includes `isBiometricKeyInvalidated` (if added in error) | Very low | Low | Confirm during code review; no risk to correctness. |
| The `_canToggleBiometric` condition with `|| state.isBiometricKeyInvalidated` could allow toggle in a state where no biometric hardware is available (e.g., simulator) | Low — simulator usage is a dev concern, not a production scenario | Low — the toggle simply enables; the actual disable flow (Phase 8) will gate correctly | Accepted per user decision on the condition. |

---

## Resolved Questions

**Q1 — Flag persistence:** In-memory only. No SharedPreferences persistence. Resetting on each launch (one failed attempt before the flag is set per session) is acceptable.

**Q2 — Release scope:** Phase 7 ships independently without Phase 8.

**Q3 — Error message strings:** Final as written — copy-approved. No further review required.

**Q4 — SettingsBloc action for `keyInvalidated` in timeout handler:** Reuse the existing `biometricAuthenticationFailed` action with the specific message `'Biometrics have changed. Please use your password.'`. No new dedicated settings action is introduced.

**Q5 — `_canToggleBiometric` edge case:** The condition `(state.biometricState.isAvailable || state.isBiometricKeyInvalidated)` is intentional and accepted — the toggle is enabled when the key is invalidated so the user can initiate the disable flow.

---

## Open Questions

None.
