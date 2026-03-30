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
| 6 | Tests | :white_check_mark: Done | |
| 7 | Example app: detect and display key invalidation | :white_check_mark: Done | |
| 8 | Example app: password-only biometric disable | :white_check_mark: Done | |
| 9 | Android: `isKeyValid(tag)` silent probe | :white_check_mark: Done | Section G |
| 10 | iOS/macOS: `isKeyValid(tag)` silent probe | :white_check_mark: Done | Section G |
| 11 | Windows: `isKeyValid(tag)` silent probe | :white_check_mark: Done | Section G |
| 12 | Dart plugin: `BiometricCipher.isKeyValid(tag)` | :white_check_mark: Done | Section G |
| 13 | Locker: `BiometricState.keyInvalidated` + proactive `determineBiometricState` | :white_check_mark: Done | Section G |
| 14 | Tests for proactive detection | :white_large_square: Not started | Section G |
| 15 | Example app: proactive detection integration | :white_check_mark: Complete | Section G |

**Current Phase:** 14

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

- [x] **6.1** Test `BiometricCipherExceptionCode.fromString('KEY_PERMANENTLY_INVALIDATED')` → `keyPermanentlyInvalidated`

- [x] **6.2** Test `_mapExceptionToBiometricException` maps `keyPermanentlyInvalidated` → `BiometricExceptionType.keyInvalidated`

- [x] **6.3** Test `teardownBiometryPasswordOnly` removes `Origin.bio` wrap, calls `deleteKey`, succeeds even if `deleteKey` throws

- [x] **6.4** Verify existing exception types are unchanged (regression): `authenticationError` → `failure`, `authenticationUserCanceled` → `cancel`

**Verify:** `fvm flutter test` — all green.

---

## Iteration 7 — Example App: Detect and Display Key Invalidation

**Goal:** Wire the example app to detect `keyInvalidated` at runtime, display an inline message, and hide biometric UI when the key is invalidated.

- [x] **7.1** Add `isBiometricKeyInvalidated` flag to `LockerState` (Freezed)
  - File: `example/lib/features/locker/bloc/locker_state.dart`
  - Add `@Default(false) bool isBiometricKeyInvalidated` to `LockerState`

- [x] **7.2** Add `biometricKeyInvalidated()` action to `LockerAction` (Freezed)
  - File: `example/lib/features/locker/bloc/locker_action.dart`
  - Add `const factory LockerAction.biometricKeyInvalidated() = BiometricKeyInvalidatedAction`

- [x] **7.3** Run `make g` for code generation
  - Dir: `example/`
  - Regenerates `.freezed.dart` files for updated state, event, and action classes

- [x] **7.4** Separate `keyInvalidated` from `failure` in `_handleBiometricFailure`
  - File: `example/lib/features/locker/bloc/locker_bloc.dart`
  - Split the `case BiometricExceptionType.failure: case BiometricExceptionType.keyInvalidated:` block
  - `keyInvalidated`: set `isBiometricKeyInvalidated: true`, emit `biometricKeyInvalidated()` action, reset to `BiometricOperationState.idle`, return early
  - `failure`: keep existing behavior (call `_determineBiometricStateAndEmit`, fall through)

- [x] **7.5** Map `biometricKeyInvalidated` action in biometric stream extension
  - File: `example/lib/features/locker/views/widgets/locker_bloc_biometric_stream.dart`
  - Add `biometricKeyInvalidated: (_) => const BiometricFailed('Biometrics have changed. Please use your password.')` to the `mapOrNull` call

- [x] **7.6** Hide biometric button when `isBiometricKeyInvalidated` is true
  - File: `example/lib/features/locker/views/auth/locked_screen.dart`
    - Update `buildWhen` to include `isBiometricKeyInvalidated`
    - Update `showBiometricButton:` to `state.biometricState.isEnabled && !state.isBiometricKeyInvalidated`
    - Update biometric `onPressed` guard similarly
  - File: `example/lib/features/locker/views/widgets/biometric_unlock_button.dart`
    - Update `buildWhen` to include `isBiometricKeyInvalidated`
    - Return `SizedBox.shrink()` when `state.isBiometricKeyInvalidated` is true

- [x] **7.7** Update `SettingsScreen` for invalidation display
  - File: `example/lib/features/settings/views/settings_screen.dart`
  - Update `_getBiometricStateDescription` to accept `isKeyInvalidated` parameter
  - When invalidated: return `'Biometrics changed. Disable and re-enable to use new biometrics.'`
  - Style subtitle text in `Theme.of(context).colorScheme.error` when invalidated
  - Update `_canToggleBiometric` to allow toggle when `isBiometricKeyInvalidated` is true
  - Update `buildWhen` to include `isBiometricKeyInvalidated`
  - Account for invalidation in `_AutoLockTimeoutTile` biometric check: `state.biometricState.isEnabled && !lockerBloc.state.isBiometricKeyInvalidated`

- [x] **7.8** Update `SettingsBloc` — specific `keyInvalidated` case in timeout-with-biometric handler
  - File: `example/lib/features/settings/bloc/settings_bloc.dart`
  - In `_onAutoLockTimeoutSelectedWithBiometric` catch block: add `case BiometricExceptionType.keyInvalidated:` with message `'Biometrics have changed. Please use your password.'`, return early

- [x] **7.9** Clear `isBiometricKeyInvalidated` flag on erase
  - File: `example/lib/features/locker/bloc/locker_bloc.dart`
  - In `_onEraseStorageRequested`, after successful erase: `emit(state.copyWith(isBiometricKeyInvalidated: false))`

**Verify:** `cd example && fvm flutter analyze --fatal-warnings --fatal-infos --no-pub . && fvm dart format . --line-length 120`

---

## Iteration 8 — Example App: Password-Only Biometric Disable

**Goal:** Allow the user to disable biometrics using only their password when the biometric key has been invalidated.

- [x] **8.1** Add `disableBiometricPasswordOnly` to repository
  - File: `example/lib/features/locker/data/repositories/locker_repository.dart`
  - Add `Future<void> disableBiometricPasswordOnly({required String password})` to `LockerRepository` interface
  - Implement in `LockerRepositoryImpl`: `_securityProvider.authenticatePassword` → `_locker.teardownBiometryPasswordOnly(passwordCipherFunc, AppConstants.biometricKeyTag)`

- [x] **8.2** Add `disableBiometricPasswordOnlyRequested` event to `LockerEvent` (Freezed)
  - File: `example/lib/features/locker/bloc/locker_event.dart`
  - Add `const factory LockerEvent.disableBiometricPasswordOnlyRequested({required String password}) = _DisableBiometricPasswordOnlyRequested`

- [x] **8.3** Run `make g` for code generation
  - Dir: `example/`

- [x] **8.4** Register handler + implement `_onDisableBiometricPasswordOnlyRequested` in `LockerBloc`
  - File: `example/lib/features/locker/bloc/locker_bloc.dart`
  - Register: `on<_DisableBiometricPasswordOnlyRequested>(_onDisableBiometricPasswordOnlyRequested)`
  - Implementation: set `loadState: loading` → call `repo.disableBiometricPasswordOnly` → `_refreshBiometricState` → clear `isBiometricKeyInvalidated` → show success
  - No `biometricOperationState` management (password-only, no system biometric dialog)
  - Error handling: `onDecryptFailed` for wrong password, `onError` for generic failure

- [x] **8.5** Update `SettingsScreen._handleBiometricToggle` — route to password-only event when invalidated
  - File: `example/lib/features/settings/views/settings_screen.dart`
  - When `value == false` (disabling) and `lockerBloc.state.isBiometricKeyInvalidated == true`:
    dispatch `LockerEvent.disableBiometricPasswordOnlyRequested(password:)` instead of `disableBiometricRequested`

- [x] **8.6** Clear `isBiometricKeyInvalidated` on successful enable
  - File: `example/lib/features/locker/bloc/locker_bloc.dart`
  - In `_onEnableBiometricRequested`, after successful `enableBiometric` and `_refreshBiometricState`:
    `emit(state.copyWith(isBiometricKeyInvalidated: false))`

**Verify:** `cd example && fvm flutter analyze --fatal-warnings --fatal-infos --no-pub . && fvm dart format . --line-length 120`

---

## Iteration 9 — Android: `isKeyValid(tag)` silent probe

**Goal:** Add a platform method to probe biometric key validity without showing a `BiometricPrompt`. `Cipher.init(ENCRYPT_MODE, key)` throws `KeyPermanentlyInvalidatedException` synchronously for invalidated keys — no user interaction.

**Ref:** `docs/idea-2160.md` Section G1

- [x] **9.1** Add `isKeyValid(keyAlias)` to `SecureRepositoryImpl`
  - File: `packages/biometric_cipher/android/src/main/kotlin/…/SecureRepositoryImpl.kt`
  - Load `AndroidKeyStore`, get key by alias (return `false` if null)
  - `Cipher.getInstance(TRANSFORMATION)` → `cipher.init(Cipher.ENCRYPT_MODE, key)` → return `true`
  - Catch `KeyPermanentlyInvalidatedException` → return `false`

- [x] **9.2** Add `isKeyValid(tag)` delegation to `SecureServiceImpl`
  - File: `packages/biometric_cipher/android/src/main/kotlin/…/SecureServiceImpl.kt`
  - Delegate: `fun isKeyValid(tag: String): Boolean = secureRepository.isKeyValid(tag)`

- [x] **9.3** Add `"isKeyValid"` method channel handler to `SecureMethodCallHandlerImpl`
  - File: `packages/biometric_cipher/android/src/main/kotlin/…/handlers/SecureMethodCallHandlerImpl.kt`
  - Parse `tag` argument (error if missing)
  - Call `secureService.isKeyValid(tag)` → `result.success(Boolean)`

**Verify:** Build Android (`fvm flutter build apk --debug`).

---

## Iteration 10 — iOS/macOS: `isKeyValid(tag)` silent probe

**Goal:** Expose the existing `keyExists(tag:)` check (which uses `kSecUseAuthenticationUISkip` — no biometric prompt) as a public `isKeyValid` method through the plugin channel.

**Ref:** `docs/idea-2160.md` Section G2

- [x] **10.1** Change `keyExists(tag:)` visibility from `private` to `internal` in `KeychainService`
  - File: `packages/biometric_cipher/darwin/Classes/Services/KeychainService.swift`
  - Change `private func keyExists(tag: String) -> Bool` to `func keyExists(tag: String) -> Bool`
  - Implementation unchanged — still uses `kSecUseAuthenticationUISkip`

- [x] **10.2** Add `isKeyValid(tag:)` to `SecureEnclaveManager`
  - File: `packages/biometric_cipher/darwin/Classes/Managers/SecureEnclaveManager.swift`
  - Delegate: `func isKeyValid(tag: String) -> Bool { keychainService.keyExists(tag: tag) }`

- [x] **10.3** Add `"isKeyValid"` method channel handler to `BiometricCipherPlugin`
  - File: `packages/biometric_cipher/darwin/Classes/BiometricCipherPlugin.swift`
  - Parse `tag` from args (error if missing)
  - Call `secureEnclaveManager.isKeyValid(tag:)` → `result(Bool)`

**Verify:** Build iOS (`fvm flutter build ios --debug --no-codesign`).

---

## Iteration 11 — Windows: `isKeyValid(tag)` silent probe

**Goal:** Add a platform method to probe key validity on Windows without showing a Windows Hello prompt. `KeyCredentialManager::OpenAsync(tag)` queries credential metadata — `KeyCredentialStatus::NotFound` means the key is gone, `Success` means it exists and is usable. No signing operation is performed, so no biometric prompt is triggered.

**Ref:** `docs/idea-2160.md` Section G2b

- [x] **11.1** Add `IsKeyValidAsync` to `WindowsHelloRepository` interface
  - File: `packages/biometric_cipher/windows/include/biometric_cipher/repositories/windows_hello_repository.h`
  - Add `virtual IAsyncOperation<bool> IsKeyValidAsync(const winrt::hstring tag) const = 0;`

- [x] **11.2** Implement `IsKeyValidAsync` in `WindowsHelloRepositoryImpl`
  - File: `packages/biometric_cipher/windows/include/biometric_cipher/repositories/windows_hello_repository_impl.h` (declaration)
  - File: `packages/biometric_cipher/windows/windows_hello_repository_impl.cpp` (implementation)
  - Call `CheckWindowsHelloIsStatusAsync()` → `m_HelloWrapper->OpenAsync(tag)` → return `status == KeyCredentialStatus::Success`

- [x] **11.3** Add `IsKeyValidAsync` to `BiometricCipherService`
  - File: `packages/biometric_cipher/windows/include/biometric_cipher/services/biometric_cipher_service.h` (declaration)
  - File: `packages/biometric_cipher/windows/biometric_cipher_service.cpp` (implementation)
  - Delegate: convert tag to `hstring`, call `m_WindowsHelloRepository->IsKeyValidAsync(hTag)`

- [x] **11.4** Add `kIsKeyValid` to `MethodName` enum and mapping
  - File: `packages/biometric_cipher/windows/include/biometric_cipher/enums/method_name.h`
  - Add `kIsKeyValid` before `kNotImplemented`
  - File: `packages/biometric_cipher/windows/method_name.cpp`
  - Add `{"isKeyValid", MethodName::kIsKeyValid}` to `METHOD_NAME_MAP`

- [x] **11.5** Add `isKeyValid` method channel handler to `BiometricCipherPlugin`
  - File: `packages/biometric_cipher/windows/biometric_cipher_plugin.h` (declaration)
  - File: `packages/biometric_cipher/windows/biometric_cipher_plugin.cpp` (implementation)
  - Add `case MethodName::kIsKeyValid:` to `HandleMethodCall` switch
  - Parse `tag` argument, call `IsKeyValidCoroutine(tag, std::move(result))`
  - `IsKeyValidCoroutine`: call `m_SecureService->IsKeyValidAsync(tag)` → `result->Success(bool)`

**Verify:** Build Windows (`fvm flutter build windows --debug`).

---

## Iteration 12 — Dart plugin: `BiometricCipher.isKeyValid(tag)`

**Goal:** Expose the native key validity check through the Dart plugin API.

**Ref:** `docs/idea-2160.md` Section G3

- [x] **12.1** Add `isKeyValid` to platform interface
  - File: `packages/biometric_cipher/lib/biometric_cipher_platform_interface.dart`
  - Add `Future<bool> isKeyValid({required String tag})`

- [x] **12.2** Add `isKeyValid` to `BiometricCipher`
  - File: `packages/biometric_cipher/lib/biometric_cipher.dart`
  - Validate non-empty tag (throw `BiometricCipherException` with `invalidArgument` code if empty)
  - Delegate to `_instance.isKeyValid(tag: tag)`

**Verify:** `cd packages/biometric_cipher && fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .`

---

## Iteration 13 — Locker: `BiometricState.keyInvalidated` + proactive `determineBiometricState`

**Goal:** Add proactive key validity detection at init time — `determineBiometricState()` returns `BiometricState.keyInvalidated` when the hardware key is permanently invalidated, without triggering a biometric prompt.

**Ref:** `docs/idea-2160.md` Sections G4, G5, G6

- [x] **13.1** Add `keyInvalidated` to `BiometricState` enum + `isKeyInvalidated` getter
  - File: `lib/locker/models/biometric_state.dart`
  - Add `keyInvalidated` value (after `enabled`)
  - Add `bool get isKeyInvalidated => this == keyInvalidated`

- [x] **13.2** Add `isKeyValid` to `BiometricCipherProvider` abstract class
  - File: `lib/security/biometric_cipher_provider.dart`
  - Add `Future<bool> isKeyValid({required String tag})`

- [x] **13.3** Implement `isKeyValid` in `BiometricCipherProviderImpl`
  - File: `lib/security/providers/biometric_cipher_provider_impl.dart`
  - Delegate: `_biometricCipher.isKeyValid(tag: tag)`

- [x] **13.4** Add optional `biometricKeyTag` parameter to `determineBiometricState` in `Locker` interface
  - File: `lib/locker/locker.dart`
  - Change signature to: `Future<BiometricState> determineBiometricState({String? biometricKeyTag})`

- [x] **13.5** Implement key validity check in `MFALocker.determineBiometricState`
  - File: `lib/locker/mfa_locker.dart`
  - After confirming biometrics are enabled in settings, before returning `enabled`:
  - If `biometricKeyTag != null`: call `_secureProvider.isKeyValid(tag: biometricKeyTag)`
  - If `!isValid` → return `BiometricState.keyInvalidated`
  - Backwards compatible: callers without `biometricKeyTag` get existing behavior

**Verify:** `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` + `fvm flutter test`

---

## Iteration 14 — Tests for proactive detection

**Goal:** Unit tests for `isKeyValid` delegation, `BiometricState.keyInvalidated`, and proactive `determineBiometricState`.

- [ ] **14.1** Test `BiometricState.keyInvalidated` enum value and `isKeyInvalidated` getter
  - `BiometricState.keyInvalidated.isKeyInvalidated` → `true`
  - `BiometricState.enabled.isKeyInvalidated` → `false`
  - `BiometricState.keyInvalidated.isEnabled` → `false`
  - `BiometricState.keyInvalidated.isAvailable` → `false`

- [ ] **14.2** Test `isKeyValid` delegation in `BiometricCipherProviderImpl`
  - Mock `BiometricCipher.isKeyValid` → verify delegation and return value pass-through

- [ ] **14.3** Test `determineBiometricState(biometricKeyTag:)` returns `keyInvalidated` when key is invalid
  - Mock `isKeyValid` → `false`, biometrics enabled in settings
  - Expect `BiometricState.keyInvalidated`

- [ ] **14.4** Test `determineBiometricState()` without `biometricKeyTag` retains existing behavior
  - Biometrics enabled, no tag passed → expect `BiometricState.enabled` (no key validity check)

**Verify:** `fvm flutter test` — all green.

---

## Iteration 15 — Example app: proactive detection integration

**Goal:** Use `BiometricState.keyInvalidated` from `determineBiometricState` to hide biometric UI at init time — eliminating the brief biometric button flash before a failed attempt hides it.

**Ref:** `docs/idea-2160.md` Sections G7, G8

- [x] **15.1** Pass `biometricKeyTag` in repository's `determineBiometricState` call
  - File: `example/lib/features/locker/data/repositories/locker_repository.dart`
  - Update the `determineBiometricState()` call to pass `biometricKeyTag: AppConstants.biometricKeyTag`

- [x] **15.2** Handle `BiometricState.keyInvalidated` in `LockerBloc`
  - File: `example/lib/features/locker/bloc/locker_bloc.dart`
  - When `determineBiometricState` returns `keyInvalidated`: set `isBiometricKeyInvalidated: true` on state

- [x] **15.3** Update locked screen biometric button visibility to use `biometricState.isKeyInvalidated`
  - File: `example/lib/features/locker/views/auth/locked_screen.dart`
  - Update `showBiometricButton:` to also check `!state.biometricState.isKeyInvalidated`
  - This provides init-time hiding (no button flash) alongside the runtime flag

- [x] **15.4** Update `BiometricUnlockButton` to check `biometricState.isKeyInvalidated`
  - File: `example/lib/features/locker/views/widgets/biometric_unlock_button.dart`
  - Add `state.biometricState.isKeyInvalidated` check alongside existing `isBiometricKeyInvalidated` check

**Verify:** `cd example && fvm flutter analyze --fatal-warnings --fatal-infos --no-pub . && fvm dart format . --line-length 120`
