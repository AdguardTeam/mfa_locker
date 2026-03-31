# Phase 14: Tests for Proactive Detection

**Goal:** Unit tests for `isKeyValid` delegation, `BiometricState.keyInvalidated`, and proactive `determineBiometricState`.

## Context

### Feature Motivation

Phase 13 added `BiometricState.keyInvalidated`, `BiometricCipherProvider.isKeyValid(tag)`, and the proactive key validity check in `MFALocker.determineBiometricState(biometricKeyTag:)`. This phase adds unit test coverage for all three additions.

Tests are spread across three existing test files — each at the layer it tests:
- `test/locker/models/biometric_state_test.dart` — enum value and getters
- `test/security/biometric_cipher_provider_test.dart` — `isKeyValid` delegation
- `test/locker/mfa_locker_test.dart` — `determineBiometricState` with and without tag

### What Phase 13 Added (this phase tests)

| Symbol | File | What to verify |
|--------|------|----------------|
| `BiometricState.keyInvalidated` | `lib/locker/models/biometric_state.dart` | value exists; `isKeyInvalidated`, `isEnabled`, `isAvailable` return correct booleans |
| `BiometricCipherProviderImpl.isKeyValid` | `lib/security/biometric_cipher_provider.dart` | delegates to `BiometricCipher.isKeyValid` and passes return value through |
| `MFALocker.determineBiometricState(biometricKeyTag:)` | `lib/locker/mfa_locker.dart` | returns `keyInvalidated` when `isKeyValid` returns `false`; skips check when tag is `null` |

### Test Structure

```
test/
├── locker/
│   ├── models/
│   │   └── biometric_state_test.dart      # Task 14.1 — BiometricState enum
│   └── mfa_locker_test.dart               # Tasks 14.3, 14.4 — determineBiometricState
└── security/
    └── biometric_cipher_provider_test.dart # Task 14.2 — isKeyValid delegation
```

## Tasks

- [x] **14.1** Test `BiometricState.keyInvalidated` enum value and `isKeyInvalidated` getter
  - `BiometricState.keyInvalidated.isKeyInvalidated` → `true`
  - `BiometricState.enabled.isKeyInvalidated` → `false`
  - `BiometricState.keyInvalidated.isEnabled` → `false`
  - `BiometricState.keyInvalidated.isAvailable` → `false`

- [x] **14.2** Test `isKeyValid` delegation in `BiometricCipherProviderImpl`
  - Mock `BiometricCipher.isKeyValid` → verify delegation and return value pass-through

- [x] **14.3** Test `determineBiometricState(biometricKeyTag:)` returns `keyInvalidated` when key is invalid
  - Mock `isKeyValid` → `false`, biometrics enabled in settings
  - Expect `BiometricState.keyInvalidated`

- [x] **14.4** Test `determineBiometricState()` without `biometricKeyTag` retains existing behavior
  - Biometrics enabled, no tag passed → expect `BiometricState.enabled` (no key validity check)

## Acceptance Criteria

**Test:** `fvm flutter test` — all green.

- `BiometricState.keyInvalidated.isKeyInvalidated` returns `true`
- `BiometricState.enabled.isKeyInvalidated` returns `false`
- `BiometricState.keyInvalidated.isEnabled` returns `false`
- `BiometricState.keyInvalidated.isAvailable` returns `false`
- `BiometricCipherProviderImpl.isKeyValid` delegates to `BiometricCipher.isKeyValid` and passes return value through
- `determineBiometricState(biometricKeyTag: tag)` calls `isKeyValid(tag: tag)` when biometrics are enabled
- `determineBiometricState(biometricKeyTag: tag)` returns `BiometricState.keyInvalidated` when `isKeyValid` returns `false`
- `determineBiometricState()` without `biometricKeyTag` does NOT call `isKeyValid` and returns `BiometricState.enabled`

## Dependencies

- Phase 13 complete (`BiometricState.keyInvalidated`, `BiometricCipherProvider.isKeyValid`, `MFALocker.determineBiometricState` with tag all implemented)

## Technical Details

### Task 14.1 — `BiometricState` tests (`biometric_state_test.dart`)

Tests the new `keyInvalidated` value and `isKeyInvalidated` getter, plus regression check that `enabled.isKeyInvalidated` returns `false`. File: `test/locker/models/biometric_state_test.dart`.

### Task 14.2 — `isKeyValid` delegation (`biometric_cipher_provider_test.dart`)

Uses `MockBiometricCipher` (already in `test/mocks/mock_biometric_cipher.dart`). Stubs `isKeyValid(tag:)` on the mock and verifies the provider passes through `true`/`false` unmodified. File: `test/security/biometric_cipher_provider_test.dart`.

### Tasks 14.3 & 14.4 — `determineBiometricState` (`mfa_locker_test.dart`)

Added to the existing `determineBiometricState` group in `test/locker/mfa_locker_test.dart`. The group already mocks `secureProvider` as `MockBiometricCipherProvider`; `isKeyValid(tag:)` is stubbed per-test.

- **14.3** — stubs `isKeyValid → false`, passes `biometricKeyTag`, expects `keyInvalidated`
- **14.4** — calls `determineBiometricState()` with no tag, expects `enabled` and verifies `isKeyValid` is never called

## Implementation Notes

- All tests are pure unit tests — no I/O, no platform channels
- `MockBiometricCipherProvider` must have `isKeyValid` stubbed; its mock declaration in `test/mocks/mock_biometric_cipher_provider.dart` uses `mocktail` so no explicit stub registration is needed beyond `when()`
- The `determineBiometricState` group setUp already stubs `getTPMStatus → supported`, `getBiometryStatus → supported`, and `isBiometricEnabled → true` — tasks 14.3 and 14.4 reuse this baseline
