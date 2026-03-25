# Research: AW-2160 Phase 3 — Dart Plugin: Map `KEY_PERMANENTLY_INVALIDATED` to `BiometricCipherExceptionCode`

## 1. Resolved Questions

The PRD contains no open questions. All design decisions (placement, naming, string key, style) are directly derivable from the existing codebase.

---

## 2. Phase Scope

Phase 3 is limited to a single Dart file:

```
packages/biometric_cipher/lib/data/biometric_cipher_exception_code.dart
```

Two additive changes only:
1. Add a new enum value `keyPermanentlyInvalidated` immediately before `unknown` in the `BiometricCipherExceptionCode` enum body.
2. Add a new switch case `'KEY_PERMANENTLY_INVALIDATED' => keyPermanentlyInvalidated` in the `fromString` factory, immediately before the final `'UNKNOWN_ERROR' || 'UNKNOWN_EXCEPTION' || 'CONVERTING_STRING_ERROR' || _ => unknown` line.

No other files change in this phase. No new files are created.

---

## 3. Current State of Target File

**File:** `/Users/comrade77/Documents/Performix/Projects/mfa_locker/packages/biometric_cipher/lib/data/biometric_cipher_exception_code.dart`

### 3.1 Enum values (13 total, in declaration order)

| Position | Value | Doc comment |
|----------|-------|-------------|
| 1 | `invalidArgument` | An invalid argument was provided to the operation. |
| 2 | `keyNotFound` | The requested cryptographic key was not found in storage. |
| 3 | `keyAlreadyExists` | A key with the given identifier already exists. |
| 4 | `biometricNotSupported` | Biometric authentication is not supported on this device. |
| 5 | `authenticationUserCanceled` | The user canceled the biometric authentication prompt. |
| 6 | `authenticationError` | Biometric or device authentication failed. |
| 7 | `encryptionError` | Data encryption failed. |
| 8 | `decryptionError` | Data decryption failed. |
| 9 | `keyGenerationError` | Cryptographic key generation failed. |
| 10 | `keyDeletionError` | Cryptographic key deletion failed. |
| 11 | `secureEnclaveUnavailable` | The Secure Enclave is unavailable on this device. |
| 12 | `tpmUnsupported` | The device TPM is unsupported or has an incompatible version. |
| 13 | `configureError` | Platform plugin configuration failed. |
| 14 | `unknown` | An unknown or unclassified error occurred. ← **last; also the `_` fallback** |

`keyPermanentlyInvalidated` must be inserted as position 14, pushing `unknown` to position 15.

### 3.2 `fromString` switch — all current branches

```dart
static BiometricCipherExceptionCode fromString(String code) => switch (code) {
  'INVALID_ARGUMENT' => invalidArgument,

  'KEY_NOT_FOUND' || 'FAILED_GET_PRIVATE_KEY' || 'FAILED_GET_PUBLIC_KEY' => keyNotFound,

  'KEY_ALREADY_EXISTS' => keyAlreadyExists,

  'BIOMETRIC_NOT_SUPPORTED' || 'BIOMETRY_NOT_SUPPORTED' || 'BIOMETRY_NOT_AVAILABLE' => biometricNotSupported,

  'AUTHENTICATION_USER_CANCELED' => authenticationUserCanceled,

  'AUTHENTICATION_ERROR' ||
  'ERROR_EVALUATING_BIOMETRY' ||
  'USER_PREFERS_PASSWORD' ||
  'SECURE_DEVICE_LOCKED' => authenticationError,

  'ENCRYPT_ERROR' ||
  'ENCRYPTION_ERROR' ||
  'FAILED_TO_ENCRYPT_DATA' ||
  'ENCRYPTION_ALGORITHM_NOT_SUPPORTED' ||
  'INVALID_ENCRYPTION_DATA' => encryptionError,

  'DECRYPT_ERROR' ||
  'DECRYPTION_ERROR' ||
  'FAILED_TO_DECRYPT_DATA' ||
  'DECRYPTION_ALGORITHM_NOT_SUPPORTED' ||
  'DECODE_DECRYPTED_DATA_ERROR' ||
  'DECODE_DATA_INVALID_SIZE' => decryptionError,

  'GENERATE_KEY_ERROR' ||
  'KEY_GENERATION_ERROR' ||
  'FAILED_TO_CREATE_RANDOM_KEY' ||
  'FAILED_TO_COPY_PUBLIC_KEY' => keyGenerationError,

  'DELETE_KEY_ERROR' || 'KEY_DELETION_ERROR' || 'FAILED_TO_DELETE_ITEM' => keyDeletionError,

  'SECURE_ENCLAVE_UNAVAILABLE' => secureEnclaveUnavailable,

  'TPM_UNSUPPORTED' || 'TPM_VERSION_ERROR' => tpmUnsupported,

  'CONFIGURE_ERROR' ||
  'CONFIGURE_BIOMETRIC_ERROR' ||
  'CONFIGURE_NEGATIVE_BUTTON_ERROR' ||
  'CONFIGURE_TITLE_PROMPT_ERROR' ||
  'CONFIGURE_SUBTITLE_PROMPT_ERROR' ||
  'FAILED_CREATE_SEC_ACCESS_CONTROL' ||
  'INVALID_TAG_ERROR' ||
  'INVALID_AUTH_TITLE_ERROR' ||
  'ACTIVITY_NOT_SET' => configureError,

  'UNKNOWN_ERROR' || 'UNKNOWN_EXCEPTION' || 'CONVERTING_STRING_ERROR' || _ => unknown,
};
```

**Gap confirmed:** No branch for `'KEY_PERMANENTLY_INVALIDATED'`. This string currently falls through to `_ => unknown`.

---

## 4. Platform Channel Verification (Phases 1 and 2)

Both upstream native layers have been implemented and emit exactly the string `"KEY_PERMANENTLY_INVALIDATED"` over the Flutter method channel.

### Android (Phase 1 — complete)

File: `packages/biometric_cipher/android/src/main/kotlin/com/adguard/cryptowallet/biometric_cipher/handlers/SecureMethodCallHandlerImpl.kt`

The `executeOperation()` catch block now has:
```kotlin
is KeyPermanentlyInvalidatedException -> {
    ErrorType.KEY_PERMANENTLY_INVALIDATED.name
}
```

`ErrorType.KEY_PERMANENTLY_INVALIDATED.name` resolves at runtime to the string `"KEY_PERMANENTLY_INVALIDATED"` (Kotlin enum `.name` returns the identifier as written). This is passed as the `code` argument to `result.error(errorCode, errorMessage, null)`, which surfaces as `PlatformException(code: "KEY_PERMANENTLY_INVALIDATED")` in Dart.

### iOS/macOS (Phase 2 — complete)

File: `packages/biometric_cipher/darwin/Classes/BiometricCipherPlugin.swift`

The `decrypt()` method now has:
```swift
} catch SecureEnclaveManagerError.keyPermanentlyInvalidated {
    result(FlutterError(
        code: "KEY_PERMANENTLY_INVALIDATED",
        message: "Biometric key has been permanently invalidated",
        details: nil
    ))
```

The hardcoded string `"KEY_PERMANENTLY_INVALIDATED"` is identical to the Android emission.

Both platforms produce the same error code string. The `fromString` key `'KEY_PERMANENTLY_INVALIDATED'` is confirmed correct.

---

## 5. Error Propagation Chain (Dart Plugin Layer)

The single call site for `BiometricCipherExceptionCode.fromString()` in the Dart plugin is:

**File:** `packages/biometric_cipher/lib/biometric_cipher_method_channel.dart`, line 100

```dart
BiometricCipherException _mapPlatformException(PlatformException e) {
  return BiometricCipherException(
    code: BiometricCipherExceptionCode.fromString(e.code),
    message: e.message ?? 'Unknown error',
    details: e.details,
  );
}
```

This is called by the `catch (e: PlatformException)` handlers in `generateKey`, `encrypt`, `decrypt`, and `deleteKey`. After Phase 3, `fromString('KEY_PERMANENTLY_INVALIDATED')` will return `keyPermanentlyInvalidated` instead of `unknown`, causing `BiometricCipherException.code` to be `keyPermanentlyInvalidated`.

---

## 6. Downstream Consumers of `BiometricCipherExceptionCode`

All files that reference `BiometricCipherExceptionCode`:

| File | How it uses the enum |
|------|---------------------|
| `packages/biometric_cipher/lib/data/biometric_cipher_exception_code.dart` | Defines it |
| `packages/biometric_cipher/lib/biometric_cipher_method_channel.dart` | Calls `fromString()` |
| `packages/biometric_cipher/lib/biometric_cipher.dart` | Constructs `BiometricCipherException` directly with named enum literals (`invalidArgument`, `configureError`) — no switch on the full enum |
| `packages/biometric_cipher/test/mock_biometric_cipher_platform.dart` | Constructs `BiometricCipherException` directly with named enum literals — no exhaustive switch |
| `packages/biometric_cipher/test/biometric_cipher_test.dart` | Pattern-matches on individual literals in `predicate` callbacks — no exhaustive switch |
| `lib/security/biometric_cipher_provider.dart` | Contains the one **non-exhaustive** switch on `e.code` (see below) |

### Critical consumer: `BiometricCipherProviderImpl._mapExceptionToBiometricException()`

File: `lib/security/biometric_cipher_provider.dart`, lines 108–124

```dart
BiometricException _mapExceptionToBiometricException(BiometricCipherException e) => switch (e.code) {
  BiometricCipherExceptionCode.keyNotFound => const BiometricException(BiometricExceptionType.keyNotFound),
  BiometricCipherExceptionCode.keyAlreadyExists =>
    const BiometricException(BiometricExceptionType.keyAlreadyExists),
  BiometricCipherExceptionCode.authenticationUserCanceled =>
    const BiometricException(BiometricExceptionType.cancel),
  BiometricCipherExceptionCode.authenticationError ||
  BiometricCipherExceptionCode.encryptionError ||
  BiometricCipherExceptionCode.decryptionError =>
    const BiometricException(BiometricExceptionType.failure),
  BiometricCipherExceptionCode.biometricNotSupported ||
  BiometricCipherExceptionCode.secureEnclaveUnavailable ||
  BiometricCipherExceptionCode.tpmUnsupported =>
    const BiometricException(BiometricExceptionType.notAvailable),
  BiometricCipherExceptionCode.configureError => const BiometricException(BiometricExceptionType.notConfigured),
  _ => BiometricException(BiometricExceptionType.failure, originalError: e),
};
```

This switch has a `_ =>` wildcard fallback. Adding `keyPermanentlyInvalidated` to the enum will **not** cause a compile error here because the switch is already non-exhaustive via `_`. When `keyPermanentlyInvalidated` flows in, it falls to the `_ =>` branch and is mapped to `BiometricException(BiometricExceptionType.failure, originalError: e)`.

This is the correct behavior for Phase 3: Phase 3 only closes the Dart plugin gap. Phase 4 (the locker library layer) will add an explicit arm for `keyPermanentlyInvalidated` in `BiometricExceptionType` and update `_mapExceptionToBiometricException` accordingly.

### `BiometricExceptionType` — current values

File: `lib/security/models/exceptions/biometric_exception.dart`

```dart
enum BiometricExceptionType {
  cancel,
  failure,
  keyNotFound,
  keyAlreadyExists,
  notAvailable,
  notConfigured,
}
```

No `keyInvalidated` value exists yet. This is Phase 4's concern, not Phase 3's.

---

## 7. Naming and Style Conventions Observed

From examining adjacent enum values in `biometric_cipher_exception_code.dart`:

- **Value naming:** lowerCamelCase (e.g., `keyNotFound`, `authenticationError`, `secureEnclaveUnavailable`)
- **Doc comment format:** `/// Single-sentence description ending with period.` placed on the line immediately above the value
- **Single-string switch case:** `'KEY_ALREADY_EXISTS' => keyAlreadyExists,`
- **Multi-string switch case:** `'KEY_NOT_FOUND' || 'FAILED_GET_PRIVATE_KEY' || 'FAILED_GET_PUBLIC_KEY' => keyNotFound,` (all on one line if they fit within 120 chars; otherwise split with `||` at the start of subsequent lines)
- **Placement of new case in switch:** near-end, before the final `'UNKNOWN_ERROR' || ...` wildcard line

The new enum value follows this pattern:
- Name: `keyPermanentlyInvalidated`
- Doc comment: `/// The biometric key has been permanently invalidated.` (consistent with one-sentence doc pattern)
- Switch case: `'KEY_PERMANENTLY_INVALIDATED' => keyPermanentlyInvalidated,` (single-string, single-line)

---

## 8. No Serialization Impact

`BiometricCipherExceptionCode` is never written to disk, stored in any JSON, or transmitted externally. It is a transient, in-memory classification of a platform error. Adding a new enum value carries zero migration risk.

---

## 9. Phase-Specific Limitations and Risks

| Risk | Likelihood | Impact | Assessment |
|------|-----------|--------|-----------|
| New value placed after `unknown`, breaking `unknown` as last/fallback | Low — straightforward edit | Medium — exhaustive switch consumers expecting `unknown` as last may be affected | Verify placement in code review; `fromString` switch is positionally unordered so that part is unaffected; only the enum declaration order matters for exhaustive consumers |
| Adding `keyPermanentlyInvalidated` causes a compile error in `BiometricCipherProviderImpl._mapExceptionToBiometricException()` | None — that switch has a `_ =>` wildcard | None | Already confirmed non-exhaustive |
| Existing `biometric_cipher_test.dart` tests fail | None — no test references `fromString` or the new value | None | Confirmed: existing tests only check `keyNotFound` and `configureError` via mock-thrown exceptions, not through `fromString` |
| String mismatch: `'KEY_PERMANENTLY_INVALIDATED'` in Dart vs what platforms actually emit | None — Phase 1 (Android) and Phase 2 (iOS/macOS) both confirmed to emit exactly this string | High if it occurred | Eliminated by reading both native implementations directly |
| The new value `keyPermanentlyInvalidated` reaches `_mapExceptionToBiometricException` and is swallowed as `failure` instead of `keyInvalidated` | Certain for Phase 3 alone | Acceptable — Phase 4 adds the proper mapping | This is intentional and expected. Phase 3 is a plugin-layer change; Phase 4 closes the locker-layer gap |

---

## 10. New Technical Questions Discovered

None. The scope is fully defined. Both native layers are confirmed complete and emit the exact string `"KEY_PERMANENTLY_INVALIDATED"`. The target file's current content is verified. All style and placement conventions are clear from the existing code.
