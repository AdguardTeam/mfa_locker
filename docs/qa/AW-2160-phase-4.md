# QA Plan: AW-2160 Phase 4 — Locker Layer: Map `keyPermanentlyInvalidated` to `BiometricExceptionType.keyInvalidated`

Status: REVIEWED
Date: 2026-03-17

---

## Phase Scope

Phase 4 closes the locker-layer gap in the full-stack error propagation chain for biometric key invalidation detection. Phases 1–3 wired everything from native platforms through the Dart plugin, ensuring `BiometricCipherExceptionCode.keyPermanentlyInvalidated` reaches the locker layer. Prior to this phase, that code fell through to the `_ =>` wildcard in `_mapExceptionToBiometricException` and was treated as a generic `BiometricExceptionType.failure`. The app layer had no way to distinguish permanent key invalidation from a wrong-fingerprint error.

**This phase adds exactly three additive changes across two production files, plus supporting infrastructure:**

- `lib/security/models/exceptions/biometric_exception.dart`
  - New enum value `keyInvalidated` (position 3, between `failure` and `keyNotFound`) with a `///` doc comment.
- `lib/security/biometric_cipher_provider.dart`
  - `@visibleForTesting` named constructor `BiometricCipherProviderImpl.forTesting(this._biometricCipher)` with `_biometricCipher` moved from inline initialization to constructor initialization.
  - New standalone switch arm: `BiometricCipherExceptionCode.keyPermanentlyInvalidated => const BiometricException(BiometricExceptionType.keyInvalidated)` placed before the `_ =>` wildcard.

**Out of scope for this phase:** `teardownBiometryPasswordOnly` (Phase 5), app-layer BLoC recovery UX (Phase 5), and automated unit tests for the new mapping (deferred to Phase 6 per plan). The `keyInvalidated` case in `locker_bloc.dart` and `settings_bloc.dart` is present but grouped with generic failure handling temporarily — targeted recovery UX belongs to Phase 5.

---

## Implementation Status (observed)

All source files were read directly from the repository.

**`lib/security/models/exceptions/biometric_exception.dart`** — verified:
- `keyInvalidated` is present at line 17–18, between `failure` (line 16) and `keyNotFound` (line 19).
- Doc comment present: `/// Hardware-backed biometric key permanently invalidated due to a biometric enrollment change.`
- Total enum values: 7 (`cancel`, `failure`, `keyInvalidated`, `keyNotFound`, `keyAlreadyExists`, `notAvailable`, `notConfigured`). Correct.

**`lib/security/biometric_cipher_provider.dart`** — verified:
- Private constructor correctly initialized: `BiometricCipherProviderImpl._() : _biometricCipher = BiometricCipher();` (line 58). Field is not inline-initialized.
- `@visibleForTesting` constructor present at lines 60–61: `BiometricCipherProviderImpl.forTesting(this._biometricCipher);`. Accepts injectable `BiometricCipher`. Correct.
- `static final BiometricCipherProvider instance = BiometricCipherProviderImpl._();` at line 63 — singleton unaffected.
- In `_mapExceptionToBiometricException`, the new arm is at lines 116–117:
  ```
  BiometricCipherExceptionCode.keyPermanentlyInvalidated =>
    const BiometricException(BiometricExceptionType.keyInvalidated),
  ```
  It is placed as a standalone arm before the `_ =>` wildcard. Uses `const`. Correct.
- The `_ =>` wildcard arm at line 129 is preserved intact: `_ => BiometricException(BiometricExceptionType.failure, originalError: e)`. Correct.
- All existing arms verified unchanged: `keyNotFound` → `keyNotFound`, `keyAlreadyExists` → `keyAlreadyExists`, `authenticationUserCanceled` → `cancel`, `authenticationError || encryptionError || decryptionError` → `failure`, `biometricNotSupported || secureEnclaveUnavailable || tpmUnsupported` → `notAvailable`, `configureError` → `notConfigured`.

**`example/lib/features/locker/bloc/locker_bloc.dart`** — observed:
- `BiometricExceptionType.keyInvalidated` is present at line 1082, grouped with `BiometricExceptionType.failure` in the `_handleBiometricFailure` switch (falls through to `_determineBiometricStateAndEmit` and then to a generic `biometricAuthenticationFailed` action). This is the accepted interim behavior — no targeted recovery UX yet. Phase 5 will handle the distinct case.

**`example/lib/features/settings/bloc/settings_bloc.dart`** — observed:
- `BiometricExceptionType.keyInvalidated` is present at line 133, grouped with `failure` and `notConfigured` in a `case` that falls through to a `break`. Same interim treatment. Phase 5 will add the targeted path.

**Note on phase task 4 ("Revert example app BLoC changes"):** The code review fix task asked to remove `keyInvalidated` cases from the example BLoCs. The observed implementation instead keeps them but groups them with `failure` rather than reverting. This is a valid alternative that avoids analyzer failures in `example/` when running `flutter analyze` from within the `example/` package — the enum value must be handled in any exhaustive switch. The approach is acceptable provided the root-level `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` passes (which does not scan `example/`). However, because the cases are present in `example/`, running `cd example && flutter analyze` is expected to pass too (the case is handled). This should be verified manually.

**Missing deliverables (deferred):**
- `test/mocks/mock_biometric_cipher.dart` — does not exist yet.
- `test/security/biometric_cipher_provider_test.dart` — does not exist yet.
Both are deferred to Phase 6 per the plan's testing strategy.

---

## Positive Scenarios

### PS-1: `keyPermanentlyInvalidated` code maps to `BiometricExceptionType.keyInvalidated` via `decrypt()`

**Setup:** A `BiometricCipherProviderImpl.forTesting(mockBiometricCipher)` instance is created. The mock `BiometricCipher.decrypt()` throws `BiometricCipherException(code: BiometricCipherExceptionCode.keyPermanentlyInvalidated, message: 'Key permanently invalidated')`.

**Expected:** The `decrypt()` call on the provider throws `BiometricException` with `type == BiometricExceptionType.keyInvalidated`.

**How to verify:** Dart unit test in `test/security/biometric_cipher_provider_test.dart` (deferred to Phase 6).

### PS-2: `keyPermanentlyInvalidated` code maps to `BiometricExceptionType.keyInvalidated` via `encrypt()`

**Setup:** Same as PS-1 but the mock throws from `encrypt()`.

**Expected:** Same result — `BiometricException(BiometricExceptionType.keyInvalidated)`.

**How to verify:** Dart unit test (deferred to Phase 6).

### PS-3: Android key invalidation end-to-end propagation

**Setup:** An Android device with an existing biometric wrap. Fingerprint is added or removed in device settings, invalidating the KeyStore key. The app calls a biometric-authenticated operation (decrypt or read entry with biometric).

**Expected flow:**
1. Android `Cipher.init()` throws `KeyPermanentlyInvalidatedException` (Phase 1).
2. `executeOperation()` emits `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")` (Phase 1).
3. Dart plugin `fromString("KEY_PERMANENTLY_INVALIDATED")` returns `BiometricCipherExceptionCode.keyPermanentlyInvalidated` (Phase 3).
4. `_mapExceptionToBiometricException` returns `BiometricException(BiometricExceptionType.keyInvalidated)` (Phase 4 — this phase).
5. `locker_bloc.dart` receives `BiometricExceptionType.keyInvalidated` and routes to `_handleBiometricFailure`.
6. A `biometricAuthenticationFailed` action is dispatched (interim — targeted recovery in Phase 5).

**How to verify:** Manual test on physical Android device.

### PS-4: iOS/macOS key invalidation end-to-end propagation

**Setup:** An iOS/macOS device with an existing biometric wrap. Biometric enrollment changes (Touch ID / Face ID fingerprint removed or added).

**Expected flow:** Identical to PS-3 from step 3 onward. iOS/macOS Secure Enclave emits `"KEY_PERMANENTLY_INVALIDATED"` (Phase 2); same Dart-layer path applies.

**How to verify:** Manual test on physical iOS or macOS device.

### PS-5: `BiometricExceptionType.keyInvalidated` is a distinct, directly referenceable enum value

**Verification:** `BiometricExceptionType.keyInvalidated` can be referenced by name in switch arms and equality comparisons without any cast or dynamic lookup. Confirmed by reading the source file.

### PS-6: `@visibleForTesting` constructor enables mock injection

**Setup:** `BiometricCipherProviderImpl.forTesting(mockBiometricCipher)` is instantiated. The `_biometricCipher` field is set to `mockBiometricCipher` (not to `BiometricCipher()`).

**Expected:** All operations on the provider instance use the injected mock. The singleton `instance` is unaffected and continues to use the private `_()` constructor.

**How to verify:** Dart unit test (deferred to Phase 6); compile-time constructor signature confirms the contract is correct.

### PS-7: Existing singleton behavior is unchanged

**Verification:** `BiometricCipherProviderImpl.instance` is created via `BiometricCipherProviderImpl._()` which initializes `_biometricCipher = BiometricCipher()`. The new `forTesting` constructor has no effect on the singleton. Confirmed by reading line 63 of `biometric_cipher_provider.dart`.

---

## Negative and Edge Cases

### NC-1: `keyPermanentlyInvalidated` does NOT produce `BiometricExceptionType.failure`

**Setup:** Same as PS-1.

**Expected:** The thrown exception has `type != BiometricExceptionType.failure`. The new arm is reached before the `_ =>` wildcard.

**How to verify:** Negative assertion in Phase 6 unit test.

### NC-2: Wrong fingerprint — `failure` unchanged

**Setup:** Mock `BiometricCipher.decrypt()` throws `BiometricCipherException(code: BiometricCipherExceptionCode.authenticationError, ...)`.

**Expected:** `_mapExceptionToBiometricException` returns `BiometricException(BiometricExceptionType.failure)`. The `authenticationError || encryptionError || decryptionError` multi-value arm is hit, not the new `keyPermanentlyInvalidated` arm.

**How to verify:** Unit test (deferred to Phase 6) and code inspection.

### NC-3: User cancels biometric prompt — `cancel` unchanged

**Setup:** Mock throws `BiometricCipherException(code: BiometricCipherExceptionCode.authenticationUserCanceled, ...)`.

**Expected:** Returns `BiometricException(BiometricExceptionType.cancel)`. Unchanged from pre-Phase-4.

**How to verify:** Unit test (deferred to Phase 6) and code inspection.

### NC-4: Device lockout — `failure` unchanged

**Setup:** Device lockout produces `authenticationError` code.

**Expected:** Returns `BiometricException(BiometricExceptionType.failure)`. No change.

**How to verify:** Manual test or unit test regression guard.

### NC-5: Unrecognised / future `BiometricCipherExceptionCode` values — `failure` unchanged

**Setup:** A hypothetical future code value (unknown at compile time) arrives.

**Expected:** Falls through to `_ => BiometricException(BiometricExceptionType.failure, originalError: e)`. The wildcard arm is intact. No crash.

**How to verify:** Code inspection confirms wildcard is preserved at line 129.

### NC-6: `keyNotFound`, `keyAlreadyExists`, `notAvailable`, `notConfigured` mappings unchanged

**Inputs / expected outputs (verified by source inspection):**

| Input code | Expected `BiometricExceptionType` |
|---|---|
| `keyNotFound` | `keyNotFound` |
| `keyAlreadyExists` | `keyAlreadyExists` |
| `biometricNotSupported` | `notAvailable` |
| `secureEnclaveUnavailable` | `notAvailable` |
| `tpmUnsupported` | `notAvailable` |
| `configureError` | `notConfigured` |

All verified unchanged by reading the switch body. Adding `keyPermanentlyInvalidated` as a standalone arm before `_ =>` cannot displace any existing arm because the existing arms appear before it in the switch.

### NC-7: Exhaustive switch consumers — compile-time regression

**Concern:** Adding `keyInvalidated` to `BiometricExceptionType` would cause a compile error or analyzer warning in any exhaustive `switch` that lacks a `_ =>` wildcard.

**Verification:** The switch in `locker_bloc.dart` at line 1023 is a non-exhaustive statement switch with named cases. `keyInvalidated` is handled at line 1082. The switch in `settings_bloc.dart` at line 106 handles `keyInvalidated` at line 133. Both compile. No other switch on `BiometricExceptionType` was identified in the root `lib/` package (`MFALocker` propagates `BiometricException` without switching on its type). `fvm flutter analyze` is the definitive verification.

### NC-8: `encrypt()` path uses identical mapping logic

**Verification:** Both `encrypt()` (lines 78–91) and `decrypt()` (lines 93–107) catch `BiometricCipherException` and call `_mapExceptionToBiometricException(e)`. The new mapping applies equally to both paths. Code inspection confirms they share the same mapping method.

### NC-9: `@visibleForTesting` constructor does not produce a `prefer_const_constructors` or lint warning

**Verification:** The constructor itself does not return a const instance. `@visibleForTesting` is applied from `package:meta/meta.dart`, which is already imported at line 9. No new import is required. The annotation is a marker, not a functional change.

### NC-10: `const` correctness on new switch arm

**Verification:** The new arm uses `const BiometricException(BiometricExceptionType.keyInvalidated)`, matching all other named arms. `BiometricException` is declared with a `const` constructor. Correct.

---

## Automated Tests Coverage

### Existing tests — non-regression

The existing root test suite (`test/`) does not directly exercise `BiometricCipherProviderImpl` or `_mapExceptionToBiometricException`. All existing tests use mock `EncryptedStorage` and mock cipher functions (`MockBioCipherFunc`, `MockPasswordCipherFunc`). They do not reference `BiometricExceptionType` switch mappings. No existing tests are broken by Phase 4 changes.

Files confirmed unaffected:
- `test/locker/mfa_locker_test.dart`
- `test/storage/encrypted_storage_impl_test.dart`
- `test/storage/hmac_storage_mixin_test.dart`
- `test/utils/cryptography_utils_test.dart`
- `test/utils/erasable_byte_array_test.dart`

### Missing automated tests — deferred to Phase 6

The plan explicitly defers unit tests for `_mapExceptionToBiometricException` to Phase 6. The following test artifacts do not yet exist:

- `test/mocks/mock_biometric_cipher.dart` — `MockBiometricCipher extends Mock implements BiometricCipher`
- `test/security/biometric_cipher_provider_test.dart` — four required test cases:
  1. `decrypt()` with mock throwing `keyPermanentlyInvalidated` → `BiometricException` with `type == keyInvalidated`
  2. Same input does NOT produce `type == failure` (negative assertion)
  3. `authenticationUserCanceled` → `cancel` (regression guard)
  4. `authenticationError` → `failure` (regression guard)

This is the most significant gap for this phase. The PRD explicitly lists a Dart unit test as the verification method for the primary success criterion. Without it, correctness is established by code inspection only.

---

## Manual Checks Needed

### MC-1: Static analysis — root package

**Command:**
```
fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .
```
Run from the repository root.

**Pass criterion:** Exits with code 0. This validates:
- No exhaustive-switch warning from the new `keyInvalidated` enum value in `_mapExceptionToBiometricException` (which has a `_ =>` wildcard — no issue expected).
- `@visibleForTesting` import (`package:meta/meta.dart`) resolves correctly.
- `const BiometricException(BiometricExceptionType.keyInvalidated)` satisfies `prefer_const_constructors`.
- 120-character line length respected.
- Doc comment format on `keyInvalidated` satisfies any doc-comment lints.

**Status:** Not executed as part of this QA review. Must be confirmed before release.

### MC-2: All existing tests pass

**Command:**
```
fvm flutter test
```
Run from the repository root.

**Pass criterion:** All tests exit green. No new failures introduced by Phase 4 changes.

**Status:** Not executed as part of this QA review. Must be confirmed before release.

### MC-3: Manual end-to-end on Android — key invalidation produces `keyInvalidated`

**Procedure:**
1. Install the app with a biometric wrap already established.
2. Add or remove a fingerprint in Android device settings.
3. Open the app and trigger a biometric operation (unlock or read entry with biometric).
4. Observe the thrown `BiometricException` via a debug log or breakpoint.

**Pass criterion:** `BiometricException.type == BiometricExceptionType.keyInvalidated` is observed. No generic `failure` is produced for this scenario.

**Status:** Not executed. Recommended before full release of the AW-2160 ticket (can be performed alongside Phase 5 device testing).

### MC-4: Manual end-to-end on iOS or macOS — key invalidation produces `keyInvalidated`

**Procedure:** Same as MC-3, substituting Touch ID / Face ID enrollment change on the target Apple device.

**Pass criterion:** Same as MC-3.

**Status:** Not executed. Recommended before full release.

### MC-5: Regression — wrong fingerprint still produces `failure`

**Procedure:** On any supported device with biometrics enrolled, present a wrong fingerprint during a biometric operation.

**Pass criterion:** The app responds with the existing failure UX (biometric auth failed message), not a "key invalidated" message. No regression in the `authenticationError` → `failure` path.

### MC-6: Regression — user cancel still produces `cancel`

**Procedure:** On any supported device, dismiss the biometric prompt by tapping cancel.

**Pass criterion:** The app responds with the existing cancel UX. `BiometricExceptionType.cancel` is produced, not `keyInvalidated`.

### MC-7: Verify `forTesting` constructor correctly injects mock (compile-time check)

**Procedure:** Confirm that writing `BiometricCipherProviderImpl.forTesting(mockBiometricCipher)` compiles and that `mockBiometricCipher` is actually used for operations (verifiable via mock expectations once Phase 6 tests are written).

**Pass criterion:** Compiles; no `_biometricCipher = BiometricCipher()` inline-initialization remains (verified by source reading — confirmed correct).

---

## Risk Zone

| Risk | Severity | Status |
|---|---|---|
| No automated unit test for the primary acceptance criterion (`_mapExceptionToBiometricException` with `keyPermanentlyInvalidated` returns `keyInvalidated`) | High | Open. Deferred to Phase 6 by plan. The implementation appears correct by code inspection, but without automated tests this mapping is unprotected against future regressions. Phase 6 must close this. |
| `fvm flutter analyze` not executed in this QA pass | Medium | Must be confirmed before release. Primary acceptance criterion in the PRD and plan. |
| `fvm flutter test` not executed in this QA pass | Medium | Must be confirmed before release. Validates no existing test is broken. |
| Example app `locker_bloc.dart` and `settings_bloc.dart` contain `keyInvalidated` — deviates from code review task 4 ("revert") | Low | The approach is valid: keeping the case prevents analyzer errors within `example/` and avoids a future churn when Phase 5 adds the targeted recovery. The root `flutter analyze` does not scan `example/`. No functional risk. Document in PR description. |
| `keyInvalidated` enum position (between `failure` and `keyNotFound`) differs from plan spec (position 7, after `notConfigured`) | Low | The actual position (position 3) does not affect correctness — `BiometricExceptionType` is not serialized, and switch matching is by value name, not position. The doc comment and switch arm are present. No impact. |
| Phase 3 testing gap carries forward | Low | Phase 3 QA verdict was "with reservations" due to missing `fromString` test. That gap is still open. Phase 4 depends on `fromString('KEY_PERMANENTLY_INVALIDATED') == keyPermanentlyInvalidated` as a contract — unverified by automation. Phase 6 tests will indirectly cover this by exercising the full stack through mock injection. |
| No end-to-end device test performed for Phase 4 in isolation | Low | Accepted for this phase. Phases 5 and 6 will involve device testing as part of the recovery UX implementation and full regression suite. |

---

## Final Verdict

**With reservations.**

The Phase 4 implementation is structurally correct and complete for its defined scope:

- `BiometricExceptionType.keyInvalidated` exists as a distinct enum value with a proper `///` doc comment.
- `_mapExceptionToBiometricException` has a standalone `keyPermanentlyInvalidated` arm that returns `const BiometricException(BiometricExceptionType.keyInvalidated)`, placed correctly before the `_ =>` wildcard.
- The `_ =>` wildcard is preserved intact.
- All existing mapping arms are confirmed unchanged by source inspection.
- `BiometricCipherProviderImpl.forTesting(this._biometricCipher)` correctly accepts an injectable `BiometricCipher`, enabling the Phase 6 unit tests. The singleton `instance` path is unaffected.
- The example app BLoCs handle `keyInvalidated` without crashing (grouped with `failure` as an interim until Phase 5 adds targeted recovery).

The reservations are:

1. **No automated unit tests exist for `_mapExceptionToBiometricException`.** This is the primary acceptance criterion from the PRD. The plan defers this to Phase 6, but it is the most material gap. Phase 6 must deliver `test/security/biometric_cipher_provider_test.dart` and `test/mocks/mock_biometric_cipher.dart` with all four specified test cases — including the negative assertion — before AW-2160 can be considered fully released.

2. **`fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` has not been executed** as part of this QA review. This must pass before Phase 4 is considered released.

3. **`fvm flutter test` has not been executed.** Required to confirm no existing tests are broken.

4. **No device-level manual test has been performed for Phase 4.** End-to-end verification on Android and iOS/macOS that a biometric enrollment change produces `BiometricExceptionType.keyInvalidated` is deferred to Phase 5 device testing.

Once items 2 and 3 are confirmed green, Phase 4 is releasable as a library change. Items 1 and 4 remain as tracked gaps to be closed in Phases 5 and 6.
