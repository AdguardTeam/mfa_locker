# Research: AW-2160 Phase 1 — Android: Detect `KeyPermanentlyInvalidatedException`

## 1. Resolved Questions

**Q1 — Test scope:** Verify SecureServiceTest and AuthenticateServiceTest exist and understand their scope.
**A:** Both files exist (unit tests, Robolectric runner). Neither tests `executeOperation()` directly — they test `SecureServiceImpl` and `AuthenticateServiceImpl` in isolation, with mocked repositories. No existing test touches the `when(e)` catch block in `SecureMethodCallHandlerImpl`. The new catch branch therefore has no test to break and no existing test needs modification for Phase 1.

**Q2 — `errorDescription` getter:** Include the new entry.
**A:** Yes — add `KEY_PERMANENTLY_INVALIDATED -> "Biometric key has been permanently invalidated"` to the `errorDescription` getter in `ErrorType.kt` as part of Phase 1.

**Q3 — File paths:** No additional constraints; use paths from the idea/vision documents.
**A:** Exact paths confirmed below via filesystem inspection.

**Q4 — Other constraints:** None.

---

## 2. Phase Scope

Phase 1 is limited to two Kotlin files in the Android native layer of the `biometric_cipher` package:

1. Add `KEY_PERMANENTLY_INVALIDATED` enum value (and its `errorDescription` entry) to `ErrorType.kt`.
2. Add one `is KeyPermanentlyInvalidatedException` catch branch and one import to `SecureMethodCallHandlerImpl.kt`.

No new files. No Kotlin unit tests. No changes to any other layer (iOS/macOS, Dart plugin, Dart locker library).

---

## 3. Related Modules and Files

### Target files (to be modified)

| File | Absolute path |
|------|--------------|
| `ErrorType.kt` | `/Users/comrade77/Documents/Performix/Projects/mfa_locker/packages/biometric_cipher/android/src/main/kotlin/com/adguard/cryptowallet/biometric_cipher/errors/ErrorType.kt` |
| `SecureMethodCallHandlerImpl.kt` | `/Users/comrade77/Documents/Performix/Projects/mfa_locker/packages/biometric_cipher/android/src/main/kotlin/com/adguard/cryptowallet/biometric_cipher/handlers/SecureMethodCallHandlerImpl.kt` |

### Existing test files (read-only for Phase 1 — must not regress)

| File | Absolute path |
|------|--------------|
| `SecureServiceTest.kt` | `/Users/comrade77/Documents/Performix/Projects/mfa_locker/packages/biometric_cipher/android/src/test/kotlin/com/adguard/cryptowallet/biometric_cipher/services/SecureServiceTest.kt` |
| `AuthenticateServiceTest.kt` | `/Users/comrade77/Documents/Performix/Projects/mfa_locker/packages/biometric_cipher/android/src/test/kotlin/com/adguard/cryptowallet/biometric_cipher/services/AuthenticateServiceTest.kt` |

### Reference-only files (not modified in Phase 1)

- `SecureServiceImpl.kt` — shows where `getCipher(secretKey, Cipher.DECRYPT_MODE, spec)` (the throw site) lives.
- `SecureRepositoryImpl.kt` — confirms `getCipher()` calls `cipher.init()` directly, which is where `KeyPermanentlyInvalidatedException` is thrown.
- `BaseException.kt` — confirms `BaseException` extends `Exception`, not `GeneralSecurityException`, so `KeyPermanentlyInvalidatedException` can never be a `BaseException` subclass. The new branch is unreachable-risk is negated.

---

## 4. Current State of Target Files

### 4.1 `ErrorType.kt` — current content

Package: `com.adguard.cryptowallet.biometric_cipher.errors`

Current enum values (in order):
```
INVALID_ARGUMENT
KEY_NOT_FOUND
KEY_ALREADY_EXISTS
BIOMETRIC_NOT_SUPPORTED
CONFIGURE_BIOMETRIC_ERROR
CONFIGURE_NEGATIVE_BUTTON_ERROR
CONFIGURE_TITLE_PROMPT_ERROR
CONFIGURE_SUBTITLE_PROMPT_ERROR
ACTIVITY_NOT_SET
DECODE_DATA_INVALID_SIZE
AUTHENTICATION_USER_CANCELED
AUTHENTICATION_ERROR
UNKNOWN_EXCEPTION   ← terminator; new value goes immediately before this
```

Current `errorDescription` getter — full `when` block (13 branches, exhaustive):
```kotlin
INVALID_ARGUMENT          -> "Invalid argument"
KEY_NOT_FOUND             -> "Key not found"
KEY_ALREADY_EXISTS        -> "Key already exists"
BIOMETRIC_NOT_SUPPORTED   -> "Biometric not supported"
CONFIGURE_BIOMETRIC_ERROR -> "Biometric prompt data is not configured"
CONFIGURE_NEGATIVE_BUTTON_ERROR -> "Negative button text is not configured"
CONFIGURE_TITLE_PROMPT_ERROR    -> "Title text is not configured"
CONFIGURE_SUBTITLE_PROMPT_ERROR -> "Subtitle text is not configured"
ACTIVITY_NOT_SET          -> "Activity not set"
DECODE_DATA_INVALID_SIZE  -> "Decode data invalid size"
AUTHENTICATION_USER_CANCELED -> "Authentication user canceled"
AUTHENTICATION_ERROR      -> "Authentication error"
UNKNOWN_EXCEPTION         -> "Unknown exception"
```

The `when` expression is exhaustive (no `else` branch). Adding a new enum value without a corresponding `when` branch will cause a **compile error** — this is a safe guard that prevents the description getter from silently returning nothing.

**Required changes:**
1. Insert `KEY_PERMANENTLY_INVALIDATED,` between `AUTHENTICATION_ERROR,` and `UNKNOWN_EXCEPTION;` in the enum declaration.
2. Insert `KEY_PERMANENTLY_INVALIDATED -> "Biometric key has been permanently invalidated"` in the `when` block, between the `AUTHENTICATION_ERROR` branch and the `UNKNOWN_EXCEPTION` branch.

### 4.2 `SecureMethodCallHandlerImpl.kt` — current `executeOperation()` catch block

```kotlin
} catch (e: Exception) {
    val errorCode = when (e) {
        is BaseException -> {
            e.code
        }

        else -> {
            operationName
        }
    }
    val errorMessage = e.message ?: ErrorType.UNKNOWN_EXCEPTION.errorDescription
    Log.e(TAG, "Error during '$operationName': $errorCode, details: $errorMessage")
    onError(errorCode, errorMessage)
}
```

Current imports include `BaseException` and `ErrorType` but **not** `KeyPermanentlyInvalidatedException`.

**Required changes:**
1. Add import: `import android.security.keystore.KeyPermanentlyInvalidatedException`
2. Insert `is KeyPermanentlyInvalidatedException` branch between the `is BaseException` branch and the `else` branch.

The `errorMessage` line (`e.message ?: ErrorType.UNKNOWN_EXCEPTION.errorDescription`) applies to all branches uniformly. For `KeyPermanentlyInvalidatedException`, `e.message` is typically non-null (the Android SDK provides a message), but the fallback is harmless.

---

## 5. Existing Test Scope

### `SecureServiceTest.kt`

- Runner: Robolectric (`@RunWith(RobolectricTestRunner::class)`)
- Class under test: `SecureServiceImpl`
- Mocks: `SecureRepository`, `AuthenticateService`
- Tests: `getTPMStatus`, `generateKey` (×2), `encrypt` (×2), `decrypt` (×2), `deleteKey` (×2)
- **Does not touch `SecureMethodCallHandlerImpl` or `ErrorType`** — tests at the service layer, one level below the handler. Phase 1 changes are invisible to this test.

### `AuthenticateServiceTest.kt`

- Runner: Robolectric (`@RunWith(RobolectricTestRunner::class)`)
- Class under test: `AuthenticateServiceImpl`
- Mocks: `AuthenticationRepository`, `ConfigStorage`
- Tests: `authenticateUser` — three cases (not configured, no activity, happy path)
- **Does not touch `SecureMethodCallHandlerImpl` or `ErrorType`** — tests at the authentication service layer. Phase 1 changes are invisible to this test.

**Conclusion:** Neither test file references `executeOperation()`, `ErrorType`, or any exception type added in Phase 1. Both will continue to pass without modification.

### `AuthenticationRepositoryTest.kt` (additional test file found)

Located at: `/Users/comrade77/Documents/Performix/Projects/mfa_locker/packages/biometric_cipher/android/src/test/kotlin/com/adguard/cryptowallet/biometric_cipher/repositories/AuthenticationRepositoryTest.kt`

Not in the PRD's success criteria list, but present. Tests the `AuthenticationRepository` layer — unaffected by Phase 1 changes.

---

## 6. Exception Hierarchy Verification

`BaseException` (plugin-defined):
```kotlin
open class BaseException(val code: String, message: String, cause: Throwable? = null) : Exception(message, cause)
```

`KeyPermanentlyInvalidatedException` (Android SDK):
- Extends `InvalidKeyException` → `KeyException` → `GeneralSecurityException` → `Exception`
- Is **not** a `BaseException` subclass. Confirmed: no shared ancestor between the two hierarchies below `Exception`.

This means the new `is KeyPermanentlyInvalidatedException` branch will always be reached for this exception type and will never be shadowed by the `is BaseException` branch. The PRD's risk of the new branch being unreachable is definitively mitigated.

---

## 7. How `KeyPermanentlyInvalidatedException` Is Thrown

From `SecureRepositoryImpl.getCipher()`:
```kotlin
override fun getCipher(secretKey: SecretKey, optMode: Int, spec: GCMParameterSpec?): Cipher =
    Cipher.getInstance(SecureObjects.TRANSFORMATION).apply {
        if (spec != null) {
            init(optMode, secretKey, spec)  // ← throws KeyPermanentlyInvalidatedException here
        } else {
            init(optMode, secretKey)         // ← or here
        }
    }
```

This is called by `SecureServiceImpl.decrypt()` and `SecureServiceImpl.encrypt()` before `authenticateService.authenticateUser(cipher)` is invoked, so the biometric prompt is never shown. The exception propagates through `SecureServiceImpl` up into `executeOperation()` in `SecureMethodCallHandlerImpl`.

The `executeOperation()` function wraps the entire `operation` lambda in a single `try/catch (e: Exception)`, so `KeyPermanentlyInvalidatedException` (which is an `Exception` subclass) is already caught — it just falls to the `else` branch today, producing `operationName` (e.g. `"decrypt"`) as the error code.

---

## 8. Phase-Specific Limitations and Risks

| Risk | Status |
|------|--------|
| New `when` branch is unreachable because `KeyPermanentlyInvalidatedException` is a `BaseException` subclass | **Eliminated.** `BaseException` extends `Exception`; `KeyPermanentlyInvalidatedException` extends `GeneralSecurityException`. No shared hierarchy. |
| `errorDescription` `when` is non-exhaustive after adding the enum value | **Mitigated by Kotlin compiler.** The `when` expression has no `else` branch, so adding the enum value without its description entry is a compile error. The build will fail before it can ship. |
| Placement of new enum value disrupts serialization | **Not applicable.** `ErrorType` values are used only as `.name` strings on the channel. No serialized ordinal is used anywhere in the plugin. |
| Existing tests break | **Not applicable.** Both test files operate on layers below `executeOperation()` and do not reference `ErrorType` or the handler. |
| `e.message` is null for `KeyPermanentlyInvalidatedException` | **Low risk.** The Android SDK typically provides a message. The fallback `ErrorType.UNKNOWN_EXCEPTION.errorDescription` ("Unknown exception") is acceptable — the error *code* is what matters for the Dart layer. |
| `operationName` fallback (`else` branch) still fires for some `KeyPermanentlyInvalidatedException` instances | **Impossible.** Kotlin `when` with `is` checks at runtime; any instance of the class (or subclasses) will match the `is KeyPermanentlyInvalidatedException` branch. |

---

## 9. New Technical Questions

None discovered during research. The PRD, idea, and vision documents are internally consistent with the actual codebase state.
