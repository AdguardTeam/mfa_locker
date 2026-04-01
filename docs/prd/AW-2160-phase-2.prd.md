# AW-2160-2: iOS/macOS — Detect Biometric Key Invalidation via Secure Enclave

Status: PRD_READY

## Context / Idea

This is Phase 2 of AW-2160, which as a whole adds biometric key invalidation detection and a password-only teardown path across the full stack (Android, iOS/macOS native, Dart plugin, and locker library). Phase 2 is narrowly scoped to the **iOS/macOS native layer** only.

**Phase dependency:** Phase 1 (Android `KeyPermanentlyInvalidatedException` detection) is complete.

**The problem:** On iOS and macOS, the Secure Enclave key is created with the `.biometryCurrentSet` access control flag. When a user enrolls a new fingerprint, removes biometrics, or makes any biometric enrollment change, the hardware key becomes permanently inaccessible. The current code does not distinguish this case from a generic auth failure (user cancel, wrong fingerprint, lockout). The Dart layer cannot trigger the appropriate recovery flow (password-only teardown) because it cannot tell that the key is gone permanently.

**Two distinct invalidation points must be handled:**

- **Point A — `getPrivateKey` returns `nil`:** When the `.biometryCurrentSet` policy can no longer be satisfied after a biometric change, `SecItemCopyMatching` with an `LAContext` returns no result. This is ambiguous: user cancel and lockout also produce `nil`. A secondary `keyExists(tag:)` call using `kSecUseAuthenticationUISkip` (no auth prompt) distinguishes permanent invalidation (key item deleted by OS) from a transient failure (key still present but temporarily inaccessible). This check lives in `SecureEnclaveManager.decrypt()` because the `String` tag is available there.
- **Point B — `SecKeyCreateDecryptedData` fails with `errSecAuthFailed (-25293)`:** A key reference was obtained but the Secure Enclave refuses the cryptographic operation due to invalidation. This check is added as a new `case` in the existing `switch errorCode` block inside `KeychainService.decryptData(key:algorithm:data:)`, consistent with the existing `errSecUserCanceled` handling.

**Critical constraint:** `getPrivateKey` on `SecureEnclaveManager` returns `SecKey?` — it does **not** throw. It must not be wrapped in a `do { try }` block.

**Architecture of the two invalidation points:**

```
Point A (nil key → key gone):
  SecureEnclaveManager.decrypt()
    getPrivateKey(tag:) → nil
    keyExists(tag:) → false          ← private helper on SecureEnclaveManager
    throw SecureEnclaveManagerError.keyPermanentlyInvalidated

Point B (errSecAuthFailed from decryption op):
  KeychainService.decryptData(key:algorithm:data:)
    SecKeyCreateDecryptedData fails
    switch errorCode { case errSecAuthFailed: }
    throw KeychainServiceError.keyPermanentlyInvalidated
      ↓
  SecureEnclaveManager.decrypt()
    catch KeychainServiceError.keyPermanentlyInvalidated
    throw SecureEnclaveManagerError.keyPermanentlyInvalidated
```

**Full error propagation chain:**

```
Point A: keyExists() == false
  → SecureEnclaveManagerError.keyPermanentlyInvalidated

Point B: errSecAuthFailed
  → KeychainServiceError.keyPermanentlyInvalidated
  → SecureEnclaveManagerError.keyPermanentlyInvalidated (re-throw in SecureEnclaveManager)

Both paths converge:
  → SecureEnclaveManagerError.keyPermanentlyInvalidated
  → FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")   (BiometricCipherPlugin)
  → BiometricCipherExceptionCode.keyPermanentlyInvalidated  (Dart, Phase 3)
```

**Current codebase state (relevant to Phase 2):**

- `KeychainService.decryptData(key:algorithm:data:)` — takes `key: SecKey` directly (key lookup is the caller's responsibility). Already has a `switch errorCode` block handling `errSecUserCanceled` and `LAError.userCancel`. Point B's `errSecAuthFailed` case is added here.
- `SecureEnclaveManager.decrypt()` — calls its own private `getPrivateKey(tag:)`, throws `SecureEnclaveManagerError.failedGetPrivateKey` on nil today. Point A's `keyExists` check is added here, replacing the `failedGetPrivateKey` throw path. The method also wraps the `keychainService.decryptData()` call in a do/catch to re-throw `KeychainServiceError.keyPermanentlyInvalidated` as `SecureEnclaveManagerError.keyPermanentlyInvalidated`.
- `BiometricCipherPlugin.decrypt()` — already catches `KeychainServiceError.authenticationUserCanceled` explicitly. A new catch for `SecureEnclaveManagerError.keyPermanentlyInvalidated` is added before the generic fallthrough.

**Files to modify (all in `packages/biometric_cipher/darwin/Classes/`):**

```
Errors/KeychainServiceError.swift       — + .keyPermanentlyInvalidated case (Point B source)
Services/KeychainService.swift          — + errSecAuthFailed case in switch (Point B detection)
Errors/SecureEnclaveManagerError.swift  — + .keyPermanentlyInvalidated case
Managers/SecureEnclaveManager.swift     — + keyExists() helper + Point A detection + re-throw Point B
Errors/SecureEnclavePluginError.swift   — + .keyPermanentlyInvalidated case
BiometricCipherPlugin.swift             — + catch SecureEnclaveManagerError.keyPermanentlyInvalidated
```

No changes to `KeychainServiceProtocol.swift`. Zero new files. Six existing files modified.

---

## Goals

1. Surface a distinct `FlutterError` with code `"KEY_PERMANENTLY_INVALIDATED"` when the Secure Enclave key has been permanently invalidated by a biometric enrollment change, instead of the existing generic `"DECRYPTION_ERROR"`.
2. Correctly distinguish permanent key invalidation from transient failures (user cancel, wrong fingerprint, lockout) — these must continue producing their current error codes unchanged.
3. Handle both invalidation points: nil key reference with key gone from keychain (Point A, in `SecureEnclaveManager`) and `errSecAuthFailed` from `SecKeyCreateDecryptedData` (Point B, in `KeychainService`).
4. Keep changes minimal: one new enum case per error type, one private helper method, one new switch case, one new catch branch — no refactoring of surrounding code, no protocol changes.

---

## User Stories

**US-1 — App detects permanently invalidated Secure Enclave key**
As the app layer consuming the `biometric_cipher` plugin on iOS/macOS, I need to receive a distinct `"KEY_PERMANENTLY_INVALIDATED"` error code when the Secure Enclave key has been invalidated by a biometric enrollment change, so that I can trigger password-only teardown instead of showing a generic biometric failure.

**US-2 — Existing transient failures are unaffected**
As the app layer, I need user-cancel, wrong-fingerprint, and lockout errors to continue producing their current codes (`AUTHENTICATION_USER_CANCELED`, `DECRYPTION_ERROR`), so that existing recovery flows are not broken.

**US-3 — Key existence check does not trigger a biometric prompt**
As an end user, I do not want to see a biometric prompt when the app is merely checking whether a Secure Enclave key item still exists. The `keyExists(tag:)` check must be silent, using `kSecUseAuthenticationUISkip`.

---

## Main Scenarios

### Scenario 1: Biometric enrollment change — key deleted by OS (Point A, primary path)

1. User previously enabled biometric unlock; a Secure Enclave key exists in the keychain with `.biometryCurrentSet` access control.
2. User adds or removes a fingerprint in device settings; the OS deletes the key item.
3. App attempts biometric decrypt.
4. `SecureEnclaveManager.decrypt()` calls `getPrivateKey(tag:)` → `SecItemCopyMatching` returns no result → `nil`.
5. `SecureEnclaveManager.decrypt()` calls `keyExists(tag:)` (private helper, no auth prompt) → `SecItemCopyMatching` with `kSecUseAuthenticationUISkip` returns `errSecItemNotFound` → `false`.
6. `SecureEnclaveManager.decrypt()` throws `SecureEnclaveManagerError.keyPermanentlyInvalidated` directly (Point A does not go through `KeychainServiceError`).
7. `BiometricCipherPlugin.decrypt()` catches `SecureEnclaveManagerError.keyPermanentlyInvalidated`, returns `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED", message: "Biometric key has been permanently invalidated", details: nil)`.
8. Dart layer (Phase 3) maps this to `BiometricCipherExceptionCode.keyPermanentlyInvalidated`.

### Scenario 2: Key reference obtained but Secure Enclave refuses operation (Point B)

1. Biometric enrollment has changed but the OS did not delete the key item (it exists but is hardware-locked).
2. `getPrivateKey(tag:)` returns a non-nil `SecKey` reference.
3. `keychainService.decryptData(key:algorithm:data:)` is called.
4. `SecKeyCreateDecryptedData` fails; `CFErrorGetCode(cfError) == errSecAuthFailed` (`-25293`).
5. The new `case Int(errSecAuthFailed):` branch in `KeychainService.decryptData()` throws `KeychainServiceError.keyPermanentlyInvalidated`.
6. `SecureEnclaveManager.decrypt()` catches `KeychainServiceError.keyPermanentlyInvalidated`, re-throws `SecureEnclaveManagerError.keyPermanentlyInvalidated`.
7. `BiometricCipherPlugin.decrypt()` catches `SecureEnclaveManagerError.keyPermanentlyInvalidated` and returns the same `FlutterError` as Scenario 1.

### Scenario 3: `getPrivateKey` returns nil — key still present (user cancel / lockout, Point A non-invalidation)

1. User cancels the biometric prompt or device is locked out.
2. `getPrivateKey(tag:)` returns `nil` (OS withheld the key due to failed auth, item not deleted).
3. `SecureEnclaveManager.decrypt()` calls `keyExists(tag:)` → `SecItemCopyMatching` returns `errSecInteractionNotAllowed` (item exists but requires UI interaction) → `true`.
4. `SecureEnclaveManager.decrypt()` throws `SecureEnclaveManagerError.failedGetPrivateKey` (existing error, unchanged behavior).
5. `BiometricCipherPlugin.decrypt()` wraps this as `SecureEnclavePluginError.decryptionError` (existing behavior).

### Scenario 4: User cancels during `SecKeyCreateDecryptedData` (Point B, non-invalidation)

1. User cancels mid-operation.
2. `SecKeyCreateDecryptedData` fails with `errSecUserCanceled` or `LAError.userCancel`.
3. Existing `case Int(errSecUserCanceled), Int(LAError.userCancel.rawValue):` branch throws `KeychainServiceError.authenticationUserCanceled` — no change.
4. `BiometricCipherPlugin.decrypt()` catches `KeychainServiceError.authenticationUserCanceled` (existing branch) — no change.

---

## Success / Metrics

| Criterion | How to verify |
|-----------|--------------|
| `"KEY_PERMANENTLY_INVALIDATED"` is emitted for Point A (key deleted by OS, `keyExists` returns false) | Verified via Dart unit tests in Phase 3 (mocked method channel) |
| `"KEY_PERMANENTLY_INVALIDATED"` is emitted for Point B (`errSecAuthFailed` from `SecKeyCreateDecryptedData`) | Verified via Dart unit tests in Phase 3 (mocked method channel) |
| `keyExists()` does not trigger a biometric prompt | Uses `kSecUseAuthenticationUISkip` — verified by code review |
| User-cancel continues to emit `"AUTHENTICATION_USER_CANCELED"` | Existing behavior; confirmed by existing tests passing without modification |
| Generic decryption failure continues to emit `"DECRYPTION_ERROR"` | Existing behavior; confirmed by existing tests passing without modification |
| iOS debug build succeeds | `fvm flutter build ios --debug --no-codesign` completes without errors |
| macOS build succeeds | macOS target builds cleanly (CI: `make ci-build-macos` in example app) |

Dart-side verification (`BiometricCipherExceptionCode.keyPermanentlyInvalidated` received end-to-end) is out of scope for Phase 2 — covered by Phase 3.

---

## Constraints and Assumptions

- `keyExists(tag:)` is a **private method on `SecureEnclaveManager`** (not on `KeychainService` or `KeychainServiceProtocol`). It accepts a `String` tag, converts it to `Data` using `.utf8`, and queries the keychain with `kSecUseAuthenticationUISkip`. Zero changes to `KeychainServiceProtocol`.
- Point A (nil key) and Point B (`errSecAuthFailed`) originate in different classes but converge at `SecureEnclaveManagerError.keyPermanentlyInvalidated` before reaching the plugin. This is intentional: the plugin only needs to catch one error type.
- `errSecAuthFailed` = `-25293`. `CFErrorGetCode()` must be used to extract the numeric code; direct cast to `OSStatus` is not used.
- `kSecUseAuthenticationUISkip` suppresses the auth prompt. `errSecInteractionNotAllowed` → item exists, key is still present (transient failure). `errSecItemNotFound` → item gone (permanent invalidation).
- `BiometricCipherPlugin.decrypt()` currently has a `catch let error as KeychainServiceError` block with a `default:` path that would re-wrap any `KeychainServiceError` as `decryptionError`. Because Point B is re-thrown as `SecureEnclaveManagerError.keyPermanentlyInvalidated` before reaching the plugin, this block does not interfere with the new path. The plugin catches `SecureEnclaveManagerError.keyPermanentlyInvalidated` as a distinct branch before the generic `KeychainServiceError` catch.
- Only the `decrypt` path is affected. The `encrypt` path uses the public key and is not subject to `.biometryCurrentSet` access control for the encryption operation itself.
- No Swift unit tests are added in Phase 2. All testing is deferred to Phase 3 via Dart unit tests with a mocked method channel.
- `SecureEnclavePluginError.keyPermanentlyInvalidated` is added to `SecureEnclavePluginError` for completeness and consistency with the existing error hierarchy, even though the plugin catches `SecureEnclaveManagerError.keyPermanentlyInvalidated` directly and emits a `FlutterError` without going through `getFlutterError(SecureEnclavePluginError.keyPermanentlyInvalidated)`. The case may be used for internal consistency or future needs.

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| `errSecAuthFailed` (-25293) is returned for reasons other than key invalidation (e.g., transient Secure Enclave hardware error) | Low — Apple documents this code specifically for permanent key access failure after biometric change in the Secure Enclave context | Medium | Acceptable per KISS; password-only teardown is a safe recovery action even on a false positive — it only removes the bio wrap, not any vault data |
| `keyExists()` using `kSecUseAuthenticationUISkip` behaves differently on iOS vs macOS | Low — both platforms share the Security framework; the flag is documented consistently | Low | Verified by building for both targets in Phase 2 acceptance; integration confirmed in Phase 3 |
| `getPrivateKey` returning nil for a reason other than biometric change or auth failure (e.g., key tag mismatch, corrupt entry) causes a false `keyPermanentlyInvalidated` | Very low — `keyExists` returning `false` requires the OS to have deleted the item; a tag mismatch or corrupt entry would produce a different keychain status | Low | The two-step check (nil key + key gone) is conservative; only absence of the keychain item triggers invalidation |

---

## Resolved Questions

1. **Where does `keyExists(tag:)` live?** Resolved: private method on `SecureEnclaveManager`. The `String` tag is already available there. Zero protocol changes required.

2. **`KeychainServiceProtocol` impact?** Resolved: N/A. `keyExists` lives on `SecureEnclaveManager`, not on `KeychainService` or `KeychainServiceProtocol`. The protocol file is not touched.

3. **`errSecAuthFailed` check location (Point B)?** Resolved: added as a new `case` in the existing `switch errorCode` block inside `KeychainService.decryptData(key:algorithm:data:)`. This is consistent with the existing `errSecUserCanceled` / `LAError.userCancel` handling pattern in the same switch. Point A is in `SecureEnclaveManager`; Point B is in `KeychainService`; both converge at `SecureEnclaveManagerError.keyPermanentlyInvalidated`.

---

## Open Questions

None.
