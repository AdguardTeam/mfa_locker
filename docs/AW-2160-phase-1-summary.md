# AW-2160 Phase 1 Summary — Android: Detect `KeyPermanentlyInvalidatedException`

## What Was Done

Phase 1 is the Android native portion of AW-2160. It resolves a gap in the `biometric_cipher` plugin where a permanently invalidated biometric key was indistinguishable from any other decrypt failure.

Two Kotlin files in `packages/biometric_cipher/android/` were modified. No new files were created and no other layers (iOS/macOS, Dart plugin, locker library) were touched.

### The Problem

When a user adds or removes a fingerprint on Android, the Android KeyStore permanently invalidates the key backing the biometric wrap. The next call to `Cipher.init()` throws `KeyPermanentlyInvalidatedException` before the biometric prompt is even shown. Because this exception is a `java.security.GeneralSecurityException` subclass — not a `BaseException` from the plugin's own hierarchy — it fell through to the `else` branch in `executeOperation()` and surfaced on the Flutter method channel as `result.error("decrypt", ...)`. That generic error code is identical to any other unclassified decrypt crash, so the Dart layer had no way to detect key invalidation and could not trigger the appropriate recovery flow (password-only biometric teardown).

### The Fix

**`errors/ErrorType.kt`**

Added `KEY_PERMANENTLY_INVALIDATED` as a new enum value immediately before `UNKNOWN_EXCEPTION`, and added the corresponding `errorDescription` entry (`"Biometric key has been permanently invalidated"`). The `errorDescription` getter has no `else` branch, so Kotlin's exhaustiveness check guarantees a compile error if the description is ever omitted — this is a built-in safety net.

**`handlers/SecureMethodCallHandlerImpl.kt`**

Added the import `android.security.keystore.KeyPermanentlyInvalidatedException` and inserted a new branch in the `when(e)` block inside `executeOperation()`:

```
is BaseException                    → e.code            (unchanged — first, highest priority)
is KeyPermanentlyInvalidatedException → "KEY_PERMANENTLY_INVALIDATED"  (new)
else                                → operationName     (unchanged fallback)
```

Branch ordering is critical: `KeyPermanentlyInvalidatedException` extends `GeneralSecurityException`, not `BaseException`, so both branches are independently reachable. Placing the new branch after `is BaseException` ensures existing plugin exceptions are never misrouted.

The fix applies to both `encrypt` and `decrypt` (and any other operation routed through `executeOperation()`) because key invalidation is a property of the key itself, not of the specific operation.

---

## Decisions Made

**Why a new enum value, not an inline string constant?**
Following the existing pattern in `ErrorType.kt`. Using the enum keeps error code definitions in one place and gives the compiler exhaustiveness guarantees on `errorDescription`.

**Why no new Kotlin unit test in Phase 1?**
Explicitly deferred to Phase 3 by design. Phase 3 adds `keyPermanentlyInvalidated` to the Dart `BiometricCipherExceptionCode` enum and writes Dart unit tests that validate the full method channel contract, including the `"KEY_PERMANENTLY_INVALIDATED"` code. A Kotlin unit test for `executeOperation()` routing is also absent from the existing test suite — adding it only for the new branch, without covering the existing branches, would be inconsistent. Phase 3 closes this gap holistically.

**Why no change to `SecureRepositoryImpl.getCipher()` or `AuthenticationRepositoryImpl`?**
The exception is thrown from `Cipher.init()` inside the repository before the biometric prompt appears. `BiometricPrompt.onAuthenticationError` is never invoked for this condition (`ERROR_KEY_PERMANENTLY_INVALIDATED` does not exist in the Android SDK — error code 7 is `ERROR_LOCKOUT`). Catching at the handler level is the correct and minimal approach.

---

## API Contract Change

| Condition | Before Phase 1 | After Phase 1 |
|-----------|----------------|---------------|
| `KeyPermanentlyInvalidatedException` during `decrypt` | `result.error("decrypt", ...)` | `result.error("KEY_PERMANENTLY_INVALIDATED", ...)` |
| `KeyPermanentlyInvalidatedException` during `encrypt` | `result.error("encrypt", ...)` | `result.error("KEY_PERMANENTLY_INVALIDATED", ...)` |
| `BaseException` subclass (any operation) | `result.error(e.code, ...)` | Unchanged |
| Other unclassified exception | `result.error(operationName, ...)` | Unchanged |

Until Phase 3 ships, the Dart plugin's `BiometricCipherExceptionCode.fromString` will map `"KEY_PERMANENTLY_INVALIDATED"` to the `unknown` case. This is the documented and accepted interim state — no crash, no incorrect recovery, simply an unrouted error code.

---

## Files Changed

| File | Change |
|------|--------|
| `packages/biometric_cipher/android/src/main/kotlin/com/adguard/cryptowallet/biometric_cipher/errors/ErrorType.kt` | Added `KEY_PERMANENTLY_INVALIDATED` enum value and `errorDescription` entry |
| `packages/biometric_cipher/android/src/main/kotlin/com/adguard/cryptowallet/biometric_cipher/handlers/SecureMethodCallHandlerImpl.kt` | Added import and `is KeyPermanentlyInvalidatedException` catch branch in `executeOperation()` |

---

## QA Status

The QA review (docs/qa/AW-2160-phase-1.md) confirmed the implementation matches the plan exactly:
- Enum value placement, `errorDescription` entry, import, and `when` branch ordering are all correct.
- No existing tests are broken.

Two open items from the QA review before Phase 1 is fully releasable:
1. **APK build verification** (`fvm flutter build apk --debug`) has not been confirmed. This is the primary acceptance criterion from the PRD and must pass before release.
2. **Tasklist checkboxes** for tasks 1.1 and 1.2 in `docs/tasklist-2160.md` remain unchecked despite the implementation being complete — an administrative inconsistency to correct.

---

## Phase Dependencies

- **Depends on:** Nothing (Phase 1 is the first iteration).
- **Unblocks:** Phase 3 (Dart plugin enum) — Phase 3 maps the `"KEY_PERMANENTLY_INVALIDATED"` channel code emitted here to `BiometricCipherExceptionCode.keyPermanentlyInvalidated` and provides the Dart-layer unit tests for the full contract.
