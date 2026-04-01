# Iteration 3: iOS/macOS — `ScreenLockStreamHandler`

**Goal:** Detect screen lock via platform-specific notifications — `protectedDataWillBecomeUnavailable` (iOS) and `com.apple.screenIsLocked` (macOS).

## Context

Iteration 2 wired the Android native implementation. This iteration provides the iOS/macOS native implementation that pushes events through the same `EventChannel("biometric_cipher/screen_lock")` established in Iteration 1.

iOS and macOS share code in `packages/biometric_cipher/darwin/Classes/` with `#if os(iOS)` / `#elseif os(macOS)` guards where needed. The screen lock signals differ:

- **iOS**: `UIApplication.protectedDataWillBecomeUnavailableNotification` — fires when data protection activates (device locks with passcode enabled). This is a public, App Store-safe API. The alternative (`com.apple.springboard.lockstate` Darwin notification) is private and risks App Store rejection.
- **macOS**: `com.apple.screenIsLocked` — distributed notification fired when the screen locks (Cmd+Ctrl+Q, auto-lock, sleep lock). Uses `DistributedNotificationCenter` for system-wide notifications.

Key design points:
- `NotificationCenter` is used for iOS (app-local notifications); `DistributedNotificationCenter` for macOS (system-wide).
- Observer added in `onListen`, removed in `onCancel` — matches EventChannel lifecycle.
- The `ScreenLockStreamHandler` instance is retained by the event channel (no explicit field needed in the plugin).
- macOS full-screen transitions do **not** trigger false screen lock events — the distributed notification is independent of app lifecycle.

## Tasks

- [x] **3.1** Create `ScreenLockStreamHandler`
  - File: new — `packages/biometric_cipher/darwin/Classes/ScreenLockStreamHandler.swift`
  - `FlutterStreamHandler` with `#if os(iOS)` / `#elseif os(macOS)` guards
  - iOS: `NotificationCenter` + `protectedDataWillBecomeUnavailableNotification`
  - macOS: `DistributedNotificationCenter` + `com.apple.screenIsLocked`
  - `onListen`: add observer, `onCancel`: remove observer

- [x] **3.2** Register EventChannel in `BiometricCipherPlugin.register(with:)`
  - File: `packages/biometric_cipher/darwin/Classes/BiometricCipherPlugin.swift`
  - Create `FlutterEventChannel(name: "biometric_cipher/screen_lock")`, set stream handler

## Acceptance Criteria

**Verify:** `cd example && fvm flutter build macos --debug`

Functional criteria:
- On iOS, the locker transitions to `locked` state when `protectedDataWillBecomeUnavailableNotification` fires while the locker is `unlocked`.
- On macOS, the locker transitions to `locked` state when the `com.apple.screenIsLocked` distributed notification fires while the locker is `unlocked`.
- Screen lock detection does **not** trigger a biometric prompt or any user-visible system dialog.
- macOS full-screen transitions do not trigger false screen lock events.

## Dependencies

- Iteration 1 complete (Dart-side EventChannel wired) ✅
- Iteration 2 complete (Android native handler) ✅

## Technical Details

### `ScreenLockStreamHandler.swift` (new file)

```swift
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
import Flutter

class ScreenLockStreamHandler: NSObject, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events

        #if os(iOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onScreenLocked),
            name: UIApplication.protectedDataWillBecomeUnavailableNotification,
            object: nil
        )
        #elseif os(macOS)
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(onScreenLocked),
            name: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil
        )
        #endif

        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        #if os(iOS)
        NotificationCenter.default.removeObserver(self)
        #elseif os(macOS)
        DistributedNotificationCenter.default().removeObserver(self)
        #endif

        eventSink = nil
        return nil
    }

    @objc private func onScreenLocked() {
        eventSink?(true)
    }
}
```

### Changes to `BiometricCipherPlugin.swift`

In `register(with registrar:)`, add after the existing `FlutterMethodChannel` setup:

```swift
let screenLockChannel = FlutterEventChannel(
    name: "biometric_cipher/screen_lock",
    binaryMessenger: registrar.messenger()
)
screenLockChannel.setStreamHandler(ScreenLockStreamHandler())
```

Note: on macOS the messenger accessor may differ. Follow the existing pattern used for the `FlutterMethodChannel` in the same method. The `ScreenLockStreamHandler` instance is retained by the event channel — no extra field needed.

## Implementation Notes

- No new Swift dependencies required. `NotificationCenter`, `DistributedNotificationCenter`, and `FlutterStreamHandler` are all in the existing SDKs.
- The `darwin/Classes/` directory already exists and is shared between iOS and macOS targets via `#if os(...)` guards.
- Check the existing `BiometricCipherPlugin.swift` for the exact messenger accessor pattern used — it may be `registrar.messenger()` or `registrar.messenger` depending on the Flutter plugin API version in use.
