# Phase 10: iOS/macOS — `isKeyValid(tag)` Silent Probe

**Goal:** Expose the existing `keyExists(tag:)` check (which uses `kSecUseAuthenticationUISkip` — no biometric prompt) as a public `isKeyValid` method through the plugin channel.

## Context

### Feature Motivation

Phases 1–8 implement **reactive** detection: `keyInvalidated` is discovered only when the user triggers a biometric operation. This causes the lock screen to briefly show the biometric button before hiding it.

Iterations 9–14 add **proactive** detection: `determineBiometricState()` checks key validity at init time without triggering any biometric prompt. The lock screen can immediately hide the biometric button when the key is invalidated — no button flash.

This iteration is the iOS/macOS half of the platform method (Android was Phase 9).

### Why iOS/macOS Can Do This Silently

On iOS/macOS, `SecItemCopyMatching` with `kSecUseAuthenticationUISkip` suppresses all authentication UI. The existing `keyExists(tag:)` method in `KeychainService` already uses this flag. It simply queries whether the key item exists in the keychain — no biometric prompt, no user interaction.

- `kSecUseAuthenticationUISkip` tells the Security framework to skip the authentication UI entirely
- If the OS deleted the key after a biometric enrollment change, `SecItemCopyMatching` returns `errSecItemNotFound` → `keyExists` returns `false`
- If the key is still present (valid enrollment), returns `true`

### iOS/macOS Method Channel Path (New)

```
keyExists(tag:)  [KeychainService — already implemented in Phase 2]
  → isKeyValid(tag:)  [SecureEnclaveManager — new: delegate]
  → "isKeyValid" handler  [BiometricCipherPlugin — new: channel handler]
  → Flutter method channel → Dart
```

### How isKeyValid Differs from decrypt

The existing `decrypt` path involves `SecureEnclaveManager.decrypt()` which triggers a biometric prompt. The new `isKeyValid` path:
- Only calls `keyExists(tag:)` — a `SecItemCopyMatching` query with `kSecUseAuthenticationUISkip`
- Never triggers any authentication prompt or UI
- Returns a `Bool` result immediately

### Project Structure — Files Changed

```
packages/biometric_cipher/darwin/Classes/
├── Services/
│   └── KeychainService.swift         # change keyExists visibility: private → internal
├── Managers/
│   └── SecureEnclaveManager.swift    # + isKeyValid(tag:) method
└── BiometricCipherPlugin.swift       # + "isKeyValid" channel handler
```

No new files. All changes are additions/modifications to existing files.

## Tasks

- [ ] **10.1** Change `keyExists(tag:)` visibility from `private` to `internal` in `KeychainService`
  - File: `packages/biometric_cipher/darwin/Classes/Services/KeychainService.swift`
  - Change `private func keyExists(tag: String) -> Bool` to `func keyExists(tag: String) -> Bool`
  - Implementation unchanged — still uses `kSecUseAuthenticationUISkip`

- [ ] **10.2** Add `isKeyValid(tag:)` to `SecureEnclaveManager`
  - File: `packages/biometric_cipher/darwin/Classes/Managers/SecureEnclaveManager.swift`
  - Delegate: `func isKeyValid(tag: String) -> Bool { keychainService.keyExists(tag: tag) }`

- [ ] **10.3** Add `"isKeyValid"` method channel handler to `BiometricCipherPlugin`
  - File: `packages/biometric_cipher/darwin/Classes/BiometricCipherPlugin.swift`
  - Parse `tag` from args (error if missing)
  - Call `secureEnclaveManager.isKeyValid(tag:)` → `result(Bool)`

## Acceptance Criteria

**Test:** Build iOS (`fvm flutter build ios --debug --no-codesign`) — build succeeds with no compilation errors.

- `isKeyValid` is callable from the Flutter method channel with a `tag` string argument
- Returns `false` for a permanently invalidated / deleted key without showing any biometric prompt
- Returns `true` for a valid key without showing any biometric prompt
- Missing `tag` argument returns a channel error (not a crash)

## Dependencies

- Phase 9 complete (Android `isKeyValid` is done — same method name must match)
- `keyExists(tag:)` already implemented in `KeychainService` (Phase 2, task 2.2) — only visibility change needed
- Method name `"isKeyValid"` must match Android's channel method name and the Dart-side call in Phase 11

## Technical Details

### Task 10.1 — `KeychainService.keyExists` visibility change

Change the access modifier from `private` to `internal` (default in Swift — omit the keyword):

```swift
/// Returns `true` if a Secure Enclave key item with the given tag exists in the keychain,
/// regardless of whether the caller can authenticate to use it.
///
/// Uses `kSecUseAuthenticationUISkip` to suppress any biometric prompt.
func keyExists(tag: String) -> Bool {  // was: private func
    // ... implementation unchanged from Phase 2 ...
}
```

No logic change — this purely makes the method accessible to `SecureEnclaveManager`.

### Task 10.2 — `SecureEnclaveManager.isKeyValid`

```swift
func isKeyValid(tag: String) -> Bool {
    return keychainService.keyExists(tag: tag)
}
```

Simple delegation. Same pattern as existing methods that delegate to `keychainService`.

### Task 10.3 — Channel handler in `BiometricCipherPlugin`

```swift
case "isKeyValid":
    guard let tag = args["tag"] as? String else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Tag is required", details: nil))
        return
    }
    result(secureEnclaveManager.isKeyValid(tag: tag))
```

Add this `case` alongside existing `"encrypt"`, `"decrypt"`, `"deleteKey"`, etc. in the method channel switch.

## Implementation Notes

- Tasks 10.1 → 10.2 → 10.3 must be done in order (each depends on the previous).
- Do not add logging — the operation is a silent probe with no side effects.
- Do not change the `keyExists` implementation — only its visibility. The `kSecUseAuthenticationUISkip` behaviour is already correct from Phase 2.
- The method name `"isKeyValid"` must be identical to the Android handler name from Phase 9 — both are called from the same Dart-side channel invocation in Phase 11.
