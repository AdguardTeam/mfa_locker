## Unreleased

### Android

* Emit distinct error code `KEY_PERMANENTLY_INVALIDATED` on the Flutter method channel when the Android KeyStore key has been permanently invalidated by a biometric enrollment change. Previously, this condition surfaced as the generic `"decrypt"` or `"encrypt"` error code, making it indistinguishable from other decrypt/encrypt failures. Affected files: `ErrorType.kt` (new enum value) and `SecureMethodCallHandlerImpl.kt` (new catch branch in `executeOperation()`).

### iOS / macOS

* Emit distinct error code `KEY_PERMANENTLY_INVALIDATED` on the Flutter method channel when the Secure Enclave key has been permanently invalidated by a biometric enrollment change on iOS or macOS. Previously, both invalidation points produced the generic `"DECRYPTION_ERROR"` code.

  Two detection points are handled:

  * **Point A** — `getPrivateKey(tag:)` returns `nil` and a silent existence check (`kSecUseAuthenticationUISkip`) confirms the keychain item is gone. Detected in `SecureEnclaveManager.decrypt()` via the new private `keyExists(tag: Data)` helper. Transient nil-key cases (user cancel, lockout — where the item still exists) continue producing `"DECRYPTION_ERROR"` unchanged.
  * **Point B** — `SecKeyCreateDecryptedData` fails with `errSecAuthFailed` (-25293). Detected in `KeychainService.decryptData()` via a new `case Int(errSecAuthFailed):` branch and re-thrown by `SecureEnclaveManager.decrypt()`.

  Both paths converge at `SecureEnclaveManagerError.keyPermanentlyInvalidated` before reaching `BiometricCipherPlugin`, which emits `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")`. Existing error codes (`AUTHENTICATION_USER_CANCELED`, `DECRYPTION_ERROR`) are unaffected. Affected files: `KeychainServiceError.swift`, `KeychainService.swift`, `SecureEnclaveManagerError.swift`, `SecureEnclaveManager.swift`, `SecureEnclavePluginError.swift`, `BiometricCipherPlugin.swift`.

## 0.0.1

* TODO: Describe initial release.
