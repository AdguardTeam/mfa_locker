# QA Plan: AW-2160 Phase 3 — Dart Plugin: Map `KEY_PERMANENTLY_INVALIDATED` to `BiometricCipherExceptionCode`

Status: REVIEWED
Date: 2026-03-17

---

## Phase Scope

Phase 3 closes the Dart plugin gap in the error propagation chain established by Phase 1 (Android) and Phase 2 (iOS/macOS). Both platforms already emit `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")` over the method channel when a biometric key is permanently invalidated.

**This phase touches exactly one file with exactly two additive lines:**

- `packages/biometric_cipher/lib/data/biometric_cipher_exception_code.dart`
  - New enum value: `keyPermanentlyInvalidated` added before `unknown` (position 14; `unknown` shifts to 15 and remains last).
  - New switch case: `'KEY_PERMANENTLY_INVALIDATED' => keyPermanentlyInvalidated` added before the final `_ => unknown` fallthrough.

**Out of scope for this phase:** locker library mapping (`BiometricCipherProviderImpl._mapExceptionToBiometricException`), `BiometricExceptionType.keyInvalidated`, `teardownBiometryPasswordOnly`, app-layer wiring, and any Swift or Kotlin changes (those belong to Phases 1–2 and 4–5).

The key acceptance criterion is:

```
BiometricCipherExceptionCode.fromString('KEY_PERMANENTLY_INVALIDATED')
  returns BiometricCipherExceptionCode.keyPermanentlyInvalidated  (not unknown)
```

---

## Implementation Status (observed)

The target file was read directly from the repository.

**Enum body** — verified:
- `keyPermanentlyInvalidated` is present at line 44 with the doc comment:
  `/// The hardware-backed biometric key has been permanently invalidated`
  `/// due to a biometric enrollment change (e.g., fingerprint added/removed).`
- Placement is immediately before `unknown` (line 47), which remains the last enum value and the `_ =>` fallback. Correct.
- Total enum values: 15 (was 14 before this phase). `configureError` is immediately before `keyPermanentlyInvalidated`. Correct.

**`fromString` switch** — verified:
- `'KEY_PERMANENTLY_INVALIDATED' => keyPermanentlyInvalidated` is present at line 99.
- Placement is after the `configureError` case group (lines 89–97) and before the final fallthrough `'UNKNOWN_ERROR' || 'UNKNOWN_EXCEPTION' || 'CONVERTING_STRING_ERROR' || _ => unknown` (line 101). Correct.
- All 13 previously existing switch cases are unchanged. Verified by inspection: `'INVALID_ARGUMENT'`, `'KEY_NOT_FOUND'`, `'KEY_ALREADY_EXISTS'`, `'BIOMETRIC_NOT_SUPPORTED'`, `'AUTHENTICATION_USER_CANCELED'`, `'AUTHENTICATION_ERROR'`, `'ENCRYPT_ERROR'` group, `'DECRYPT_ERROR'` group, `'GENERATE_KEY_ERROR'` group, `'DELETE_KEY_ERROR'` group, `'SECURE_ENCLAVE_UNAVAILABLE'`, `'TPM_UNSUPPORTED'`, `'CONFIGURE_ERROR'` group — all produce the same results as before this phase.

**Downstream consumer** — verified:
- `BiometricCipherMethodChannel._mapPlatformException()` calls `BiometricCipherExceptionCode.fromString(e.code)` at line 100. It picks up the new mapping automatically with no code change required. Correct.
- `BiometricCipherProviderImpl._mapExceptionToBiometricException()` uses a `_ => BiometricException(BiometricExceptionType.failure, originalError: e)` wildcard as its final arm. `keyPermanentlyInvalidated` falls through to `failure` in Phase 3. This is correct and intentional — Phase 4 will add the explicit `keyInvalidated` arm.

---

## Positive Scenarios

### PS-1: `fromString` maps `'KEY_PERMANENTLY_INVALIDATED'` to `keyPermanentlyInvalidated`

**Input:** `BiometricCipherExceptionCode.fromString('KEY_PERMANENTLY_INVALIDATED')`

**Expected:** Returns `BiometricCipherExceptionCode.keyPermanentlyInvalidated`.

**Negative assertion:** Does NOT return `BiometricCipherExceptionCode.unknown`.

**How to verify:** Dart unit test (see Automated Tests section).

### PS-2: Android key invalidation — full Dart plugin path

**Setup:** Android emits `PlatformException(code: 'KEY_PERMANENTLY_INVALIDATED')` over the method channel (Phase 1 contract).

**Expected flow:**
1. `BiometricCipherMethodChannel._mapPlatformException(e)` calls `fromString('KEY_PERMANENTLY_INVALIDATED')`.
2. `fromString` returns `keyPermanentlyInvalidated`.
3. A `BiometricCipherException` with `code == keyPermanentlyInvalidated` is thrown to the plugin consumer.
4. The error code is no longer swallowed as `unknown`.

### PS-3: iOS/macOS key invalidation — full Dart plugin path

**Setup:** iOS/macOS emits `PlatformException(code: 'KEY_PERMANENTLY_INVALIDATED')` over the method channel (Phase 2 contract). Covers both Point A (OS deleted the key item) and Point B (`errSecAuthFailed` path).

**Expected flow:** Identical to PS-2. Same `fromString` mapping; same result. The Dart plugin layer is platform-agnostic — it handles the string regardless of which platform emitted it.

### PS-4: Enum value is a compile-time accessible constant

**Verification:** `BiometricCipherExceptionCode.keyPermanentlyInvalidated` is directly referenceable as a named enum value. Code in Phase 4 can write `BiometricCipherExceptionCode.keyPermanentlyInvalidated` in a switch arm without any cast or dynamic lookup. Verified by enum declaration.

### PS-5: `unknown` remains the last enum value

**Verification:** The enum declaration ends with `keyPermanentlyInvalidated` (position 14) then `unknown;` (position 15). No value appears after `unknown`. Verified by reading the file. The `fromString` switch's `_ => unknown` fallthrough is unaffected.

---

## Negative and Edge Cases

### NC-1: Unrecognised string — `unknown` fallback unchanged

**Input:** `BiometricCipherExceptionCode.fromString('SOME_NEW_FUTURE_ERROR')`

**Expected:** Returns `BiometricCipherExceptionCode.unknown`. The `_ => unknown` arm in the switch is unchanged. Adding the new case before it does not affect the fallthrough.

### NC-2: Explicit `unknown` aliases still map to `unknown`

**Inputs:** `fromString('UNKNOWN_ERROR')`, `fromString('UNKNOWN_EXCEPTION')`, `fromString('CONVERTING_STRING_ERROR')`

**Expected:** All return `BiometricCipherExceptionCode.unknown`. The multi-value case `'UNKNOWN_ERROR' || 'UNKNOWN_EXCEPTION' || 'CONVERTING_STRING_ERROR' || _ => unknown` is preserved verbatim. No regression.

### NC-3: All existing mappings — no regression

**Inputs (representative sample):**

| Input string | Expected result |
|---|---|
| `'INVALID_ARGUMENT'` | `invalidArgument` |
| `'KEY_NOT_FOUND'` | `keyNotFound` |
| `'FAILED_GET_PRIVATE_KEY'` | `keyNotFound` |
| `'KEY_ALREADY_EXISTS'` | `keyAlreadyExists` |
| `'BIOMETRIC_NOT_SUPPORTED'` | `biometricNotSupported` |
| `'BIOMETRY_NOT_SUPPORTED'` | `biometricNotSupported` |
| `'BIOMETRY_NOT_AVAILABLE'` | `biometricNotSupported` |
| `'AUTHENTICATION_USER_CANCELED'` | `authenticationUserCanceled` |
| `'AUTHENTICATION_ERROR'` | `authenticationError` |
| `'ERROR_EVALUATING_BIOMETRY'` | `authenticationError` |
| `'USER_PREFERS_PASSWORD'` | `authenticationError` |
| `'SECURE_DEVICE_LOCKED'` | `authenticationError` |
| `'ENCRYPT_ERROR'` | `encryptionError` |
| `'DECRYPT_ERROR'` | `decryptionError` |
| `'FAILED_TO_DECRYPT_DATA'` | `decryptionError` |
| `'DECODE_DATA_INVALID_SIZE'` | `decryptionError` |
| `'GENERATE_KEY_ERROR'` | `keyGenerationError` |
| `'DELETE_KEY_ERROR'` | `keyDeletionError` |
| `'SECURE_ENCLAVE_UNAVAILABLE'` | `secureEnclaveUnavailable` |
| `'TPM_UNSUPPORTED'` | `tpmUnsupported` |
| `'CONFIGURE_ERROR'` | `configureError` |
| `'ACTIVITY_NOT_SET'` | `configureError` |

**Expected:** Every input produces the same result as before Phase 3. No existing mapping is displaced.

### NC-4: Empty string falls through to `unknown`

**Input:** `BiometricCipherExceptionCode.fromString('')`

**Expected:** The empty string does not match any named case. It falls through to `_ => unknown`. Returns `BiometricCipherExceptionCode.unknown`. No crash, no exception.

### NC-5: String case sensitivity — `'key_permanently_invalidated'` (lowercase) does NOT match

**Input:** `BiometricCipherExceptionCode.fromString('key_permanently_invalidated')`

**Expected:** Dart switch cases are case-sensitive. The lowercase string does not match `'KEY_PERMANENTLY_INVALIDATED'`. Returns `unknown`. This is correct: the platforms emit the exact uppercase string.

### NC-6: Downstream consumer receives `keyPermanentlyInvalidated` and maps it to `failure` (Phase 3 interim behavior)

**Context:** `BiometricCipherProviderImpl._mapExceptionToBiometricException()` has no explicit arm for `keyPermanentlyInvalidated` in Phase 3. The `_ =>` wildcard arm catches it.

**Expected:** A `BiometricCipherException` with `code == keyPermanentlyInvalidated` is mapped to `BiometricException(BiometricExceptionType.failure, originalError: e)`. This is the correct and documented interim behavior. Phase 4 adds the `keyInvalidated` mapping. No crash, no silent swallow — the exception is correctly typed at the plugin boundary.

**Regression check:** This behavior (`_ => failure`) was the behavior for `keyPermanentlyInvalidated` in Phase 3 by design and is identical to the pre-Phase-3 behavior (where it arrived as `unknown`). No regression; actually a slight improvement because `originalError` now carries the correctly typed `BiometricCipherException.code`.

### NC-7: No `fromString` callers other than `_mapPlatformException`

**Verification:** Searching the Dart codebase reveals only one call site for `fromString`: `BiometricCipherMethodChannel._mapPlatformException()` at line 100 of `biometric_cipher_method_channel.dart`. No other code creates `BiometricCipherExceptionCode` values via string parsing. Adding the new enum value cannot break any consumer that uses it only by named reference.

### NC-8: Exhaustive switch consumers — compile-time regression check

**Context:** If any `switch` on `BiometricCipherExceptionCode` is exhaustive (no wildcard), the Dart analyzer will emit a warning or error if the new `keyPermanentlyInvalidated` value is unhandled.

**Verification:** `_mapExceptionToBiometricException()` uses `_ =>` as its final arm — it is a non-exhaustive switch. No other switch on `BiometricCipherExceptionCode` was found in the codebase. `fvm flutter analyze` is the definitive check (see Manual Checks).

---

## Automated Tests Coverage

### Existing tests — non-regression

The existing test suite in `packages/biometric_cipher/test/biometric_cipher_test.dart` covers `BiometricCipher` operations (configure, encrypt-decrypt cycle, deleteKey) via `MockBiometricCipherPlatform`. These tests do not exercise `BiometricCipherExceptionCode.fromString` directly and are unaffected by Phase 3.

The mock (`MockBiometricCipherPlatform`) constructs exceptions using named enum literals (e.g., `BiometricCipherExceptionCode.keyNotFound`, `BiometricCipherExceptionCode.configureError`) — not via `fromString`. No mock changes are required.

### Missing automated test for `fromString` — new gap

There is no Dart unit test that directly asserts:

```dart
expect(
  BiometricCipherExceptionCode.fromString('KEY_PERMANENTLY_INVALIDATED'),
  equals(BiometricCipherExceptionCode.keyPermanentlyInvalidated),
);
```

This is the primary acceptance criterion from the PRD. It is the smallest possible test — a single `expect` with no async/mock setup. The PRD lists this test as the verification method for the success criterion. Its absence is a gap.

**Recommended test location:** A new test group in `packages/biometric_cipher/test/biometric_cipher_test.dart`, or a dedicated file `packages/biometric_cipher/test/biometric_cipher_exception_code_test.dart`.

**Recommended test cases:**
1. `fromString('KEY_PERMANENTLY_INVALIDATED')` returns `keyPermanentlyInvalidated`.
2. `fromString('KEY_PERMANENTLY_INVALIDATED')` does not return `unknown`.
3. `fromString('UNKNOWN_ERROR')` still returns `unknown` (regression guard).
4. `fromString('AUTHENTICATION_ERROR')` still returns `authenticationError` (regression guard).
5. `fromString('SOME_UNRECOGNISED_CODE')` returns `unknown` (fallthrough guard).

---

## Manual Checks Needed

### MC-1: Static analysis on `packages/biometric_cipher`

**Command:**
```
cd packages/biometric_cipher && fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .
```

**Pass criterion:** Exits with code 0. No warnings or infos. This is the primary acceptance criterion stated in the PRD and phase tasklist (task 3.1 acceptance check). It validates:
- No exhaustive-switch compile error from the new enum value in any consuming switch.
- No style violations (line length, doc comment format, etc.).
- No unused enum value warning.

**Status:** Not yet executed as part of this QA review. Must be confirmed before release.

### MC-2: Static analysis on root package

**Command (from repository root):**
```
fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .
```

**Pass criterion:** Exits with code 0. The root package imports `biometric_cipher_provider.dart`, which switches on `BiometricCipherExceptionCode`. Its `_ =>` wildcard must remain valid after the new value is added.

**Status:** Not yet executed. Must be confirmed before release.

### MC-3: Confirm `BiometricCipherExceptionCode.keyPermanentlyInvalidated` is reachable from consuming code

**Check:** In a temporary Dart snippet or a test, write:
```dart
const code = BiometricCipherExceptionCode.keyPermanentlyInvalidated;
```
and confirm it compiles and the IDE resolves the symbol without error.

**Pass criterion:** No compile error; symbol is resolved. Confirms the enum value is exported and accessible.

### MC-4: Verify no existing test is broken by `fvm flutter test`

**Command (from `packages/biometric_cipher`):**
```
fvm flutter test
```

**Pass criterion:** All existing tests pass. No new failures. The existing mock-based tests do not reference `fromString` or the new enum value, so no failures are expected — but this must be verified.

---

## Risk Zone

| Risk | Severity | Status |
|---|---|---|
| No automated test for the primary acceptance criterion (`fromString('KEY_PERMANENTLY_INVALIDATED')` returns `keyPermanentlyInvalidated`) | Medium | Gap. The PRD explicitly calls out a Dart unit test as the verification method. The implementation looks correct by inspection, but a test should exist for regression protection, especially before Phase 4 depends on this contract. Recommended to add before merge. |
| `fvm flutter analyze` not executed in this QA pass | Medium | Must be confirmed before release. This is both the PRD's acceptance criterion and the tasklist checkbox (task 3.1). |
| Enum position of `keyPermanentlyInvalidated` (must be before `unknown`) | Low | Verified correct in source: `keyPermanentlyInvalidated` is line 44, `unknown` is line 47 with the semicolon. No risk. |
| String literal mismatch between Dart switch and platform emitters | Very Low | Verified: Phase 1 uses `ErrorType.KEY_PERMANENTLY_INVALIDATED.name` (Kotlin enum `.name` property produces the exact string `"KEY_PERMANENTLY_INVALIDATED"`). Phase 2 uses a hardcoded `"KEY_PERMANENTLY_INVALIDATED"` string in `BiometricCipherPlugin.swift`. Both match the Dart switch case exactly. |
| Downstream `_mapExceptionToBiometricException` still routes to `failure` in Phase 3 | Low | Accepted and documented by design. Phase 3 scope is plugin-only. Phase 4 adds the explicit `keyInvalidated` arm. No incorrect recovery is triggered at this phase because Phase 4 has not shipped yet. |
| `unknown` no longer being last enum value | Very Low | Not a risk — verified `unknown` is last. Listed for completeness as it was the primary placement risk in the PRD. |

---

## Final Verdict

**With reservations.**

The implementation is functionally correct and complete:

- `keyPermanentlyInvalidated` is present in the enum body at the correct position (before `unknown`, which remains last).
- `'KEY_PERMANENTLY_INVALIDATED' => keyPermanentlyInvalidated` is present in the `fromString` switch at the correct position (before the final `_ => unknown` fallthrough).
- All 13 previously existing switch cases are unchanged.
- The doc comment matches the style of adjacent values (single sentence, period at end).
- The method channel call site (`_mapPlatformException`) picks up the new mapping automatically with no code change.
- The downstream wildcard `_ =>` in `_mapExceptionToBiometricException` correctly absorbs the new value without a compile error.
- The string literal `'KEY_PERMANENTLY_INVALIDATED'` is confirmed to match both Phase 1 and Phase 2 channel codes exactly.

The reservations are:

1. **`fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` has not been executed** as part of this QA review. This is the PRD's primary acceptance criterion and the task 3.1 checkbox. It must be confirmed green before Phase 3 is considered released.

2. **No Dart unit test exists for `BiometricCipherExceptionCode.fromString('KEY_PERMANENTLY_INVALIDATED')`**. The PRD explicitly names this test as the verification method. Without it, the acceptance criterion is met only by code inspection — and Phase 4 will depend on this mapping as a contract. Adding the test before merge is strongly recommended. It is a five-line test that provides permanent regression protection for all downstream phases.

Once both items are resolved, Phase 3 is releasable and Phase 4 can proceed with the `BiometricCipherExceptionCode.keyPermanentlyInvalidated` contract this phase establishes.
