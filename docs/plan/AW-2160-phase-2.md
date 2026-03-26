# Plan: AW-2160 Phase 2 -- iOS/macOS: Detect Biometric Key Invalidation via Secure Enclave

Status: PLAN_APPROVED

## Phase Scope

Phase 2 modifies six existing Swift files in `packages/biometric_cipher/darwin/Classes/` to detect when a Secure Enclave key has been permanently invalidated by a biometric enrollment change on iOS/macOS. The output is a distinct `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")` on the method channel, replacing the current generic `"DECRYPTION_ERROR"` or `"FAILED_GET_PRIVATE_KEY"` codes.

No new files are created. No Dart code is modified. No protocol changes. No changes to the `encrypt` path.

Two invalidation detection points are implemented:
- **Point A** -- `getPrivateKey` returns `nil` and the keychain item is gone (detected in `SecureEnclaveManager.decrypt()`)
- **Point B** -- `SecKeyCreateDecryptedData` fails with `errSecAuthFailed` (`-25293`) (detected in `KeychainService.decryptData()`)

Both paths converge at `SecureEnclaveManagerError.keyPermanentlyInvalidated` before reaching `BiometricCipherPlugin`.

---

## Components

### 1. `KeychainServiceError.swift` -- new enum case

**Path:** `packages/biometric_cipher/darwin/Classes/Errors/KeychainServiceError.swift`

**Change:** Add `case keyPermanentlyInvalidated` (no associated value, same as `authenticationUserCanceled`). Add `code` return `"KEY_PERMANENTLY_INVALIDATED"` and `errorDescription` return `"Biometric key has been permanently invalidated."` in the respective `switch` blocks.

**Placement:** After `authenticationUserCanceled` (last case before closing brace).

### 2. `KeychainService.swift` -- `errSecAuthFailed` detection (Point B)

**Path:** `packages/biometric_cipher/darwin/Classes/Services/KeychainService.swift`

**Change:** In `decryptData(key:algorithm:data:)`, add a new `case Int(errSecAuthFailed):` branch in the existing `switch errorCode` block, between the `errSecUserCanceled`/`LAError.userCancel` branch and `default:`. This throws `KeychainServiceError.keyPermanentlyInvalidated`.

**Target state of the switch block:**

```swift
switch errorCode {
case Int(errSecUserCanceled), Int(LAError.userCancel.rawValue):
    throw KeychainServiceError.authenticationUserCanceled
case Int(errSecAuthFailed):
    throw KeychainServiceError.keyPermanentlyInvalidated
default:
    throw KeychainServiceError.failedToDecryptData(cfError)
}
```

No other changes to `KeychainService`. The `decryptData` signature remains `(key: SecKey, algorithm: SecKeyAlgorithm, data: Data) throws -> Data`. No `tag` parameter is added. No `keyExists` method is placed here.

### 3. `SecureEnclaveManagerError.swift` -- new enum case

**Path:** `packages/biometric_cipher/darwin/Classes/Errors/SecureEnclaveManagerError.swift`

**Change:** Add `case keyPermanentlyInvalidated` (no associated value). Add `code` return `"KEY_PERMANENTLY_INVALIDATED"` and `errorDescription` return `"Biometric key has been permanently invalidated."` in the respective `switch` blocks.

**Placement:** After `keyAlreadyExists` (last case before the `code` property).

### 4. `SecureEnclaveManager.swift` -- Point A detection + Point B re-throw + `keyExists` helper

**Path:** `packages/biometric_cipher/darwin/Classes/Managers/SecureEnclaveManager.swift`

Three changes to this file:

**4a. Add private `keyExists(tag: Data) -> Bool` helper method.**

This method queries the keychain to check whether a key item with the given tag still exists, without triggering a biometric prompt. It uses `kSecUseAuthenticationUI: kSecUseAuthenticationUISkip`.

Parameter type is `Data` (not `String`) because the call site in `decrypt()` already has the prefixed `Data` form produced by `getTagData()`. This avoids duplicating the tag prefix logic.

The query attributes mirror `getPrivateKey`'s query structure for accurate item matching:
- `kSecClass: kSecClassKey`
- `kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom`
- `kSecAttrTokenID: kSecAttrTokenIDSecureEnclave`
- `kSecAttrApplicationTag: tag`
- `kSecUseAuthenticationUI: kSecUseAuthenticationUISkip`

`kSecReturnRef` is omitted (existence check only, no key retrieval). `kSecReturnAttributes: true` is used to have a defined return behavior without triggering auth.

Status interpretation:
- `errSecSuccess` or `errSecInteractionNotAllowed` --> `true` (key exists; interaction-not-allowed means item is present but auth UI was suppressed)
- `errSecItemNotFound` --> `false` (item deleted by OS after biometric change)
- Any other status --> `true` (conservative; only confirmed absence triggers invalidation)

**4b. Modify `decrypt()` -- Point A detection.**

In the existing `guard let privateKey = getPrivateKey(tag: privateKeyTag) else { ... }` block, replace the unconditional `throw SecureEnclaveManagerError.failedGetPrivateKey` with:

```swift
guard let privateKey = getPrivateKey(tag: privateKeyTag) else {
    if !keyExists(tag: privateKeyTag) {
        throw SecureEnclaveManagerError.keyPermanentlyInvalidated
    }
    throw SecureEnclaveManagerError.failedGetPrivateKey
}
```

This distinguishes permanent invalidation (key item gone) from transient failures (user cancel, lockout -- key item still present). The `failedGetPrivateKey` path is preserved for non-invalidation nil-key cases.

**4c. Modify `decrypt()` -- Point B re-throw.**

Wrap the `keychainService.decryptData()` call in a do/catch that specifically catches `KeychainServiceError.keyPermanentlyInvalidated` and re-throws it as `SecureEnclaveManagerError.keyPermanentlyInvalidated`. All other errors propagate unchanged.

```swift
let decryptedData: Data
do {
    decryptedData = try keychainService.decryptData(key: privateKey,
                                                     algorithm: algorithm,
                                                     data: encryptedData)
} catch KeychainServiceError.keyPermanentlyInvalidated {
    throw SecureEnclaveManagerError.keyPermanentlyInvalidated
}
```

The specific `catch KeychainServiceError.keyPermanentlyInvalidated` pattern ensures that `KeychainServiceError.authenticationUserCanceled` and other errors propagate to `BiometricCipherPlugin.decrypt()` unchanged. This is critical -- the plugin's existing `catch let error as KeychainServiceError` block must continue to receive `authenticationUserCanceled` directly.

### 5. `SecureEnclavePluginError.swift` -- new enum case

**Path:** `packages/biometric_cipher/darwin/Classes/Errors/SecureEnclavePluginError.swift`

**Change:** Add `case keyPermanentlyInvalidated` (no associated value). Add `code` return `"KEY_PERMANENTLY_INVALIDATED"` and `errorDescription` return `"Biometric key has been permanently invalidated."` in the respective `switch` blocks.

**Placement:** After `keyDeletionError` (before `unknown`).

**Usage note:** This case is added for completeness and consistency with the error hierarchy. The plugin catches `SecureEnclaveManagerError.keyPermanentlyInvalidated` directly and constructs a `FlutterError` without going through `getFlutterError(SecureEnclavePluginError.keyPermanentlyInvalidated)`. The case exists for potential future use or internal consistency.

### 6. `BiometricCipherPlugin.swift` -- new catch branch

**Path:** `packages/biometric_cipher/darwin/Classes/BiometricCipherPlugin.swift`

**Change:** In the `decrypt()` method, add a new catch branch for `SecureEnclaveManagerError.keyPermanentlyInvalidated` that returns `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED", message: "Biometric key has been permanently invalidated", details: nil)`.

**Insertion point:** The new catch must be inserted **before** the existing `catch let error as KeychainServiceError` block. This ordering is necessary because `SecureEnclaveManagerError.keyPermanentlyInvalidated` is a different type than `KeychainServiceError` -- Swift evaluates catch clauses top-to-bottom, and we need the new error to be caught before the generic `KeychainServiceError` sweep.

**Target catch structure:**

```swift
do {
    let decryptedDatabase64Data = try Base64Codec.decode(data)
    let decryptedData = try secureEnclaveManager.decrypt(decryptedDatabase64Data, tag: tag)
    result(decryptedData)
} catch SecureEnclaveManagerError.keyPermanentlyInvalidated {
    result(FlutterError(
        code: "KEY_PERMANENTLY_INVALIDATED",
        message: "Biometric key has been permanently invalidated",
        details: nil
    ))
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

The `FlutterError` is constructed directly (not via `getFlutterError`) with hardcoded code `"KEY_PERMANENTLY_INVALIDATED"`. This matches the Android Phase 1 output and the Dart Phase 3 expectation.

---

## API Contract

### Method channel output (changed behavior)

| Condition | Before Phase 2 | After Phase 2 |
|-----------|----------------|---------------|
| Point A: `getPrivateKey` returns nil, key item gone from keychain | `FlutterError(code: "DECRYPTION_ERROR")` via `failedGetPrivateKey` -> `decryptionError` | `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")` |
| Point B: `SecKeyCreateDecryptedData` fails with `errSecAuthFailed` (-25293) | `FlutterError(code: "DECRYPTION_ERROR")` via `failedToDecryptData` -> `decryptionError` | `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")` |
| Point A: `getPrivateKey` returns nil, key item still present (user cancel/lockout) | `FlutterError(code: "DECRYPTION_ERROR")` via `failedGetPrivateKey` -> `decryptionError` | Unchanged -- `failedGetPrivateKey` path preserved |
| User cancels during `SecKeyCreateDecryptedData` | `FlutterError(code: "AUTHENTICATION_USER_CANCELED")` | Unchanged |
| Generic decryption failure | `FlutterError(code: "DECRYPTION_ERROR")` | Unchanged |

### Downstream consumers (Phase 3)

The Dart plugin layer will map `"KEY_PERMANENTLY_INVALIDATED"` to `BiometricCipherExceptionCode.keyPermanentlyInvalidated`. Until Phase 3, this code falls through to the `unknown` case in the Dart enum's `fromString`. This is acceptable.

---

## Data Flows

### Point A flow (primary -- key item deleted by OS)

```
User biometric enrollment changes
  -> OS deletes Secure Enclave key item from keychain
  -> App calls decrypt via method channel
  -> BiometricCipherPlugin.decrypt()
    -> secureEnclaveManager.decrypt(data, tag)
      -> getTagData(tag:) -> privateKeyTag (Data)
      -> getPrivateKey(tag: privateKeyTag) -> nil
      -> keyExists(tag: privateKeyTag) -> false  (SecItemCopyMatching returns errSecItemNotFound)
      -> throw SecureEnclaveManagerError.keyPermanentlyInvalidated
    -> catch SecureEnclaveManagerError.keyPermanentlyInvalidated
    -> result(FlutterError(code: "KEY_PERMANENTLY_INVALIDATED", ...))
  -> Dart receives PlatformException with code "KEY_PERMANENTLY_INVALIDATED"
```

### Point B flow (key reference obtained but Secure Enclave refuses operation)

```
User biometric enrollment changes
  -> OS invalidates key but item still exists in keychain
  -> App calls decrypt via method channel
  -> BiometricCipherPlugin.decrypt()
    -> secureEnclaveManager.decrypt(data, tag)
      -> getPrivateKey(tag: privateKeyTag) -> SecKey (non-nil reference)
      -> keychainService.decryptData(key:algorithm:data:)
        -> SecKeyCreateDecryptedData fails
        -> CFErrorGetCode(cfError) == errSecAuthFailed (-25293)
        -> throw KeychainServiceError.keyPermanentlyInvalidated
      -> catch KeychainServiceError.keyPermanentlyInvalidated
      -> throw SecureEnclaveManagerError.keyPermanentlyInvalidated
    -> catch SecureEnclaveManagerError.keyPermanentlyInvalidated
    -> result(FlutterError(code: "KEY_PERMANENTLY_INVALIDATED", ...))
  -> Dart receives PlatformException with code "KEY_PERMANENTLY_INVALIDATED"
```

### Non-invalidation flow (user cancel, preserved behavior)

```
User cancels biometric prompt
  -> getPrivateKey(tag:) -> nil (OS withheld key)
  -> keyExists(tag:) -> true (errSecInteractionNotAllowed, item still present)
  -> throw SecureEnclaveManagerError.failedGetPrivateKey (existing behavior)
  -> BiometricCipherPlugin generic catch
  -> result(FlutterError(code: "DECRYPTION_ERROR", ...)) (existing behavior)
```

---

## NFR

| Requirement | How satisfied |
|-------------|---------------|
| No regression to existing error flows | Point A: `failedGetPrivateKey` path preserved when `keyExists` returns `true`. Point B: `authenticationUserCanceled` propagates unchanged through specific `catch`. |
| `keyExists` does not trigger biometric prompt | Uses `kSecUseAuthenticationUI: kSecUseAuthenticationUISkip` |
| iOS build succeeds | Verify with `fvm flutter build ios --debug --no-codesign` |
| macOS build succeeds | Verify with `cd example && make ci-build-macos` |
| Minimal change footprint | Six files, one new private method, one new switch case, three new enum cases, one new catch branch |
| No protocol changes | `KeychainServiceProtocol` is untouched |
| Consistent error code across platforms | Both Android (Phase 1) and iOS/macOS (Phase 2) emit `"KEY_PERMANENTLY_INVALIDATED"` |

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| `errSecAuthFailed` (-25293) returned for reasons other than key invalidation (e.g., transient Secure Enclave hardware error) | Low -- Apple documents this code specifically for permanent key access failure after biometric change in the SE context | Medium | Acceptable per KISS; password-only teardown is a safe recovery action (removes bio wrap, not vault data) |
| `keyExists` query attribute mismatch with `getPrivateKey` query causes false negatives (always returns `false`) | Low -- plan specifies matching `kSecClass`, `kSecAttrKeyType`, `kSecAttrTokenID`, `kSecAttrApplicationTag` | High | Code review must verify attribute parity with `getPrivateKey`'s query on lines 197-203 of `SecureEnclaveManager.swift` |
| `kSecUseAuthenticationUISkip` behaves differently on iOS vs macOS | Very low -- both share the Security framework; flag is documented consistently | Low | Verified by building for both targets |
| `do/catch` in `SecureEnclaveManager.decrypt()` accidentally catches `authenticationUserCanceled` | Eliminated | High | Uses specific `catch KeychainServiceError.keyPermanentlyInvalidated` -- other `KeychainServiceError` variants propagate through |
| Catch ordering in `BiometricCipherPlugin.decrypt()` shadows new error type | Eliminated | High | `SecureEnclaveManagerError` and `KeychainServiceError` are unrelated enum types; catch order is for clarity, not correctness |

---

## Dependencies

- **Phase 1 (Android):** Complete. Phase 2 follows the same channel code convention (`"KEY_PERMANENTLY_INVALIDATED"`).
- **Phase 3 (Dart plugin + locker library):** Will depend on the channel code emitted by this phase. Until Phase 3, the code falls through to `unknown` in the Dart enum.
- **External:** Apple Security framework (`errSecAuthFailed`, `kSecUseAuthenticationUISkip`) -- available on all supported iOS/macOS versions.
- **No protocol changes:** `KeychainServiceProtocol` is untouched, so mock-based tests in the native layer are unaffected.

---

## Implementation Steps

1. **Edit `KeychainServiceError.swift`:**
   - Add `case keyPermanentlyInvalidated` after `authenticationUserCanceled`
   - Add `"KEY_PERMANENTLY_INVALIDATED"` in `code` switch
   - Add `"Biometric key has been permanently invalidated."` in `errorDescription` switch

2. **Edit `KeychainService.swift`:**
   - In `decryptData(key:algorithm:data:)`, add `case Int(errSecAuthFailed):` in the `switch errorCode` block, between `errSecUserCanceled`/`LAError.userCancel` and `default:`
   - This case throws `KeychainServiceError.keyPermanentlyInvalidated`

3. **Edit `SecureEnclaveManagerError.swift`:**
   - Add `case keyPermanentlyInvalidated` after `keyAlreadyExists`
   - Add `"KEY_PERMANENTLY_INVALIDATED"` in `code` switch
   - Add `"Biometric key has been permanently invalidated."` in `errorDescription` switch

4. **Edit `SecureEnclaveManager.swift`:**
   - Add private `keyExists(tag: Data) -> Bool` method (after `getTagData`)
   - In `decrypt()`, modify the `guard let privateKey` else block to call `keyExists` and conditionally throw `keyPermanentlyInvalidated` vs `failedGetPrivateKey`
   - In `decrypt()`, wrap `keychainService.decryptData()` in `do { ... } catch KeychainServiceError.keyPermanentlyInvalidated { throw SecureEnclaveManagerError.keyPermanentlyInvalidated }`

5. **Edit `SecureEnclavePluginError.swift`:**
   - Add `case keyPermanentlyInvalidated` after `keyDeletionError` (before `unknown`)
   - Add `"KEY_PERMANENTLY_INVALIDATED"` in `code` switch
   - Add `"Biometric key has been permanently invalidated."` in `errorDescription` switch

6. **Edit `BiometricCipherPlugin.swift`:**
   - In `decrypt()`, insert `catch SecureEnclaveManagerError.keyPermanentlyInvalidated { ... }` before the existing `catch let error as KeychainServiceError` block
   - The catch body calls `result(FlutterError(code: "KEY_PERMANENTLY_INVALIDATED", message: "Biometric key has been permanently invalidated", details: nil))`

7. **Verify builds:**
   - iOS: `fvm flutter build ios --debug --no-codesign`
   - macOS: `cd example && make ci-build-macos`

---

## Open Questions

None.
