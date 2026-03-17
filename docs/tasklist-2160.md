# Tasklist: Biometric Key Invalidation Handling (AW-2160)

Companion to: `docs/idea-2160.md`, `docs/vision-2160.md`

---

## Progress Report

| # | Iteration | Status | Notes |
|---|-----------|--------|-------|
| 1 | Android: detect `KeyPermanentlyInvalidatedException` | :white_check_mark: Done | |
| 2 | iOS/macOS: detect biometric key invalidation | :white_check_mark: Done | |
| 3 | Dart plugin: `keyPermanentlyInvalidated` code | :white_check_mark: Complete | |
| 4 | Locker: `keyInvalidated` exception type | :white_large_square: Not started | |
| 5 | Locker: `teardownBiometryPasswordOnly` method | :white_large_square: Not started | |
| 6 | Tests | :white_large_square: Not started | |

**Current Phase:** 4

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

- [ ] **4.1** Add `keyInvalidated` to `BiometricExceptionType`
  - File: `lib/security/models/exceptions/biometric_exception.dart`
  - Add enum value

- [ ] **4.2** Map `keyPermanentlyInvalidated` → `keyInvalidated` in provider
  - File: `lib/security/biometric_cipher_provider.dart`
  - In `_mapExceptionToBiometricException`: add `BiometricCipherExceptionCode.keyPermanentlyInvalidated => const BiometricException(BiometricExceptionType.keyInvalidated)`

**Verify:** `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` + `fvm flutter test`

---

## Iteration 5 — Locker: `teardownBiometryPasswordOnly` method

**Goal:** Allow removing the `Origin.bio` wrap using password auth only, for when the biometric key is already invalidated.

- [ ] **5.1** Add `teardownBiometryPasswordOnly` to `Locker` abstract interface
  - File: `lib/locker/locker.dart`
  - Signature: `Future<void> teardownBiometryPasswordOnly({required PasswordCipherFunc passwordCipherFunc, required String biometricKeyTag})`

- [ ] **5.2** Implement `teardownBiometryPasswordOnly` in `MFALocker`
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
