# Phase 11: Dart Plugin — `BiometricCipher.isKeyValid(tag)`

**Goal:** Expose the native key validity check through the Dart plugin API, bridging the platform channel calls from Phase 9 (Android) and Phase 10 (iOS/macOS) to a typed Dart method.

## Context

### Feature Motivation

Phases 9 and 10 added `"isKeyValid"` method channel handlers on Android and iOS/macOS. Phase 11 is the Dart-side bridge: it adds the method to the platform interface and the public `BiometricCipher` class so the Dart locker library (Phase 12) can call it.

The method must **never trigger a biometric prompt** — the platform implementations use silent probes (`Cipher.init()` on Android, `SecItemCopyMatching` with `kSecUseAuthenticationUISkip` on iOS/macOS). The Dart layer simply forwards the call.

### Call Path (Complete — Phases 9–11)

```
BiometricCipher.isKeyValid(tag: tag)   [Phase 11 — biometric_cipher.dart]
  → _instance.isKeyValid(tag: tag)     [Phase 11 — platform interface]
  → MethodChannel("isKeyValid", tag)   [existing channel infrastructure]
  → Android: Cipher.init() probe       [Phase 9]
  → iOS/macOS: keyExists() probe       [Phase 10]
```

### Consumer (Phase 12)

Phase 12 (`BiometricCipherProvider.isKeyValid`) will call `BiometricCipher.isKeyValid(tag: tag)` directly. Phase 11 must be complete before Phase 12 can implement.

### Validation

- Empty `tag` → throw `BiometricCipherException(code: invalidArgument)` before reaching the channel.
- Non-empty `tag` → delegate to `_instance.isKeyValid(tag: tag)`.
- No other validation. The platform handles key-not-found by returning `false`, not by throwing.

## Tasks

- [ ] **11.1** Add `isKeyValid` to platform interface
  - File: `packages/biometric_cipher/lib/biometric_cipher_platform_interface.dart`
  - Add `Future<bool> isKeyValid({required String tag})`

- [ ] **11.2** Add `isKeyValid` to `BiometricCipher`
  - File: `packages/biometric_cipher/lib/biometric_cipher.dart`
  - Validate non-empty tag (throw `BiometricCipherException` with `invalidArgument` code if empty)
  - Delegate to `_instance.isKeyValid(tag: tag)`

## Acceptance Criteria

**Test:** `cd packages/biometric_cipher && fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .`

- `BiometricCipher.isKeyValid(tag: '')` throws `BiometricCipherException` with `invalidArgument` code (client-side guard, no channel call).
- `BiometricCipher.isKeyValid(tag: 'biometric')` invokes the channel and returns the platform bool.
- Method is present on the platform interface — no `UnimplementedError` on any platform.

## Dependencies

- Phase 9 complete (Android channel handler `"isKeyValid"` in place)
- Phase 10 complete (iOS/macOS channel handler `"isKeyValid"` in place)
- `BiometricCipherExceptionCode.invalidArgument` already exists (used in existing `encrypt`/`decrypt` tag validation)

## Technical Details

### Task 11.1 — Platform interface

```dart
Future<bool> isKeyValid({required String tag});
```

Add alongside existing `encrypt`, `decrypt`, `deleteKey` signatures in `BiometricCipherPlatformInterface`. Follow the same pattern — no default implementation (forces all platform implementations to implement it).

### Task 11.2 — `BiometricCipher` public method

```dart
/// Checks whether the biometric key identified by [tag] exists and is still valid,
/// WITHOUT triggering a biometric prompt.
///
/// Returns `true` if the key exists and is usable, `false` if it has been
/// permanently invalidated (e.g. due to a biometric enrollment change) or deleted.
///
/// Throws [BiometricCipherException] with [BiometricCipherExceptionCode.invalidArgument]
/// if [tag] is empty.
Future<bool> isKeyValid({required String tag}) {
  if (tag.isEmpty) {
    throw const BiometricCipherException(
      code: BiometricCipherExceptionCode.invalidArgument,
    );
  }
  return _instance.isKeyValid(tag: tag);
}
```

Follow the same structure as `deleteKey(tag:)` which has the same empty-tag guard pattern.

## Implementation Notes

- Tasks 11.1 → 11.2 must be done in order (11.2 calls the interface added in 11.1).
- Do not add logging — this is a pure delegation with no side effects.
- The method name `isKeyValid` and parameter `tag` must match exactly what the platform channel handlers expect (set in Phases 9 and 10).
- `_instance` is the singleton platform interface accessor already used by all other `BiometricCipher` methods.
