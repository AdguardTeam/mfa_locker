# Iteration 1: Dart plugin — `screenLockStream`

**Goal:** Add `screenLockStream` getter through the Dart plugin layer — platform interface, method channel, and public API.

## Context

MFA spec Section 8 requires: "if the device is locked (lock screen) -> lock immediately." Currently the app only locks via timer expiration (`TimerService`) or background timeout (`shouldLockOnResume` check on `AppLifecycleState.resumed`). There is no detection of the device screen being locked.

This iteration adds the Dart-side plumbing for a new `EventChannel` (`"biometric_cipher/screen_lock"`) that will carry native screen lock events to Dart. The `EventChannel` sits alongside the existing `MethodChannel` in the `biometric_cipher` plugin.

Key design points:
- `screenLockStream` returns `Stream<bool>` — emits `true` when device locks
- Default platform implementation returns `const Stream.empty()` for unsupported platforms
- `MethodChannelBiometricCipher` uses `receiveBroadcastStream()` — lazily initialized via `late final`
- No `_configured` check needed — screen lock detection is independent of biometric configuration

## Tasks

- [x] **1.1** Add `screenLockStream` to `BiometricCipherPlatform`
  - File: `packages/biometric_cipher/lib/biometric_cipher_platform_interface.dart`
  - Add `Stream<bool> get screenLockStream => const Stream.empty();`

- [x] **1.2** Implement `screenLockStream` in `MethodChannelBiometricCipher`
  - File: `packages/biometric_cipher/lib/biometric_cipher_method_channel.dart`
  - Add `EventChannel('biometric_cipher/screen_lock')`
  - Add `late final Stream<bool> screenLockStream` via `receiveBroadcastStream().map()`

- [x] **1.3** Expose `screenLockStream` from `BiometricCipher`
  - File: `packages/biometric_cipher/lib/biometric_cipher.dart`
  - Add `Stream<bool> get screenLockStream => _instance.screenLockStream;`
  - No `_configured` check — independent of biometric configuration

## Acceptance Criteria

**Verify:** `cd packages/biometric_cipher && fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .`

## Dependencies

- No prior iterations required — this is the first iteration.

## Technical Details

### Platform interface (`biometric_cipher_platform_interface.dart`)

```dart
/// Stream that emits `true` when the device screen is locked.
///
/// The stream uses an EventChannel to receive native screen lock events.
/// Returns an empty stream on platforms that do not support screen lock detection.
Stream<bool> get screenLockStream => const Stream.empty();
```

### Method channel (`biometric_cipher_method_channel.dart`)

```dart
static const _screenLockEventChannel = EventChannel('biometric_cipher/screen_lock');

@override
late final Stream<bool> screenLockStream = _screenLockEventChannel
    .receiveBroadcastStream()
    .map((event) => event as bool);
```

The stream is lazily initialized and cached via `late final` — only one native subscription is created regardless of how many Dart listeners subscribe. `receiveBroadcastStream()` returns a broadcast stream that supports multiple listeners.

### Public API (`biometric_cipher.dart`)

```dart
/// Stream that emits `true` when the device screen is locked.
///
/// Uses platform-specific silent detection:
/// - Android: `ACTION_SCREEN_OFF` broadcast
/// - iOS: `protectedDataWillBecomeUnavailableNotification`
/// - macOS: `com.apple.screenIsLocked` distributed notification
/// - Windows: `WTS_SESSION_LOCK` session change event
///
/// Does NOT require `configure()` to be called first.
Stream<bool> get screenLockStream => _instance.screenLockStream;
```

## Implementation Notes

- The EventChannel name `"biometric_cipher/screen_lock"` follows the existing naming convention (plugin name prefix).
- Native handlers (Android, iOS/macOS, Windows) will be implemented in subsequent iterations (2, 3, 4).
- Until native handlers are wired, the stream will emit no events (no native side to push events).
