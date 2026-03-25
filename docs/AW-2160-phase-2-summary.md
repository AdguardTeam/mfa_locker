# AW-2160 Phase 2 Summary — iOS/macOS: Detect Biometric Key Invalidation via Secure Enclave

## What Was Done

Phase 2 is the iOS and macOS native portion of AW-2160. It resolves the same gap as Phase 1 (Android), but for the Apple platform: a permanently invalidated Secure Enclave key was indistinguishable from a generic biometric failure (user cancel, wrong fingerprint, lockout). Six existing Swift files in `packages/biometric_cipher/darwin/Classes/` were modified. No new files were created, no Dart code was changed, and no protocols were modified.

### The Problem

On iOS and macOS, biometric keys are created in the Secure Enclave with the `.biometryCurrentSet` access control flag. When the user adds a new fingerprint, removes biometrics, or makes any biometric enrollment change, the OS permanently revokes access to the key. This invalidation can manifest at two distinct points during a decrypt call:

- **Point A:** `getPrivateKey(tag:)` returns `nil`. This also happens on user cancel and lockout, so nil alone is ambiguous — the code had no way to distinguish "key is gone" from "key is temporarily inaccessible."
- **Point B:** A key reference (`SecKey`) is obtained but the Secure Enclave refuses the actual cryptographic operation, returning `errSecAuthFailed` (-25293) from `SecKeyCreateDecryptedData`. Previously this fell through to the generic `failedToDecryptData` error.

In both cases the Flutter method channel emitted a generic `"DECRYPTION_ERROR"` or `"FAILED_GET_PRIVATE_KEY"` code, giving the Dart layer no signal to trigger the appropriate recovery path (password-only biometric teardown).

### The Fix

#### Point A Detection — `SecureEnclaveManager.decrypt()`

A new private helper `keyExists(tag: Data)` was added to `SecureEnclaveManager`. It queries the keychain with `kSecUseAuthenticationUISkip`, which suppresses any biometric prompt and returns only the existence status of the keychain item. The status interpretation is:

- `errSecSuccess` or `errSecInteractionNotAllowed` → item still present (`true`)
- `errSecItemNotFound` → OS deleted the item after biometric change (`false`)
- Any other status → conservative `true` (only confirmed absence triggers invalidation)

The existing `guard let privateKey = getPrivateKey(tag: privateKeyTag) else { ... }` block in `decrypt()` was updated to call `keyExists` before deciding which error to throw:

```
getPrivateKey returns nil
  keyExists returns false → throw SecureEnclaveManagerError.keyPermanentlyInvalidated
  keyExists returns true  → throw SecureEnclaveManagerError.failedGetPrivateKey (existing behavior)
```

This preserves the existing path for user cancel and lockout exactly as before.

#### Point B Detection — `KeychainService.decryptData()`

A new `case Int(errSecAuthFailed):` branch was inserted in the existing `switch errorCode` block inside `KeychainService.decryptData(key:algorithm:data:)`, between the `errSecUserCanceled`/`LAError.userCancel` case and `default:`. When `CFErrorGetCode(cfError)` equals `errSecAuthFailed`, the method throws `KeychainServiceError.keyPermanentlyInvalidated`. All other failure codes continue to fall through to the existing `default` branch.

#### Point B Re-Throw — `SecureEnclaveManager.decrypt()`

The call to `keychainService.decryptData()` was wrapped in a specific `do/catch KeychainServiceError.keyPermanentlyInvalidated` block that re-throws as `SecureEnclaveManagerError.keyPermanentlyInvalidated`. Only this one case is caught; `KeychainServiceError.authenticationUserCanceled` and all other `KeychainServiceError` variants propagate unchanged to `BiometricCipherPlugin`, where the existing `authenticationUserCanceled` catch branch handles them.

#### Error Enum Updates

Three error enums each received one new `case keyPermanentlyInvalidated` (no associated value), with matching `code` (`"KEY_PERMANENTLY_INVALIDATED"`) and `errorDescription` (`"Biometric key has been permanently invalidated."`):

- `KeychainServiceError` — source of the Point B error
- `SecureEnclaveManagerError` — the convergence point for both paths
- `SecureEnclavePluginError` — added for consistency with the existing error hierarchy; not exercised by the active catch path (by design)

#### Plugin Catch — `BiometricCipherPlugin.decrypt()`

A new catch branch for `SecureEnclaveManagerError.keyPermanentlyInvalidated` was inserted before the existing `catch let error as KeychainServiceError` block. It constructs `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED", message: "Biometric key has been permanently invalidated", details: nil)` directly — not via `getFlutterError` — matching the channel code established by Phase 1 (Android).

---

## Decisions Made

**Why does `keyExists` live on `SecureEnclaveManager` (not on `KeychainService` or `KeychainServiceProtocol`)?**

The `tag` parameter available at the Point A call site (`privateKeyTag`) is already in its prefixed `Data` form (produced by `getTagData()`). Placing `keyExists(tag: Data)` directly on `SecureEnclaveManager` avoids duplicating the prefix logic and requires zero changes to `KeychainServiceProtocol`. This was a resolved design question in the PRD.

**Why does `keyExists` take `Data`, not `String`?**

The call site passes `privateKeyTag`, which is the `Data` value already produced by `getTagData()` with the `AppConstants.privateKeyTag` prefix. Using `Data` directly ensures the `kSecAttrApplicationTag` in the existence query is attribute-compatible with the `kSecAttrApplicationTag` in `getPrivateKey`. A `String` parameter would require duplicating the prefix conversion and risked a mismatch that could cause `keyExists` to always return `false` (false positive invalidation).

**Why is the Point B catch in `SecureEnclaveManager.decrypt()` pattern-specific?**

The `do { ... } catch KeychainServiceError.keyPermanentlyInvalidated` form catches only that one case. A broader `catch let error as KeychainServiceError` would accidentally intercept `authenticationUserCanceled`, preventing it from reaching the plugin's existing dedicated catch branch and breaking the `"AUTHENTICATION_USER_CANCELED"` error flow.

**Why is `SecureEnclavePluginError.keyPermanentlyInvalidated` added if it is not used?**

The plugin catches `SecureEnclaveManagerError.keyPermanentlyInvalidated` and emits `FlutterError` directly, bypassing `getFlutterError(SecureEnclavePluginError...)`. Adding the case to `SecureEnclavePluginError` maintains consistency with the existing error hierarchy and leaves a hook for future use. This is explicitly documented as intentional in the PRD and QA review.

**Why is `errSecAuthFailed` (-25293) treated as a permanent invalidation?**

Apple documents this code specifically for permanent key access failure after biometric enrollment change in the Secure Enclave context. The accepted false-positive risk is low (transient Secure Enclave hardware error), and the recovery action (password-only teardown) removes only the biometric wrap, not any vault data — making it safe even on a spurious trigger.

**Why no Swift unit tests in Phase 2?**

Explicitly deferred by design. `keyExists` cannot easily be unit-tested without a live keychain or a `SecItemCopyMatching` mock. All test coverage for the `"KEY_PERMANENTLY_INVALIDATED"` channel contract — including Points A and B — is deferred to Phase 3, which adds the Dart-side `BiometricCipherExceptionCode.keyPermanentlyInvalidated` mapping and writes Dart unit tests with a mocked method channel.

---

## Error Propagation — Both Paths

```
Point A: getPrivateKey returns nil, keyExists returns false
  → throw SecureEnclaveManagerError.keyPermanentlyInvalidated
  → BiometricCipherPlugin catches SecureEnclaveManagerError.keyPermanentlyInvalidated
  → FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")

Point B: SecKeyCreateDecryptedData fails with errSecAuthFailed (-25293)
  → throw KeychainServiceError.keyPermanentlyInvalidated  (in KeychainService.decryptData)
  → catch KeychainServiceError.keyPermanentlyInvalidated  (in SecureEnclaveManager.decrypt)
  → throw SecureEnclaveManagerError.keyPermanentlyInvalidated
  → BiometricCipherPlugin catches SecureEnclaveManagerError.keyPermanentlyInvalidated
  → FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")
```

Both paths produce an identical `FlutterError` at the channel boundary.

---

## API Contract Change

| Condition | Before Phase 2 | After Phase 2 |
|-----------|----------------|---------------|
| Point A: `getPrivateKey` returns nil, key item gone from keychain | `FlutterError(code: "DECRYPTION_ERROR")` via `failedGetPrivateKey` | `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")` |
| Point B: `SecKeyCreateDecryptedData` fails with `errSecAuthFailed` (-25293) | `FlutterError(code: "DECRYPTION_ERROR")` via `failedToDecryptData` | `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")` |
| Point A: `getPrivateKey` returns nil, key item still present (user cancel / lockout) | `FlutterError(code: "DECRYPTION_ERROR")` via `failedGetPrivateKey` | Unchanged |
| User cancels during `SecKeyCreateDecryptedData` (`errSecUserCanceled`) | `FlutterError(code: "AUTHENTICATION_USER_CANCELED")` | Unchanged |
| Generic decryption failure | `FlutterError(code: "DECRYPTION_ERROR")` | Unchanged |
| Encrypt path | Unchanged | Unchanged |

---

## Files Changed

| File | Change |
|------|--------|
| `packages/biometric_cipher/darwin/Classes/Errors/KeychainServiceError.swift` | Added `case keyPermanentlyInvalidated` with `code` and `errorDescription` |
| `packages/biometric_cipher/darwin/Classes/Services/KeychainService.swift` | Added `case Int(errSecAuthFailed):` branch in `decryptData()` switch block (Point B detection) |
| `packages/biometric_cipher/darwin/Classes/Errors/SecureEnclaveManagerError.swift` | Added `case keyPermanentlyInvalidated` with `code` and `errorDescription` |
| `packages/biometric_cipher/darwin/Classes/Managers/SecureEnclaveManager.swift` | Added private `keyExists(tag: Data) -> Bool` helper; modified `decrypt()` guard block (Point A detection); wrapped `decryptData()` call in specific `catch KeychainServiceError.keyPermanentlyInvalidated` (Point B re-throw) |
| `packages/biometric_cipher/darwin/Classes/Errors/SecureEnclavePluginError.swift` | Added `case keyPermanentlyInvalidated` with `code` and `errorDescription` |
| `packages/biometric_cipher/darwin/Classes/BiometricCipherPlugin.swift` | Added `catch SecureEnclaveManagerError.keyPermanentlyInvalidated` branch before the `catch let error as KeychainServiceError` block in `decrypt()` |

---

## QA Status

The QA review (`docs/qa/AW-2160-phase-2.md`) confirmed all six files match the plan exactly. Key verifications:

- `keyExists(tag: Data)` uses `kSecUseAuthenticationUISkip` (no biometric prompt) and mirrors the query attributes of `getPrivateKey(tag: Data)` for attribute-compatible matching.
- `getPrivateKey` is called inside a plain `guard` nil-check, not inside a `do { try }` block (it returns `SecKey?` and does not throw).
- The `do/catch KeychainServiceError.keyPermanentlyInvalidated` in `SecureEnclaveManager.decrypt()` is pattern-specific — `authenticationUserCanceled` propagates unchanged.
- Catch ordering in `BiometricCipherPlugin.decrypt()` is correct: `SecureEnclaveManagerError.keyPermanentlyInvalidated` is caught before the generic `KeychainServiceError` sweep.
- All three error enums have consistent `code` and `errorDescription` values.

Two open items before Phase 2 is fully releasable:

1. **iOS and macOS builds have not been confirmed.** `fvm flutter build ios --debug --no-codesign` and `cd example && make ci-build-macos` must complete without errors. These are the primary acceptance criteria in the PRD.
2. **No Swift unit tests cover the new code.** This is accepted by design — deferred to Phase 3, where Dart unit tests with a mocked method channel will exercise the full `"KEY_PERMANENTLY_INVALIDATED"` channel contract for both platforms.

Additionally, the Technical Details section (lines 80–145) in `docs/phase/AW-2160/phase-2.md` describes a stale architecture (Task 8 in that document's Code Review Fixes list) where `keyExists` and Point A detection lived in `KeychainService`. The actual implementation follows the PRD and plan: both live in `SecureEnclaveManager`. That tasklist document should be corrected before Phase 3 begins to avoid confusing the Phase 3 implementer.

---

## Phase Dependencies

- **Depends on:** Phase 1 (Android `KeyPermanentlyInvalidatedException` detection) — complete.
- **Unblocks:** Phase 3 (Dart plugin enum + locker library) — Phase 3 maps the `"KEY_PERMANENTLY_INVALIDATED"` channel code (now emitted by both Android and iOS/macOS) to `BiometricCipherExceptionCode.keyPermanentlyInvalidated`, adds `BiometricExceptionType.keyInvalidated` to the locker layer, and delivers the Dart-side unit tests for the full contract.

Until Phase 3 ships, the Dart plugin's `BiometricCipherExceptionCode.fromString` maps `"KEY_PERMANENTLY_INVALIDATED"` to `unknown`. No crash, no incorrect recovery — simply an unrouted code.
