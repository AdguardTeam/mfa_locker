# AW-2160-6: Locker: Unit Tests for Biometric Key Invalidation and Password-Only Teardown

Status: PRD_READY

## Context / Idea

This is Phase 6 of AW-2160. The ticket as a whole adds biometric key invalidation detection and a password-only teardown path across the full stack. Phase 6 is the final phase and adds explicit unit test coverage for all new Dart-layer code paths introduced in Phases 3–5.

**Phases 1–5 status (all complete):**
- Phase 1: Android native emits `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")` for `KeyPermanentlyInvalidatedException`.
- Phase 2: iOS/macOS native emits `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")` when the Secure Enclave key is inaccessible after a biometric enrollment change.
- Phase 3: Dart plugin adds `BiometricCipherExceptionCode.keyPermanentlyInvalidated` and maps `'KEY_PERMANENTLY_INVALIDATED'` string → that enum value via `fromString`.
- Phase 4: Locker library adds `BiometricExceptionType.keyInvalidated` and maps `BiometricCipherExceptionCode.keyPermanentlyInvalidated` → `BiometricExceptionType.keyInvalidated` in `BiometricCipherProviderImpl._mapExceptionToBiometricException`.
- Phase 5: `Locker.teardownBiometryPasswordOnly` interface and `MFALocker.teardownBiometryPasswordOnly` implementation are complete. The method removes the `Origin.bio` wrap using password auth only and suppresses errors from `_secureProvider.deleteKey`.

**The problem this phase solves:** Phases 1–5 were verified through analyze passes and the existing test suite. No new tests were written for the new enum values, the new exception mapping, or `teardownBiometryPasswordOnly`. Without dedicated tests, future regressions (e.g., an accidental removal of the `keyPermanentlyInvalidated` mapping, a change to error suppression logic) would not be caught automatically.

**Scope:** Near-pure test additions — no production logic changes. Four test groups across two test files and one `biometric_cipher` package test file. The only production code change permitted is adding a `@visibleForTesting` injectable `secureProvider` constructor parameter to `MFALocker` to enable Task 6.3b.

**Test file locations (from phase-6.md):**
- `packages/biometric_cipher/test/biometric_cipher_test.dart` — Task 6.1: `BiometricCipherExceptionCode.fromString` (added to existing file)
- `test/security/biometric_cipher_provider_test.dart` — Tasks 6.2 and 6.4: `_mapExceptionToBiometricException` plus regression mappings
- `test/locker/mfa_locker_test.dart` — Task 6.3: `teardownBiometryPasswordOnly`

Note: `test/security/biometric_cipher_provider_test.dart` does not exist yet; it must be created. `BiometricCipherProviderImpl.forTesting(biometricCipher)` constructor is already present for this purpose.

---

## Goals

1. Test that `BiometricCipherExceptionCode.fromString('KEY_PERMANENTLY_INVALIDATED')` returns `BiometricCipherExceptionCode.keyPermanentlyInvalidated` (Task 6.1).
2. Test that `BiometricCipherProviderImpl._mapExceptionToBiometricException` maps a `BiometricCipherException` with code `keyPermanentlyInvalidated` to `BiometricException(BiometricExceptionType.keyInvalidated)` (Task 6.2).
3. Test `MFALocker.teardownBiometryPasswordOnly` across three cases: happy path, `deleteKey` throws (suppressed), and locked-state unlock via password auth (Task 6.3).
4. Verify that existing exception mappings (`authenticationError` → `failure`, `authenticationUserCanceled` → `cancel`) are unchanged after the new mapping line was inserted (Task 6.4 regression).

---

## User Stories

**US-1 — Automated detection of `fromString` regression**
As a developer, I need a unit test that asserts `BiometricCipherExceptionCode.fromString('KEY_PERMANENTLY_INVALIDATED')` returns the correct enum value, so that if this mapping is accidentally removed or reassigned, the test suite fails immediately.

**US-2 — Automated detection of provider mapping regression**
As a developer, I need a unit test that asserts `BiometricCipherProviderImpl` translates `keyPermanentlyInvalidated` cipher code to `BiometricExceptionType.keyInvalidated`, so that the end-to-end exception type chain from native platform to app layer is protected against silent regressions.

**US-3 — `teardownBiometryPasswordOnly` behavior is formally specified via tests**
As a developer, I need unit tests for all three `teardownBiometryPasswordOnly` branches (success, suppressed key deletion error, and locked-state unlock), so that the contract for this method is machine-enforced rather than only documented.

**US-4 — Existing exception mappings cannot silently regress**
As a developer, I need regression tests for `authenticationError` → `failure` and `authenticationUserCanceled` → `cancel`, so that adding the new `keyPermanentlyInvalidated` branch cannot inadvertently break those existing mappings.

---

## Main Scenarios

### Scenario 1: `BiometricCipherExceptionCode.fromString` — correct mapping (Task 6.1)

1. Call `BiometricCipherExceptionCode.fromString('KEY_PERMANENTLY_INVALIDATED')`.
2. Assert the result equals `BiometricCipherExceptionCode.keyPermanentlyInvalidated`.

**Placement:** Added as a new test case inside the existing `biometric_cipher_test.dart` file — consolidated approach, no new file created.

### Scenario 2: Provider maps `keyPermanentlyInvalidated` → `keyInvalidated` (Task 6.2)

1. Create `BiometricCipherProviderImpl.forTesting(mockBiometricCipher)`.
2. Configure `mockBiometricCipher.decrypt` to throw `BiometricCipherException(code: BiometricCipherExceptionCode.keyPermanentlyInvalidated)`.
3. Call `provider.decrypt(tag: 'tag', data: someData)`.
4. Assert it throws `BiometricException` with `type == BiometricExceptionType.keyInvalidated`.

### Scenario 3: `teardownBiometryPasswordOnly` — happy path (Task 6.3a)

1. Set up `MockEncryptedStorage` with `readAllMeta` and `deleteWrap` stubbed to succeed.
2. Call `locker.teardownBiometryPasswordOnly(passwordCipherFunc: pc, biometricKeyTag: 'tag')`.
3. Assert `storage.deleteWrap(originToDelete: Origin.bio, cipherFunc: pc)` was called exactly once.
4. Assert no exception is thrown.

### Scenario 4: `teardownBiometryPasswordOnly` — `deleteKey` throws (Task 6.3b)

1. Same setup as Scenario 3.
2. A `@visibleForTesting` injectable `secureProvider` constructor parameter is added to `MFALocker`, allowing `MockBiometricCipherProvider` to be injected in tests.
3. Stub `mockSecureProvider.deleteKey(tag: 'tag')` to throw an arbitrary exception.
4. Call `teardownBiometryPasswordOnly`.
5. Assert no exception propagates from `teardownBiometryPasswordOnly` (error suppression is verified at the locker level).

### Scenario 5: `teardownBiometryPasswordOnly` — calls `loadAllMetaIfLocked` when locked (Task 6.3c)

1. Locker starts in locked state (default after construction with `MockEncryptedStorage`).
2. Stub `storage.readAllMeta(cipherFunc: pc)` to return a valid meta map.
3. Stub `storage.deleteWrap` to succeed.
4. Call `teardownBiometryPasswordOnly`.
5. Use `verifyInOrder` to explicitly assert that `storage.readAllMeta` (i.e., `loadAllMetaIfLocked`) is called before `storage.deleteWrap`.

### Scenario 6: Regression — `authenticationError` still maps to `failure` (Task 6.4a)

1. Configure mock `decrypt` to throw `BiometricCipherException(code: BiometricCipherExceptionCode.authenticationError)`.
2. Assert provider throws `BiometricException` with `type == BiometricExceptionType.failure`.

### Scenario 7: Regression — `authenticationUserCanceled` still maps to `cancel` (Task 6.4b)

1. Configure mock `decrypt` to throw `BiometricCipherException(code: BiometricCipherExceptionCode.authenticationUserCanceled)`.
2. Assert provider throws `BiometricException` with `type == BiometricExceptionType.cancel`.

---

## Success / Metrics

| Criterion | How to verify |
|-----------|--------------|
| `fvm flutter test` passes with 0 failures on all existing tests | CI / local run |
| New test for `fromString('KEY_PERMANENTLY_INVALIDATED')` is green | `fvm flutter test packages/biometric_cipher/test/biometric_cipher_test.dart` |
| New tests for `_mapExceptionToBiometricException` are green | `fvm flutter test test/security/biometric_cipher_provider_test.dart` |
| New tests for `teardownBiometryPasswordOnly` are green | `fvm flutter test test/locker/mfa_locker_test.dart` |
| Regression tests for `authenticationError` and `authenticationUserCanceled` are green | Same provider test file |
| `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` exits 0 for root package | CI / local run |
| No production logic is modified (only minimal `@visibleForTesting` constructor parameter added) | Code review |

---

## Constraints and Assumptions

- **Minimal production code change only.** All changes are in test files, except for adding a single `@visibleForTesting` injectable `secureProvider` constructor parameter to `MFALocker` (required for Task 6.3b). No logic changes are permitted.
- **Use `mocktail`.** Existing test infrastructure uses `mocktail`; no new mocking libraries introduced.
- **`MockEncryptedStorage` is already available** at `test/mocks/mock_encrypted_storage.dart`.
- **`BiometricCipherProviderImpl.forTesting`** constructor exists and accepts a `BiometricCipher` — use it for provider-level tests (Tasks 6.2 and 6.4).
- **Task 6.3b uses injected `_secureProvider`.** `MFALocker` will receive a `@visibleForTesting` `secureProvider` parameter so that `MockBiometricCipherProvider` can be injected, enabling full suppression verification at the locker level.
- **Task 6.3c uses `verifyInOrder`.** Explicit ordering is verified with `verifyInOrder([storage.readAllMeta(...), storage.deleteWrap(...)])` rather than separate `verify` calls.
- **Task 6.1 is added to the existing file.** The `fromString` test is added as a new case inside `packages/biometric_cipher/test/biometric_cipher_test.dart`, not in a new file.
- **Dart code style applies to test files:** Line length 120, single quotes, trailing commas, `// Arrange / // Act / // Assert` pattern consistent with existing test files.
- **Tasks 6.1 through 6.4 are additive** — they must not remove or modify any existing test cases.
- **Phase 5 is complete.** `teardownBiometryPasswordOnly` is implemented. No need to re-implement or stub its internals.
- **Test for 6.3c (locked state):** `loadAllMetaIfLocked` is already exercised indirectly via `storage.readAllMeta` in existing tests. The same `_Helpers.stubReadAllMeta` helper can be reused.

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Adding the `@visibleForTesting` `secureProvider` parameter to `MFALocker` may require updating existing call sites in the example app or elsewhere | Low — it is an optional named parameter with a default of `BiometricCipherProviderImpl.instance` | Low — existing call sites pass no argument and pick up the default | Verify with analyze pass after the change. |
| `test/security/biometric_cipher_provider_test.dart` does not exist — creating a new test file for a class that straddles two packages (`locker` depends on `biometric_cipher`) may require additional imports to resolve | Low — `BiometricCipherProviderImpl` is in `lib/security/biometric_cipher_provider.dart` under the root package | Low — straightforward dependency resolution | Verify pub get resolves `biometric_cipher` as a path dependency before writing the file. |
| New `BiometricCipherExceptionCode.fromString` test case may duplicate coverage already present in `biometric_cipher_test.dart` | Low — the existing test exercises the mock platform channel, not `fromString` directly | Low — test is still valuable as a direct unit test | Read existing test file before writing to confirm no exact duplication. |
| Regression tests (Task 6.4) may already exist in the test files | Low | Low | Confirm no duplication before writing. |

---

## Resolved Questions

**Q1 — `_secureProvider` injectability in `MFALocker`:**
Add a `@visibleForTesting` injectable constructor parameter for `secureProvider` to `MFALocker`. This is a minimal production code change and enables full suppression verification in Task 6.3b at the locker level.

**Q2 — Placement of the Task 6.1 `fromString` test:**
Add to the existing `biometric_cipher_test.dart` file — consolidated approach, no new file created.

**Q3 — Ordering verification for Task 6.3c:**
Use `verifyInOrder` to explicitly verify that `loadAllMetaIfLocked` (i.e., `storage.readAllMeta`) is called before `storage.deleteWrap`.

---

## Open Questions

None.
