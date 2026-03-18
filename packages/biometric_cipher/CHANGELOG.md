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

* Added unit test for `BiometricCipherExceptionCode.fromString('KEY_PERMANENTLY_INVALIDATED')` to confirm it returns `BiometricCipherExceptionCode.keyPermanentlyInvalidated`. The test is a direct call to the static method with no mocks. Affected file: `packages/biometric_cipher/test/biometric_cipher_test.dart`.

### Locker library

* Added `BiometricExceptionType.keyInvalidated` to the locker library's `BiometricExceptionType` enum. This is a distinct value separate from `failure` and `cancel`, representing a hardware-backed biometric key that has been permanently invalidated by a biometric enrollment change. Affected file: `lib/security/models/exceptions/biometric_exception.dart`.

* Added a mapping arm in `BiometricCipherProviderImpl._mapExceptionToBiometricException` so that `BiometricCipherExceptionCode.keyPermanentlyInvalidated` now produces `BiometricException(BiometricExceptionType.keyInvalidated)` instead of falling through to the generic `failure` wildcard. All existing mappings (`authenticationError` → `failure`, `authenticationUserCanceled` → `cancel`, etc.) are unchanged. Affected file: `lib/security/biometric_cipher_provider.dart`.

* Added a `@visibleForTesting` named constructor `BiometricCipherProviderImpl.forTesting(BiometricCipher)` to `BiometricCipherProviderImpl`. This enables unit tests to inject a mock `BiometricCipher` without affecting the production singleton. The existing `instance` singleton and its private `_()` constructor are unaffected. Affected file: `lib/security/biometric_cipher_provider.dart`.

* Added `teardownBiometryPasswordOnly` to the `Locker` abstract interface and implemented it in `MFALocker`. The method removes the `Origin.bio` wrap using password authentication alone, without triggering a biometric prompt. This is the recovery path for the app layer after detecting `BiometricExceptionType.keyInvalidated`: the hardware key is already gone, so the existing `teardownBiometry` (which requires a `BioCipherFunc` and would trigger a failing biometric prompt) cannot be used. After removing the wrap from storage, the method attempts to delete the hardware key via the platform provider; any error during key deletion is suppressed and logged at warning level, because the OS may have already removed the key. Existing `teardownBiometry` behavior is unchanged. Affected files: `lib/locker/locker.dart`, `lib/locker/mfa_locker.dart`.

* Added unit tests for all new Dart-layer code paths introduced in Phases 3–5. The only production code change is a `@visibleForTesting BiometricCipherProvider? secureProvider` constructor parameter on `MFALocker`, which replaces a private getter with a field initialized in the constructor initializer list (functionally equivalent for all existing call sites). Seven new tests across three test files:
  - `test/security/biometric_cipher_provider_test.dart` (new file): three tests verifying that `BiometricCipherProviderImpl._mapExceptionToBiometricException` maps `keyPermanentlyInvalidated` → `BiometricExceptionType.keyInvalidated` and that the pre-existing `authenticationError` → `failure` and `authenticationUserCanceled` → `cancel` mappings remain unchanged.
  - `test/locker/mfa_locker_test.dart`: three tests for `teardownBiometryPasswordOnly` — happy path (wrap and key deleted), `deleteKey` error suppressed (method completes normally), and locked-state ordering (uses `verifyInOrder` to confirm `loadAllMetaIfLocked` runs before `deleteWrap`).
  - Two new mock files: `test/mocks/mock_biometric_cipher.dart` and `test/mocks/mock_biometric_cipher_provider.dart`.
  - Total test count: 146 passing tests, 0 failures.

### Example app (mfa_demo)

* Wired the example app to detect `BiometricExceptionType.keyInvalidated` at runtime and respond with clear UI feedback. No library-layer files were changed. All changes are in `example/lib/`.

* Added `isBiometricKeyInvalidated` runtime flag to `LockerState` (in-memory, `@Default(false)`, resets on cold launch). The flag is set by `LockerBloc` the first time a biometric operation returns `keyInvalidated`, and cleared on storage erase. Affected file: `example/lib/features/locker/bloc/locker_state.dart`.

* Added `LockerAction.biometricKeyInvalidated()` Freezed factory, distinct from `biometricAuthenticationFailed`, so the biometric stream extension and other consumers can handle the two conditions independently. Affected file: `example/lib/features/locker/bloc/locker_action.dart`.

* Separated `BiometricExceptionType.keyInvalidated` from the generic `failure` case in `LockerBloc._handleBiometricFailure`. The `keyInvalidated` branch sets the flag, emits `biometricKeyInvalidated()`, resets biometric operation state to idle, and returns early — it does not fall through to the generic `biometricAuthenticationFailed` action. The `failure` case retains its original behavior unchanged. Affected file: `example/lib/features/locker/bloc/locker_bloc.dart`.

* Added `biometricKeyInvalidated` arm to `LockerBlocBiometricStream`, mapping it to `BiometricFailed('Biometrics have changed. Please use your password.')`. The auth bottom sheet displays this message inline when the key is invalidated. Affected file: `example/lib/features/locker/views/widgets/locker_bloc_biometric_stream.dart`.

* Updated `LockedScreen` and `BiometricUnlockButton` to hide the biometric unlock button when `isBiometricKeyInvalidated` is `true`. Both widgets also update `buildWhen` to rebuild immediately when the flag changes. The locked screen button label switches to `'Unlock with Password'` when the biometric path is unavailable. Affected files: `example/lib/features/locker/views/auth/locked_screen.dart`, `example/lib/features/locker/views/widgets/biometric_unlock_button.dart`.

* Updated `SettingsScreen` to show `'Biometrics changed. Disable and re-enable to use new biometrics.'` as the biometric tile subtitle in the theme error color when `isBiometricKeyInvalidated` is `true`. The biometric tile toggle remains enabled when the key is invalidated so the user can initiate the disable flow. The auto-lock timeout tile no longer shows a biometric button when the key is invalidated. Affected file: `example/lib/features/settings/views/settings_screen.dart`.

* Updated `SettingsBloc._onAutoLockTimeoutSelectedWithBiometric` to emit `biometricAuthenticationFailed(message: 'Biometrics have changed. Please use your password.')` and return early when `BiometricExceptionType.keyInvalidated` is caught, instead of falling through to the generic `'Failed to update timeout using biometric.'` message and snackbar. Affected file: `example/lib/features/settings/bloc/settings_bloc.dart`.

* Completed the biometric key invalidation recovery flow. When `isBiometricKeyInvalidated` is `true`, toggling biometrics OFF in Settings now dispatches a new `disableBiometricPasswordOnlyRequested` event instead of `disableBiometricRequested`. The repository method `disableBiometricPasswordOnly` calls `MFALocker.teardownBiometryPasswordOnly` using password-only authentication — no biometric system dialog fires. On success, `isBiometricKeyInvalidated` is cleared and the Settings screen returns to its normal non-error state. The `isBiometricKeyInvalidated` flag is also cleared on successful biometric re-enable as an idempotent safety measure. The normal biometric disable path (when the key is valid) is unaffected. Affected files: `example/lib/features/locker/data/repositories/locker_repository.dart`, `example/lib/features/locker/bloc/locker_event.dart`, `example/lib/features/locker/bloc/locker_bloc.dart`, `example/lib/features/settings/views/settings_screen.dart`.

## 0.0.1

* TODO: Describe initial release.
