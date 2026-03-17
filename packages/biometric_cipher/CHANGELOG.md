## Unreleased

### Android

* Emit distinct error code `KEY_PERMANENTLY_INVALIDATED` on the Flutter method channel when the Android KeyStore key has been permanently invalidated by a biometric enrollment change. Previously, this condition surfaced as the generic `"decrypt"` or `"encrypt"` error code, making it indistinguishable from other decrypt/encrypt failures. Affected files: `ErrorType.kt` (new enum value) and `SecureMethodCallHandlerImpl.kt` (new catch branch in `executeOperation()`).

### iOS / macOS

* Emit distinct error code `KEY_PERMANENTLY_INVALIDATED` on the Flutter method channel when the Secure Enclave key has been permanently invalidated by a biometric enrollment change on iOS or macOS. Previously, both invalidation points produced the generic `"DECRYPTION_ERROR"` code.

  Two detection points are handled:

  * **Point A** — `getPrivateKey(tag:)` returns `nil` and a silent existence check (`kSecUseAuthenticationUISkip`) confirms the keychain item is gone. Detected in `SecureEnclaveManager.decrypt()` via the new private `keyExists(tag: Data)` helper. Transient nil-key cases (user cancel, lockout — where the item still exists) continue producing `"DECRYPTION_ERROR"` unchanged.
  * **Point B** — `SecKeyCreateDecryptedData` fails with `errSecAuthFailed` (-25293). Detected in `KeychainService.decryptData()` via a new `case Int(errSecAuthFailed):` branch and re-thrown by `SecureEnclaveManager.decrypt()`.

  Both paths converge at `SecureEnclaveManagerError.keyPermanentlyInvalidated` before reaching `BiometricCipherPlugin`, which emits `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")`. Existing error codes (`AUTHENTICATION_USER_CANCELED`, `DECRYPTION_ERROR`) are unaffected. Affected files: `KeychainServiceError.swift`, `KeychainService.swift`, `SecureEnclaveManagerError.swift`, `SecureEnclaveManager.swift`, `SecureEnclavePluginError.swift`, `BiometricCipherPlugin.swift`.

### Dart

* Added `BiometricCipherExceptionCode.keyPermanentlyInvalidated` to the `BiometricCipherExceptionCode` enum and mapped the channel string `'KEY_PERMANENTLY_INVALIDATED'` to it in `fromString`. Previously this string fell through to `BiometricCipherExceptionCode.unknown`; it now produces a distinct, named code that downstream consumers (locker layer) can match explicitly. All existing `fromString` mappings are unchanged. `unknown` remains the last enum value and the fallback for unrecognised codes. Affected file: `biometric_cipher_exception_code.dart`.

### Locker library

* Added `BiometricExceptionType.keyInvalidated` to the locker library's `BiometricExceptionType` enum. This is a distinct value separate from `failure` and `cancel`, representing a hardware-backed biometric key that has been permanently invalidated by a biometric enrollment change. Affected file: `lib/security/models/exceptions/biometric_exception.dart`.

* Added a mapping arm in `BiometricCipherProviderImpl._mapExceptionToBiometricException` so that `BiometricCipherExceptionCode.keyPermanentlyInvalidated` now produces `BiometricException(BiometricExceptionType.keyInvalidated)` instead of falling through to the generic `failure` wildcard. All existing mappings (`authenticationError` → `failure`, `authenticationUserCanceled` → `cancel`, etc.) are unchanged. Affected file: `lib/security/biometric_cipher_provider.dart`.

* Added a `@visibleForTesting` named constructor `BiometricCipherProviderImpl.forTesting(BiometricCipher)` to `BiometricCipherProviderImpl`. This enables unit tests to inject a mock `BiometricCipher` without affecting the production singleton. The existing `instance` singleton and its private `_()` constructor are unaffected. Affected file: `lib/security/biometric_cipher_provider.dart`.

* Added `teardownBiometryPasswordOnly` to the `Locker` abstract interface and implemented it in `MFALocker`. The method removes the `Origin.bio` wrap using password authentication alone, without triggering a biometric prompt. This is the recovery path for the app layer after detecting `BiometricExceptionType.keyInvalidated`: the hardware key is already gone, so the existing `teardownBiometry` (which requires a `BioCipherFunc` and would trigger a failing biometric prompt) cannot be used. After removing the wrap from storage, the method attempts to delete the hardware key via the platform provider; any error during key deletion is suppressed and logged at warning level, because the OS may have already removed the key. Existing `teardownBiometry` behavior is unchanged. Affected files: `lib/locker/locker.dart`, `lib/locker/mfa_locker.dart`.

## 0.0.1

* TODO: Describe initial release.
