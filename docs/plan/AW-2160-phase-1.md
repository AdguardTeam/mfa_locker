# Plan: AW-2160 Phase 1 -- Android: Detect `KeyPermanentlyInvalidatedException`

Status: PLAN_APPROVED

## Phase Scope

Phase 1 is limited to the **Android native layer** of the `biometric_cipher` plugin. It adds detection of `KeyPermanentlyInvalidatedException` so that the Flutter method channel emits a distinct error code (`"KEY_PERMANENTLY_INVALIDATED"`) instead of the current generic fallback (`operationName`, e.g. `"decrypt"`).

Two Kotlin files are modified. No new files are created. No other layers (iOS/macOS, Dart plugin, Dart locker library) are touched.

---

## Components

### 1. `ErrorType.kt` -- enum value addition

**Path:** `packages/biometric_cipher/android/src/main/kotlin/com/adguard/cryptowallet/biometric_cipher/errors/ErrorType.kt`

**Change:** Insert `KEY_PERMANENTLY_INVALIDATED` as a new enum value immediately before `UNKNOWN_EXCEPTION`. Add the corresponding branch to the exhaustive `errorDescription` getter.

**Rationale:** The `when` expression in `errorDescription` has no `else` branch. Kotlin's exhaustiveness check guarantees a compile error if the new value is added to the enum but not to the `when` block. This provides a safety net against incomplete changes.

**Placement convention:** New value goes between `AUTHENTICATION_ERROR` and `UNKNOWN_EXCEPTION`, preserving the pattern where `UNKNOWN_EXCEPTION` is always last.

### 2. `SecureMethodCallHandlerImpl.kt` -- catch branch addition

**Path:** `packages/biometric_cipher/android/src/main/kotlin/com/adguard/cryptowallet/biometric_cipher/handlers/SecureMethodCallHandlerImpl.kt`

**Changes:**
1. Add import: `import android.security.keystore.KeyPermanentlyInvalidatedException`
2. Insert `is KeyPermanentlyInvalidatedException` branch in the `when(e)` block inside `executeOperation()`, between the existing `is BaseException` branch and the `else` branch.

**Branch ordering rationale:** The `when(e)` expression evaluates branches top-to-bottom. The order must be:
1. `is BaseException` -- catches all plugin-defined exceptions (uses `e.code`)
2. `is KeyPermanentlyInvalidatedException` -- catches the specific Android SDK exception (uses `ErrorType.KEY_PERMANENTLY_INVALIDATED.name`)
3. `else` -- fallback for any other unclassified exception (uses `operationName`)

`KeyPermanentlyInvalidatedException` extends `GeneralSecurityException`, not `BaseException`, so there is no shadowing risk. Both branches are independently reachable.

---

## API Contract

### Method channel output (changed behavior)

| Condition | Before Phase 1 | After Phase 1 |
|-----------|----------------|---------------|
| `KeyPermanentlyInvalidatedException` thrown during `decrypt` | `result.error("decrypt", ...)` | `result.error("KEY_PERMANENTLY_INVALIDATED", ...)` |
| `KeyPermanentlyInvalidatedException` thrown during `encrypt` | `result.error("encrypt", ...)` | `result.error("KEY_PERMANENTLY_INVALIDATED", ...)` |
| `BaseException` thrown (any operation) | `result.error(e.code, ...)` | Unchanged |
| Other unclassified exception | `result.error(operationName, ...)` | Unchanged |

The error message is taken from `e.message` (the Android SDK typically provides one) with fallback to `ErrorType.UNKNOWN_EXCEPTION.errorDescription`. This behavior is unchanged -- only the error code differs.

**Downstream consumers (Phase 3):** The Dart plugin layer will map the `"KEY_PERMANENTLY_INVALIDATED"` channel code to `BiometricCipherExceptionCode.keyPermanentlyInvalidated`. Until Phase 3 is implemented, this code will fall through to the `unknown` case in the Dart enum's `fromString` method. This is acceptable -- Phase 1 is purely about emitting the correct code on the channel.

---

## Data Flows

```
SecureRepositoryImpl.getCipher()
  -> Cipher.init() throws KeyPermanentlyInvalidatedException
    -> propagates through SecureServiceImpl.decrypt()/encrypt()
      -> caught by executeOperation() catch block
        -> when(e) matches `is KeyPermanentlyInvalidatedException`
          -> errorCode = ErrorType.KEY_PERMANENTLY_INVALIDATED.name  ("KEY_PERMANENTLY_INVALIDATED")
          -> onError(errorCode, errorMessage)
            -> result.error("KEY_PERMANENTLY_INVALIDATED", message, null)
              -> Flutter method channel delivers PlatformException to Dart
```

No data model changes. No storage changes. No new data paths. The only change is the error code string carried by the existing error propagation path.

---

## NFR

| Requirement | How satisfied |
|-------------|---------------|
| No regression to existing error flows | Branch ordering preserves `is BaseException` priority; `KeyPermanentlyInvalidatedException` is not a `BaseException` subclass |
| Build must succeed | `fvm flutter build apk --debug` as verification step |
| Minimal change footprint | Two files, one enum value, one catch branch, one import |
| No new dependencies | `KeyPermanentlyInvalidatedException` is in the Android SDK (API 23+), which is already the plugin's minimum |

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| `KeyPermanentlyInvalidatedException` is also a `BaseException` subclass, making the new branch unreachable | Eliminated | High | Research confirmed: `BaseException` extends `Exception`; `KeyPermanentlyInvalidatedException` extends `GeneralSecurityException`. No shared hierarchy below `Exception`. |
| `errorDescription` `when` block becomes non-exhaustive after adding enum value without description | Eliminated | Build failure | Kotlin compiler enforces exhaustiveness on `when` expressions without `else`. Adding the enum value without the description branch is a compile error. |
| `e.message` is null for `KeyPermanentlyInvalidatedException` | Very low | Low | The fallback `ErrorType.UNKNOWN_EXCEPTION.errorDescription` produces `"Unknown exception"`. The error *code* is what matters for the Dart layer, not the message. |
| New enum value breaks serialization or ordinal comparisons | Not applicable | N/A | `ErrorType` values are used only as `.name` strings. No ordinal-based logic exists in the codebase. |
| Existing unit tests break | Not applicable | N/A | `SecureServiceTest` and `AuthenticateServiceTest` test service layers, not the handler. Neither references `executeOperation()` or `ErrorType`. |

---

## Dependencies

- **Previous phases:** None. Phase 1 is the first iteration.
- **External systems:** Android SDK (API 23+) -- `KeyPermanentlyInvalidatedException` is available at the plugin's minimum API level.
- **Downstream phases:** Phase 3 (Dart plugin enum) depends on the `"KEY_PERMANENTLY_INVALIDATED"` channel code emitted by this phase.

---

## Implementation Steps

1. **Edit `ErrorType.kt`:**
   - Insert `KEY_PERMANENTLY_INVALIDATED,` between `AUTHENTICATION_ERROR,` and `UNKNOWN_EXCEPTION;`
   - Insert `KEY_PERMANENTLY_INVALIDATED -> "Biometric key has been permanently invalidated"` in the `errorDescription` `when` block, between the `AUTHENTICATION_ERROR` and `UNKNOWN_EXCEPTION` branches

2. **Edit `SecureMethodCallHandlerImpl.kt`:**
   - Add import: `import android.security.keystore.KeyPermanentlyInvalidatedException`
   - In the `when(e)` block inside the `catch` clause of `executeOperation()`, insert a new branch after `is BaseException`:
     ```kotlin
     is KeyPermanentlyInvalidatedException -> {
         ErrorType.KEY_PERMANENTLY_INVALIDATED.name
     }
     ```

3. **Verify:** Run `fvm flutter build apk --debug` to confirm the Android build succeeds.

---

## Open Questions

None.
