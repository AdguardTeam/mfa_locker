# AW-2160-14: Locker — Unit Tests for Phase 13 Additions

Status: PRD_READY

## Context / Idea

This is Phase 14 of AW-2160. The ticket as a whole adds biometric key invalidation detection and a password-only teardown path across the full stack, plus proactive key validity detection at init time without triggering a biometric prompt.

**Phases 1–13 status (all complete):**
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

**The problem this phase solves:** Phase 13 added three new symbols across three files in `lib/`. These additions have no automated test coverage yet. Phase 14 adds that coverage across three existing test files, one test file per tested layer.

**Scope:** Pure unit tests only — additions to three existing test files within `test/`. No production code changes. No new files. No I/O or platform channel involvement.

**What is being tested (produced by Phase 13):**

| Symbol | File | What to verify |
|--------|------|----------------|
| `BiometricState.keyInvalidated` | `lib/locker/models/biometric_state.dart` | Value exists; `isKeyInvalidated`, `isEnabled`, `isAvailable` return correct booleans |
| `BiometricCipherProviderImpl.isKeyValid` | `lib/security/biometric_cipher_provider.dart` | Delegates to `BiometricCipher.isKeyValid` and passes return value through |
| `MFALocker.determineBiometricState(biometricKeyTag:)` | `lib/locker/mfa_locker.dart` | Returns `keyInvalidated` when `isKeyValid` returns `false`; skips check when tag is `null` |

**Test file mapping:**
```
test/
├── locker/
│   ├── models/
│   │   └── biometric_state_test.dart      # Task 14.1 — BiometricState enum
│   └── mfa_locker_test.dart               # Tasks 14.3, 14.4 — determineBiometricState
└── security/
    └── biometric_cipher_provider_test.dart # Task 14.2 — isKeyValid delegation
```

---

## Goals

1. Test that `BiometricState.keyInvalidated` exists as a distinct enum value and that all its boolean getters (`isKeyInvalidated`, `isEnabled`, `isAvailable`) return the correct values.
2. Test that `BiometricState.enabled.isKeyInvalidated` returns `false` as a regression guard against misclassification.
3. Test that `BiometricCipherProviderImpl.isKeyValid` correctly delegates to `BiometricCipher.isKeyValid` and passes the return value through unchanged for both `true` and `false`.
4. Test that `MFALocker.determineBiometricState(biometricKeyTag: tag)` calls `isKeyValid(tag: tag)` when biometrics are enabled in settings and returns `BiometricState.keyInvalidated` when `isKeyValid` returns `false`.
5. Test that `MFALocker.determineBiometricState()` called without `biometricKeyTag` never calls `isKeyValid` and returns `BiometricState.enabled` — confirming backwards compatibility.
6. Ensure `fvm flutter test` passes with all new tests green, no existing tests broken.

---

## User Stories

**US-1 — BiometricState enum is verifiably correct**
As a developer maintaining the `locker` library, I need automated tests to confirm that `BiometricState.keyInvalidated` has the correct getter values, so that any future refactoring of the enum or its getters is caught immediately by CI.

**US-2 — Provider delegation is verifiably correct**
As a developer maintaining the `locker` library, I need a unit test that verifies `BiometricCipherProviderImpl.isKeyValid` delegates to the underlying `BiometricCipher` plugin and passes the result through unmodified, so that the delegation contract cannot silently break.

**US-3 — Proactive detection logic is verifiably correct**
As a developer maintaining the `locker` library, I need unit tests that confirm `MFALocker.determineBiometricState` calls `isKeyValid` when a tag is supplied, returns `keyInvalidated` when the probe returns `false`, and never calls `isKeyValid` when no tag is passed, so that the proactive detection behavior and its backwards-compatibility guarantee are both captured in CI.

---

## Main Scenarios

### Scenario 1 (Task 14.1): `BiometricState.keyInvalidated` enum value and getters

1. `BiometricState.keyInvalidated.isKeyInvalidated` returns `true`.
2. `BiometricState.enabled.isKeyInvalidated` returns `false`.
3. `BiometricState.keyInvalidated.isEnabled` returns `false`.
4. `BiometricState.keyInvalidated.isAvailable` returns `false`.

All four assertions are pure enum evaluations — no mocking required.

### Scenario 2 (Task 14.2): `isKeyValid` delegation in `BiometricCipherProviderImpl`

1. A `MockBiometricCipher` is instantiated (already exists in `test/mocks/mock_biometric_cipher.dart`).
2. `when(() => mockBiometricCipher.isKeyValid(tag: any(named: 'tag'))).thenAnswer((_) async => true)` — stub returns `true`.
3. `await provider.isKeyValid(tag: 'biometric')` is called.
4. The result is `true` and `verify(() => mockBiometricCipher.isKeyValid(tag: 'biometric')).called(1)` passes.
5. Repeated with stub returning `false` to verify pass-through in the negative case.

### Scenario 3 (Task 14.3): `determineBiometricState` returns `keyInvalidated` when key is invalid

1. The existing `determineBiometricState` group `setUp` stubs: `getTPMStatus → supported`, `getBiometryStatus → supported`, `isBiometricEnabled → true`.
2. `isKeyValid(tag: any(named: 'tag'))` is stubbed to return `false`.
3. `await locker.determineBiometricState(biometricKeyTag: 'biometric')` is called.
4. The result equals `BiometricState.keyInvalidated`.
5. `verify(() => mockSecureProvider.isKeyValid(tag: 'biometric')).called(1)` passes.

### Scenario 4 (Task 14.4): `determineBiometricState()` without tag — no key validity check

1. The existing group `setUp` is reused (biometrics enabled in settings).
2. `await locker.determineBiometricState()` is called with no `biometricKeyTag`.
3. The result equals `BiometricState.enabled`.
4. `verifyNever(() => mockSecureProvider.isKeyValid(tag: any(named: 'tag')))` passes — `isKeyValid` is never invoked.

---

## Success / Metrics

| Criterion | How to verify |
|-----------|--------------|
| `BiometricState.keyInvalidated.isKeyInvalidated` returns `true` | Unit test in `biometric_state_test.dart` |
| `BiometricState.enabled.isKeyInvalidated` returns `false` | Unit test in `biometric_state_test.dart` |
| `BiometricState.keyInvalidated.isEnabled` returns `false` | Unit test in `biometric_state_test.dart` |
| `BiometricState.keyInvalidated.isAvailable` returns `false` | Unit test in `biometric_state_test.dart` |
| `BiometricCipherProviderImpl.isKeyValid` delegates to `BiometricCipher.isKeyValid` and passes `true` | Unit test in `biometric_cipher_provider_test.dart` |
| `BiometricCipherProviderImpl.isKeyValid` delegates to `BiometricCipher.isKeyValid` and passes `false` | Unit test in `biometric_cipher_provider_test.dart` |
| `determineBiometricState(biometricKeyTag: tag)` calls `isKeyValid(tag: tag)` when biometrics are enabled | Unit test in `mfa_locker_test.dart` (verify) |
| `determineBiometricState(biometricKeyTag: tag)` returns `BiometricState.keyInvalidated` when `isKeyValid` returns `false` | Unit test in `mfa_locker_test.dart` |
| `determineBiometricState()` without tag never calls `isKeyValid` | Unit test in `mfa_locker_test.dart` (verifyNever) |
| `determineBiometricState()` without tag returns `BiometricState.enabled` | Unit test in `mfa_locker_test.dart` |
| `fvm flutter test` passes | CI |
| `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` passes | CI |
| No new files created | Code review |
| No production code changed | Code review |

---

## Constraints and Assumptions

- **Test-only phase.** No changes to production code in `lib/` or `packages/`. All modifications are additions to three existing test files in `test/`.
- **No new files.** All test additions go into the three existing test files listed above.
- **Mocking via `mocktail`.** `MockBiometricCipher` and `MockBiometricCipherProvider` already exist in `test/mocks/`; no new mock declarations are required.
- **`MockBiometricCipherProvider` must expose `isKeyValid`.** The mock is generated via `mocktail`, so `isKeyValid` is available via `when()` without additional code — but the mock declaration file must include `isKeyValid` as a registered fallback value if `mocktail` requires it. Verify the mock file before adding stubs.
- **Task 14.3 and 14.4 reuse the existing group `setUp`.** The `determineBiometricState` group in `mfa_locker_test.dart` already stubs `getTPMStatus → supported`, `getBiometryStatus → supported`, and `isBiometricEnabled → true`. Tasks 14.3 and 14.4 add per-test stubs for `isKeyValid` on top of this baseline.
- **Phase 13 must be complete.** The three symbols under test (`BiometricState.keyInvalidated`, `BiometricCipherProviderImpl.isKeyValid`, updated `MFALocker.determineBiometricState`) must already exist in the codebase.
- **All tests are pure unit tests.** No I/O, no platform channel calls, no `flutter_test` widget test infrastructure needed — plain `dart:test` group/test structure.
- **Task ordering is flexible.** Tasks 14.1, 14.2, 14.3, 14.4 have no inter-task dependencies and can be done in any order.

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| `MockBiometricCipherProvider` in `test/mocks/` does not yet declare `isKeyValid` as a stubbed method (missing `registerFallbackValue` or similar) | Low — `mocktail` auto-generates stubs for all interface methods; the mock class only needs to extend the right abstract class | Medium — tests will fail at runtime with `MissingStubError` | Read the existing mock declaration before writing the test; add any required `registerFallbackValue` call in `setUpAll` if needed |
| `determineBiometricState` group `setUp` in `mfa_locker_test.dart` stubs `isBiometricEnabled` but the actual guard condition checks a different method or field name | Very low — Phase 13 was verified working; the test setup is consistent with the implementation | Medium — Task 14.3 test would incorrectly not reach the `isKeyValid` call | Review the existing `determineBiometricState` group setup in the test file before writing new test cases |
| New test cases inadvertently break existing tests in the same group via shared mutable state | Very low — `mocktail` mocks are reset per test if `setUp` is used correctly; no shared mutable state expected | Low | Follow the existing group `setUp` pattern; do not introduce shared state outside `setUp` |
| Task 14.1 enum tests are trivially simple and may seem unnecessary, but omitting them leaves the getters untested | N/A — coverage decision, not a technical risk | Low | Include all four assertions as specified; they serve as regression guards |

---

## Open Questions

None — the phase description (`docs/phase/AW-2160/phase-14.md`), vision doc (`docs/vision-2160.md`, Section 4), and Phase 13 PRD (`docs/prd/AW-2160-phase-13.prd.md`) provide sufficient detail to write all four test tasks without ambiguity. Mock infrastructure and test group structure are already established by Phase 6 and Phase 13 tests.
