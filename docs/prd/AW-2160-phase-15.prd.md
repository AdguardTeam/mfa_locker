# AW-2160-15: Example App — Proactive Biometric Key Invalidation Detection Integration

Status: PRD_READY

## Context / Idea

This is Phase 15 of AW-2160. The ticket as a whole adds biometric key invalidation detection and a password-only teardown path across the full stack, plus proactive key validity detection at init time without triggering a biometric prompt.

**Phases 1–14 status (all complete):**
- Phase 1: Android native emits `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")` for `KeyPermanentlyInvalidatedException`.
- Phase 2: iOS/macOS native emits `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")` when the Secure Enclave key is inaccessible after a biometric enrollment change.
- Phase 3: Dart plugin maps `'KEY_PERMANENTLY_INVALIDATED'` → `BiometricCipherExceptionCode.keyPermanentlyInvalidated`.
- Phase 4: Locker library maps `BiometricCipherExceptionCode.keyPermanentlyInvalidated` → `BiometricExceptionType.keyInvalidated`.
- Phase 5: `MFALocker.teardownBiometryPasswordOnly` is complete.
- Phase 6: Unit tests for all new Dart-layer code paths are complete.
- Phase 7: Example app detects `keyInvalidated` at runtime and updates UI accordingly.
- Phase 8: Example app password-only biometric disable recovery flow is complete.
- Phase 9: Android native `isKeyValid(tag)` silent probe is complete.
- Phase 10: iOS/macOS native `isKeyValid(tag)` silent probe is complete.
- Phase 11: Windows native `isKeyValid(tag)` silent probe is complete.
- Phase 12: Dart plugin `BiometricCipher.isKeyValid(tag)` public API is complete.
- Phase 13: `BiometricState.keyInvalidated`, `BiometricCipherProvider.isKeyValid(tag)`, and proactive `MFALocker.determineBiometricState(biometricKeyTag:)` implemented in the Dart locker library.
- Phase 14: Unit tests for Phase 13 additions complete.

**The problem this phase solves:** When a user's biometric key is invalidated (e.g., they enrolled a new fingerprint), the lock screen previously showed the biometric button briefly before hiding it — the "button flash" UX problem. The button appeared because biometric state was determined reactively (only after the user tapped the button and the prompt failed). Phase 13 added the proactive `determineBiometricState(biometricKeyTag:)` capability that can detect key invalidity at init time without triggering a biometric prompt. This phase wires the example app to use that capability.

**Scope:** Pure example app wiring — four changes across four files in `example/lib/`. No library or plugin code changes. No new files. The `isBiometricKeyInvalidated` runtime flag from Phase 7 is preserved and remains useful for in-session state changes discovered via explicit biometric attempts.

---

## Goals

1. Wire `LockerRepository.determineBiometricState()` to pass `biometricKeyTag: AppConstants.biometricKeyTag`, activating the proactive key validity check for all callers.
2. Ensure `LockerBloc` handles `BiometricState.keyInvalidated` returned at init time by setting `isBiometricKeyInvalidated: true` in state — so both init-time and runtime detection paths produce the same state flag.
3. Update `LockedScreen` to hide the biometric button when `biometricState.isKeyInvalidated` is true, eliminating the button flash from the very first frame.
4. Update `BiometricUnlockButton` to also check `biometricState.isKeyInvalidated`, ensuring the widget itself never renders when the key is known-invalidated at init time.
5. Ensure analyze and format pass with no warnings or errors after all changes.

---

## User Stories

**US-1 — No biometric button flash when key is invalidated**
As a user whose biometric enrollment has changed, when I open the app with a locked vault, I want to see only the password field from the first frame — without the biometric button appearing and then disappearing — so that the UI communicates the correct state immediately.

**US-2 — Init-time detection is consistent with runtime detection**
As a developer maintaining the example app, I want the `isBiometricKeyInvalidated` flag to be set regardless of whether invalidation is discovered at init time (via `determineBiometricState`) or at runtime (via a failed biometric attempt), so that downstream UI logic remains uniform and does not need separate code paths.

**US-3 — Backwards-compatible wiring**
As a developer integrating the locker library, I want the repository's `determineBiometricState()` call to pass the biometric key tag transparently, without changing the interface exposed to the BLoC layer, so that the BLoC continues calling `repo.determineBiometricState()` with no arguments.

---

## Main Scenarios

### Scenario 1 — App start with invalidated biometric key (Proactive Detection — Workflow 4)

1. App starts or lock screen mounts.
2. `LockerBloc` calls `repo.determineBiometricState()`.
3. `LockerRepositoryImpl.determineBiometricState()` calls `locker.determineBiometricState(biometricKeyTag: AppConstants.biometricKeyTag)`.
4. The library performs a silent key validity probe (no biometric prompt).
5. The key is invalid — library returns `BiometricState.keyInvalidated`.
6. `LockerBloc` receives `keyInvalidated`, sets `isBiometricKeyInvalidated: true` in state, and stores `biometricState: BiometricState.keyInvalidated`.
7. `LockedScreen` evaluates `state.biometricState.isEnabled && !state.biometricState.isKeyInvalidated && !state.isBiometricKeyInvalidated` → `false` → biometric button is not rendered.
8. `BiometricUnlockButton`, if reached, also returns `SizedBox.shrink()` because `state.biometricState.isKeyInvalidated` is true.
9. User sees password-only lock screen from the first frame — no button flash.

### Scenario 2 — App start with valid biometric key (No Regression)

1. App starts or lock screen mounts.
2. `LockerBloc` calls `repo.determineBiometricState()`.
3. `LockerRepositoryImpl.determineBiometricState()` calls `locker.determineBiometricState(biometricKeyTag: AppConstants.biometricKeyTag)`.
4. The library performs a silent key validity probe — key is valid.
5. Library returns `BiometricState.enabled`.
6. `LockerBloc` receives `enabled`, keeps `isBiometricKeyInvalidated: false`.
7. `LockedScreen` shows biometric button normally.

### Scenario 3 — Runtime invalidation discovery (Phase 7 path, unchanged)

1. Biometric key is valid at init — lock screen shows biometric button.
2. User taps biometric button — `BiometricPrompt` triggers.
3. Platform throws `keyPermanentlyInvalidated` during the attempt.
4. `LockerBloc._handleBiometricFailure` sets `isBiometricKeyInvalidated: true` (Phase 7 logic).
5. Biometric button hides via the `isBiometricKeyInvalidated` check.
6. This runtime path continues to work as before — Phase 15 does not change it.

### Scenario 4 — Dual-layer hiding idempotency

1. Key is invalidated — detected proactively at init (Phase 15 sets both `biometricState.isKeyInvalidated` and `isBiometricKeyInvalidated: true`).
2. User somehow triggers the biometric path again mid-session.
3. Both flags are already set — UI remains hidden without any additional state transition.

---

## Success / Metrics

| Criterion | How to verify |
|-----------|--------------|
| `LockerRepository.determineBiometricState()` passes `biometricKeyTag: AppConstants.biometricKeyTag` | Code review of `locker_repository.dart` |
| When `determineBiometricState` returns `BiometricState.keyInvalidated`, `LockerBloc` sets `isBiometricKeyInvalidated: true` in state | Code review of `locker_bloc.dart` |
| `LockedScreen` hides biometric button when `state.biometricState.isKeyInvalidated` is true (in addition to existing `isBiometricKeyInvalidated` check) | Code review of `locked_screen.dart` |
| `BiometricUnlockButton` returns `SizedBox.shrink()` when `state.biometricState.isKeyInvalidated` is true | Code review of `biometric_unlock_button.dart` |
| No biometric button flash on locked screen when key is invalidated — UI correct from first frame | Manual test: invalidate biometric key on device, open app, observe lock screen |
| Normal biometric unlock still works when key is valid | Manual test: valid biometric key, open app, observe biometric button |
| `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` passes | CI / local run in `example/` |
| `fvm dart format . --line-length 120` produces no diff | CI / local run in `example/` |

---

## Constraints and Assumptions

- **Example app only.** No changes to `lib/` (locker library) or `packages/biometric_cipher/` (native plugin). All four changes are confined to `example/lib/features/locker/`.
- **No new files.** All changes go into four existing files in `example/lib/features/locker/`.
- **Phase 13 must be complete.** `BiometricState.keyInvalidated`, `BiometricState.isKeyInvalidated`, `MFALocker.determineBiometricState(biometricKeyTag:)`, and `BiometricCipherProvider.isKeyValid` must already exist.
- **Phase 7 must be complete.** `isBiometricKeyInvalidated` flag in `LockerState` and the runtime detection path in `LockerBloc._handleBiometricFailure` must already exist.
- **Phase 8 must be complete.** Password-only biometric disable flow must already be wired so the full recovery flow works end-to-end.
- **`AppConstants.biometricKeyTag` is available.** This constant is assumed to already exist in the example app and is used consistently throughout.
- **`buildWhen` already includes `biometricState` in relevant widgets.** Both `LockedScreen` and `BiometricUnlockButton` are assumed to already rebuild when `biometricState` changes (established in prior phases). If not, `buildWhen` must also be updated.
- **No new unit tests are required for this phase.** The phase acceptance criteria (`cd example && fvm flutter analyze ...`) confirms the scope is wiring + static analysis, not test coverage.
- **The `biometricState` property on state carries `BiometricState.keyInvalidated` after init.** The BLoC stores the full enum value returned by `determineBiometricState` — the `isKeyInvalidated` getter on the stored enum drives the init-time UI check.

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| `buildWhen` in `LockedScreen` or `BiometricUnlockButton` does not include `biometricState` — widget does not rebuild when init state arrives | Low — prior phases likely added this; confirm with code review | High — biometric button flash persists despite code change | Read `locked_screen.dart` and `biometric_unlock_button.dart` before implementing; add `biometricState` to `buildWhen` if missing |
| `LockerBloc` already handles `keyInvalidated` via a generic branch that does not set `isBiometricKeyInvalidated: true` — flag not set at init | Low — Phase 7 handler is for runtime detection; init-time path may not share it | Medium — runtime hiding works but `isBiometricKeyInvalidated` flag inconsistent | Read `locker_bloc.dart` `_refreshBiometricState` to confirm the `keyInvalidated` case is handled; add explicit branch if needed |
| Dual-layer check introduces a subtle precedence bug (`&&`/`\|\|` logic error) in `showBiometricButton` | Very low — the logic is additive (`&&` for show, `\|\|` for hide) | Medium — biometric button may never show even when key is valid | Verify both Scenario 1 (no button with invalid key) and Scenario 2 (button shown with valid key) manually |
| `AppConstants.biometricKeyTag` does not exist or has a different name | Very low — used throughout the app in prior phases | Low — compile error caught immediately by analyze | Confirm constant name via code search before implementing |

---

## Open Questions

None — the phase description (`docs/phase/AW-2160/phase-15.md`), vision doc (`docs/vision-2160.md`, Workflow 4 and Section G7/G8), and prior phase PRDs provide sufficient detail to implement all four tasks without ambiguity. The file locations, method names, logic conditions, and acceptance criteria are all explicitly specified.
