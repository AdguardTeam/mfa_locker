# AW-2160 Phase 13 Summary — Locker: `BiometricState.keyInvalidated` + Proactive `determineBiometricState`

## What Was Done

Phase 13 adds proactive biometric key validity detection to the Dart locker library. Before this phase, key invalidation was detected only reactively — when the user tapped the biometric button and the decrypt attempt failed. That caused the lock screen to briefly show the biometric button and then hide it. Phase 13 eliminates that flash: `determineBiometricState()` can now detect invalidation silently at init time and return `BiometricState.keyInvalidated` before any user interaction.

The implementation builds entirely on top of the silent key validity probes added in Phases 9–12. No native code was changed. No new files were created. All five changes are additions to existing files.

---

## Files Changed

| File | Change |
|------|--------|
| `lib/locker/models/biometric_state.dart` | Added `keyInvalidated` enum value and `isKeyInvalidated` getter |
| `lib/security/biometric_cipher_provider.dart` | Added `isKeyValid({required String tag})` abstract method and its implementation in `BiometricCipherProviderImpl` |
| `lib/locker/locker.dart` | Added optional `biometricKeyTag` parameter to `determineBiometricState` signature |
| `lib/locker/mfa_locker.dart` | Inserted key validity check in `determineBiometricState` |

---

## Key Decisions

### `keyInvalidated` is an error state, not an available state

`BiometricState.keyInvalidated` is intentionally excluded from `isEnabled` and `isAvailable`. The hardware key is gone, so the state must not be treated as a usable biometric state. Callers that use exhaustive switches on `BiometricState` will receive a compile error when upgrading — this is by design and forces them to handle the new case explicitly.

### Backwards compatibility via optional parameter

The `biometricKeyTag` parameter on `determineBiometricState` is `String?`. Callers that do not pass it get the same behavior they had before Phase 13. The key validity check is skipped entirely when the parameter is null. This was the only safe approach because not all callers have a key tag available at the point where they query biometric state.

### Key validity check is placed after the app settings guard

The `isKeyValid()` call runs only when biometrics are enabled in the app's storage settings. This ordering is deliberate: there is no point probing the hardware key when the app has already disabled biometrics. The check is skipped for all other early-exit paths (TPM unsupported, hardware unavailable, not enrolled, etc.) because those paths return before reaching the key validity block.

### No try-catch around `isKeyValid`

If `isKeyValid()` throws, the exception propagates to the caller of `determineBiometricState`. This is intentional and consistent with how all other provider calls in the method behave. The caller is responsible for handling errors from `determineBiometricState`.

### No logging

The key validity probe is silent. No log calls were added — consistent with the design of the silent probes in Phases 9–11.

---

## How the Proactive Flow Works

```
determineBiometricState(biometricKeyTag: "biometric")
  |
  +-- TPM check .............. tpmUnsupported / tpmVersionIncompatible
  +-- Biometry hardware check  hardwareUnavailable / notEnrolled / disabledByPolicy / securityUpdateRequired
  +-- App settings check ..... availableButDisabled
  |
  +-- NEW: biometricKeyTag provided + biometrics enabled
        |
        +-- isKeyValid(tag) returns false --> BiometricState.keyInvalidated (early return)
        +-- isKeyValid(tag) returns true  --> BiometricState.enabled
```

The `isKeyValid` call never shows a biometric prompt on any platform. That guarantee comes from Phases 9–11:
- Android: `Cipher.init()` only — no `BiometricPrompt`
- iOS/macOS: `SecItemCopyMatching` with `kSecUseAuthenticationUISkip`
- Windows: `KeyCredentialManager::OpenAsync()` — no signing request

---

## Test Coverage

All acceptance criteria pass. New tests were added across three files:

- `test/locker/models/biometric_state_test.dart` — verifies `isKeyInvalidated`, `isEnabled`, and `isAvailable` for `keyInvalidated`
- `test/security/biometric_cipher_provider_test.dart` — verifies `isKeyValid` delegation returns both `true` and `false` correctly
- `test/locker/mfa_locker_test.dart` — verifies `determineBiometricState` returns `keyInvalidated` when `isKeyValid` is `false`, returns `enabled` when `true`, and never calls `isKeyValid` when no tag is provided

Two test coverage gaps were identified and documented in the QA report (NC-9 and NC-10). Neither represents a defect in the implementation; both are deferred to Phase 14 (Tests for proactive detection):
- NC-9: No `verifyNever(isKeyValid)` assertion for the case where `biometricKeyTag` is provided but biometrics are disabled in app settings.
- NC-10: No `verifyNever` assertions for early-exit hardware paths when a tag is provided.

---

## QA Result

QA status: **RELEASE**. All five tasks (13.1–13.5) and code review fix R1 (CHANGELOG entry) are implemented correctly. All acceptance criteria pass. No defects found.

---

## What Comes Next

- **Phase 14** (Tests for proactive detection) closes the NC-9 and NC-10 coverage gaps identified in the QA report.
- **Phase 15** (Example app: proactive detection integration) passes `biometricKeyTag` in the repository's `determineBiometricState` call, activating the proactive path and eliminating the biometric button flash. Phase 15 is already marked complete.
