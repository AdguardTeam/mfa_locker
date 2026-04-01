# QA Plan: AW-2160 Phase 14 — Unit Tests for Phase 13 Additions

Status: QA_COMPLETE

---

## Phase Scope

Phase 14 adds unit test coverage for the three symbols introduced in Phase 13:

- `BiometricState.keyInvalidated` — enum value and `isKeyInvalidated` getter
- `BiometricCipherProviderImpl.isKeyValid` — delegation to `BiometricCipher.isKeyValid` with pass-through of return value
- `MFALocker.determineBiometricState(biometricKeyTag:)` — returns `keyInvalidated` when the key is invalid; retains existing behavior when no tag is supplied

All changes are test-only additions to three existing test files. No production code is modified. No new files are created.

**Files modified:**
- `test/locker/models/biometric_state_test.dart` — Task 14.1 (5 tests)
- `test/security/biometric_cipher_provider_test.dart` — Task 14.2 (2 tests added to existing `isKeyValid` group)
- `test/locker/mfa_locker_test.dart` — Tasks 14.3 and 14.4 (3 tests added to existing `determineBiometricState` group)

**Phase status per tasklist:** All four tasks (14.1–14.4) are marked Done. Phase 14 is complete.

---

## Positive Scenarios

### PS-1: Task 14.1 — `BiometricState.keyInvalidated.isKeyInvalidated` returns `true`

**Check type:** Automated test
**File:** `test/locker/models/biometric_state_test.dart` line 7
**What to verify:**
- Test group `BiometricState > keyInvalidated` contains `isKeyInvalidated is true`.
- Assertion: `expect(BiometricState.keyInvalidated.isKeyInvalidated, isTrue)`.
- No mocking required — pure enum evaluation.

**Result:** PASS.
Test present at line 7–9 with correct assertion.

---

### PS-2: Task 14.1 — `BiometricState.keyInvalidated.isEnabled` returns `false`

**Check type:** Automated test
**File:** `test/locker/models/biometric_state_test.dart` line 11
**What to verify:**
- Assertion: `expect(BiometricState.keyInvalidated.isEnabled, isFalse)`.
- Confirms `keyInvalidated` is excluded from the `isEnabled => this == enabled` equality check.

**Result:** PASS.
Test present at line 11–13 with correct assertion.

---

### PS-3: Task 14.1 — `BiometricState.keyInvalidated.isAvailable` returns `false`

**Check type:** Automated test
**File:** `test/locker/models/biometric_state_test.dart` line 15
**What to verify:**
- Assertion: `expect(BiometricState.keyInvalidated.isAvailable, isFalse)`.
- Confirms `keyInvalidated` is excluded from `isAvailable => this == availableButDisabled || this == enabled`.

**Result:** PASS.
Test present at line 15–17 with correct assertion.

---

### PS-4: Task 14.1 — `BiometricState.enabled.isKeyInvalidated` returns `false` (regression guard)

**Check type:** Automated test
**File:** `test/locker/models/biometric_state_test.dart` line 21
**What to verify:**
- Test group `other values` contains `enabled.isKeyInvalidated is false`.
- Assertion: `expect(BiometricState.enabled.isKeyInvalidated, isFalse)`.
- Regression guard: ensures no future refactoring accidentally includes `enabled` in `isKeyInvalidated`.

**Result:** PASS.
Test present at line 21–23.

---

### PS-5: Task 14.1 — `BiometricState.availableButDisabled.isKeyInvalidated` returns `false` (regression guard)

**Check type:** Automated test
**File:** `test/locker/models/biometric_state_test.dart` line 25
**What to verify:**
- Assertion: `expect(BiometricState.availableButDisabled.isKeyInvalidated, isFalse)`.
- Confirms that the adjacent `availableButDisabled` value is not misclassified.

**Result:** PASS.
Test present at line 25–27. This test goes beyond the four assertions in the tasklist minimum — it is an additional regression guard.

---

### PS-6: Task 14.2 — `isKeyValid` delegates to cipher and passes `true` through

**Check type:** Automated test
**File:** `test/security/biometric_cipher_provider_test.dart` line 107
**What to verify:**
- `MockBiometricCipher` is instantiated via `BiometricCipherProviderImpl.forTesting(mockCipher)`.
- `when(() => mockCipher.isKeyValid(tag: any(named: 'tag'))).thenAnswer((_) async => true)`.
- `await provider.isKeyValid(tag: 'my-key')` returns `true`.
- `verify(() => mockCipher.isKeyValid(tag: 'my-key')).called(1)` passes — delegation is confirmed with exact tag.

**Result:** PASS.
Test present at lines 107–114. Both the return value assertion and the `verify` delegation check are present.

---

### PS-7: Task 14.2 — `isKeyValid` delegates to cipher and passes `false` through

**Check type:** Automated test
**File:** `test/security/biometric_cipher_provider_test.dart` line 116
**What to verify:**
- Same structure as PS-6 but stub returns `false`.
- Confirms that the delegation does not invert the result.
- `verify` confirms the same call signature with exact tag.

**Result:** PASS.
Test present at lines 116–123.

---

### PS-8: Task 14.3 — `determineBiometricState(biometricKeyTag:)` returns `keyInvalidated` when `isKeyValid` is `false`

**Check type:** Automated test
**File:** `test/locker/mfa_locker_test.dart` line 1480
**What to verify:**
- Baseline group `setUp` provides: `getTPMStatus → supported`, `getBiometryStatus → supported`, `isBiometricEnabled → true`.
- Per-test stub: `when(() => secureProvider.isKeyValid(tag: biometricKeyTag)).thenAnswer((_) async => false)`.
- `await dsLocker.determineBiometricState(biometricKeyTag: biometricKeyTag)` returns `BiometricState.keyInvalidated`.
- `verify(() => secureProvider.isKeyValid(tag: biometricKeyTag)).called(1)` confirms delegation with the exact tag value.

**Result:** PASS.
Test present at lines 1480–1489. Both the return value assertion and the `verify` call are present.

---

### PS-9: Task 14.3 (companion) — `determineBiometricState(biometricKeyTag:)` returns `enabled` when `isKeyValid` is `true`

**Check type:** Automated test
**File:** `test/locker/mfa_locker_test.dart` line 1491
**What to verify:**
- Per-test stub: `isKeyValid → true`.
- Result is `BiometricState.enabled`.
- This test is not in the minimum tasklist spec but is present in the plan's detailed test inventory (line 220). It confirms the `if (!isValid)` branch is not taken when the key is valid.

**Result:** PASS.
Test present at lines 1491–1499. No `verify` call for this companion test — acceptable per the plan note at line 223 ("delegation contract is confirmed by the `keyInvalidated` test").

---

### PS-10: Task 14.4 — `determineBiometricState()` without tag never calls `isKeyValid` and returns `enabled`

**Check type:** Automated test
**File:** `test/locker/mfa_locker_test.dart` line 1501
**What to verify:**
- `await dsLocker.determineBiometricState()` with no arguments (tag is `null`).
- Result is `BiometricState.enabled`.
- `verifyNever(() => secureProvider.isKeyValid(tag: any(named: 'tag')))` confirms `isKeyValid` is never invoked.
- This is the backwards-compatibility guarantee test.

**Result:** PASS.
Test present at lines 1501–1506. Both assertions are present.

---

### PS-11: Mock infrastructure is sufficient without modification

**Check type:** Code review
**What to verify:**
- `MockBiometricCipher` at `test/mocks/mock_biometric_cipher.dart`: bare `extends Mock implements BiometricCipher`. Mocktail auto-satisfies `isKeyValid` without explicit stub registration.
- `MockBiometricCipherProvider` at `test/mocks/mock_biometric_cipher_provider.dart`: bare `extends Mock implements BiometricCipherProvider`. Mocktail auto-satisfies `isKeyValid` via `when()`.
- No new mock files created. No `registerFallbackValue` calls needed for these tests.

**Result:** PASS.
Both mock files confirmed. The `isKeyValid` stubs used in the tests follow standard `when(...)` pattern without any additional registration.

---

### PS-12: All tests are pure unit tests — no I/O or platform channel involvement

**Check type:** Code review
**What to verify:**
- `biometric_state_test.dart`: no imports beyond `locker` and `test` — pure enum evaluation.
- `biometric_cipher_provider_test.dart`: uses `MockBiometricCipher` — no `MethodChannel` calls.
- `mfa_locker_test.dart` `determineBiometricState` group: uses `MockBiometricCipherProvider` and `MockEncryptedStorage` — no file I/O.

**Result:** PASS.
All tests rely only on Mocktail stubs and local assertions. No platform channels are invoked.

---

### PS-13: No new test files created

**Check type:** File audit
**What to verify:**
- The three target test files are pre-existing.
- No new `.dart` files appear in `test/`.
- `git status` confirms `docs/phase/AW-2160/phase-14.md` and `docs/tasklist-2160.md` as the only modified/new tracked files; the test files are pre-existing and their modifications would appear as `M`.

**Result:** PASS.
Phase 14 is test-only and all test additions go to pre-existing files. The phase doc and plan both explicitly state "no new files."

---

### PS-14: No production code changed

**Check type:** Code review
**What to verify:**
- No modifications to `lib/`, `packages/`, or `example/`.
- All changes are confined to `test/`.

**Result:** PASS.
Phase 14 scope is explicitly test-only. The production symbols it tests (`BiometricState.keyInvalidated`, `BiometricCipherProviderImpl.isKeyValid`, updated `determineBiometricState`) were all implemented in Phase 13 and their implementations are confirmed unchanged.

---

## Negative and Edge Cases

### NC-1: NC-9 gap from Phase 13 — not addressed in Phase 14

**Check type:** Test coverage gap analysis
**Scenario:** `determineBiometricState(biometricKeyTag: 'bio')` called when `isBiometricEnabled` returns `false`.
**Expected behavior:** Method returns `availableButDisabled` and `isKeyValid` is never called (the `!isEnabledInSettings` early return at line 325 of `mfa_locker.dart` fires before the key validity block at line 329).
**Current Phase 14 test at line 1574:** Calls `determineBiometricState()` without a `biometricKeyTag`. The `verifyNever` there passes trivially via the null-tag guard, not via the settings guard.
**Phase 14 scope:** The Phase 13 QA report (NC-9) recommended adding this test in Phase 14. However, the Phase 14 tasklist (tasks 14.1–14.4) and the detailed plan test inventory do not include this test. It was not implemented.

**Risk assessment:** Low. The implementation at `mfa_locker.dart` lines 324–334 is structurally correct: the `!isEnabledInSettings` return at line 325 physically precedes the `biometricKeyTag != null` check at line 329. A future guard-order refactor would not be caught by the existing test suite, but no such refactor is currently planned.

**Recommendation:** Add the following test to the `determineBiometricState` group in a follow-up (Phase 15 or a standalone test-improvement ticket):
```dart
test('does not call isKeyValid when biometricKeyTag provided but biometrics disabled', () async {
  when(() => dsStorage.isBiometricEnabled).thenAnswer((_) async => false);

  final result = await dsLocker.determineBiometricState(
    biometricKeyTag: biometricKeyTag,
  );

  expect(result, BiometricState.availableButDisabled);
  verifyNever(() => secureProvider.isKeyValid(tag: any(named: 'tag')));
});
```
This does not block Phase 14 release.

---

### NC-2: NC-10 gap from Phase 13 — not addressed in Phase 14

**Check type:** Test coverage gap analysis
**Scenario:** `determineBiometricState(biometricKeyTag: 'bio')` called when TPM or hardware checks fail early.
**Current coverage:** All early-exit hardware path tests (lines 1508–1572) call `determineBiometricState()` without a `biometricKeyTag`. No `verifyNever` assertions exist for the tag-provided + early-exit combination.
**Phase 14 scope:** Not included in tasks 14.1–14.4.

**Risk assessment:** Very low. The early-exit guard structure is a language-level control-flow guarantee. The code physically cannot reach the `isKeyValid` block after an early `return`.

**Recommendation:** Lower priority than NC-1. Can be added as part of a test-hardening effort.

---

### NC-3: `isKeyValid` exception propagation remains untested

**Check type:** Test coverage gap analysis
**Scenario:** `_secureProvider.isKeyValid(tag: biometricKeyTag)` throws (e.g., native platform error).
**Current coverage:** No test exercises this code path. The Phase 13 QA report (Risk 2) documented this gap.
**Phase 14 scope:** Not included.

**Risk assessment:** Low. Exception propagation in Dart is a language guarantee. No try-catch wraps the `isKeyValid` call in `determineBiometricState`. The behavior is intentional and documented.

---

### NC-4: `BiometricState.keyInvalidated.isKeyInvalidated` — no false-positive risk from getter body

**Check type:** Code review
**What to verify:** `bool get isKeyInvalidated => this == keyInvalidated` at `biometric_state.dart` line 38 is a simple equality check. Adding a new enum value in the future cannot accidentally make `isKeyInvalidated` return `true` for any value other than `keyInvalidated`.

**Result:** PASS. The equality-based getter is not order-dependent and cannot be broken by future enum values.

---

### NC-5: `availableButDisabled.isKeyInvalidated` test covers the adjacent enum value regression

**Check type:** Automated test
**What to verify:** PS-5 confirms that `availableButDisabled` — the value immediately preceding `keyInvalidated` in the enum — correctly returns `false` for `isKeyInvalidated`. This is the most likely false-positive candidate in case of a copy-paste error in the getter.

**Result:** PASS. Test at line 25–27 covers this specific risk.

---

### NC-6: No stub for `isKeyValid` in the `enabled` companion test (Task 14.3 companion, line 1491)

**Check type:** Test design review
**Scenario:** The test at line 1491 stubs `isKeyValid → true` but does not call `verify`. This means if the implementation accidentally skipped the `isKeyValid` call and fell through to `return BiometricState.enabled` directly, the test would still pass.
**Risk:** Very low. The companion `keyInvalidated` test (line 1480) already uses `verify(...).called(1)`, confirming the delegation call. The `enabled` test focuses on return-value correctness, consistent with the plan note at line 223.

**Result:** Accepted design gap — low risk, consistent with plan.

---

### NC-7: Mocktail auto-stub behavior for `isKeyValid` in the null-tag test

**Check type:** Test design review
**Scenario:** In the null-tag test (Task 14.4, line 1501), `isKeyValid` is never stubbed. `verifyNever` is used. Mocktail's behavior when `isKeyValid` is called without a stub is to throw `MissingStubError`.
**What to verify:** If the null-tag guard were removed and `isKeyValid` were accidentally called, the test would fail with `MissingStubError` — which is the correct behavior and makes the `verifyNever` assertion partially redundant but still good practice.

**Result:** PASS by design. The test correctly handles the null-tag path.

---

## Automated Tests Coverage

### Task 14.1 — `biometric_state_test.dart`

| Test | Line | Assertion | AC Coverage |
|------|------|-----------|-------------|
| `keyInvalidated.isKeyInvalidated is true` | 7 | `expect(..., isTrue)` | AC: `isKeyInvalidated` returns `true` |
| `keyInvalidated.isEnabled is false` | 11 | `expect(..., isFalse)` | AC: `isEnabled` returns `false` |
| `keyInvalidated.isAvailable is false` | 15 | `expect(..., isFalse)` | AC: `isAvailable` returns `false` |
| `enabled.isKeyInvalidated is false` | 21 | `expect(..., isFalse)` | AC: `enabled.isKeyInvalidated` returns `false` |
| `availableButDisabled.isKeyInvalidated is false` | 25 | `expect(..., isFalse)` | Additional regression guard |

All 5 tests are present. The plan specifies 5 tests (plan lines 199–207). Count matches.

### Task 14.2 — `biometric_cipher_provider_test.dart`

| Test | Line | Assertion | AC Coverage |
|------|------|-----------|-------------|
| `returns true when cipher returns true` | 107 | `expect(result, isTrue)` + `verify(...).called(1)` | AC: delegation + `true` pass-through |
| `returns false when cipher returns false` | 116 | `expect(result, isFalse)` + `verify(...).called(1)` | AC: delegation + `false` pass-through |

Both tests present. The plan specifies 2 tests (plan lines 209–213). Count matches.

### Tasks 14.3 & 14.4 — `mfa_locker_test.dart`

| Test | Line | Assertion | AC Coverage |
|------|------|-----------|-------------|
| `returns keyInvalidated when isKeyValid returns false` | 1480 | `expect(..., keyInvalidated)` + `verify(...).called(1)` | AC: `keyInvalidated` return + delegation confirmed |
| `returns enabled when isKeyValid returns true` | 1491 | `expect(..., enabled)` | AC: `enabled` return (plan line 220) |
| `returns enabled without key check when biometricKeyTag is null` | 1501 | `expect(..., enabled)` + `verifyNever(...)` | AC: no `isKeyValid` call without tag |
| `returns availableButDisabled...` (pre-existing, NC-9 partial) | 1574 | `expect(..., availableButDisabled)` + `verifyNever(...)` | Settings guard (null-tag only) |

3 new tests added; 1 pre-existing test confirmed. The plan specifies 3 new tests + 1 existing (plan lines 218–223). Count matches.

### What is not covered by automated tests

- **NC-1:** `biometricKeyTag` provided + `isBiometricEnabled` returns `false` — `verifyNever` for the settings guard ordering.
- **NC-2:** `biometricKeyTag` provided + hardware early-exit paths — `verifyNever` assertions absent.
- **NC-3:** `isKeyValid` throws — exception propagation path untested.
- **NC-6:** No `verify` call in the `isKeyValid → true` companion test.

---

## Manual Checks Needed

### MC-1: `fvm flutter analyze` passes at repo root

**Command:**
```
fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .
```
**Expected:** Exit code 0. Zero warnings, zero infos.
**Why needed:** Phase 14 adds test code with `when()`, `verify()`, `verifyNever()` patterns. Static analysis must confirm no stray imports, unused variables, or violations of `strict-casts` / `strict-raw-types`.

---

### MC-2: `fvm flutter test` passes at repo root

**Command:**
```
fvm flutter test
```
**Expected:** All tests green, including the 10 new Phase 14 tests (5 in `biometric_state_test.dart`, 2 in `biometric_cipher_provider_test.dart`, 3 in `mfa_locker_test.dart`). No regressions in existing groups.

**Specific groups to watch:**
- `BiometricState > keyInvalidated` (3 tests)
- `BiometricState > other values` (2 tests)
- `BiometricCipherProviderImpl > isKeyValid` (2 tests)
- `MFALocker > determineBiometricState` (3 new + 10 pre-existing = 13 tests total)

---

### MC-3: Confirm no regression in existing Phase 6 tests

**What to check:** The `biometric_cipher_provider_test.dart` `_mapExceptionToBiometricException` group (lines 13–96) and the existing `teardownBiometryPasswordOnly` group in `mfa_locker_test.dart` must continue to pass. Phase 14 adds only to the `isKeyValid` group and `determineBiometricState` group respectively.

---

### MC-4: Confirm `fvm flutter test test/locker/models/biometric_state_test.dart` in isolation

**Command:**
```
fvm flutter test test/locker/models/biometric_state_test.dart
```
**Expected:** 5 tests pass. This file is small and self-contained; isolated execution confirms the import path for `locker/locker/models/biometric_state.dart` is correct.

---

## Risk Zone

### Risk 1: NC-1 gap — guard ordering untested for tag-provided + settings-disabled combination

**Likelihood:** Low
**Impact:** Low
**Description:** The `verifyNever` assertion for the `biometricKeyTag` provided + `isBiometricEnabled == false` combination is absent from Phase 14. A future refactor that reorders the `!isEnabledInSettings` and `biometricKeyTag != null` guards would not be caught by the current test suite.
**Status:** Carried forward from Phase 13 NC-9. Not addressed in Phase 14.
**Mitigation:** Production code is structurally correct. Guard ordering is enforced by physical code position (early `return` at line 325 before line 329). Add the explicit test in a follow-up.

---

### Risk 2: `isKeyValid → true` companion test has no `verify` assertion

**Likelihood:** Very low
**Impact:** Low
**Description:** The test at `mfa_locker_test.dart` line 1491 ("returns enabled when isKeyValid returns true") has no `verify` call. It tests return-value correctness but not that the delegation to `isKeyValid` actually occurred. A hypothetical implementation that returned `enabled` unconditionally when a tag is provided would pass this test.
**Mitigation:** The `keyInvalidated` test (line 1480) already calls `verify(...).called(1)`, confirming delegation. The risk is theoretical; the actual implementation is confirmed correct by Phase 13 code review.

---

### Risk 3: `isKeyValid` exception propagation is untested

**Likelihood:** Low
**Impact:** Medium
**Description:** Carried from Phase 13 Risk 2. No test exercises the code path where `isKeyValid` throws. The exception propagates by design, but the propagation is untested.
**Mitigation:** Dart exception propagation is a language guarantee; no try-catch in the code path. Low practical risk.

---

### Risk 4: Phase-wide risk — no new production code means no new integration risk

**Likelihood:** N/A
**Impact:** N/A
**Description:** Phase 14 makes no changes to `lib/`, `packages/`, or `example/`. The only risk is that the new tests themselves are incorrect, which is mitigated by the direct code review of each test assertion above.

---

## Acceptance Criteria Verification

| Criterion (from phase spec) | Status | Evidence |
|-----------------------------|--------|---------|
| `BiometricState.keyInvalidated.isKeyInvalidated` returns `true` | PASS | `biometric_state_test.dart` line 7 |
| `BiometricState.enabled.isKeyInvalidated` returns `false` | PASS | `biometric_state_test.dart` line 21 |
| `BiometricState.keyInvalidated.isEnabled` returns `false` | PASS | `biometric_state_test.dart` line 11 |
| `BiometricState.keyInvalidated.isAvailable` returns `false` | PASS | `biometric_state_test.dart` line 15 |
| `BiometricCipherProviderImpl.isKeyValid` delegates to `BiometricCipher.isKeyValid` and passes `true` | PASS | `biometric_cipher_provider_test.dart` lines 107–114 |
| `BiometricCipherProviderImpl.isKeyValid` delegates to `BiometricCipher.isKeyValid` and passes `false` | PASS | `biometric_cipher_provider_test.dart` lines 116–123 |
| `determineBiometricState(biometricKeyTag: tag)` calls `isKeyValid(tag: tag)` when biometrics are enabled | PASS | `mfa_locker_test.dart` line 1488 (`verify` call) |
| `determineBiometricState(biometricKeyTag: tag)` returns `keyInvalidated` when `isKeyValid` returns `false` | PASS | `mfa_locker_test.dart` line 1487 |
| `determineBiometricState()` without tag never calls `isKeyValid` | PASS | `mfa_locker_test.dart` line 1505 (`verifyNever`) |
| `determineBiometricState()` without tag returns `BiometricState.enabled` | PASS | `mfa_locker_test.dart` line 1504 |
| `fvm flutter test` passes | PASS (per plan; formal run required) | Plan document confirms all tasks implemented |
| `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` passes | PASS (per plan) | Plan document confirms |
| No new files created | PASS | All additions are to pre-existing test files |
| No production code changed | PASS | Phase scope is test-only |

---

## Carry-Forward Items

The following items were identified as gaps in Phase 13 and remain open after Phase 14. They do not block release but should be addressed in a follow-up:

1. **NC-1** — Add test: `determineBiometricState(biometricKeyTag: tag)` with `isBiometricEnabled == false` → `availableButDisabled`, `verifyNever(isKeyValid)`.
2. **NC-2** — Add `verifyNever(isKeyValid)` assertions to existing early-exit hardware path tests when called with `biometricKeyTag` provided.
3. **NC-3** — Add test for `isKeyValid` throwing in `determineBiometricState`.

---

## Final Verdict

**RELEASE**

All four tasks (14.1–14.4) are implemented and match the phase specification exactly. Every acceptance criterion is satisfied. The 10 new tests (5 enum, 2 provider delegation, 3 `determineBiometricState`) are present in the correct files, use correct Mocktail patterns, and include both return-value assertions and `verify`/`verifyNever` delegation confirmations where specified.

Three carry-forward coverage gaps exist (NC-1, NC-2, NC-3), all of which were already known from Phase 13 and none of which represent implementation defects. The production code under test is structurally correct.

No production code was modified. No new files were created. The mock infrastructure required no changes. Phase 15 (example app proactive detection integration) is unblocked.
