# Phase 2: iOS/macOS — detect biometric key invalidation

**Goal:** Detect invalidated Secure Enclave keys at two points (nil key + `errSecAuthFailed`) and surface `KEY_PERMANENTLY_INVALIDATED` through the Flutter method channel.

## Context

**Feature motivation:** On iOS and macOS, the Secure Enclave key is created with the `.biometryCurrentSet` access control flag. When any biometric change occurs (enrollment or removal), the hardware key becomes permanently inaccessible. This must produce a distinct `KEY_PERMANENTLY_INVALIDATED` channel code rather than a generic auth failure, so the app can trigger password-only teardown.

**Technical approach:** Two distinct invalidation points must be handled:
- **Point A** — `getPrivateKey` returns `nil`: `SecItemCopyMatching` with `LAContext` returns no result when `.biometryCurrentSet` policy can no longer be satisfied. A secondary `keyExists(tag:)` call distinguishes this from user-cancel/lockout.
- **Point B** — `SecKeyCreateDecryptedData` fails with `errSecAuthFailed (-25293)`: a key reference was obtained but the Secure Enclave refuses the cryptographic operation.

**Critical note:** `getPrivateKey` returns `SecKey?` — it does **not** throw. Wrapping it in a `do { try }` block is incorrect.

**Error propagation chain (iOS/macOS path):**
```
keyExists() == false  OR  errSecAuthFailed
  → KeychainServiceError.keyPermanentlyInvalidated
  → SecureEnclaveManagerError.keyPermanentlyInvalidated
  → SecureEnclavePluginError.keyPermanentlyInvalidated (mapped in BiometricCipherPlugin)
  → FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")
  → BiometricCipherExceptionCode.keyPermanentlyInvalidated (Dart, Iteration 3)
```

**Files affected (all existing):**
```
packages/biometric_cipher/darwin/Classes/
├── Errors/KeychainServiceError.swift       # + .keyPermanentlyInvalidated case
├── Services/KeychainService.swift          # rewrite decryptData() + add keyExists()
├── Errors/SecureEnclaveManagerError.swift  # + .keyPermanentlyInvalidated case
├── Managers/SecureEnclaveManager.swift     # rewrite decrypt()
├── Errors/SecureEnclavePluginError.swift   # + .keyPermanentlyInvalidated case
└── BiometricCipherPlugin.swift             # + catch → FlutterError mapping
```

## Tasks

- [ ] **2.1** Add `.keyPermanentlyInvalidated` to `KeychainServiceError`
  - File: `packages/biometric_cipher/darwin/Classes/Errors/KeychainServiceError.swift`
  - Add case + code `"KEY_PERMANENTLY_INVALIDATED"` + description

- [ ] **2.2** Add `keyExists(tag:)` helper to `KeychainService`
  - File: `packages/biometric_cipher/darwin/Classes/Services/KeychainService.swift`
  - Query keychain with `kSecUseAuthenticationUI: kSecUseAuthenticationUISkip`, no auth prompt
  - Returns `true` if `errSecSuccess` or `errSecInteractionNotAllowed`

- [ ] **2.3** Update `KeychainService.decryptData()` — detect `errSecAuthFailed`
  - Same file as 2.2
  - Replace the `guard let key = getPrivateKey(tag: tag)` nil path: call `keyExists(tag:)` to distinguish invalidation from cancel/lockout
  - In the `SecKeyCreateDecryptedData` error path: check `CFErrorGetCode(cfError) == errSecAuthFailed` → throw `.keyPermanentlyInvalidated`

- [ ] **2.4** Add `.keyPermanentlyInvalidated` to `SecureEnclaveManagerError`
  - File: `packages/biometric_cipher/darwin/Classes/Errors/SecureEnclaveManagerError.swift`
  - Add case + code + description

- [ ] **2.5** Update `SecureEnclaveManager.decrypt()` — propagate invalidation
  - File: `packages/biometric_cipher/darwin/Classes/Managers/SecureEnclaveManager.swift`
  - Wrap `keychainService.decryptData()` call in do/catch to re-throw `KeychainServiceError.keyPermanentlyInvalidated` as `SecureEnclaveManagerError.keyPermanentlyInvalidated`
  - Other `KeychainServiceErrors` propagate unchanged

- [ ] **2.6** Add `.keyPermanentlyInvalidated` to `SecureEnclavePluginError`
  - File: `packages/biometric_cipher/darwin/Classes/Errors/SecureEnclavePluginError.swift`
  - Add case + code `"KEY_PERMANENTLY_INVALIDATED"` + description

- [ ] **2.7** Catch `.keyPermanentlyInvalidated` in `BiometricCipherPlugin.decrypt()`
  - File: `packages/biometric_cipher/darwin/Classes/BiometricCipherPlugin.swift`
  - Add catch branch for `SecureEnclaveManagerError.keyPermanentlyInvalidated` (follow existing `authenticationUserCanceled` pattern)
  - Map to `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED", message: "Biometric key has been permanently invalidated", details: nil)`

## Acceptance Criteria

**Verify:** Build iOS/macOS (`fvm flutter build ios --debug --no-codesign`). Channel code `KEY_PERMANENTLY_INVALIDATED` flows correctly — fully testable via Dart unit tests in Iteration 3.

## Dependencies

- Phase 1 complete ✅

## Technical Details

### `KeychainService.swift` — `decryptData()` and `keyExists()` target state

```swift
func decryptData(_ data: Data, tag: String) throws -> Data {
    guard let key = getPrivateKey(tag: tag) else {
        // Key reference is nil — check whether the item still exists in the keychain.
        // If the OS deleted it (biometric change), keyExists returns false → permanently invalidated.
        // If it still exists (user cancel / lockout), surface a regular auth error.
        if !keyExists(tag: tag) {
            throw KeychainServiceError.keyPermanentlyInvalidated
        }
        throw KeychainServiceError.failedToDecryptData
    }

    var error: Unmanaged<CFError>?
    guard let decrypted = SecKeyCreateDecryptedData(
        key, .eciesEncryptionCofactorVariableIVX963SHA256AESGCM, data as CFData, &error
    ) as Data? else {
        if let cfError = error?.takeRetainedValue() {
            if CFErrorGetCode(cfError) == errSecAuthFailed {  // -25293
                throw KeychainServiceError.keyPermanentlyInvalidated
            }
        }
        throw KeychainServiceError.failedToDecryptData
    }
    return decrypted
}

/// Returns `true` if a Secure Enclave key item with the given tag exists in the keychain,
/// regardless of whether the caller can authenticate to use it.
private func keyExists(tag: String) -> Bool {
    guard let tagData = tag.data(using: .utf8) else { return false }
    let query: [CFString: Any] = [
        kSecClass: kSecClassKey,
        kSecAttrApplicationTag: tagData,
        kSecUseAuthenticationUI: kSecUseAuthenticationUISkip,
        kSecReturnAttributes: true,
    ]
    let status = SecItemCopyMatching(query as CFDictionary, nil)
    // errSecInteractionNotAllowed → item exists but requires auth → key is still there
    // errSecItemNotFound          → item gone (deleted by OS after biometric change)
    return status == errSecSuccess || status == errSecInteractionNotAllowed
}
```

### `SecureEnclaveManager.swift` — `decrypt()` target state

```swift
// Before:
func decrypt(data: Data, tag: String) throws -> Data {
    guard let key = getPrivateKey(tag: tag) else {
        throw SecureEnclaveManagerError.keyNotFound
    }
    return try keychainService.decryptData(data, tag: tag)
}

// After:
func decrypt(data: Data, tag: String) throws -> Data {
    do {
        return try keychainService.decryptData(data, tag: tag)
    } catch KeychainServiceError.keyPermanentlyInvalidated {
        throw SecureEnclaveManagerError.keyPermanentlyInvalidated
    }
    // Other KeychainServiceErrors propagate unchanged.
}
```

### `BiometricCipherPlugin.swift` — catch branch (follows existing pattern)

```swift
} catch SecureEnclaveManagerError.keyPermanentlyInvalidated {
    result(FlutterError(
        code: "KEY_PERMANENTLY_INVALIDATED",
        message: "Biometric key has been permanently invalidated",
        details: nil,
    ))
}
```

## Implementation Notes

- `getPrivateKey` returns `SecKey?` and does **not** throw — do NOT wrap in `do { try }`.
- `errSecAuthFailed` = `-25293`. Use `CFErrorGetCode()` to extract it from `CFError`.
- `kSecUseAuthenticationUISkip` suppresses the auth prompt in `keyExists()` — we only want to check existence, not authenticate.
- `errSecInteractionNotAllowed` in `keyExists()` means the item exists but requires UI interaction → key is still present.
- `errSecItemNotFound` in `keyExists()` means the OS deleted the item after a biometric change → key is gone.
- Follow KISS principle: minimal changes, follow existing error enum + catch patterns already present in the codebase.
- No behavior changes to existing flows: wrong fingerprint / lockout / user cancel continue producing existing error types.
