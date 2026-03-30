# Changelog

All notable changes to this project are documented here.

---

## [Unreleased]

### Added

- **AW-2160 Phase 14 — Unit tests for proactive biometric key validity detection**
  Added 10 unit tests covering the three symbols introduced in Phase 13. `test/locker/models/biometric_state_test.dart` gains 5 tests: `keyInvalidated.isKeyInvalidated` returns `true`; `keyInvalidated.isEnabled` and `keyInvalidated.isAvailable` both return `false`; and regression guards confirming `enabled.isKeyInvalidated` and `availableButDisabled.isKeyInvalidated` return `false`. `test/security/biometric_cipher_provider_test.dart` gains 2 tests confirming `BiometricCipherProviderImpl.isKeyValid` delegates to `BiometricCipher.isKeyValid` and passes the return value through unchanged for both `true` and `false`. `test/locker/mfa_locker_test.dart` gains 3 tests: `determineBiometricState(biometricKeyTag:)` returns `keyInvalidated` when `isKeyValid` is `false` (with `verify` confirming delegation), returns `enabled` when `isKeyValid` is `true`, and never calls `isKeyValid` when no tag is supplied (confirmed by `verifyNever`). No production code changed. No new files created. All existing tests unbroken.

- **AW-2160 Phase 13 — Locker: `BiometricState.keyInvalidated` + proactive `determineBiometricState`**
  Added `BiometricState.keyInvalidated` enum value and `isKeyInvalidated` getter to the locker library. `keyInvalidated` is an error state (not included in `isAvailable` or `isEnabled`) returned when the hardware biometric key has been permanently invalidated after an enrollment change. Wired the silent key validity probe (built in Phases 9–12) into `MFALocker.determineBiometricState` via a new optional `biometricKeyTag` parameter: when provided and biometrics are enabled in settings, `isKeyValid(tag:)` is called without triggering a biometric prompt — if the key is gone, `keyInvalidated` is returned immediately. Backwards compatible: callers without `biometricKeyTag` retain existing behavior. Added `isKeyValid({required String tag})` to `BiometricCipherProvider` and `BiometricCipherProviderImpl`. Five files modified, no new files, no native changes.

- **AW-2160 Phase 12 — Dart plugin: `BiometricCipher.isKeyValid(tag)`**
  Wired the Dart-side bridge for the `isKeyValid` method channel call, completing the silent key validity probe stack built across Phases 9–11. `BiometricCipherPlatform` gains the abstract `isKeyValid({required String tag})` method; `BiometricCipher` gains the public API with an empty-tag guard (throws `BiometricCipherException(invalidArgument)` synchronously) and delegation to the platform interface. The method channel override calls `invokeMethod('isKeyValid', {'tag': tag})` with a `?? false` null guard and `PlatformException` mapping. Does not require the plugin to be configured — no biometric prompt is involved. Four automated tests added: `true` for an existing key, `false` for a nonexistent key, `false` after deletion, and the empty-tag guard. No native files touched, no new files created. Phase 13 (`BiometricCipherProvider.isKeyValid` + `determineBiometricState` integration) is now unblocked.

- **AW-2160 Phase 11 — Windows: `isKeyValid(tag)` silent probe**
  Added `IsKeyValidAsync(tag)` to the Windows C++/WinRT native layer of the `biometric_cipher` plugin. The method uses `KeyCredentialManager::OpenAsync(tag)` to probe whether a Windows Hello credential exists without triggering a biometric dialog. Returns `true` when the credential is accessible (`KeyCredentialStatus::Success`) and `false` for all other statuses including `NotFound`. Errors from WinRT exceptions surface as `PlatformException` to the Dart layer. The method name `"isKeyValid"` matches the Android (Phase 9) and iOS/macOS (Phase 10) handlers, completing native platform support for the Dart-side `invokeMethod` call planned in Phase 12. All changes are additions to existing files in `packages/biometric_cipher/windows/`; no Dart files, no new files, no logging added.

- **AW-2160 Phase 10 — iOS/macOS: `isKeyValid(tag)` silent probe**
  Added `isKeyValid(tag)` to the iOS/macOS Swift native layer. Uses `SecItemCopyMatching` with `kSecUseAuthenticationUISkip` to probe Secure Enclave key existence without triggering any authentication UI. Returns `false` when `errSecItemNotFound` — key has been deleted by the OS after a biometric enrollment change.

- **AW-2160 Phase 9 — Android: `isKeyValid(tag)` silent probe**
  Added `isKeyValid(tag)` to the Android Kotlin native layer. Uses `Cipher.init()` without a `BiometricPrompt` to probe key validity. `KeyPermanentlyInvalidatedException` is caught and mapped to `false`. Establishes the shared method name `"isKeyValid"` used across all platforms.

- **AW-2160 Phase 8 — Example app: password-only biometric disable recovery flow**
  Added `disableBiometricPasswordOnlyRequested` event, `_onDisableBiometricPasswordOnlyRequested` BLoC handler, and `disableBiometricPasswordOnly` repository method to the example app. When `isBiometricKeyInvalidated` is `true`, the Settings biometric toggle-off routes to the password-only path instead of a biometric prompt. The `isBiometricKeyInvalidated` flag is cleared on success and on successful biometric re-enable.

- **AW-2160 Phase 7 — Example app: biometric key invalidation UI**
  Added `isBiometricKeyInvalidated` flag to `LockerState`. Biometric unlock button and locked screen hide the biometric option when the flag is set. Auth bottom sheet shows an inline "Biometrics have changed" message. Settings screen shows an error-color description on the biometric tile. `biometricKeyInvalidated` side-effect action emitted from `_handleBiometricFailure`.

- **AW-2160 Phase 6 — Unit tests for Dart-layer key invalidation code paths**
  Added unit tests covering `BiometricCipherExceptionCode.keyPermanentlyInvalidated` mapping (Phase 3), `BiometricExceptionType.keyInvalidated` mapping (Phase 4), and `MFALocker.teardownBiometryPasswordOnly` (Phase 5).

- **AW-2160 Phase 5 — `MFALocker.teardownBiometryPasswordOnly`**
  Added `teardownBiometryPasswordOnly({required PasswordCipherFunc, required String biometricKeyTag})` to the `Locker` interface and `MFALocker` implementation. Removes the `Origin.bio` wrap using password authentication alone; hardware key deletion errors are suppressed because the key may already be gone.

- **AW-2160 Phase 4 — Locker library: `BiometricExceptionType.keyInvalidated`**
  Added `keyInvalidated` to `BiometricExceptionType`. `BiometricCipherProviderImpl` maps `BiometricCipherExceptionCode.keyPermanentlyInvalidated` to this new type.

- **AW-2160 Phase 3 — Dart plugin: `BiometricCipherExceptionCode.keyPermanentlyInvalidated`**
  Added `keyPermanentlyInvalidated` to `BiometricCipherExceptionCode` and mapped the platform error string `"KEY_PERMANENTLY_INVALIDATED"` to it in `fromString`.

- **AW-2160 Phase 2 — iOS/macOS native: `KEY_PERMANENTLY_INVALIDATED` error**
  iOS/macOS Swift layer emits `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")` when the Secure Enclave key is inaccessible after a biometric enrollment change, propagated through `KeychainServiceError`, `SecureEnclaveManagerError`, and `SecureEnclavePluginError`.

- **AW-2160 Phase 1 — Android native: `KEY_PERMANENTLY_INVALIDATED` error**
  Added `KEY_PERMANENTLY_INVALIDATED` to `ErrorType`. Android Kotlin layer catches `KeyPermanentlyInvalidatedException` in `executeOperation()` and emits `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")` to the Flutter channel.
