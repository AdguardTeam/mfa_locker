# AW-2349 Phase 3 Plan: iOS/macOS -- `ScreenLockStreamHandler`

**Status:** PLAN_APPROVED

## Phase Scope

Phase 3 delivers the iOS and macOS native side of the `EventChannel("biometric_cipher/screen_lock")` contract. It creates one new Swift file and modifies one existing Swift file in `packages/biometric_cipher/darwin/Classes/`.

The Dart-side `EventChannel` wiring was completed in Phase 1. The Android native handler was completed in Phase 2. This phase adds the Apple platform handlers so that `BiometricCipher.screenLockStream` begins emitting events on iOS and macOS.

All changes are scoped to `packages/biometric_cipher/darwin/Classes/`.

## Components

### 1. `ScreenLockStreamHandler` (new)

**File:** `packages/biometric_cipher/darwin/Classes/ScreenLockStreamHandler.swift`

A `FlutterStreamHandler` implementation that listens for platform-specific screen lock notifications and forwards them as `true` events through the EventChannel sink.

Platform-specific behavior via compile-time guards:

- **iOS:** Observes `UIApplication.protectedDataWillBecomeUnavailableNotification` on `NotificationCenter.default`. This is a public, App Store-safe API that fires when data protection activates (device locks with passcode enabled).
- **macOS:** Observes `com.apple.screenIsLocked` on `DistributedNotificationCenter.default()`. This system-wide distributed notification fires on Cmd+Ctrl+Q, auto-lock, and sleep lock.

Design decisions:

- **Single file with `#if os(iOS)` / `#elseif os(macOS)` guards** -- consistent with the existing `BiometricCipherPlugin.swift` pattern. No separate iOS/macOS files.
- **`NSObject` superclass** -- required for `#selector` usage with target/selector observer API.
- **Target/selector observer API** (not block-based) -- avoids retain cycle complexity. The observer is `self`, and `removeObserver` in `onCancel` cleanly breaks the reference.
- **`eventSink` stored as optional field** -- set in `onListen`, nilled in `onCancel`. The `@objc` callback checks it implicitly via optional chaining (`eventSink?(true)`).
- **No `DispatchQueue.main.async` needed** -- iOS `NotificationCenter` delivers on the posting thread (main for `protectedDataWillBecomeUnavailable`); macOS `DistributedNotificationCenter` also delivers on the main thread by default.

### 2. `BiometricCipherPlugin` (modified)

**File:** `packages/biometric_cipher/darwin/Classes/BiometricCipherPlugin.swift`

Add `FlutterEventChannel` registration in the existing `register(with:)` static method, after the method channel setup.

Design decisions:

- **No instance field needed** -- `FlutterEventChannel` retains the `ScreenLockStreamHandler`. The event channel itself is retained by the Flutter engine's registrar. This matches Flutter plugin conventions where event channels registered in `register(with:)` do not need explicit instance storage.
- **Messenger accessor uses platform guards** -- the existing code already demonstrates the pattern: `registrar.messenger()` on iOS vs `registrar.messenger` on macOS. The event channel registration must follow the same pattern.

## API Contract

### EventChannel (unchanged from Phase 1)

| Property | Value |
|----------|-------|
| Channel name | `"biometric_cipher/screen_lock"` |
| Payload type | `bool` |
| Semantics | `true` = device screen locked |
| Direction | Native to Dart (one-way) |

### Native notification sources (new in Phase 3)

| Platform | Notification center | Notification name |
|----------|-------------------|-------------------|
| iOS | `NotificationCenter.default` | `UIApplication.protectedDataWillBecomeUnavailableNotification` |
| macOS | `DistributedNotificationCenter.default()` | `com.apple.screenIsLocked` |

### Public API surface

No new public API in Phase 3. The Dart-side API was established in Phase 1. This phase provides the native backing that causes that API to emit events on Apple platforms.

## Data Flows

```
iOS:
  UIApplication posts protectedDataWillBecomeUnavailableNotification
      |
      v
  NotificationCenter.default delivers to ScreenLockStreamHandler.onScreenLocked()
      |
      v
  eventSink?(true)
      |
      v
  FlutterEventChannel("biometric_cipher/screen_lock")
      |
      v
  MethodChannelBiometricCipher.screenLockStream (Dart)
      |
      v
  BiometricCipher.screenLockStream (Dart)

macOS:
  System posts com.apple.screenIsLocked distributed notification
      |
      v
  DistributedNotificationCenter.default() delivers to ScreenLockStreamHandler.onScreenLocked()
      |
      v
  eventSink?(true)
      |
      v
  FlutterEventChannel("biometric_cipher/screen_lock")
      |
      v
  MethodChannelBiometricCipher.screenLockStream (Dart)
      |
      v
  BiometricCipher.screenLockStream (Dart)
```

The notification observer is added when the Dart side calls `listen()` on the stream (triggers `onListen`), and removed when the subscription is cancelled (triggers `onCancel`). No events flow when no Dart listener is active.

## NFR

| Requirement | How met |
|-------------|---------|
| Zero runtime cost when unused | Observer registered only in `onListen`, removed in `onCancel`. No polling, no background threads. |
| No memory leaks | `removeObserver` in `onCancel` breaks the notification center reference to `self`. `eventSink` nilled in `onCancel`. |
| No false positives on macOS | `com.apple.screenIsLocked` is a dedicated screen lock notification; full-screen transitions, app lifecycle changes, and display sleep do not trigger it. |
| App Store compliance on iOS | Uses public `protectedDataWillBecomeUnavailableNotification` API, not private `com.apple.springboard.lockstate` Darwin notification. |
| No user-visible prompts | Notification observation is silent -- no biometric prompt, no system dialog, no permission request. |
| No podspec changes | `darwin/biometric_cipher.podspec` uses `s.source_files = 'Classes/**/*'` which automatically includes new files in `Classes/`. |
| Static analysis clean | Must compile without warnings via `cd example && fvm flutter build macos --debug` and `cd example && fvm flutter build ios --debug --no-codesign`. |

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| `protectedDataWillBecomeUnavailable` requires passcode to be set on iOS | Medium | Low | This is expected behavior. Without a passcode, the device does not "lock" in a data-protection sense. The feature is only meaningful when the device has a passcode, which is a prerequisite for biometric authentication anyway. |
| macOS `DistributedNotificationCenter` delivery timing | Low | Low | The notification is delivered on the main run loop. Flutter event channels also operate on the main thread. No cross-thread synchronization needed. |
| Messenger accessor mismatch (`messenger()` vs `messenger`) | Certain | None | Already handled by existing `#if os(iOS)` / `#elseif os(macOS)` guards in the plugin. The event channel registration reuses the same pattern. |
| `ScreenLockStreamHandler` import in `BiometricCipherPlugin.swift` | None | None | Swift files in the same module are visible to each other without explicit imports. No `import` statement needed. |
| iOS simulator does not fire `protectedDataWillBecomeUnavailable` | High | Low | This is a known simulator limitation. Testing requires a physical iOS device. Functional verification on iOS deferred to Phase 5 (plugin tests) and manual QA. macOS can be verified on any Mac. |

## Dependencies

- **Phase 1 complete** -- Dart-side `EventChannel` wiring (`screenLockStream` getter on `BiometricCipherPlatform`, `MethodChannelBiometricCipher`, and `BiometricCipher`).
- **Phase 2 complete** -- Android native handler (establishes the pattern; not a code dependency but confirms the EventChannel contract works end-to-end).
- **No external dependencies** -- `NotificationCenter`, `DistributedNotificationCenter`, `UIKit`, `AppKit`, and `FlutterStreamHandler` are all part of the existing platform SDKs.
- **No podspec changes** -- `s.source_files = 'Classes/**/*'` already covers new files in `darwin/Classes/`.

## Implementation Order

1. **Create `ScreenLockStreamHandler.swift`** -- new file at `packages/biometric_cipher/darwin/Classes/ScreenLockStreamHandler.swift`
2. **Modify `BiometricCipherPlugin.swift`** -- add `FlutterEventChannel` registration in `register(with:)` after the existing method channel setup
3. **Verify macOS build:** `cd example && fvm flutter build macos --debug`

Steps 1 and 2 are independent in terms of compilation (the plugin compiles with either change alone), but functionally step 2 depends on step 1 existing for the event channel to have a handler.

## Open Questions

None. All design decisions are fully resolved.
