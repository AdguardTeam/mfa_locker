# QA Plan: AW-2160 Phase 2 — iOS/macOS: Detect Biometric Key Invalidation via Secure Enclave

Status: REVIEWED
Date: 2026-03-16

---

## Phase Scope

Phase 2 is limited to the **iOS/macOS native layer** of the `biometric_cipher` plugin. It introduces detection of a permanently invalidated Secure Enclave key so that the Flutter method channel emits a distinct error code `"KEY_PERMANENTLY_INVALIDATED"` instead of the previous generic `"DECRYPTION_ERROR"`.

Six existing Swift files are in scope (all under `packages/biometric_cipher/darwin/Classes/`):

- `Errors/KeychainServiceError.swift` — new `.keyPermanentlyInvalidated` enum case
- `Services/KeychainService.swift` — new `errSecAuthFailed` case in `decryptData()` switch (Point B)
- `Errors/SecureEnclaveManagerError.swift` — new `.keyPermanentlyInvalidated` enum case
- `Managers/SecureEnclaveManager.swift` — new `keyExists(tag:)` private helper + Point A detection + Point B re-throw
- `Errors/SecureEnclavePluginError.swift` — new `.keyPermanentlyInvalidated` enum case
- `BiometricCipherPlugin.swift` — new catch branch for `SecureEnclaveManagerError.keyPermanentlyInvalidated`

Two invalidation detection points are implemented:

- **Point A** — `getPrivateKey(tag:)` returns `nil` and `keyExists(tag:)` confirms the keychain item is gone (detected in `SecureEnclaveManager.decrypt()`).
- **Point B** — `SecKeyCreateDecryptedData` fails with `errSecAuthFailed` (-25293) (detected in `KeychainService.decryptData()`), re-thrown by `SecureEnclaveManager.decrypt()`.

Both paths converge at `SecureEnclaveManagerError.keyPermanentlyInvalidated` before reaching `BiometricCipherPlugin`, which emits `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")`.

Out of scope for this phase: Dart plugin enum mapping (`BiometricCipherExceptionCode`), locker library changes, app-layer wiring, and Swift unit tests (all deferred to Phase 3).

---

## Implementation Status (observed)

All six files were read directly from the repository.

### `KeychainServiceError.swift`

- `case keyPermanentlyInvalidated` is present after `authenticationUserCanceled`.
- `code` switch: `case .keyPermanentlyInvalidated: return "KEY_PERMANENTLY_INVALIDATED"` — correct.
- `errorDescription` switch: `case .keyPermanentlyInvalidated: return "Biometric key has been permanently invalidated."` — correct.
- The `code` and `errorDescription` switch blocks are exhaustive (no `default` arm); all cases are listed.

### `KeychainService.swift` — Point B detection

- `decryptData(key:algorithm:data:)` retains the correct protocol signature from `KeychainServiceProtocol` — no `tag` parameter was added.
- In the `switch errorCode` block the order is: `errSecUserCanceled`/`LAError.userCancel.rawValue` → `errSecAuthFailed` → `default`. This matches the plan.
- `case Int(errSecAuthFailed): throw KeychainServiceError.keyPermanentlyInvalidated` is present.
- `CFErrorGetCode(cfError)` is used correctly to extract the numeric code from `CFError` (no direct `OSStatus` cast).
- The `default` arm still throws `KeychainServiceError.failedToDecryptData(cfError)`, preserving all other failure paths.
- No `keyExists` helper was added to `KeychainService` — per the plan, this helper lives on `SecureEnclaveManager`. Correct.

### `SecureEnclaveManagerError.swift`

- `case keyPermanentlyInvalidated` is present after `keyAlreadyExists`, before the `code` property. Placement matches plan.
- `code` switch: `"KEY_PERMANENTLY_INVALIDATED"` — correct.
- `errorDescription` switch: `"Biometric key has been permanently invalidated."` — correct.
- Switch blocks exhaustive (no `default` arm).

### `SecureEnclaveManager.swift` — Point A detection + Point B re-throw + `keyExists` helper

**Point A — guard block in `decrypt()`:**

```swift
guard let privateKey = getPrivateKey(tag: privateKeyTag) else {
    if !keyExists(tag: privateKeyTag) {
        throw SecureEnclaveManagerError.keyPermanentlyInvalidated
    }
    throw SecureEnclaveManagerError.failedGetPrivateKey
}
```

This is implemented exactly as specified. The `failedGetPrivateKey` path is preserved for the non-invalidation case (user cancel / lockout with item still present).

**Point B — do/catch wrapping `keychainService.decryptData()` in `decrypt()`:**

```swift
do {
    decryptedData = try keychainService.decryptData(key: privateKey,
                                                    algorithm: algorithm,
                                                    data: encryptedData)
} catch KeychainServiceError.keyPermanentlyInvalidated {
    throw SecureEnclaveManagerError.keyPermanentlyInvalidated
}
```

Pattern-specific catch (not `catch let error as KeychainServiceError`) — `authenticationUserCanceled` and other `KeychainServiceError` variants propagate unchanged to the plugin. Correct.

**`keyExists(tag: Data)` private helper:**

- Parameter type is `Data` (not `String`) — the call site passes `privateKeyTag` which is already the prefixed `Data` form from `getTagData()`. This avoids duplicating the prefix logic. Correct.
- Query attributes: `kSecClass`, `kSecAttrKeyType`, `kSecAttrTokenID`, `kSecAttrApplicationTag`, `kSecUseAuthenticationUISkip`, `kSecReturnAttributes: true`. This mirrors the key-relevant attributes of `getPrivateKey(tag:)` without `kSecReturnRef` (existence check only). Correct.
- Return logic: `errSecSuccess || errSecInteractionNotAllowed` → `true`; `errSecItemNotFound` → `false`; any other status → `true` (conservative — only confirmed absence triggers invalidation). Correct.
- `kSecUseAuthenticationUI: kSecUseAuthenticationUISkip` suppresses the biometric prompt. Correct.

**Critical architectural detail confirmed:** `getPrivateKey(tag:)` returns `SecKey?` and is not called inside a `do { try }` block. The guard statement `guard let privateKey = getPrivateKey(tag: privateKeyTag) else { ... }` is a plain nil-check, not a try/catch. Correct.

### `SecureEnclavePluginError.swift`

- `case keyPermanentlyInvalidated` is present after `keyDeletionError`, before `unknown`. Placement matches plan.
- `code` switch: `"KEY_PERMANENTLY_INVALIDATED"` — correct.
- `errorDescription` switch: `"Biometric key has been permanently invalidated."` — correct.

### `BiometricCipherPlugin.swift` — new catch branch

The `decrypt()` method catch structure:

```swift
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

- The `SecureEnclaveManagerError.keyPermanentlyInvalidated` catch appears before the `KeychainServiceError` catch — ordering is correct.
- `FlutterError` is constructed directly (not via `getFlutterError`) with the hardcoded string `"KEY_PERMANENTLY_INVALIDATED"`. This matches the Android Phase 1 channel code and the Phase 3 expectation.
- `details: nil` is consistent with the plan.
- The existing `authenticationUserCanceled` path in the `KeychainServiceError` block is unchanged.

---

## Positive Scenarios

### PS-1: Point A — Biometric enrollment change, OS deletes key item

**Setup:** User had biometric unlock enabled (Secure Enclave key present). User adds or removes a fingerprint in device Settings. OS deletes the keychain item. App calls `decrypt` via method channel.

**Expected flow:**
1. `BiometricCipherPlugin.decrypt()` calls `secureEnclaveManager.decrypt(data, tag: tag)`.
2. `getPrivateKey(tag: privateKeyTag)` → `SecItemCopyMatching` returns no result (policy no longer satisfied) → `nil`.
3. `keyExists(tag: privateKeyTag)` → `SecItemCopyMatching` with `kSecUseAuthenticationUISkip` returns `errSecItemNotFound` → `false`.
4. `SecureEnclaveManager.decrypt()` throws `SecureEnclaveManagerError.keyPermanentlyInvalidated`.
5. `BiometricCipherPlugin.decrypt()` catches `SecureEnclaveManagerError.keyPermanentlyInvalidated`.
6. Method channel delivers `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED", message: "Biometric key has been permanently invalidated", details: nil)`.
7. Dart layer receives `PlatformException(code: "KEY_PERMANENTLY_INVALIDATED")`.

**No biometric prompt appears** at any step because `keyExists` uses `kSecUseAuthenticationUISkip`.

### PS-2: Point B — Key reference obtained but Secure Enclave refuses operation (`errSecAuthFailed`)

**Setup:** Biometric enrollment changed but OS did not delete the keychain item (key exists but is hardware-locked). App calls `decrypt` via method channel.

**Expected flow:**
1. `getPrivateKey(tag: privateKeyTag)` returns a non-nil `SecKey` reference.
2. `keychainService.decryptData(key:algorithm:data:)` is called.
3. `SecKeyCreateDecryptedData` fails; `CFErrorGetCode(cfError) == errSecAuthFailed` (-25293).
4. `KeychainService.decryptData()` throws `KeychainServiceError.keyPermanentlyInvalidated`.
5. `SecureEnclaveManager.decrypt()` catches `KeychainServiceError.keyPermanentlyInvalidated`, re-throws `SecureEnclaveManagerError.keyPermanentlyInvalidated`.
6. `BiometricCipherPlugin.decrypt()` catches `SecureEnclaveManagerError.keyPermanentlyInvalidated`.
7. Method channel delivers `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")`.

Output is identical to PS-1 at the channel boundary.

### PS-3: Normal successful decrypt

**Setup:** Key is valid, user authenticates successfully.

**Expected flow:**
1. `getPrivateKey(tag:)` returns a non-nil `SecKey`.
2. `keychainService.decryptData()` succeeds and returns `Data`.
3. Decrypted string is returned to the caller via `result(decryptedData)`.
4. No error case is triggered. `keyExists` is never called.

### PS-4: Error code strings match across all three error enums

**Setup:** Code review verification.

**Expected:** All three enums (`KeychainServiceError`, `SecureEnclaveManagerError`, `SecureEnclavePluginError`) return `"KEY_PERMANENTLY_INVALIDATED"` from their `code` property. All three return `"Biometric key has been permanently invalidated."` from `errorDescription`. Verified in source — all consistent.

---

## Negative and Edge Cases

### NC-1: Point A — key still present (user cancel), `keyExists` returns `true`

**Setup:** User cancels biometric prompt. `getPrivateKey(tag:)` returns `nil` because the OS withheld the key during auth failure, but the keychain item still exists.

**Expected flow:**
1. `getPrivateKey(tag:)` → `nil`.
2. `keyExists(tag: privateKeyTag)` → `SecItemCopyMatching` returns `errSecInteractionNotAllowed` (item present, auth UI suppressed) → `true`.
3. `SecureEnclaveManager.decrypt()` does NOT throw `keyPermanentlyInvalidated`; falls through to `throw SecureEnclaveManagerError.failedGetPrivateKey`.
4. `BiometricCipherPlugin.decrypt()` hits the generic `catch` block → `SecureEnclavePluginError.decryptionError` → `FlutterError(code: "DECRYPTION_ERROR")`.
5. Existing behavior preserved — no regression.

### NC-2: Point A — key still present (device lockout), `keyExists` returns `true`

**Setup:** Device is locked out from biometrics after too many failed attempts. `getPrivateKey(tag:)` → `nil`.

**Expected:** Same as NC-1. `keyExists` returns `true`; `failedGetPrivateKey` is thrown; existing `"DECRYPTION_ERROR"` code is emitted. No regression.

### NC-3: User cancels during `SecKeyCreateDecryptedData` (`errSecUserCanceled`)

**Setup:** User cancels mid-operation after the key reference is obtained.

**Expected flow:**
1. `getPrivateKey(tag:)` returns a non-nil `SecKey`.
2. `SecKeyCreateDecryptedData` fails with `errSecUserCanceled` or `LAError.userCancel.rawValue`.
3. Existing `case Int(errSecUserCanceled), Int(LAError.userCancel.rawValue):` branch throws `KeychainServiceError.authenticationUserCanceled`.
4. This error is NOT caught by `catch KeychainServiceError.keyPermanentlyInvalidated` in `SecureEnclaveManager.decrypt()` — it propagates unchanged.
5. `BiometricCipherPlugin.decrypt()` catches it in `catch let error as KeychainServiceError` → `authenticationUserCanceled` branch → `FlutterError(code: "AUTHENTICATION_USER_CANCELED")`.
6. Existing behavior preserved — no regression.

### NC-4: Generic `SecKeyCreateDecryptedData` failure (non-auth error)

**Setup:** An unexpected decryption failure that is neither `errSecAuthFailed` nor `errSecUserCanceled` (e.g., invalid data format).

**Expected flow:**
1. `switch errorCode` falls to `default` → `throw KeychainServiceError.failedToDecryptData(cfError)`.
2. This is NOT caught by `catch KeychainServiceError.keyPermanentlyInvalidated` in `SecureEnclaveManager.decrypt()` — propagates to plugin.
3. `BiometricCipherPlugin.decrypt()` catches it in `catch let error as KeychainServiceError` → `default` branch → `SecureEnclavePluginError.decryptionError` → `FlutterError(code: "DECRYPTION_ERROR")`.
4. Existing behavior preserved.

### NC-5: `keyExists` called with prefixed `Data` tag (not raw `String`)

**Setup:** Code review verification of `keyExists(tag: Data)` call site.

**Expected:** `keyExists` is called with `privateKeyTag` (a `Data` value produced by `getTagData(tag:)` with the `AppConstants.privateKeyTag` prefix). The query attribute `kSecAttrApplicationTag: tag` uses the same prefixed form that `getPrivateKey(tag:)` uses. The two queries are attribute-compatible — no false positives or false negatives from tag mismatch.

**Verified in source:** `keyExists(tag: Data)` takes `Data` and uses it directly as `kSecAttrApplicationTag`. `getPrivateKey(tag: Data)` uses the same `kSecAttrApplicationTag: tag`. The call site `keyExists(tag: privateKeyTag)` passes the same `privateKeyTag` variable. Correct.

### NC-6: `keyExists` with an empty or malformed tag

**Setup:** `tag` is empty or non-UTF-8 encodable before reaching `getTagData()`.

**Expected:** `getTagData(tag:)` would throw `SecureEnclaveManagerError.invalidTag` before `getPrivateKey` or `keyExists` are ever called. `keyExists` is never reached with a bad tag. The guard on `tag.isEmpty` in `getTagData()` prevents this path.

### NC-7: `keyExists` returns `false` for an unexpected reason (not biometric invalidation)

**Risk scenario:** `SecItemCopyMatching` returns a status other than `errSecSuccess`, `errSecInteractionNotAllowed`, or `errSecItemNotFound` (e.g., `errSecNotAvailable` during keychain service disruption).

**Expected:** The conservative `else` branch in `keyExists` returns `true` (item not confirmed absent). `SecureEnclaveManager.decrypt()` throws `failedGetPrivateKey` rather than `keyPermanentlyInvalidated`. This produces `"DECRYPTION_ERROR"` instead of a false `"KEY_PERMANENTLY_INVALIDATED"`. Correct fail-safe behavior.

### NC-8: `errSecAuthFailed` for non-invalidation reason (false positive, Point B)

**Risk scenario:** Apple's Secure Enclave returns `errSecAuthFailed` (-25293) for a transient hardware error unrelated to biometric enrollment change.

**Expected:** Phase 2 treats this as `keyPermanentlyInvalidated` (emits `"KEY_PERMANENTLY_INVALIDATED"`). Per the PRD, this is an accepted false positive: password-only teardown removes only the biometric wrap (not vault data), making it a safe recovery action. The PRD documents this as acceptable per KISS.

### NC-9: Encrypt path is unaffected

**Setup:** App calls the `encrypt` method channel operation.

**Expected:** The `encrypt` path uses the public key and is not subject to `.biometryCurrentSet` access control for the encryption operation itself. Neither `keyExists` nor the new `errSecAuthFailed` case is in the encrypt path. `"KEY_PERMANENTLY_INVALIDATED"` is never emitted during encryption. No change.

### NC-10: `"KEY_PERMANENTLY_INVALIDATED"` channel code reaching Dart before Phase 3

**Expected (accepted interim behavior):** Until Phase 3 maps `"KEY_PERMANENTLY_INVALIDATED"` in `BiometricCipherExceptionCode.fromString`, the code falls through to `unknown` in the Dart enum. This is documented in the plan as acceptable. No crash; no incorrect recovery triggered.

### NC-11: Catch ordering in `BiometricCipherPlugin.decrypt()` — shadowing check

**Setup:** Swift evaluates catch clauses top-to-bottom.

**Expected:** `SecureEnclaveManagerError` and `KeychainServiceError` are unrelated enum types. The `catch SecureEnclaveManagerError.keyPermanentlyInvalidated` branch catches only that specific case of that specific type. It does not shadow the `catch let error as KeychainServiceError` branch. The existing `authenticationUserCanceled` path in the `KeychainServiceError` block remains reachable.

**Verified in source:** Both `catch SecureEnclaveManagerError.keyPermanentlyInvalidated` and `catch let error as KeychainServiceError` are present and correctly ordered. No shadowing.

### NC-12: `SecureEnclavePluginError.keyPermanentlyInvalidated` is unused by the plugin (by design)

**Setup:** The plugin catches `SecureEnclaveManagerError.keyPermanentlyInvalidated` and constructs `FlutterError` directly — it does not call `getFlutterError(SecureEnclavePluginError.keyPermanentlyInvalidated)`.

**Expected:** `SecureEnclavePluginError.keyPermanentlyInvalidated` is present for consistency and future use but is not exercised by current plugin code. This is an intentional design decision per the plan. The case must exist to keep the enum consistent, but its absence from the active catch path is not a bug.

---

## Automated Tests Coverage

### Existing Swift tests — non-regression

There are no Swift unit tests added in Phase 2, and the existing test suite does not exercise the `decrypt()` method channel path at the unit level. The existing tests cover lower-level components that are unaffected by Phase 2:

| Component | Relevance |
|-----------|-----------|
| Any existing mock-based Swift tests for `SecureEnclaveManager` | Point A and Point B changes are in `decrypt()`. Protocol (`SecureEnclaveManagerProtocol`) and public signature are unchanged. Existing mocks should compile without modification. |
| `KeychainServiceProtocol` | Not modified. Protocol-conforming mocks are unaffected. |

### Missing automated tests (deferred by design)

- **No Swift unit test covers `keyExists()` behavior.** The helper cannot easily be unit-tested without a live keychain or a `SecItemCopyMatching` mock. Deferred to Phase 3.
- **No Swift unit test verifies Point A detection** (nil key + `keyExists` returning `false` → `keyPermanentlyInvalidated`). Deferred to Phase 3 via Dart mocked method channel tests.
- **No Swift unit test verifies Point B detection** (`errSecAuthFailed` → `keyPermanentlyInvalidated`). Deferred to Phase 3.
- **No automated test exercises the `BiometricCipherPlugin.decrypt()` catch ordering.** Deferred to Phase 3.

---

## Manual Checks Needed

### MC-1: iOS debug build

**Check:** Run `fvm flutter build ios --debug --no-codesign` from the repository root.

**Pass criterion:** Build completes without Swift compilation errors. Implicit validation of enum exhaustiveness, type-checking of the `keyExists` parameter (`Data`), and `kSecUseAuthenticationUISkip` availability.

**Status:** Not yet executed as part of this QA review. This is the primary acceptance criterion per the PRD. Must be confirmed before release.

### MC-2: macOS debug build

**Check:** Run `cd example && make ci-build-macos` from the repository root.

**Pass criterion:** Build completes without errors. Validates that `kSecUseAuthenticationUI` / `kSecUseAuthenticationUISkip` behave consistently on macOS (where both are available via the same Security framework headers).

**Status:** Not yet executed. Must be confirmed before release.

### MC-3: Verify `keyExists` does not trigger a biometric prompt (Point A, non-invalidation path)

**Check:** On an iOS/macOS device with biometrics enrolled and a valid Secure Enclave key, cancel the biometric prompt during a decrypt operation. Observe whether a second biometric prompt appears immediately after the cancel.

**Pass criterion:** No second prompt appears. The `keyExists(tag:)` call with `kSecUseAuthenticationUISkip` is silent.

**Note:** This requires a real device or a simulator with biometric simulation support. Recommended to verify manually before Phase 3 automated test work begins.

### MC-4: Verify `"KEY_PERMANENTLY_INVALIDATED"` channel code — Point A (key deleted)

**Check:** On an iOS/macOS device:
1. Create a biometric wrap (encrypt using bio key).
2. Add or remove a fingerprint/face in device Settings, which causes the OS to delete the Secure Enclave key item.
3. Trigger a decrypt operation from the app.
4. Observe the method channel error code in debug logs or a temporary diagnostic.

**Pass criterion:** Debug output or catch handler receives `PlatformException` with `code == "KEY_PERMANENTLY_INVALIDATED"`. The old generic `"DECRYPTION_ERROR"` is absent.

**Status:** Not yet executed. Recommended before Phase 3.

### MC-5: Verify `"AUTHENTICATION_USER_CANCELED"` still works after Phase 2

**Check:** On the same device, cancel a biometric decrypt prompt without changing enrollment. Observe the channel error code.

**Pass criterion:** `"AUTHENTICATION_USER_CANCELED"` is received, not `"KEY_PERMANENTLY_INVALIDATED"` or `"DECRYPTION_ERROR"`. Confirms the `keyExists` → `true` branch correctly falls through to `failedGetPrivateKey`.

### MC-6: Verify encrypt path is unaffected

**Check:** Perform a normal encrypt operation on a device where biometrics have been changed (key invalidated).

**Pass criterion:** The encrypt operation proceeds normally (uses public key, not subject to `.biometryCurrentSet` guard). No `"KEY_PERMANENTLY_INVALIDATED"` error from the encrypt path.

---

## Risk Zone

| Risk | Severity | Status |
|------|----------|--------|
| iOS and macOS builds not verified in this QA pass | High | Must be closed before release. Build verification is the primary acceptance criterion in both the PRD and plan. |
| No Swift unit tests for `keyExists()`, Point A, or Point B detection | Medium | Accepted by design — deferred to Phase 3. Gap must be closed in Phase 3; not optional. |
| `keyExists` query attribute parity with `getPrivateKey` | Medium | Verified by code review: both use `kSecClass`, `kSecAttrKeyType`, `kSecAttrTokenID`, `kSecAttrApplicationTag` with the same prefixed `Data` tag. Risk is mitigated. |
| `errSecAuthFailed` (-25293) emitted for non-invalidation reason (false positive Point B) | Low-Medium | Accepted per KISS per PRD: password-only teardown is a safe recovery action (removes bio wrap, not vault data). Documented. |
| `keyExists` returning unexpected status (not success/interactionNotAllowed/notFound) | Low | Conservative `true` return is the fallback. Results in `failedGetPrivateKey` and `"DECRYPTION_ERROR"` — no false invalidation. Mitigated. |
| `SecureEnclavePluginError.keyPermanentlyInvalidated` not exercised by current plugin code | Low | By design (consistency case). Not a runtime risk. Documented. |
| Phase-2.md technical details section (lines 80–145) describes a stale architecture | Low | The phase tasklist document (`docs/phase/AW-2160/phase-2.md`) contains a "Code Review Fixes" section (Task 8) noting that the Technical Details code snippets describe an outdated architecture where `keyExists` and Point A detection lived in `KeychainService`. The actual implementation follows the PRD/plan (both on `SecureEnclaveManager`). The tasklist doc needs to be updated, but this does not affect the implementation correctness. |
| Dart layer receives `"KEY_PERMANENTLY_INVALIDATED"` before Phase 3 ships | Low | Falls through to `unknown` in Dart enum. No crash. Documented interim state. |

---

## Final Verdict

**With reservations.**

The implementation is structurally correct and complete across all six files:

- All three error enums have `keyPermanentlyInvalidated` with matching `code` (`"KEY_PERMANENTLY_INVALIDATED"`) and `errorDescription` strings.
- Point A detection in `SecureEnclaveManager.decrypt()` is correctly implemented: nil-key guard uses `keyExists(tag:)` before deciding between `keyPermanentlyInvalidated` and `failedGetPrivateKey`.
- `keyExists(tag: Data)` uses `kSecUseAuthenticationUISkip`, mirrors `getPrivateKey`'s query attributes, and applies the conservative `true` fallback for unexpected statuses.
- Point B detection in `KeychainService.decryptData()` correctly uses `CFErrorGetCode(cfError)` and inserts `errSecAuthFailed` between the `errSecUserCanceled` case and `default`.
- The `do/catch KeychainServiceError.keyPermanentlyInvalidated` in `SecureEnclaveManager.decrypt()` is pattern-specific — `authenticationUserCanceled` and other `KeychainServiceError` variants propagate unchanged.
- `BiometricCipherPlugin.decrypt()` catch ordering is correct: `SecureEnclaveManagerError.keyPermanentlyInvalidated` is caught before the generic `KeychainServiceError` sweep.
- The `encrypt` path is unmodified.
- `KeychainServiceProtocol` is unmodified.
- `getPrivateKey` is not wrapped in a `do { try }` block (it returns `SecKey?`, not throws).

The reservations are:

1. **iOS and macOS builds have not been executed** as part of this QA pass. Both builds are the primary acceptance criteria in the PRD and must be confirmed green before the phase is considered released.
2. **No Swift unit tests cover any of the new code.** This is accepted by design (deferred to Phase 3), but Phase 3 must close this gap — it is not optional.
3. **The Technical Details section of `docs/phase/AW-2160/phase-2.md`** (Task 8 in the Code Review Fixes list) describes a stale architecture. This is a documentation inconsistency that should be corrected before Phase 3 begins to avoid confusion for the Phase 3 implementer.

Once the iOS and macOS builds are confirmed green, Phase 2 is releasable and Phase 3 can proceed with the method channel contract this phase establishes.
