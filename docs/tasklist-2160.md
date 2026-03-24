# Tasklist: Biometric Key Invalidation Handling (AW-2160)

Companion to: `docs/idea-2160.md`, `docs/vision-2160.md`

---

## Progress Report

| # | Iteration | Status | Notes |
|---|-----------|--------|-------|
| 1 | Android: detect `KeyPermanentlyInvalidatedException` | :white_check_mark: Done | |
| 2 | iOS/macOS: detect biometric key invalidation | :white_check_mark: Done | |
| 3 | Dart plugin: `keyPermanentlyInvalidated` code | :white_check_mark: Complete | |
| 4 | Locker: `keyInvalidated` exception type | :white_check_mark: Complete | |
| 5 | Locker: `teardownBiometryPasswordOnly` method | :white_check_mark: Complete | |
| 6 | Tests | :white_large_square: Not started | |
| 7 | Example app: detect and display key invalidation | :white_large_square: Not started | |
| 8 | Example app: password-only biometric disable | :white_large_square: Not started | |

**Current Phase:** 8

---

## Iteration 1 — Android: detect `KeyPermanentlyInvalidatedException`

**Goal:** Surface `KEY_PERMANENTLY_INVALIDATED` through the Flutter method channel instead of the generic `"decrypt"` fallback.

- [x] **1.1** Add `KEY_PERMANENTLY_INVALIDATED` to `ErrorType` enum and its `errorDescription`
  - File: `packages/biometric_cipher/android/src/main/kotlin/…/errors/ErrorType.kt`
  - Add value before `UNKNOWN_EXCEPTION`
  - Description: `"Biometric key has been permanently invalidated"`

- [x] **1.2** Catch `KeyPermanentlyInvalidatedException` in `executeOperation()`
  - File: `packages/biometric_cipher/android/src/main/kotlin/…/handlers/SecureMethodCallHandlerImpl.kt`
  - Add import: `android.security.keystore.KeyPermanentlyInvalidatedException`
  - Add `is KeyPermanentlyInvalidatedException` branch in the `when(e)` block, between `is BaseException` and `else`
  - Map to `ErrorType.KEY_PERMANENTLY_INVALIDATED.name`

**Verify:** Build Android (`fvm flutter build apk --debug`). The new error code flows through the channel — testable via Dart unit tests in Iteration 3.

---

## Iteration 2 — iOS/macOS: detect biometric key invalidation

**Goal:** Detect invalidated Secure Enclave keys at two points (nil key + `errSecAuthFailed`) and surface `KEY_PERMANENTLY_INVALIDATED` through the Flutter method channel.

- [x] **2.1** Add `.keyPermanentlyInvalidated` to `KeychainServiceError`
  - File: `packages/biometric_cipher/darwin/Classes/Errors/KeychainServiceError.swift`
  - Add case + code `"KEY_PERMANENTLY_INVALIDATED"` + description

- [x] **2.2** Add `keyExists(tag:)` helper to `KeychainService`
  - File: `packages/biometric_cipher/darwin/Classes/Services/KeychainService.swift`
  - Query keychain with `kSecUseAuthenticationUISkip`, no auth prompt
  - Returns `true` if `errSecSuccess` or `errSecInteractionNotAllowed`

- [x] **2.3** Update `KeychainService.decryptData()` — detect `errSecAuthFailed`
  - Same file as 2.2
  - In the `default` branch of the error switch: check `errorCode == errSecAuthFailed` → throw `.keyPermanentlyInvalidated`

- [x] **2.4** Add `.keyPermanentlyInvalidated` to `SecureEnclaveManagerError`
  - File: `packages/biometric_cipher/darwin/Classes/Errors/SecureEnclaveManagerError.swift`
  - Add case + code + description

- [x] **2.5** Update `SecureEnclaveManager.decrypt()` — propagate invalidation
  - File: `packages/biometric_cipher/darwin/Classes/Managers/SecureEnclaveManager.swift`
  - When `getPrivateKey` returns `nil`: call `keyExists(tag:)` on `keychainService`. If key doesn't exist → throw `.keyPermanentlyInvalidated`. Otherwise keep existing `.failedGetPrivateKey`.
  - Wrap `keychainService.decryptData()` call in do/catch to re-throw `KeychainServiceError.keyPermanentlyInvalidated` as `SecureEnclaveManagerError.keyPermanentlyInvalidated`

- [x] **2.6** Add `.keyPermanentlyInvalidated` to `SecureEnclavePluginError`
  - File: `packages/biometric_cipher/darwin/Classes/Errors/SecureEnclavePluginError.swift`
  - Add case + code `"KEY_PERMANENTLY_INVALIDATED"` + description

- [x] **2.7** Catch `.keyPermanentlyInvalidated` in `BiometricCipherPlugin.decrypt()`
  - File: `packages/biometric_cipher/darwin/Classes/BiometricCipherPlugin.swift`
  - Add catch branch for `SecureEnclaveManagerError.keyPermanentlyInvalidated` (similar to existing `authenticationUserCanceled` pattern)
  - Map to `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED", …)`

**Verify:** Build iOS/macOS (`fvm flutter build ios --debug --no-codesign`). Channel code testable via Dart in Iteration 3.

---

## Iteration 3 — Dart plugin: `keyPermanentlyInvalidated` code

**Goal:** Map the native `KEY_PERMANENTLY_INVALIDATED` channel code to a Dart enum value.

- [x] **3.1** Add `keyPermanentlyInvalidated` to `BiometricCipherExceptionCode`
  - File: `packages/biometric_cipher/lib/data/biometric_cipher_exception_code.dart`
  - Add enum value (before `unknown`)
  - Add `'KEY_PERMANENTLY_INVALIDATED' => keyPermanentlyInvalidated` to `fromString`

**Verify:** `cd packages/biometric_cipher && fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .`

---

## Iteration 4 — Locker: `keyInvalidated` exception type

**Goal:** Map the plugin exception to a locker-level `BiometricExceptionType.keyInvalidated`.

- [x] **4.1** Add `keyInvalidated` to `BiometricExceptionType`
  - File: `lib/security/models/exceptions/biometric_exception.dart`
  - Add enum value

- [x] **4.2** Map `keyPermanentlyInvalidated` → `keyInvalidated` in provider
  - File: `lib/security/biometric_cipher_provider.dart`
  - In `_mapExceptionToBiometricException`: add `BiometricCipherExceptionCode.keyPermanentlyInvalidated => const BiometricException(BiometricExceptionType.keyInvalidated)`

**Verify:** `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` + `fvm flutter test`

---

## Iteration 5 — Locker: `teardownBiometryPasswordOnly` method

**Goal:** Allow removing the `Origin.bio` wrap using password auth only, for when the biometric key is already invalidated.

- [x] **5.1** Add `teardownBiometryPasswordOnly` to `Locker` abstract interface
  - File: `lib/locker/locker.dart`
  - Signature: `Future<void> teardownBiometryPasswordOnly({required PasswordCipherFunc passwordCipherFunc, required String biometricKeyTag})`

- [x] **5.2** Implement `teardownBiometryPasswordOnly` in `MFALocker`
  - File: `lib/locker/mfa_locker.dart`
  - Password-only `disableBiometry` logic: `loadAllMetaIfLocked(passwordCipherFunc)` → `_storage.deleteWrap(originToDelete: Origin.bio, cipherFunc: passwordCipherFunc)`
  - Wrap in `_sync` + `_executeWithCleanup` (follow existing patterns)
  - After wrap deletion: `try { _secureProvider.deleteKey(tag: biometricKeyTag) } catch (_) { /* suppress */ }`
  - Log warning on suppressed key deletion error

**Verify:** `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` + `fvm flutter test`

---

## Iteration 6 — Tests

**Goal:** Unit tests for new exception mapping and password-only teardown.

- [ ] **6.1** Test `BiometricCipherExceptionCode.fromString('KEY_PERMANENTLY_INVALIDATED')` → `keyPermanentlyInvalidated`

- [ ] **6.2** Test `_mapExceptionToBiometricException` maps `keyPermanentlyInvalidated` → `BiometricExceptionType.keyInvalidated`

- [ ] **6.3** Test `teardownBiometryPasswordOnly` removes `Origin.bio` wrap, calls `deleteKey`, succeeds even if `deleteKey` throws

- [ ] **6.4** Verify existing exception types are unchanged (regression): `authenticationError` → `failure`, `authenticationUserCanceled` → `cancel`

**Verify:** `fvm flutter test` — all green.

---

## Iteration 7 — Example App: Detect and Display Key Invalidation

**Goal:** Wire the example app to detect `keyInvalidated` at runtime, display an inline message, and hide biometric UI when the key is invalidated.

- [ ] **7.1** Add `isBiometricKeyInvalidated` flag to `LockerState` (Freezed)
  - File: `example/lib/features/locker/bloc/locker_state.dart`
  - Add `@Default(false) bool isBiometricKeyInvalidated` to `LockerState`

- [ ] **7.2** Add `biometricKeyInvalidated()` action to `LockerAction` (Freezed)
  - File: `example/lib/features/locker/bloc/locker_action.dart`
  - Add `const factory LockerAction.biometricKeyInvalidated() = BiometricKeyInvalidatedAction`

- [ ] **7.3** Run `make g` for code generation
  - Dir: `example/`
  - Regenerates `.freezed.dart` files for updated state, event, and action classes

- [ ] **7.4** Separate `keyInvalidated` from `failure` in `_handleBiometricFailure`
  - File: `example/lib/features/locker/bloc/locker_bloc.dart`
  - Split the `case BiometricExceptionType.failure: case BiometricExceptionType.keyInvalidated:` block
  - `keyInvalidated`: set `isBiometricKeyInvalidated: true`, emit `biometricKeyInvalidated()` action, reset to `BiometricOperationState.idle`, return early
  - `failure`: keep existing behavior (call `_determineBiometricStateAndEmit`, fall through)

- [ ] **7.5** Map `biometricKeyInvalidated` action in biometric stream extension
  - File: `example/lib/features/locker/views/widgets/locker_bloc_biometric_stream.dart`
  - Add `biometricKeyInvalidated: (_) => const BiometricFailed('Biometrics have changed. Please use your password.')` to the `mapOrNull` call

- [ ] **7.6** Hide biometric button when `isBiometricKeyInvalidated` is true
  - File: `example/lib/features/locker/views/auth/locked_screen.dart`
    - Update `buildWhen` to include `isBiometricKeyInvalidated`
    - Update `showBiometricButton:` to `state.biometricState.isEnabled && !state.isBiometricKeyInvalidated`
    - Update biometric `onPressed` guard similarly
  - File: `example/lib/features/locker/views/widgets/biometric_unlock_button.dart`
    - Update `buildWhen` to include `isBiometricKeyInvalidated`
    - Return `SizedBox.shrink()` when `state.isBiometricKeyInvalidated` is true

- [ ] **7.7** Update `SettingsScreen` for invalidation display
  - File: `example/lib/features/settings/views/settings_screen.dart`
  - Update `_getBiometricStateDescription` to accept `isKeyInvalidated` parameter
  - When invalidated: return `'Biometrics changed. Disable and re-enable to use new biometrics.'`
  - Style subtitle text in `Theme.of(context).colorScheme.error` when invalidated
  - Update `_canToggleBiometric` to allow toggle when `isBiometricKeyInvalidated` is true
  - Update `buildWhen` to include `isBiometricKeyInvalidated`
  - Account for invalidation in `_AutoLockTimeoutTile` biometric check: `state.biometricState.isEnabled && !lockerBloc.state.isBiometricKeyInvalidated`

- [ ] **7.8** Update `SettingsBloc` — specific `keyInvalidated` case in timeout-with-biometric handler
  - File: `example/lib/features/settings/bloc/settings_bloc.dart`
  - In `_onAutoLockTimeoutSelectedWithBiometric` catch block: add `case BiometricExceptionType.keyInvalidated:` with message `'Biometrics have changed. Please use your password.'`, return early

- [ ] **7.9** Clear `isBiometricKeyInvalidated` flag on erase
  - File: `example/lib/features/locker/bloc/locker_bloc.dart`
  - In `_onEraseStorageRequested`, after successful erase: `emit(state.copyWith(isBiometricKeyInvalidated: false))`

**Verify:** `cd example && fvm flutter analyze --fatal-warnings --fatal-infos --no-pub . && fvm dart format . --line-length 120`

---

## Iteration 8 — Example App: Password-Only Biometric Disable

**Goal:** Allow the user to disable biometrics using only their password when the biometric key has been invalidated.

- [ ] **8.1** Add `disableBiometricPasswordOnly` to repository
  - File: `example/lib/features/locker/data/repositories/locker_repository.dart`
  - Add `Future<void> disableBiometricPasswordOnly({required String password})` to `LockerRepository` interface
  - Implement in `LockerRepositoryImpl`: `_securityProvider.authenticatePassword` → `_locker.teardownBiometryPasswordOnly(passwordCipherFunc, AppConstants.biometricKeyTag)`

- [ ] **8.2** Add `disableBiometricPasswordOnlyRequested` event to `LockerEvent` (Freezed)
  - File: `example/lib/features/locker/bloc/locker_event.dart`
  - Add `const factory LockerEvent.disableBiometricPasswordOnlyRequested({required String password}) = _DisableBiometricPasswordOnlyRequested`

- [ ] **8.3** Run `make g` for code generation
  - Dir: `example/`

- [ ] **8.4** Register handler + implement `_onDisableBiometricPasswordOnlyRequested` in `LockerBloc`
  - File: `example/lib/features/locker/bloc/locker_bloc.dart`
  - Register: `on<_DisableBiometricPasswordOnlyRequested>(_onDisableBiometricPasswordOnlyRequested)`
  - Implementation: set `loadState: loading` → call `repo.disableBiometricPasswordOnly` → `_refreshBiometricState` → clear `isBiometricKeyInvalidated` → show success
  - No `biometricOperationState` management (password-only, no system biometric dialog)
  - Error handling: `onDecryptFailed` for wrong password, `onError` for generic failure

- [ ] **8.5** Update `SettingsScreen._handleBiometricToggle` — route to password-only event when invalidated
  - File: `example/lib/features/settings/views/settings_screen.dart`
  - When `value == false` (disabling) and `lockerBloc.state.isBiometricKeyInvalidated == true`:
    dispatch `LockerEvent.disableBiometricPasswordOnlyRequested(password:)` instead of `disableBiometricRequested`

- [ ] **8.6** Clear `isBiometricKeyInvalidated` on successful enable
  - File: `example/lib/features/locker/bloc/locker_bloc.dart`
  - In `_onEnableBiometricRequested`, after successful `enableBiometric` and `_refreshBiometricState`:
    `emit(state.copyWith(isBiometricKeyInvalidated: false))`

**Verify:** `cd example && fvm flutter analyze --fatal-warnings --fatal-infos --no-pub . && fvm dart format . --line-length 120`
