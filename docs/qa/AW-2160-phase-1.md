# QA Plan: AW-2160 Phase 1 — Android: Detect `KeyPermanentlyInvalidatedException`

Status: REVIEWED
Date: 2026-03-16

---

## Phase Scope

Phase 1 is limited to the **Android native layer** of the `biometric_cipher` plugin. It introduces detection of `KeyPermanentlyInvalidatedException` so that the Flutter method channel emits a distinct error code `"KEY_PERMANENTLY_INVALIDATED"` instead of the previous generic fallback (`"decrypt"` or `"encrypt"`).

Two Kotlin files are in scope:

- `packages/biometric_cipher/android/src/main/kotlin/com/adguard/cryptowallet/biometric_cipher/errors/ErrorType.kt`
- `packages/biometric_cipher/android/src/main/kotlin/com/adguard/cryptowallet/biometric_cipher/handlers/SecureMethodCallHandlerImpl.kt`

Out of scope for this phase: iOS/macOS native, Dart plugin enum mapping, locker library changes, and any app-layer wiring (those are Phases 2–6).

---

## Implementation Status (observed)

Both files were read directly from the repository.

**`ErrorType.kt`** — verified:
- `KEY_PERMANENTLY_INVALIDATED` is present as the 13th enum value, immediately before `UNKNOWN_EXCEPTION`.
- The `errorDescription` `when` block contains `KEY_PERMANENTLY_INVALIDATED -> "Biometric key has been permanently invalidated"` between `AUTHENTICATION_ERROR` and `UNKNOWN_EXCEPTION`.
- The `when` block is exhaustive (no `else` branch); the compiler would reject a missing case.

**`SecureMethodCallHandlerImpl.kt`** — verified:
- Import `android.security.keystore.KeyPermanentlyInvalidatedException` is present at line 4.
- The `when(e)` block inside `executeOperation()` catch clause has the correct three-branch order:
  1. `is BaseException -> e.code`
  2. `is KeyPermanentlyInvalidatedException -> ErrorType.KEY_PERMANENTLY_INVALIDATED.name`
  3. `else -> operationName`
- The branch is applied uniformly across all operations routed through `executeOperation()` (encrypt, decrypt, generateKey, deleteKey, getTPMStatus, getBiometryStatus, configure).

---

## Positive Scenarios

### PS-1: Decrypt triggers `KeyPermanentlyInvalidatedException`

**Setup:** A biometric wrap exists in storage. The user has added or removed a fingerprint, permanently invalidating the Android KeyStore key. The app calls the `decrypt` method channel operation.

**Expected:**
- `Cipher.init()` throws `KeyPermanentlyInvalidatedException` before `BiometricPrompt` is shown.
- `executeOperation()` catches the exception; the `when` expression matches `is KeyPermanentlyInvalidatedException`.
- `errorCode` is set to `ErrorType.KEY_PERMANENTLY_INVALIDATED.name` = `"KEY_PERMANENTLY_INVALIDATED"`.
- `result.error("KEY_PERMANENTLY_INVALIDATED", <message>, null)` is delivered on the method channel.
- The Dart layer receives a `PlatformException` with `code == "KEY_PERMANENTLY_INVALIDATED"`.

### PS-2: Encrypt triggers `KeyPermanentlyInvalidatedException`

**Setup:** Same key invalidation condition; the app calls the `encrypt` method channel operation.

**Expected:** Identical channel output — `"KEY_PERMANENTLY_INVALIDATED"` — because `executeOperation()` is shared across all operations.

### PS-3: Error message fallback when `e.message` is null

**Setup:** A `KeyPermanentlyInvalidatedException` instance where `getMessage()` returns null (uncommon but possible).

**Expected:**
- `errorMessage` falls back to `ErrorType.UNKNOWN_EXCEPTION.errorDescription` = `"Unknown exception"`.
- The error *code* is still `"KEY_PERMANENTLY_INVALIDATED"` — the code is what matters for Dart-layer routing.
- Channel delivers `result.error("KEY_PERMANENTLY_INVALIDATED", "Unknown exception", null)`.

---

## Negative and Edge Cases

### NC-1: Wrong fingerprint — `BaseException` path must not change

**Setup:** User presents wrong fingerprint; `BiometricPrompt.onAuthenticationError` fires; an `AuthenticationException` (a `BaseException` subclass) is thrown.

**Expected:**
- `when(e)` matches `is BaseException` (first branch) before reaching the new branch.
- `errorCode` = `e.code` (e.g., `"AUTHENTICATION_ERROR"`).
- No change to existing behavior.

### NC-2: User cancels biometric prompt — `BaseException` path must not change

**Setup:** User taps the cancel button; `AUTHENTICATION_USER_CANCELED` is produced via `AuthenticationException`.

**Expected:**
- `when(e)` matches `is BaseException`.
- `errorCode` = `"AUTHENTICATION_USER_CANCELED"`.
- No change to existing behavior.

### NC-3: Biometric lockout

**Setup:** Too many failed attempts trigger a lockout; an `AuthenticationException` with lockout code is thrown.

**Expected:** Handled by `is BaseException` branch; error code unchanged.

### NC-4: Unclassified / unexpected exception in `executeOperation()`

**Setup:** Any `Exception` that is neither a `BaseException` nor a `KeyPermanentlyInvalidatedException` (e.g., an unexpected `NullPointerException`).

**Expected:**
- `when(e)` falls through to `else -> operationName`.
- Error code is the method name (e.g., `"decrypt"`).
- This behavior is identical to pre-Phase-1.

### NC-5: `KeyPermanentlyInvalidatedException` is NOT a `BaseException` subclass (class hierarchy regression)

**Design-time check (verified):** `KeyPermanentlyInvalidatedException` extends `java.security.GeneralSecurityException`. The plugin's `BaseException` extends `kotlin.Exception`. They share no common hierarchy below `Exception`. The new branch is independently reachable.

**Expected:** Both branches reachable; no shadowing.

### NC-6: Enum exhaustiveness — adding `KEY_PERMANENTLY_INVALIDATED` without `errorDescription` entry

**Design-time check (verified):** The `when` block in `errorDescription` has no `else` branch. Kotlin enforces exhaustiveness at compile time. The new value is already present in the `when` block. A build failure would be the observable signal of a regression here.

### NC-7: `KEY_PERMANENTLY_INVALIDATED` channel code reaching Dart before Phase 3

**Expected (accepted interim behavior):** Until Phase 3 maps `"KEY_PERMANENTLY_INVALIDATED"` in `BiometricCipherExceptionCode.fromString`, the code falls through to the `unknown` case in the Dart enum. This is acceptable and documented in the plan. The channel code itself is correct.

### NC-8: `KeyPermanentlyInvalidatedException` thrown during `generateKey`, `deleteKey`, `configure`, `getTPMStatus`, `getBiometryStatus`

**Expected:** `executeOperation()` is shared. If `KeyPermanentlyInvalidatedException` somehow propagates from any of these operations (theoretically unexpected since key invalidation is a `Cipher.init()` concern), the same `"KEY_PERMANENTLY_INVALIDATED"` code would be emitted. This is acceptable behavior — the error code remains semantically accurate regardless of operation name.

---

## Automated Tests Coverage

### Existing tests (verified to cover non-regression)

| Test file | What it covers | Relevance to Phase 1 |
|-----------|---------------|----------------------|
| `SecureServiceTest.kt` | `SecureServiceImpl` — `generateKey`, `encrypt`, `decrypt`, `deleteKey`, `getTPMStatus` via mocked `SecureRepository` and `AuthenticateService` | Does not reference `executeOperation()` or `ErrorType`. Not broken by Phase 1 changes. |
| `AuthenticateServiceTest.kt` | `AuthenticateServiceImpl` — `authenticateUser`, config and activity preconditions | Does not reference `executeOperation()` or `ErrorType`. Not broken by Phase 1 changes. |
| `AuthenticationRepositoryTest.kt` | `AuthenticationRepositoryImpl` — biometric prompt callback mapping | Does not reference `executeOperation()` or `ErrorType`. Not broken by Phase 1 changes. |
| `SecureRepositoryInstrumentedTest.kt` | `SecureRepositoryImpl` — instrumented (device) test | Does not reference `executeOperation()` or `ErrorType`. Not broken by Phase 1 changes. |

### Missing automated tests (deferred by design)

- **No Kotlin unit test for `executeOperation()` error routing** — explicitly deferred to Phase 3. There is no test that directly asserts the `when(e)` branch order or that `KeyPermanentlyInvalidatedException` produces `"KEY_PERMANENTLY_INVALIDATED"`. The plan documents this as acceptable because Phase 3 Dart unit tests will validate the full channel code flow end-to-end.
- **No integration test** — verifying the actual `Cipher.init()` exception on a real or Robolectric-emulated keystore is not implemented.

---

## Manual Checks Needed

### MC-1: Android debug APK build

**Check:** Run `fvm flutter build apk --debug` from the repository root (or from `example/`).

**Pass criterion:** Build completes without compile errors. The Kotlin compiler's exhaustiveness check on `errorDescription` and the import resolution for `KeyPermanentlyInvalidatedException` are implicitly validated here.

**Status:** Not yet executed as part of this QA review. Must be confirmed before release.

### MC-2: Confirm `KEY_PERMANENTLY_INVALIDATED` channel code on a physical Android device

**Check:** On a device with an existing biometric wrap, add or remove a fingerprint in device settings, then trigger a decrypt operation. Observe the method channel error code in debug logs or via a temporary diagnostic in the app layer.

**Pass criterion:** Log shows `"KEY_PERMANENTLY_INVALIDATED"` in the `executeOperation` error log line (`"Error during 'decrypt': KEY_PERMANENTLY_INVALIDATED, details: ..."`) instead of `"decrypt"`.

**Note:** This is a deep manual test requiring a real device with enrolled biometrics. It is the most direct end-to-end validation of the fix. Given that Phase 3 Dart tests will provide automated coverage, this check is recommended but may be deferred to Phase 3 integration testing.

### MC-3: Verify `"decrypt"` fallback no longer appears for key invalidation

**Check:** Same setup as MC-2 but specifically confirm the old error code `"decrypt"` is absent from the channel error when the key is permanently invalidated.

**Pass criterion:** No `result.error("decrypt", ...)` call is triggered for this error path.

### MC-4: Verify existing error flows on physical device

**Check:** Wrong fingerprint and user-cancel flows continue to produce `"AUTHENTICATION_ERROR"` and `"AUTHENTICATION_USER_CANCELED"` respectively.

**Pass criterion:** Existing error codes unchanged on device.

---

## Risk Zone

| Risk | Severity | Status |
|------|----------|--------|
| `executeOperation()` error routing has no dedicated unit test | Medium | Accepted — deferred to Phase 3 by design. If Phase 3 is delayed, there is a gap window where the new branch is untested by automation. |
| APK build not verified in this QA pass | Medium | Must be closed before releasing. Build verification is listed as the primary acceptance criterion in the PRD. |
| Device-level manual test not performed | Low-Medium | Acceptable for Phase 1 in isolation; Phase 3 Dart tests will provide automated coverage. |
| Tasklist checkbox state is stale (both tasks show unchecked) | Low | The source code confirms implementation is complete. The tasklist was not updated to reflect completion. Should be corrected. |
| Dart layer receives `"KEY_PERMANENTLY_INVALIDATED"` before Phase 3 ships | Low | Documented interim state. Falls through to `unknown` in the Dart enum. No crash, no incorrect recovery — just unrouted. |
| `e.message` null produces `"Unknown exception"` message | Very Low | Error code is correct; only the message is degraded. Acceptable. |

---

## Final Verdict

**With reservations.**

The implementation is structurally correct and complete:

- Both required files are modified exactly as specified in the plan.
- Enum placement, `errorDescription` exhaustiveness, import, and `when` branch ordering all match the design.
- No existing tests are broken.

The reservations are:

1. **APK build verification has not been confirmed** in this QA pass. This is the primary acceptance criterion stated in the PRD and plan. It must be executed and pass before the phase can be considered fully released.
2. **No automated test covers the `executeOperation()` routing logic directly.** This is accepted by design (deferred to Phase 3), but it represents a gap that must be closed in Phase 3 — not as an optional item.
3. **The tasklist file (`docs/tasklist-2160.md`) still shows unchecked boxes** for tasks 1.1 and 1.2 despite the implementation being present in source. This administrative inconsistency should be corrected.

Once the APK build is confirmed green, Phase 1 is releasable and Phase 3 can proceed with the contract this phase establishes.
