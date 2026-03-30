# AW-2160 Phase 14 Summary — Unit Tests for Proactive Detection

## What Was Done

Phase 14 adds unit test coverage for the three symbols introduced in Phase 13: `BiometricState.keyInvalidated`, `BiometricCipherProviderImpl.isKeyValid`, and the updated `MFALocker.determineBiometricState(biometricKeyTag:)`. All four tasks (14.1–14.4) were already implemented before the phase documentation was finalized. No production code was changed. No new files were created.

---

## Files Changed

| File | Change |
|------|--------|
| `test/locker/models/biometric_state_test.dart` | Added 5 tests: `keyInvalidated` getter group (3 assertions) + `other values` regression group (2 assertions) |
| `test/security/biometric_cipher_provider_test.dart` | Added `isKeyValid` group with 2 tests verifying delegation and pass-through of `true` and `false` |
| `test/locker/mfa_locker_test.dart` | Added 3 tests to the existing `determineBiometricState` group: `keyInvalidated` when key is invalid, `enabled` when key is valid, and no `isKeyValid` call when no tag is passed |

---

## Key Decisions

### Tests are distributed by layer, not by symbol

Rather than grouping all Phase 13 tests in one file, each test file covers exactly the layer it owns: the enum file tests the enum, the provider test file tests the provider, and the `MFALocker` test file tests `MFALocker`. This is consistent with how Phase 6 tests were organized.

### `verify` is used on the `keyInvalidated` path, not on the `enabled` path

The test that confirms `isKeyValid → false` produces `keyInvalidated` includes `verify(...).called(1)` to confirm the delegation call. The companion test (`isKeyValid → true` produces `enabled`) asserts only the return value. This is intentional: the delegation contract is fully established by the first test; the second test focuses on return-value correctness for the happy path.

### `verifyNever` as the backwards-compatibility guarantee

Task 14.4 — the no-tag test — uses `verifyNever(() => secureProvider.isKeyValid(tag: any(named: 'tag')))`. This is the strongest possible assertion for backwards compatibility: it proves `isKeyValid` is never invoked when no tag is supplied, regardless of what the method returns. Mocktail's `MissingStubError` behavior for unstubbed methods also provides an implicit safety net here.

### Additional regression guard for `availableButDisabled`

The `biometric_state_test.dart` `other values` group includes a test for `BiometricState.availableButDisabled.isKeyInvalidated`. This goes beyond the four assertions in the tasklist minimum because `availableButDisabled` is the adjacent enum value most likely to be affected by a copy-paste error in the `isKeyInvalidated` getter.

### No mock changes required

`MockBiometricCipher` and `MockBiometricCipherProvider` are bare `extends Mock implements X` declarations. Mocktail auto-satisfies `isKeyValid` via `when()` without any `registerFallbackValue` registration. The Phase 6 mock infrastructure was sufficient without modification.

---

## How the Tests Work

### Task 14.1 — `BiometricState` enum (`biometric_state_test.dart`)

Pure synchronous assertions — no mocking. The file imports only `package:test/test.dart`. Tests confirm that `keyInvalidated` is excluded from both `isEnabled` and `isAvailable`, that `isKeyInvalidated` returns `true` for `keyInvalidated` and `false` for `enabled` and `availableButDisabled`.

### Task 14.2 — Provider delegation (`biometric_cipher_provider_test.dart`)

Uses `BiometricCipherProviderImpl.forTesting(mockCipher)` to inject a `MockBiometricCipher`. Two tests stub `isKeyValid(tag:)` on the mock and assert that the provider returns the stubbed value unchanged, confirming there is no result inversion or transformation in the delegation.

### Tasks 14.3 & 14.4 — `MFALocker.determineBiometricState` (`mfa_locker_test.dart`)

Both tests are added to the existing `determineBiometricState` group. The group's `setUp` already stubs `getTPMStatus → supported`, `getBiometryStatus → supported`, and `isBiometricEnabled → true`, providing the correct baseline (biometrics enabled in settings) for both tests. Task 14.3 adds a per-test stub of `isKeyValid → false` and passes `biometricKeyTag`; the test verifies the return value is `keyInvalidated` and calls `verify` to confirm delegation. Task 14.4 calls `determineBiometricState()` with no tag, expects `enabled`, and calls `verifyNever` on `isKeyValid`.

---

## Known Coverage Gaps (Carry-Forward)

Three gaps were identified during QA — all carried over from Phase 13. None represent implementation defects.

| ID | Gap | Risk |
|----|-----|------|
| NC-1 | No `verifyNever(isKeyValid)` when `biometricKeyTag` is provided but `isBiometricEnabled` returns `false`. A guard-order refactor that swapped the settings check and the key validity check would not be caught. | Low |
| NC-2 | No `verifyNever` assertions on existing early-exit hardware-path tests when called with a tag. Language-level control flow makes this a near-theoretical risk. | Very low |
| NC-3 | No test for `isKeyValid` throwing inside `determineBiometricState`. Exception propagation is a Dart language guarantee; no try-catch surrounds the call. | Low |

All three are suitable for a test-hardening follow-up. None block Phase 14 release.

---

## QA Result

QA status: **RELEASE**. All four tasks (14.1–14.4) implemented correctly. Every acceptance criterion satisfies. 10 new tests across three files; all green. No production code modified, no new files created, no mock infrastructure changes required.

---

## What Comes Next

- **Phase 15** (Example app: proactive detection integration) passes `biometricKeyTag` in the repository's `determineBiometricState` call and updates `LockerBloc` to handle `keyInvalidated` returned at init time. Phase 15 is already marked complete in the tasklist.
