# AW-2160-13: Locker — `BiometricState.keyInvalidated` + Proactive `determineBiometricState`

Status: PRD_READY

## Context / Idea

This is Phase 13 of AW-2160. The ticket as a whole adds biometric key invalidation detection and a password-only teardown path across the full stack, plus proactive key validity detection at init time without triggering a biometric prompt.

**Phases 1–12 status (all complete):**
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

**The problem this phase solves:** Phases 1–8 implement reactive detection: `keyInvalidated` is discovered only when the user triggers a biometric operation. This causes the lock screen to briefly show the biometric button before hiding it after a failed attempt. Phase 13 closes this gap by adding proactive detection at the locker library level: `determineBiometricState()` checks key validity at init time via the silent probe built in Phases 9–12, and returns `BiometricState.keyInvalidated` when the hardware key is permanently invalidated — before the user has interacted with any biometric prompt.

**Scope:** Dart locker library only — five files within `lib/`. No native code changes. No example app changes (Phase 15 handles example app integration). No new files.

**Proactive detection flow:**
```
determineBiometricState(biometricKeyTag: "biometric")
  │
  ├── Existing checks: TPM → biometry hardware → app settings
  │
  └── NEW: if biometricKeyTag provided && biometrics enabled in settings:
        │
        ├── _secureProvider.isKeyValid(tag: biometricKeyTag)
        │     (never triggers a biometric prompt on any platform)
        │
        ├── isValid == false → return BiometricState.keyInvalidated
        └── isValid == true  → return BiometricState.enabled
```

**Backwards compatibility:** `biometricKeyTag` is optional. Callers that do not pass it get the existing behavior (no key validity check).

**Dependency on Phase 12:** `BiometricCipher.isKeyValid(tag)` Dart plugin API must be present and wired through `BiometricCipherProvider.isKeyValid(tag)` before the locker can use it.

---

## Goals

1. Add `keyInvalidated` to the `BiometricState` enum with `isKeyInvalidated` getter — making proactive invalidation detectable at the state-query level.
2. Add `isKeyValid({required String tag})` abstract method to `BiometricCipherProvider` and implement it in `BiometricCipherProviderImpl` by delegating to `BiometricCipher.isKeyValid(tag: tag)`.
3. Update the `Locker` interface's `determineBiometricState` signature to accept an optional `biometricKeyTag` parameter.
4. Implement the key validity check in `MFALocker.determineBiometricState`: when `biometricKeyTag` is provided and biometrics are enabled in app settings, silently probe the hardware key and return `BiometricState.keyInvalidated` if the key is gone.
5. Maintain full backwards compatibility — callers that omit `biometricKeyTag` get the same behavior as before this phase.

---

## User Stories

**US-1 — Proactive key invalidation detection at init time**
As a Flutter app consuming the `locker` library, when I call `determineBiometricState(biometricKeyTag: 'biometric')` at lock screen mount time and the biometric hardware key has been permanently invalidated, I need the method to return `BiometricState.keyInvalidated` immediately — without any biometric prompt — so that the lock screen can display password-only mode from the start, with no biometric button flash.

**US-2 — Unchanged behavior for valid keys**
As a Flutter app consuming the `locker` library, when I call `determineBiometricState(biometricKeyTag: 'biometric')` and the biometric key is valid, I need the method to return `BiometricState.enabled` (same as today) without showing any biometric prompt, so that the biometric button is displayed correctly and normal unlock flow proceeds.

**US-3 — Backwards compatibility for callers without key tag**
As a Flutter app that does not provide `biometricKeyTag`, when I call `determineBiometricState()` with no arguments, I need the method to behave exactly as it did before Phase 13 — no key validity check, just hardware and settings checks — so that existing integrations are not broken.

**US-4 — `keyInvalidated` state is distinguishable from `enabled`**
As a Flutter app reading `BiometricState`, I need `BiometricState.keyInvalidated` to be a distinct enum value with `isKeyInvalidated == true`, `isEnabled == false`, and `isAvailable == false`, so that my UI can differentiate a hardware key error from a normally enabled biometric.

---

## Main Scenarios

### Scenario 1: Biometric key invalidated — proactive detection at init

1. User changes biometric enrollment in device settings (e.g., enrolls a new fingerprint).
2. App starts or lock screen mounts and calls `determineBiometricState(biometricKeyTag: 'biometric')`.
3. TPM check passes, biometry hardware check passes, app settings show biometric enabled.
4. `biometricKeyTag` is non-null, so `_secureProvider.isKeyValid(tag: 'biometric')` is called.
5. Platform reports the key is gone (`false`): Android throws `KeyPermanentlyInvalidatedException` in `Cipher.init()`; iOS/macOS finds no key item; Windows returns `KeyCredentialStatus::NotFound`.
6. `determineBiometricState` returns `BiometricState.keyInvalidated`.
7. Lock screen reads `isKeyInvalidated == true` and renders password-only mode immediately — no biometric button is ever shown.

### Scenario 2: Valid biometric key — no regression

1. App starts or lock screen mounts and calls `determineBiometricState(biometricKeyTag: 'biometric')`.
2. TPM check passes, biometry hardware check passes, app settings show biometric enabled.
3. `_secureProvider.isKeyValid(tag: 'biometric')` returns `true`.
4. `determineBiometricState` returns `BiometricState.enabled`.
5. Lock screen shows the biometric button and normal unlock proceeds.

### Scenario 3: No `biometricKeyTag` provided — existing behavior preserved

1. App calls `determineBiometricState()` without any argument.
2. Method performs TPM check, biometry hardware check, app settings check.
3. `biometricKeyTag` is `null`, so `isKeyValid` is not called.
4. Result is the same as before Phase 13: one of `tpmUnsupported`, `tpmVersionIncompatible`, `hardwareUnavailable`, `notEnrolled`, `disabledByPolicy`, `securityUpdateRequired`, `availableButDisabled`, or `enabled`.

### Scenario 4: Biometric disabled in app settings — key validity skipped

1. App calls `determineBiometricState(biometricKeyTag: 'biometric')`.
2. TPM and biometry hardware checks pass.
3. `isBiometricEnabled` returns `false`.
4. Method returns `BiometricState.availableButDisabled` immediately — `isKeyValid` is not called (irrelevant when biometric is disabled).

### Scenario 5: `isKeyValid` is not called when hardware checks fail

1. App calls `determineBiometricState(biometricKeyTag: 'biometric')`.
2. Biometry hardware check returns `notConfiguredForUser`.
3. Method returns `BiometricState.notEnrolled` immediately — `isKeyValid` is not called (key check is unreachable when hardware prerequisites fail).

### Scenario 6: `BiometricState.keyInvalidated` getters return correct values

1. `BiometricState.keyInvalidated.isKeyInvalidated` → `true`
2. `BiometricState.keyInvalidated.isEnabled` → `false`
3. `BiometricState.keyInvalidated.isAvailable` → `false`
4. `BiometricState.enabled.isKeyInvalidated` → `false`
5. `BiometricState.availableButDisabled.isKeyInvalidated` → `false`

---

## Success / Metrics

| Criterion | How to verify |
|-----------|--------------|
| `BiometricState.keyInvalidated` exists as an enum value | Code review of `biometric_state.dart` |
| `BiometricState.keyInvalidated.isKeyInvalidated` returns `true` | Unit test in `biometric_state_test.dart` |
| `BiometricState.enabled.isKeyInvalidated` returns `false` | Unit test in `biometric_state_test.dart` |
| `BiometricState.keyInvalidated.isEnabled` returns `false` | Unit test in `biometric_state_test.dart` |
| `BiometricState.keyInvalidated.isAvailable` returns `false` | Unit test in `biometric_state_test.dart` |
| `BiometricCipherProvider.isKeyValid({required String tag})` declared as abstract | Code review of `biometric_cipher_provider.dart` |
| `BiometricCipherProviderImpl.isKeyValid` delegates to `_biometricCipher.isKeyValid(tag: tag)` | Code review of `biometric_cipher_provider.dart` + unit test in `biometric_cipher_provider_test.dart` |
| `Locker.determineBiometricState({String? biometricKeyTag})` signature updated | Code review of `locker.dart` |
| `MFALocker.determineBiometricState` calls `isKeyValid` when `biometricKeyTag != null` and biometric is enabled in settings | Unit test in `mfa_locker_test.dart` |
| `MFALocker.determineBiometricState` returns `keyInvalidated` when `isKeyValid` returns `false` | Unit test in `mfa_locker_test.dart` |
| `MFALocker.determineBiometricState` returns `enabled` when `isKeyValid` returns `true` | Unit test in `mfa_locker_test.dart` |
| `MFALocker.determineBiometricState()` without `biometricKeyTag` never calls `isKeyValid` | Unit test in `mfa_locker_test.dart` (verifyNever) |
| `isKeyValid` not called when biometrics are disabled in app settings | Unit test (Scenario 4 path) |
| `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` passes | CI analysis |
| `fvm flutter test` passes | CI tests |
| No new files created | Code review |
| No logging added for key validity check | Code review |

---

## Constraints and Assumptions

- **Dart locker library only.** All 5 file changes are within `lib/`: `biometric_state.dart`, `biometric_cipher_provider.dart`, `locker.dart`, `mfa_locker.dart`. No native code, no example app, no `biometric_cipher` plugin.
- **No new files.** All changes are additions to existing files.
- **Task ordering is strict.** Tasks 13.1, 13.2, 13.3 can be done in any order relative to each other but must all complete before 13.4 and 13.5. Task 13.4 (interface) must precede Task 13.5 (implementation).
- **Phase 12 must be complete.** `BiometricCipher.isKeyValid(tag)` Dart plugin API must exist for `BiometricCipherProviderImpl` to delegate to it.
- **`keyInvalidated` is not included in `isAvailable` or `isEnabled`.** It is an error state: the `Origin.bio` wrap may exist in storage but the hardware key is permanently gone. This is distinct from `availableButDisabled`, where the hardware key may still be valid.
- **Key validity check runs only when both conditions are met:** `biometricKeyTag != null` AND `isBiometricEnabled == true`. If biometrics are disabled in app settings, the result of `isKeyValid` is irrelevant and the call is skipped.
- **No logging for the key validity check.** It is a silent probe with no observable side effects. The phase description explicitly prohibits adding logging here.
- **No biometric prompt on any platform.** The guarantee comes from the platform implementations (Phases 9–11): Android uses `Cipher.init()` without `BiometricPrompt`; iOS/macOS uses `kSecUseAuthenticationUISkip`; Windows uses `KeyCredentialManager::OpenAsync()` without a signing request.
- **`biometricKeyTag` is a `String?`.** Passing `null` explicitly or omitting the named parameter both produce identical behavior (no key validity check).
- **Phase 15 wires the example app.** Once this phase is complete, the example app's `LockerBiometricMixin.determineBiometricState()` call (which already passes `biometricKeyTag`) will automatically benefit from proactive detection.

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| `keyInvalidated` added after `enabled` in enum definition could affect switch exhaustiveness checks in app-layer code | Low — Dart's sealed/enum exhaustiveness only requires handling all values; adding a new value to a non-sealed enum does not break callers unless they use exhaustive switches | Medium — app code with exhaustive switches on `BiometricState` (e.g., `switch(state)` without a `default`) will get a compile error | Document the new enum value in release notes; the compile error is a helpful prompt for consumers to handle the new state |
| `BiometricCipherProvider` abstract class changes break callers who implement the interface outside the library | Very low — the interface is internal to the library; the only external implementation is `BiometricCipherProviderImpl` | Low | `BiometricCipherProviderImpl` is updated in the same phase; no external implementors known |
| `isKeyValid` unexpectedly triggers a biometric prompt on a platform (regression in Phases 9–11) | Very low — platform implementations have been specifically tested for this property | High — would cause unexpected prompts at lock screen init | Unit tests mock the provider; integration verification is the responsibility of Phases 9–11 acceptance criteria |
| `isKeyValid` throws an exception (e.g., plugin not configured) and `determineBiometricState` propagates an unhandled error to the caller | Low — `isKeyValid` is a simple status check with no auth operation; plugin must be configured before any locker operation | Medium — unhandled exception in `determineBiometricState` could crash the lock screen | No try-catch is added in this phase; exception propagation to the caller is intentional (caller handles it); the exception type is the same as any other provider error |
| Unit test coverage gap: `isKeyValid` called when biometrics are not enabled in settings | Low — the condition `biometricKeyTag != null` check happens after the `!isEnabledInSettings` guard; covered by existing test structure | Low | Explicit `verifyNever` test case for the biometric-disabled code path |

---

## Open Questions

None — the phase description (`docs/phase/AW-2160/phase-13.md`), idea doc (Sections G4, G5, G6 of `docs/idea-2160.md`), and vision doc (`docs/vision-2160.md`, Section 4) provide sufficient technical detail to implement and verify without ambiguity. All architectural decisions are established by the preceding phases.
