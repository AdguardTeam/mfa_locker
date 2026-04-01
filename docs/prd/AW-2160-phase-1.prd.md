# AW-2160-1: Android — Detect `KeyPermanentlyInvalidatedException`

Status: PRD_READY

## Context / Idea

This is Phase 1 of AW-2160, which as a whole adds biometric key invalidation detection and a password-only teardown path across the full stack (Android, iOS/macOS native, Dart plugin, and locker library). Phase 1 is narrowly scoped to the **Android native layer** only.

**The problem:** When a user enrolls a new fingerprint or removes all biometrics on Android, the Android KeyStore permanently invalidates the key associated with the current biometric wrap. The next time the `decrypt` method is called, `Cipher.init()` throws `KeyPermanentlyInvalidatedException` before the `BiometricPrompt` is even shown. This exception is a `GeneralSecurityException` subclass and is not a `BaseException` in the plugin's hierarchy. Consequently it falls through to the `else` branch of the `when(e)` block in `executeOperation()` and surfaces as error code `"decrypt"` — identical to any other unclassified crash in the decrypt path. The app layer cannot distinguish a permanently invalidated key from a generic decrypt failure, so it cannot trigger the appropriate recovery flow (password-only teardown).

**The fix (Phase 1):** Add one new enum value `KEY_PERMANENTLY_INVALIDATED` to `ErrorType.kt` and catch `KeyPermanentlyInvalidatedException` explicitly in `SecureMethodCallHandlerImpl.kt`, mapping it to that enum value so the Flutter method channel emits `code: "KEY_PERMANENTLY_INVALIDATED"`.

**Affected files (both in `packages/biometric_cipher/android/`):**
- `errors/ErrorType.kt` — add `KEY_PERMANENTLY_INVALIDATED` before `UNKNOWN_EXCEPTION`
- `handlers/SecureMethodCallHandlerImpl.kt` — add `is KeyPermanentlyInvalidatedException` branch in `executeOperation()`

**Phase dependencies:**
- Phase 1 has no dependencies (it is the first iteration).
- Phase 3 (Dart plugin enum) depends on the channel code emitted by Phase 1.

---

## Goals

1. Emit the distinct channel error code `"KEY_PERMANENTLY_INVALIDATED"` when `KeyPermanentlyInvalidatedException` is caught during any biometric operation (decrypt or encrypt), instead of the misleading generic operation-name fallback.
2. Leave all existing error flows unchanged — wrong fingerprint, user cancel, lockout, and all other `BaseException`-derived errors must continue to produce their current error codes.
3. Keep the change minimal: two files touched, one new enum value, one new catch branch, one new import.

---

## User Stories

**US-1 — App detects permanently invalidated key on Android**
As the app layer consuming the `biometric_cipher` plugin, I need to receive a distinct error code when the Android KeyStore key has been permanently invalidated, so that I can trigger password-only teardown instead of showing a generic biometric error.

**US-2 — Existing auth errors are unaffected**
As the app layer, I need wrong-fingerprint, user-cancel, and lockout errors to continue producing their current error codes (`AUTHENTICATION_ERROR`, `AUTHENTICATION_USER_CANCELED`), so that existing recovery flows are not broken.

---

## Main Scenarios

### Scenario 1: Decrypt after biometric enrollment change (primary path)

1. User previously enabled biometric unlock; an `Origin.bio` wrap exists in storage.
2. User adds or removes a fingerprint in device settings.
3. App attempts biometric decrypt.
4. Android KeyStore key is invalidated; `Cipher.init()` throws `KeyPermanentlyInvalidatedException`.
5. `executeOperation()` catches the exception, matches `is KeyPermanentlyInvalidatedException`.
6. `errorCode` is set to `ErrorType.KEY_PERMANENTLY_INVALIDATED.name` = `"KEY_PERMANENTLY_INVALIDATED"`.
7. `result.error("KEY_PERMANENTLY_INVALIDATED", "Biometric key has been permanently invalidated", null)` is sent back on the Flutter method channel.
8. The Dart plugin layer (Phase 3) will map this to `BiometricCipherExceptionCode.keyPermanentlyInvalidated`.

### Scenario 2: Encrypt after biometric enrollment change (same handling, intended)

1. App attempts biometric encrypt after a biometric enrollment change.
2. `Cipher.init()` throws `KeyPermanentlyInvalidatedException`.
3. `executeOperation()` is shared across all operations — the same `is KeyPermanentlyInvalidatedException` branch fires.
4. `"KEY_PERMANENTLY_INVALIDATED"` is emitted on the channel.
5. This is intentional: key invalidation is a property of the key itself, not of the specific operation. Both paths should surface the same distinct error code.

### Scenario 3: Normal wrong-fingerprint failure (must not regress)

1. User presents wrong fingerprint.
2. `BiometricPrompt.onAuthenticationError` fires with `ERROR_AUTHENTICATION_FAILED`.
3. The existing `AuthenticationException` (a `BaseException`) is thrown.
4. `executeOperation()` matches `is BaseException` first — returns `e.code` as before.
5. No change to existing behavior.

### Scenario 4: User cancels biometric prompt (must not regress)

1. User taps the cancel button on the biometric prompt.
2. `AUTHENTICATION_USER_CANCELED` is returned as before via `AuthenticationException`.
3. No change to existing behavior.

---

## Success / Metrics

| Criterion | How to verify |
|-----------|--------------|
| `KEY_PERMANENTLY_INVALIDATED` is emitted when `KeyPermanentlyInvalidatedException` is thrown | Validated via Dart unit tests in Phase 3 (deferred; no new Kotlin unit test required in Phase 1) |
| Existing error codes are unchanged | Existing unit tests in `SecureServiceTest` and `AuthenticateServiceTest` pass without modification |
| Android debug APK builds successfully | `fvm flutter build apk --debug` completes without errors |
| `UNKNOWN_EXCEPTION` is never emitted for `KeyPermanentlyInvalidatedException` | The new branch is placed between `is BaseException` and `else`, so the `else` fallback no longer applies |

The Dart-side verification (confirming `BiometricCipherExceptionCode.keyPermanentlyInvalidated` is received) is out of scope for Phase 1 — it is covered by Phase 3.

---

## Constraints and Assumptions

- `KeyPermanentlyInvalidatedException` is available from Android API level 23 (the minimum supported by the plugin). No API level guard is needed.
- `KeyPermanentlyInvalidatedException` is thrown from `Cipher.init()` before `BiometricPrompt` is shown, so `onAuthenticationError` is never involved — no changes to `AuthenticationRepositoryImpl` are required.
- `BiometricPrompt.ERROR_KEY_PERMANENTLY_INVALIDATED` does **not** exist in the Android SDK (error code 7 is `ERROR_LOCKOUT`). The exception path is `Cipher.init()` only.
- No changes to `SecureRepositoryImpl.getCipher()` are required — the exception is caught at the handler level, not suppressed at the repository level.
- The new enum value `KEY_PERMANENTLY_INVALIDATED` must be placed immediately before `UNKNOWN_EXCEPTION` in `ErrorType.kt` to preserve the existing enum ordering convention.
- The `when` expression in `executeOperation()` must maintain the order: `is BaseException` first, then `is KeyPermanentlyInvalidatedException`, then `else`. This ensures `BaseException` subclasses are still matched by the first branch.
- No Kotlin unit tests are added in Phase 1. Testing is deferred to Phase 3 via Dart unit tests.
- The fix applies to both `encrypt` and `decrypt` paths by virtue of `executeOperation()` being shared. This is intentional.

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| `KeyPermanentlyInvalidatedException` is also a `BaseException` subclass (would make the new branch unreachable) | Low — `KeyPermanentlyInvalidatedException` extends `GeneralSecurityException`, not `BaseException` | High | Verify class hierarchy before implementation; the existing `BaseException` hierarchy is defined in the plugin, not the Android SDK |
| Exception is not thrown before biometric prompt on some Android versions | Very low — Android SDK documentation guarantees this behavior since API 23 | Medium | Acceptable; the `else` branch still catches it, only the error code would be wrong — Phase 3 tests would expose this |
| New enum value breaks serialization or comparisons elsewhere in the plugin | Low — `ErrorType` is used only for error code strings, never serialized | Low | Grep for `ErrorType` usages before submitting; no deserialization logic found |

---

## Resolved Questions

1. **Unit test scope for Phase 1:** No new Kotlin unit test in Phase 1. Testing is validated via Dart unit tests in Phase 3. The build verification (`fvm flutter build apk --debug`) is sufficient for this phase.

2. **`encrypt` path behavior:** `KEY_PERMANENTLY_INVALIDATED` is emitted for both `encrypt` and `decrypt` when `KeyPermanentlyInvalidatedException` is thrown. `executeOperation()` is shared across all operations, so the same catch branch fires regardless of which operation triggered it. This is intentional — key invalidation is a property of the key itself, not the specific operation.

---

## Open Questions

None.
