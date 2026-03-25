# Research: AW-2160 Phase 2 — iOS/macOS Biometric Key Invalidation Detection

## 1. Resolved Questions

**Q1: Where does `keyExists(tag:)` live and where does Point A detection happen?**
The PRD is authoritative. `keyExists(tag:)` is a private method on `SecureEnclaveManager`, not on `KeychainService`. Point A (nil key → key gone) is detected inside `SecureEnclaveManager.decrypt()`. `KeychainService.decryptData()` handles only Point B (`errSecAuthFailed`). The `idea-2160.md` and `phase-2.md` code snippets reflect the original design-doc state before the actual `KeychainService` signature was known; the PRD supersedes them.

**Q2: What is the actual `KeychainService.decryptData()` signature?**
`decryptData(key: SecKey, algorithm: SecKeyAlgorithm, data: Data) throws -> Data`. Key lookup is the caller's responsibility (`SecureEnclaveManager`); the method takes a `SecKey` directly. There is no `tag` parameter on `KeychainService.decryptData()`.

**Q3: Any other constraints?**
None.

---

## 2. Phase Scope

Phase 2 modifies **six Swift files** in `packages/biometric_cipher/darwin/Classes/`. No new files are created. The goal is to surface `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")` from the native layer when the Secure Enclave key has been permanently invalidated by a biometric enrollment change — distinguishing it from transient failures (user cancel, lockout, wrong fingerprint) which must continue producing their existing codes.

Two invalidation points are handled:
- **Point A** — `getPrivateKey` returns `nil` and the key item is gone from the keychain (detected in `SecureEnclaveManager.decrypt()` via a new private `keyExists(tag:)` helper).
- **Point B** — `SecKeyCreateDecryptedData` fails with `errSecAuthFailed (-25293)` (detected in `KeychainService.decryptData()` via a new `case` in the existing `switch errorCode` block).

Both paths converge at `SecureEnclaveManagerError.keyPermanentlyInvalidated` before reaching `BiometricCipherPlugin`.

---

## 3. Related Modules and Files

All files are under:
`/Users/comrade77/Documents/Performix/Projects/mfa_locker/packages/biometric_cipher/darwin/Classes/`

| File | Role in Phase 2 |
|------|----------------|
| `Errors/KeychainServiceError.swift` | Add `.keyPermanentlyInvalidated` case (Point B source) |
| `Services/KeychainService.swift` | Add `errSecAuthFailed` case in `switch errorCode` (Point B detection) |
| `Errors/SecureEnclaveManagerError.swift` | Add `.keyPermanentlyInvalidated` case |
| `Managers/SecureEnclaveManager.swift` | Add private `keyExists(tag:)` helper; rework `decrypt()` for Point A detection and Point B re-throw |
| `Errors/SecureEnclavePluginError.swift` | Add `.keyPermanentlyInvalidated` case (for completeness) |
| `BiometricCipherPlugin.swift` | Add catch branch for `SecureEnclaveManagerError.keyPermanentlyInvalidated` |

Untouched files (confirmed):
- `Protocols/KeychainServiceProtocol.swift` — zero changes required
- All other Swift files in `darwin/Classes/`

---

## 4. Current Signatures and Logic of Methods Being Modified

### `KeychainService.decryptData()` (Services/KeychainService.swift, lines 51–66)

```swift
func decryptData(key: SecKey, algorithm: SecKeyAlgorithm, data: Data) throws -> Data {
    var error: Unmanaged<CFError>?
    guard let decryptedData = SecKeyCreateDecryptedData(key, algorithm, data as CFData, &error) else {
        if let cfError = error?.takeRetainedValue() {
            let errorCode = CFErrorGetCode(cfError)
            switch errorCode {
            case Int(errSecUserCanceled), Int(LAError.userCancel.rawValue):
                throw KeychainServiceError.authenticationUserCanceled
            default:
                throw KeychainServiceError.failedToDecryptData(cfError)
            }
        }
        throw KeychainServiceError.failedToDecryptData(nil)
    }
    return decryptedData as Data
}
```

**Point B insertion:** A new `case Int(errSecAuthFailed):` branch must be added before `default:` in the `switch errorCode` block. It throws `KeychainServiceError.keyPermanentlyInvalidated` (the new case). Note that `failedToDecryptData` is an associated-value case: `case failedToDecryptData(Error?)`.

### `SecureEnclaveManager.decrypt()` (Managers/SecureEnclaveManager.swift, lines 155–181)

```swift
func decrypt(_ encryptedData: Data, tag: String) throws -> String {
    let privateKeyTag = try getTagData(tag: tag)

    guard let privateKey = getPrivateKey(tag: privateKeyTag) else {
        throw SecureEnclaveManagerError.failedGetPrivateKey
    }

    let algorithm: SecKeyAlgorithm = .eciesEncryptionCofactorX963SHA256AESGCM

    guard keychainService.isAlgorithmSupported(key: privateKey,
                                               operation: .decrypt,
                                               algorithm: algorithm) else {
        throw SecureEnclaveManagerError.decryptionAlgorithmNotSupported
    }

    let decryptedData = try keychainService.decryptData(key: privateKey,
                                                        algorithm: algorithm,
                                                        data: encryptedData)

    guard let decryptedString = String(data: decryptedData as Data, encoding: .utf8) else {
        throw SecureEnclaveManagerError.decodeEncryptedDataFailed
    }

    return decryptedString
}
```

**Key observations for the rewrite:**
- `getPrivateKey(tag: Data) -> SecKey?` is a private method on `SecureEnclaveManager` (line 196) that takes `Data`, not `String`. The `tag: Data` is produced by `getTagData(tag: String)` which prepends `AppConstants.privateKeyTag` (`"com.adguard.tpm.secureEnclavePrivateKey"`) and converts to UTF-8.
- The new private `keyExists(tag:)` helper must therefore also accept `Data` (since that is what is available at the call site in `decrypt()` after `getTagData()` is called) — or it can rebuild from the raw `String` tag. The PRD says `keyExists(tag:)` accepts a `String` tag and converts with `.utf8`. Since `decrypt()` has both the raw `String tag` parameter and the derived `Data privateKeyTag`, the implementation can use either. The `keyExists` query must use the same tag format as `getPrivateKey` to query the same keychain item: the prefixed `Data` form.
- The `do/catch` wrapping `keychainService.decryptData()` must let non-`keyPermanentlyInvalidated` `KeychainServiceError`s propagate unmodified (including `authenticationUserCanceled`, which is caught by `BiometricCipherPlugin` as a distinct branch).

**Target shape for `decrypt()` after Phase 2:**
- `getTagData(tag:)` call remains.
- `guard let privateKey = getPrivateKey(tag: privateKeyTag) else { ... }` block: instead of throwing `failedGetPrivateKey`, call `keyExists(tag: privateKeyTag)` — if `false`, throw `SecureEnclaveManagerError.keyPermanentlyInvalidated`; otherwise throw `SecureEnclaveManagerError.failedGetPrivateKey`.
- `isAlgorithmSupported` guard remains unchanged.
- `keychainService.decryptData()` call is wrapped in `do { ... } catch KeychainServiceError.keyPermanentlyInvalidated { throw SecureEnclaveManagerError.keyPermanentlyInvalidated }`. Other `KeychainServiceError`s (including `authenticationUserCanceled`) propagate unchanged.

### `getPrivateKey(tag: Data) -> SecKey?` (Managers/SecureEnclaveManager.swift, lines 196–214)

This private method is **not modified**. It takes `tag: Data`. The new `keyExists` helper must match its keychain query structure (same `kSecClass`, `kSecAttrApplicationTag`) but add `kSecUseAuthenticationUI: kSecUseAuthenticationUISkip` and omit `kSecAttrTokenID` / `kSecUseAuthenticationContext` considerations (existence check only, no auth).

---

## 5. Existing Error Enum Cases

### `KeychainServiceError` (Errors/KeychainServiceError.swift)

Current cases:
- `failedToCreateRandomKey(Error?)`
- `failedToDeleteItem`
- `failedToCopyPublicKey`
- `failedToEncryptData(Error?)`
- `failedToDecryptData(Error?)` — note this is an associated-value case
- `authenticationUserCanceled`

**New case to add:** `keyPermanentlyInvalidated` — no associated value (mirrors `authenticationUserCanceled` which also has no associated value). Required additions: `code` (`"KEY_PERMANENTLY_INVALIDATED"`) and `errorDescription` string in the respective `switch` blocks.

### `SecureEnclaveManagerError` (Errors/SecureEnclaveManagerError.swift)

Current cases:
- `invalidTag`
- `invalidAuthTitle`
- `failedGetPrivateKey`
- `failedGetPublicKey`
- `invalidEncryptionData`
- `encryptionAlgorithmNotSupported`
- `decryptionAlgorithmNotSupported`
- `decodeEncryptedDataFailed`
- `keyAlreadyExists`

**New case to add:** `keyPermanentlyInvalidated` — no associated value. Required additions: `code` (`"KEY_PERMANENTLY_INVALIDATED"`) and `errorDescription` in the respective `switch` blocks.

### `SecureEnclavePluginError` (Errors/SecureEnclavePluginError.swift)

Current cases:
- `secureEnclaveNoAvailable`
- `biometryNotAvailable`
- `invalidArgument`
- `keyGenerationError(error: Error)` — associated value
- `encryptionError(error: Error)` — associated value
- `decryptionError(error: Error)` — associated value
- `keyDeletionError(error: Error)` — associated value
- `unknown`

**New case to add:** `keyPermanentlyInvalidated` — no associated value (the plugin catches `SecureEnclaveManagerError.keyPermanentlyInvalidated` directly and emits a `FlutterError` without routing through `getFlutterError(SecureEnclavePluginError.keyPermanentlyInvalidated)`; this case is added for completeness per the PRD). Required additions: `code` (`"KEY_PERMANENTLY_INVALIDATED"`) and `errorDescription` in the respective `switch` blocks.

---

## 6. Existing Catch Patterns in `BiometricCipherPlugin.decrypt()`

The current `decrypt()` method (lines 226–261) has this catch structure:

```swift
} catch let error as KeychainServiceError {
    switch error {
    case .authenticationUserCanceled:
        let flutterError = getFlutterError(error)
        result(flutterError)
    default:
        let flutterError = getFlutterError(SecureEnclavePluginError.decryptionError(error: error))
        result(flutterError)
    }
} catch {
    let flutterError = getFlutterError(SecureEnclavePluginError.decryptionError(error: error))
    result(flutterError)
}
```

**Insertion point for new catch branch:** A new `catch let error as SecureEnclaveManagerError` block must be inserted **before** the existing `catch let error as KeychainServiceError` block. This is necessary because `SecureEnclaveManagerError.keyPermanentlyInvalidated` is re-thrown from `SecureEnclaveManager.decrypt()` and must be caught before the generic `KeychainServiceError` sweep. The existing `KeychainServiceError.authenticationUserCanceled` catch is unaffected because Point B re-throws as `SecureEnclaveManagerError` before reaching the plugin.

**Target catch block to insert:**
```swift
} catch SecureEnclaveManagerError.keyPermanentlyInvalidated {
    result(FlutterError(
        code: "KEY_PERMANENTLY_INVALIDATED",
        message: "Biometric key has been permanently invalidated",
        details: nil
    ))
```

Note: this does not use `getFlutterError()` (it constructs `FlutterError` directly with a hardcoded code string), which is consistent with the PRD spec. The existing `authenticationUserCanceled` branch does use `getFlutterError(error)` because the `KeychainServiceError` already implements `BaseError` with the right code. Either approach is valid; the PRD shows the direct construction.

---

## 7. `keyExists(tag:)` Helper — Implementation Details

The new private method on `SecureEnclaveManager`:

- **Parameter type:** The PRD says `String` tag; however, at the call site in `decrypt()`, the derived `Data` form (`privateKeyTag`) is already available. The method can accept `Data` directly to avoid re-encoding — or accept `String` and re-derive `Data`. The PRD text says "accepts a `String` tag, converts it to `Data` using `.utf8`", but the actual tag stored in the keychain is the prefixed form produced by `getTagData()`: `"com.adguard.tpm.secureEnclavePrivateKey.\(tag)"`. If `keyExists` accepts the raw `String` it must replicate the `getTagData` prefix logic. Accepting `Data` (the already-prefixed form) avoids duplication.

  **Recommended:** Accept `tag: Data` so the call site passes `privateKeyTag` (already prefixed) directly.

- **Keychain query attributes:** Match the item being queried. Current `getPrivateKey` query uses: `kSecClass: kSecClassKey`, `kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom`, `kSecAttrTokenID: kSecAttrTokenIDSecureEnclave`, `kSecAttrApplicationTag: tag`, `kSecReturnRef: true`, plus optional `kSecUseAuthenticationContext`. The existence check query must include `kSecUseAuthenticationUI: kSecUseAuthenticationUISkip` and should **not** include `kSecReturnRef: true` (we're checking existence, not retrieving the key). `kSecReturnAttributes: true` or simply omitting the return key is acceptable.

- **Status interpretation:**
  - `errSecSuccess` → item found and accessible → key still present → return `true`
  - `errSecInteractionNotAllowed` → item found but requires auth UI (suppressed) → key still present → return `true`
  - `errSecItemNotFound` → item deleted by OS after biometric change → return `false`
  - Any other status → treat as key still present (conservative; only confirmed absence of item triggers invalidation) → return `true`

---

## 8. Phase-Specific Limitations and Risks

### Risk 1: `keyExists` tag format mismatch
If `keyExists` uses the raw string tag (without the `AppConstants.privateKeyTag` prefix), it will query a non-existent keychain item and always return `false`, causing all Point A nil-key situations to be misclassified as permanent invalidation — including user cancel and lockout. **Mitigation:** Accept `tag: Data` (the already-prefixed form produced by `getTagData()`) at the call site, or replicate the prefix logic exactly.

### Risk 2: `kSecAttrTokenID` in `keyExists` query
The `getPrivateKey` query includes `kSecAttrTokenID: kSecAttrTokenIDSecureEnclave`. This is correct for finding Secure Enclave keys specifically. The `keyExists` query should include the same `kSecAttrTokenID` attribute to ensure it queries only Secure Enclave keys and not a software key with the same tag. Without it, the query might match a non-SE key that happens to share the tag.

### Risk 3: `catch` ordering in `BiometricCipherPlugin.decrypt()`
The new `catch SecureEnclaveManagerError.keyPermanentlyInvalidated` block must appear **before** `catch let error as KeychainServiceError`. Swift catches are evaluated in order; if the `KeychainServiceError` catch appeared first and `SecureEnclaveManagerError` somehow conformed to it (it doesn't — they are unrelated enums), it would shadow the new catch. In this case the ordering is for clarity and future-safety, not correctness, but it must still be inserted at the right position.

### Risk 4: `errSecAuthFailed` false positives (Point B)
`errSecAuthFailed (-25293)` is documented by Apple as indicating permanent key invalidation after biometric change in the Secure Enclave context. A transient hardware error returning the same code would be misclassified. The PRD judges this risk as low and acceptable (password-only teardown is a safe recovery action — it removes the bio wrap but no vault data).

### Risk 5: `do/catch` in `SecureEnclaveManager.decrypt()` must not catch `authenticationUserCanceled`
The do/catch wrapping `keychainService.decryptData()` must only catch `KeychainServiceError.keyPermanentlyInvalidated` and let all other errors propagate. `KeychainServiceError.authenticationUserCanceled` must reach `BiometricCipherPlugin.decrypt()`'s existing `catch let error as KeychainServiceError` block intact. Using a specific `catch KeychainServiceError.keyPermanentlyInvalidated` (not a general `catch`) ensures this.

### Risk 6: `SecureEnclaveManagerError` pattern-match in `generateKeyPair`
`BiometricCipherPlugin.generateKeyPair()` already catches `SecureEnclaveManagerError` specifically: `catch let error as SecureEnclaveManagerError where error == .keyAlreadyExists`. This uses `==` on the enum, which requires `Equatable` conformance or a pattern match. Existing `SecureEnclaveManagerError` cases are all no-argument (except they aren't — they have no associated values), so adding `keyPermanentlyInvalidated` does not affect this catch (the `where` clause limits it to `.keyAlreadyExists`).

---

## 9. New Technical Questions Discovered

None. The PRD is comprehensive and the codebase matches the PRD's description of the current state exactly.
