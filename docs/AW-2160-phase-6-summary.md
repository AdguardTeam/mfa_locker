# AW-2160 Phase 6 Summary — Unit Tests for Biometric Key Invalidation and Password-Only Teardown

## What Was Done

Phase 6 is the final phase of AW-2160. It adds dedicated unit test coverage for all new Dart-layer code paths introduced in Phases 3–5. No production logic was changed beyond a single `@visibleForTesting` constructor parameter added to enable test injection.

The problem addressed: Phases 1–5 were verified through analyzer passes and the existing test suite, but no dedicated tests existed for the new enum values, the new exception mapping, or `teardownBiometryPasswordOnly`. Without these tests, future regressions — such as accidentally removing the `keyPermanentlyInvalidated` mapping or breaking the error suppression logic in `teardownBiometryPasswordOnly` — would go undetected by the CI test suite.

All 7 new tests pass. The total test count for the root package is 146 passing tests. Static analysis exits clean.

---

## Files Changed

### Production files

| File | Change |
|------|--------|
| `lib/locker/mfa_locker.dart` | Replaced `BiometricCipherProvider get _secureProvider => BiometricCipherProviderImpl.instance;` getter (line 43) with a `final BiometricCipherProvider _secureProvider;` field initialized in the constructor initializer list via `_secureProvider = secureProvider ?? BiometricCipherProviderImpl.instance`. Added `@visibleForTesting BiometricCipherProvider? secureProvider` as an optional named constructor parameter. All existing call sites that pass no `secureProvider` argument are unaffected. |

### New test files

| File | Purpose |
|------|---------|
| `test/mocks/mock_biometric_cipher.dart` | `MockBiometricCipher extends Mock implements BiometricCipher` — used by provider-level tests (Tasks 6.2, 6.4) |
| `test/mocks/mock_biometric_cipher_provider.dart` | `MockBiometricCipherProvider extends Mock implements BiometricCipherProvider` — used by locker-level tests (Task 6.3) |
| `test/security/biometric_cipher_provider_test.dart` | Three tests covering `BiometricCipherProviderImpl._mapExceptionToBiometricException` exception mapping (Tasks 6.2 and 6.4) |

### Existing test files modified

| File | Change |
|------|--------|
| `packages/biometric_cipher/test/biometric_cipher_test.dart` | New `group('BiometricCipherExceptionCode', ...)` block appended after the existing `group('BiometricCipher tests', ...)` block — one test for `fromString('KEY_PERMANENTLY_INVALIDATED')` (Task 6.1). No existing test was modified. |
| `test/locker/mfa_locker_test.dart` | New `group('teardownBiometryPasswordOnly', ...)` inserted after the `wrap management` group and before the `eraseStorage` group — three tests (Tasks 6.3a, 6.3b, 6.3c). Added import for `MockBiometricCipherProvider`. No existing test was modified. |

---

## What Was Added

### Task 6.1 — `BiometricCipherExceptionCode.fromString` mapping test

A direct unit test for the enum static method introduced in Phase 3. Calls `BiometricCipherExceptionCode.fromString('KEY_PERMANENTLY_INVALIDATED')` with no mocks and asserts the result equals `BiometricCipherExceptionCode.keyPermanentlyInvalidated`. Protects against the mapping being accidentally removed from the `fromString` switch.

Located in `packages/biometric_cipher/test/biometric_cipher_test.dart`.

### Tasks 6.2 and 6.4 — Provider exception mapping tests (`biometric_cipher_provider_test.dart`)

Three tests inside `group('BiometricCipherProviderImpl', () { group('_mapExceptionToBiometricException', ...) })`. Each test:
1. Creates a `MockBiometricCipher` and constructs a `BiometricCipherProviderImpl.forTesting(mockCipher)`.
2. Stubs `mockCipher.decrypt` to throw a `BiometricCipherException` with a specific code.
3. Calls `provider.decrypt(...)` and uses `await expectLater(...)` with `throwsA(isA<BiometricException>().having(...))` to assert the thrown exception's `type`.

The three cases covered:

| Test | Input code | Expected `BiometricExceptionType` | Task |
|------|-----------|----------------------------------|------|
| `maps keyPermanentlyInvalidated to BiometricExceptionType.keyInvalidated` | `keyPermanentlyInvalidated` | `keyInvalidated` | 6.2 |
| `maps authenticationError to BiometricExceptionType.failure` | `authenticationError` | `failure` | 6.4a |
| `maps authenticationUserCanceled to BiometricExceptionType.cancel` | `authenticationUserCanceled` | `cancel` | 6.4b |

Tasks 6.4a and 6.4b are regression guards. They confirm that inserting the new `keyPermanentlyInvalidated` mapping arm into the switch statement did not displace or alter the two pre-existing mappings.

Note: all three tests are `async` and use `await expectLater(...)`, which is the correct pattern for asserting exceptions from `async` methods. The QA plan noted a risk around a synchronous `expect(...)` pattern; the implementation uses `expectLater` throughout, resolving that concern.

### Task 6.3 — `teardownBiometryPasswordOnly` tests (`mfa_locker_test.dart`)

A new `group('teardownBiometryPasswordOnly', ...)` with its own `setUp` and `tearDown`. The group creates a separate `tpStorage: MockEncryptedStorage` and `tpLocker: MFALocker` instance, injecting both `storage` and `secureProvider`, keeping these tests fully isolated from the outer `group('MFALocker', ...)` setup.

**Test 6.3a — happy path (`deletes bio wrap and biometric key on success`):**
Stubs `tpStorage.readAllMeta`, `tpStorage.deleteWrap(originToDelete: Origin.bio, ...)`, and `secureProvider.deleteKey(tag: ...)` to succeed. Calls `teardownBiometryPasswordOnly`. Verifies that `tpStorage.deleteWrap` and `secureProvider.deleteKey` are each called exactly once. Asserts no exception.

**Test 6.3b — `deleteKey` throws, suppressed (`completes normally when deleteKey throws`):**
Same setup as 6.3a except `secureProvider.deleteKey` is stubbed to throw `Exception('key gone')`. Asserts the method completes normally with no propagated exception. Also verifies that `deleteKey` was still called once (the call reached the provider; it was the error that was suppressed, not the call itself).

**Test 6.3c — locked-state ordering (`unlocks before deleting wrap when locker is locked`):**
Confirms the locker starts in `LockerState.locked` before calling the method. After the call, uses `verifyInOrder` to assert that `tpStorage.readAllMeta(cipherFunc: pwd)` was called before `tpStorage.deleteWrap(originToDelete: Origin.bio, cipherFunc: pwd)`. This is the first use of `verifyInOrder` in the codebase; it guards against any future refactor that might call `deleteWrap` before the locker has been unlocked via `loadAllMetaIfLocked`.

---

## Decisions Made

**`await expectLater` instead of synchronous `expect` for async assertions.**
The QA plan flagged the risk that a synchronous `expect(() => provider.decrypt(...), throwsA(...))` pattern would silently pass when `BiometricCipherProviderImpl.decrypt` is `async`, because the thrown exception would be inside an unobserved future. The implementation correctly uses `await expectLater(...)` throughout `biometric_cipher_provider_test.dart`, making the async exception visible to the test framework.

**Separate `tpStorage` and `tpLocker` instances in the `teardownBiometryPasswordOnly` group.**
The outer `group('MFALocker', ...)` has its own `storage` and `locker` instances. Rather than reusing them and risking stub pollution, the `teardownBiometryPasswordOnly` group creates fresh instances per test via its own `setUp`. This makes each test's mock expectations independent and the test body self-contained.

**`final BiometricCipherProvider _secureProvider` field rather than a getter.**
The getter `BiometricCipherProvider get _secureProvider => BiometricCipherProviderImpl.instance;` cannot be overridden by a constructor parameter. Replacing it with a field initialized in the constructor initializer list (`_secureProvider = secureProvider ?? BiometricCipherProviderImpl.instance`) is functionally identical for all production call sites and enables `MockBiometricCipherProvider` injection in tests. The change is structurally the same as the pre-existing `storage` / `_storage` pattern in the same constructor.

**`@visibleForTesting` annotation on the `secureProvider` parameter.**
Signals to the analyzer and code reviewers that this parameter exists for testing only. Consistent with the existing `storage` parameter. Production call sites will be warned by the linter if they try to pass a `secureProvider` argument outside of a test context.

**`verifyInOrder` for Task 6.3c.**
Simple separate `verify` calls cannot assert ordering. `verifyInOrder` explicitly captures call order and fails if `readAllMeta` is not recorded before `deleteWrap`. This is the correct tool for the locked-state scenario's key behavioral contract.

---

## Open Issues Closed by This Phase

Phase 5's QA report listed the following as open risks. All items within Phase 6's scope are now resolved:

| Phase 5 open risk | Resolution |
|-------------------|-----------|
| No automated unit tests for `teardownBiometryPasswordOnly` (high-severity) | Closed by Tasks 6.3a, 6.3b, 6.3c |
| No test for `_mapExceptionToBiometricException` mapping (carry-over from Phase 4) | Closed by Task 6.2 |
| No test for `BiometricCipherExceptionCode.fromString` (carry-over from Phase 3) | Closed by Task 6.1 |
| `fvm flutter analyze` and `fvm flutter test` must be confirmed green | Both pass. 146 tests, 0 failures, analyzer clean. |

**Remaining open item (carry-over, out of Phase 6 scope):**
End-to-end device tests for the full AW-2160 biometric invalidation flow have not been performed. These require a physical device (Android or iOS/macOS) with the ability to change biometric enrollment while the locker has an active biometric wrap. This is a prerequisite before AW-2160 is considered fully released to production.

---

## How Phase 6 Fits in the Full AW-2160 Flow

```
Android: KeyPermanentlyInvalidatedException → FlutterError("KEY_PERMANENTLY_INVALIDATED")   [Phase 1]
iOS/macOS: Secure Enclave key inaccessible → FlutterError("KEY_PERMANENTLY_INVALIDATED")    [Phase 2]
  → Dart plugin: BiometricCipherExceptionCode.keyPermanentlyInvalidated                     [Phase 3]
      → now tested directly: fromString('KEY_PERMANENTLY_INVALIDATED')                      [Phase 6, Task 6.1]
  → Locker: BiometricExceptionType.keyInvalidated                                           [Phase 4]
      → now tested via provider: keyPermanentlyInvalidated → keyInvalidated                 [Phase 6, Task 6.2]
      → regression tests: authenticationError → failure, cancel → cancel                   [Phase 6, Task 6.4]
  → App detects keyInvalidated
  → App calls teardownBiometryPasswordOnly(passwordCipherFunc, biometricKeyTag)             [Phase 5]
      → loadAllMetaIfLocked (ordering verified by verifyInOrder)                            [Phase 6, Task 6.3c]
      → deleteWrap (happy path, absent-key suppression)                                     [Phase 6, Tasks 6.3a, 6.3b]
```

---

## Phase Dependencies

| Phase | Status | Relevance |
|-------|--------|-----------|
| Phase 1 (Android native) | Complete | Emits `"KEY_PERMANENTLY_INVALIDATED"` from Android KeyStore |
| Phase 2 (iOS/macOS native) | Complete | Emits `"KEY_PERMANENTLY_INVALIDATED"` from Secure Enclave |
| Phase 3 (Dart plugin) | Complete | `BiometricCipherExceptionCode.keyPermanentlyInvalidated` + `fromString` mapping |
| Phase 4 (Locker library) | Complete | `BiometricExceptionType.keyInvalidated`; `_mapExceptionToBiometricException` mapping |
| Phase 5 (Locker library) | Complete | `teardownBiometryPasswordOnly` on `Locker` and `MFALocker` |
| Phase 6 (this phase) | Complete | Unit tests for all Dart-layer additions from Phases 3–5 |
