## Unreleased

### Android

* Emit distinct error code `KEY_PERMANENTLY_INVALIDATED` on the Flutter method channel when the Android KeyStore key has been permanently invalidated by a biometric enrollment change. Previously, this condition surfaced as the generic `"decrypt"` or `"encrypt"` error code, making it indistinguishable from other decrypt/encrypt failures. Affected files: `ErrorType.kt` (new enum value) and `SecureMethodCallHandlerImpl.kt` (new catch branch in `executeOperation()`).

## 0.0.1

* TODO: Describe initial release.
