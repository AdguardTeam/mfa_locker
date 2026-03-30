# Phase 12: Dart Plugin — `BiometricCipher.isKeyValid(tag)`

**Goal:** Expose the native key validity check through the Dart plugin API, bridging the three platform implementations (Android, iOS/macOS, Windows) to a single Dart method on `BiometricCipher`.

**Ref:** `docs/idea-2160.md` Section G3

## Context

### Feature Motivation

Phases 9–11 added native `isKeyValid` method channel handlers on all three platforms:
- **Phase 9 (Android):** `Cipher.init()` probe — throws `KeyPermanentlyInvalidatedException` for invalidated keys → returns `false`
- **Phase 10 (iOS/macOS):** `keyExists()` with `kSecUseAuthenticationUISkip` — no auth prompt → returns `false` if key is gone
- **Phase 11 (Windows):** `KeyCredentialManager::OpenAsync()` status check — no signing operation → returns `false` if credential not found

All three platforms use the same method channel name `"isKeyValid"` and the same argument key `"tag"`. This phase wires the Dart side: the platform interface gets the abstract method, and `BiometricCipher` gets the public API with validation.

### Why This Phase Is Needed

Without this phase, the native `isKeyValid` handlers are unreachable from Dart — there is no method channel call being made on the Dart side. This is the glue layer that connects the three native implementations to the Dart consumer (Phase 13).

### Dart Plugin Layer Structure

```
BiometricCipher.isKeyValid(tag)        ← public API (this phase)
  │ validates non-empty tag
  └── _instance.isKeyValid(tag: tag)   ← platform interface call
        │
        └── MethodChannel.invokeMethod('isKeyValid', {'tag': tag})
              │
              ├── Android: Cipher.init() probe → bool
              ├── iOS/macOS: keyExists() → bool
              └── Windows: OpenAsync() status → bool
```

### Files Changed

```
packages/biometric_cipher/lib/
├── biometric_cipher_platform_interface.dart   # + isKeyValid(tag) abstract method
└── biometric_cipher.dart                      # + isKeyValid(tag) public method
```

No native files. No new files. All changes are additions to existing Dart files.

## Tasks

- [ ] **12.1** Add `isKeyValid` to platform interface
  - File: `packages/biometric_cipher/lib/biometric_cipher_platform_interface.dart`
  - Add `Future<bool> isKeyValid({required String tag})`

- [ ] **12.2** Add `isKeyValid` to `BiometricCipher`
  - File: `packages/biometric_cipher/lib/biometric_cipher.dart`
  - Validate non-empty tag (throw `BiometricCipherException` with `invalidArgument` code if empty)
  - Delegate to `_instance.isKeyValid(tag: tag)`

## Acceptance Criteria

**Test:** `cd packages/biometric_cipher && fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .`

- `BiometricCipher.isKeyValid(tag: '')` throws `BiometricCipherException` with `BiometricCipherExceptionCode.invalidArgument`
- `BiometricCipher.isKeyValid(tag: 'some-tag')` successfully invokes the platform interface
- No new files created
- Analysis passes with no warnings or infos

## Dependencies

- Phase 11 complete (Windows `isKeyValid` native handler done)
- All three platforms (Android 9, iOS/macOS 10, Windows 11) register `"isKeyValid"` on the method channel

## Technical Details

### Task 12.1 — Platform interface (`biometric_cipher_platform_interface.dart`)

Add the abstract method to `BiometricCipherPlatform`:

```dart
Future<bool> isKeyValid({required String tag});
```

Follow the existing pattern of other method declarations in the interface (e.g., `deleteKey`, `encrypt`, `decrypt`).

### Task 12.2 — Public API (`biometric_cipher.dart`)

```dart
/// Returns `true` if the hardware-backed biometric key identified by [tag]
/// exists and has not been permanently invalidated.
///
/// Does NOT trigger a biometric prompt. Uses platform-specific silent checks:
/// - Android: `Cipher.init()` probe (throws `KeyPermanentlyInvalidatedException` for invalid keys)
/// - iOS/macOS: `SecItemCopyMatching` with `kSecUseAuthenticationUISkip`
/// - Windows: `KeyCredentialManager.OpenAsync()` status check (no signing operation)
Future<bool> isKeyValid({required String tag}) {
  if (tag.isEmpty) {
    throw const BiometricCipherException(
      code: BiometricCipherExceptionCode.invalidArgument,
      message: 'Tag cannot be empty',
    );
  }

  return _instance.isKeyValid(tag: tag);
}
```

Follow the existing pattern of other static methods in `BiometricCipher` (e.g., `deleteKey`, `encrypt`, `decrypt`).

## Implementation Notes

- Tasks 12.1 → 12.2 must be done in order: the platform interface must declare the method before `BiometricCipher` can delegate to it.
- The method is `static` on `BiometricCipher`, consistent with all other plugin API methods.
- The `invalidArgument` exception code already exists in `BiometricCipherExceptionCode` — no new enum value needed.
- Do not add logging — this is a pure delegation with a guard.
- The method name `'isKeyValid'` must exactly match the channel handler names registered in phases 9–11.
