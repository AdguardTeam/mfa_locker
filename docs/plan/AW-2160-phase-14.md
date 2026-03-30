# Plan: AW-2160 Phase 14 -- Unit Tests for Phase 13 Additions

Status: PLAN_APPROVED

## Phase Scope

Phase 14 adds unit test coverage for the three symbols introduced in Phase 13:

1. `BiometricState.keyInvalidated` -- enum value and `isKeyInvalidated` getter verification.
2. `BiometricCipherProviderImpl.isKeyValid` -- delegation to `BiometricCipher.isKeyValid` with pass-through of return value.
3. `MFALocker.determineBiometricState(biometricKeyTag:)` -- returns `keyInvalidated` when the key is invalid; retains existing behavior when no tag is supplied.

All changes are test-only additions to three existing test files. No production code is modified. No new files are created.

### Critical Finding: Implementation Already Complete

Both the research document and the tasklist confirm that all four tasks (14.1 through 14.4) are already implemented and passing. The test code is present in the three target files. The remaining work for this phase is:

1. Verify that `fvm flutter analyze` and `fvm flutter test` pass cleanly.
2. Confirm the tasklist marks Phase 14 as done (it does).

---

## Components

| Component | File | Change | Status |
|-----------|------|--------|--------|
| `BiometricState` enum tests | `test/locker/models/biometric_state_test.dart` | + `keyInvalidated` group (3 tests) + `other values` group (2 tests) | Already implemented |
| `isKeyValid` delegation tests | `test/security/biometric_cipher_provider_test.dart` | + `isKeyValid` group (2 tests: `true` pass-through, `false` pass-through) | Already implemented |
| `determineBiometricState` key validity tests | `test/locker/mfa_locker_test.dart` | + 3 tests in existing `determineBiometricState` group: `keyInvalidated` when false, `enabled` when true, `enabled` without tag (verifyNever) | Already implemented |

### Test File Mapping

```
test/
+-- locker/
|   +-- models/
|   |   +-- biometric_state_test.dart      # Task 14.1 -- BiometricState enum
|   +-- mfa_locker_test.dart               # Tasks 14.3, 14.4 -- determineBiometricState
+-- security/
    +-- biometric_cipher_provider_test.dart # Task 14.2 -- isKeyValid delegation
```

### Mock Dependencies (all pre-existing from Phase 6)

| Mock | File | Used By |
|------|------|---------|
| `MockBiometricCipher` | `test/mocks/mock_biometric_cipher.dart` | Task 14.2 |
| `MockBiometricCipherProvider` | `test/mocks/mock_biometric_cipher_provider.dart` | Tasks 14.3, 14.4 |
| `MockEncryptedStorage` | `test/mocks/mock_encrypted_storage.dart` | Tasks 14.3, 14.4 (via group setUp) |

---

## API Contract

No production API changes. Phase 14 is test-only.

### Tested Contracts

**BiometricState enum (tested in Task 14.1):**
```dart
BiometricState.keyInvalidated.isKeyInvalidated == true
BiometricState.keyInvalidated.isEnabled == false
BiometricState.keyInvalidated.isAvailable == false
BiometricState.enabled.isKeyInvalidated == false
BiometricState.availableButDisabled.isKeyInvalidated == false
```

**BiometricCipherProviderImpl.isKeyValid (tested in Task 14.2):**
```dart
// Delegates to BiometricCipher.isKeyValid and passes return value through
provider.isKeyValid(tag: 'my-key') == mockCipher.isKeyValid(tag: 'my-key')
```

**MFALocker.determineBiometricState (tested in Tasks 14.3, 14.4):**
```dart
// When biometrics enabled and key invalid:
determineBiometricState(biometricKeyTag: tag) == BiometricState.keyInvalidated
// When biometrics enabled and key valid:
determineBiometricState(biometricKeyTag: tag) == BiometricState.enabled
// When no tag supplied (backwards compat):
determineBiometricState() == BiometricState.enabled  // isKeyValid never called
```

---

## Data Flows

No production data flow changes. Test data flows are:

### Task 14.1 -- Pure enum evaluation
```
BiometricState.keyInvalidated --> getter calls --> boolean assertions
```
No mocking needed. Synchronous.

### Task 14.2 -- Provider delegation
```
MockBiometricCipher.isKeyValid(tag: 'my-key') --> stubbed return (true/false)
  |
  v
BiometricCipherProviderImpl.isKeyValid(tag: 'my-key')
  --> delegates to _biometricCipher.isKeyValid(tag: 'my-key')
  --> returns stubbed value unchanged
  |
  v
Test asserts: result matches stub, verify confirms delegation call
```

### Tasks 14.3 & 14.4 -- MFALocker determineBiometricState
```
Group setUp baseline stubs:
  secureProvider.getTPMStatus() --> supported
  secureProvider.getBiometryStatus() --> supported
  dsStorage.isBiometricEnabled --> true

Task 14.3 (key invalid):
  secureProvider.isKeyValid(tag: biometricKeyTag) --> false
  dsLocker.determineBiometricState(biometricKeyTag: tag)
    --> checks TPM, biometry, settings (all pass)
    --> calls isKeyValid(tag) --> false
    --> returns BiometricState.keyInvalidated

Task 14.3 (key valid):
  secureProvider.isKeyValid(tag: biometricKeyTag) --> true
  dsLocker.determineBiometricState(biometricKeyTag: tag)
    --> returns BiometricState.enabled

Task 14.4 (no tag):
  dsLocker.determineBiometricState()  // no biometricKeyTag
    --> returns BiometricState.enabled
    --> verifyNever: isKeyValid never called
```

---

## NFR

| Requirement | How Met |
|-------------|---------|
| No production code changes | All modifications are in `test/` directory only |
| No new files | Tests added to three existing test files |
| Uses `mocktail` | Consistent with project's testing infrastructure |
| Code style compliance | 120-char line length, single quotes, trailing commas |
| All existing tests unbroken | New tests are purely additive to existing groups |
| Static analysis passes | `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` must exit 0 |
| `fvm flutter test` passes | All new and existing tests green |

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| `MockBiometricCipherProvider` missing `isKeyValid` stub | Very low -- `mocktail` auto-generates stubs for all interface methods | Medium -- `MissingStubError` at runtime | Verified in research: mock class is bare `extends Mock implements BiometricCipherProvider`; `when()` stubs are sufficient |
| `determineBiometricState` group `setUp` stubs don't match implementation guard conditions | Very low -- Phase 13 implementation verified | Medium -- test would silently not reach `isKeyValid` call | Existing baseline stubs confirmed correct: `getTPMStatus -> supported`, `getBiometryStatus -> supported`, `isBiometricEnabled -> true` |
| Shared mutable state between tests in same group | Very low -- `setUp` reinitializes all mocks per test | Low -- flaky test failures | Each test uses per-test `when()` stubs on freshly initialized mocks |
| `returns enabled when isKeyValid returns true` test does not call `verify` | N/A -- design choice | Low -- companion test at line 1480 calls `verify` on same delegation | Delegation contract is confirmed by the `keyInvalidated` test; the `enabled` test focuses on return value correctness |

---

## Dependencies

### On Previous Phases

| Phase | Dependency | Status |
|-------|-----------|--------|
| Phase 13 | `BiometricState.keyInvalidated` enum value + `isKeyInvalidated` getter | Complete |
| Phase 13 | `BiometricCipherProviderImpl.isKeyValid` delegation method | Complete |
| Phase 13 | `MFALocker.determineBiometricState` `biometricKeyTag` parameter + key validity check | Complete |
| Phase 6 | `MockBiometricCipher`, `MockBiometricCipherProvider` mock declarations | Complete |
| Phase 6 | `BiometricCipherProviderImpl.forTesting` constructor | Complete |
| Phase 6 | `MFALocker` injectable `secureProvider` constructor parameter | Complete |

### Task Ordering

Tasks 14.1, 14.2, 14.3, and 14.4 have no inter-task dependencies. They can be implemented in any order.

### Forward Dependencies

Phase 15 (example app integration) depends on Phase 13 production code, not on Phase 14 tests. Phase 14 has no forward dependents.

---

## Implementation Approach

Given that all code is already present in the codebase:

1. **Verify** -- Run `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` and `fvm flutter test` at the root to confirm everything passes.
2. **Confirm tasklist** -- Verify `docs/tasklist-2160.md` marks Phase 14 as done (confirmed: it does).
3. **No code changes needed** -- All four tasks are implemented and match the spec.

If verification reveals failures, investigate and fix. Otherwise, the phase is complete.

---

## Detailed Test Inventory (for verification)

### Task 14.1 -- `biometric_state_test.dart`

| Test Description | Assertion |
|-----------------|-----------|
| `keyInvalidated` / `isKeyInvalidated is true` | `BiometricState.keyInvalidated.isKeyInvalidated` is `true` |
| `keyInvalidated` / `isEnabled is false` | `BiometricState.keyInvalidated.isEnabled` is `false` |
| `keyInvalidated` / `isAvailable is false` | `BiometricState.keyInvalidated.isAvailable` is `false` |
| `other values` / `enabled.isKeyInvalidated is false` | `BiometricState.enabled.isKeyInvalidated` is `false` |
| `other values` / `availableButDisabled.isKeyInvalidated is false` | `BiometricState.availableButDisabled.isKeyInvalidated` is `false` |

### Task 14.2 -- `biometric_cipher_provider_test.dart`

| Test Description | Assertion |
|-----------------|-----------|
| `isKeyValid` / `returns true when cipher returns true` | Result is `true`; `verify` confirms `isKeyValid(tag: 'my-key')` called once |
| `isKeyValid` / `returns false when cipher returns false` | Result is `false`; `verify` confirms `isKeyValid(tag: 'my-key')` called once |

### Tasks 14.3 & 14.4 -- `mfa_locker_test.dart`

| Test Description | Assertion |
|-----------------|-----------|
| `returns keyInvalidated when isKeyValid returns false` | Result is `BiometricState.keyInvalidated`; `verify` confirms `isKeyValid(tag: biometricKeyTag)` called once |
| `returns enabled when isKeyValid returns true` | Result is `BiometricState.enabled` |
| `returns enabled without key check when biometricKeyTag is null` | Result is `BiometricState.enabled`; `verifyNever` confirms `isKeyValid` not called |
| `returns availableButDisabled...` (existing, regression guard) | `verifyNever` on `isKeyValid` -- key check skipped before the enabled gate |

---

## Open Questions

None.
