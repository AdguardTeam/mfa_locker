# Phase 1: Android — detect `KeyPermanentlyInvalidatedException`

**Goal:** Surface `KEY_PERMANENTLY_INVALIDATED` through the Flutter method channel instead of the generic `"decrypt"` fallback.

## Context

**Feature motivation:** When the Android KeyStore key has been invalidated by a biometric enrollment change, `cipher.init()` throws `KeyPermanentlyInvalidatedException`. Currently this surfaces as error code `"decrypt"` — indistinguishable from any other crash in the decrypt path. The app needs a distinct error code to trigger password-only teardown.

**Technical approach:** Add one enum value to `ErrorType` and one `is KeyPermanentlyInvalidatedException` catch branch in `executeOperation()`. No changes to `SecureRepositoryImpl.getCipher()` or `AuthenticationRepositoryImpl.onAuthenticationError()`.

**Error propagation chain (Android path):**
```
KeyPermanentlyInvalidatedException (cipher.init())
  → ErrorType.KEY_PERMANENTLY_INVALIDATED
  → FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")
  → BiometricCipherExceptionCode.keyPermanentlyInvalidated (Dart, Iteration 3)
```

**Important:** `BiometricPrompt.ERROR_KEY_PERMANENTLY_INVALIDATED` does **not** exist in the Android SDK (error code 7 is `ERROR_LOCKOUT`). The exception is thrown from `Cipher.init()` _before_ the prompt is shown, so `onAuthenticationError` is never involved.

## Tasks

- [ ] **1.1** Add `KEY_PERMANENTLY_INVALIDATED` to `ErrorType` enum and its `errorDescription`
  - File: `packages/biometric_cipher/android/src/main/kotlin/.../errors/ErrorType.kt`
  - Add value before `UNKNOWN_EXCEPTION`
  - Description: `"Biometric key has been permanently invalidated"`

- [ ] **1.2** Catch `KeyPermanentlyInvalidatedException` in `executeOperation()`
  - File: `packages/biometric_cipher/android/src/main/kotlin/.../handlers/SecureMethodCallHandlerImpl.kt`
  - Add import: `android.security.keystore.KeyPermanentlyInvalidatedException`
  - Add `is KeyPermanentlyInvalidatedException` branch in the `when(e)` block, between `is BaseException` and `else`
  - Map to `ErrorType.KEY_PERMANENTLY_INVALIDATED.name`

## Acceptance Criteria

**Verify:** Build Android (`fvm flutter build apk --debug`). The new error code flows through the channel — testable via Dart unit tests in Iteration 3.

## Dependencies

- None (this is the first iteration)

## Technical Details

### ErrorType.kt — target state

```kotlin
enum class ErrorType {
    INVALID_ARGUMENT,
    KEY_NOT_FOUND,
    KEY_ALREADY_EXISTS,
    BIOMETRIC_NOT_SUPPORTED,
    CONFIGURE_BIOMETRIC_ERROR,
    CONFIGURE_NEGATIVE_BUTTON_ERROR,
    CONFIGURE_TITLE_PROMPT_ERROR,
    CONFIGURE_SUBTITLE_PROMPT_ERROR,
    ACTIVITY_NOT_SET,
    DECODE_DATA_INVALID_SIZE,
    AUTHENTICATION_USER_CANCELED,
    AUTHENTICATION_ERROR,
    KEY_PERMANENTLY_INVALIDATED,  // new
    UNKNOWN_EXCEPTION;

    val errorDescription
        get() = when (this) {
            // ... existing entries unchanged ...
            KEY_PERMANENTLY_INVALIDATED -> "Biometric key has been permanently invalidated"
            // ...
        }
}
```

### SecureMethodCallHandlerImpl.kt — catch block target state

```kotlin
import android.security.keystore.KeyPermanentlyInvalidatedException

// In executeOperation(), inside the catch block:
val errorCode = when (e) {
    is BaseException -> e.code
    is KeyPermanentlyInvalidatedException -> ErrorType.KEY_PERMANENTLY_INVALIDATED.name  // new
    else -> operationName
}
```

## Implementation Notes

- `KeyPermanentlyInvalidatedException` is a `java.security.GeneralSecurityException` subclass — it is NOT a `BaseException`, which is why it currently falls through to the `else` branch.
- The exception is thrown from `Cipher.init()` **before** `BiometricPrompt` is shown.
- No behavior changes to existing flows — generic auth failures continue producing existing error types.
- Principle: KISS — minimal changes, follow existing patterns.
