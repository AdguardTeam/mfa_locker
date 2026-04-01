# AW-2349-phase-3: Screen Lock Detection — iOS/macOS Native Handler (`ScreenLockStreamHandler.swift`)

Status: PRD_READY

## Context / Idea

MFA spec Section 8 requires: "if the device is locked (lock screen) → lock immediately." The full feature (AW-2349) adds native screen lock detection across Android, iOS, macOS, and Windows by extending the `biometric_cipher` plugin with an `EventChannel("biometric_cipher/screen_lock")`.

The implementation is split into sequential phases:

- Phase 1 (complete): Dart plugin layer — `screenLockStream` API surface established on `BiometricCipherPlatform`, `MethodChannelBiometricCipher`, and `BiometricCipher`.
- Phase 2 (complete): Android native handler — `ScreenLockStreamHandler.kt` with `BroadcastReceiver` for `ACTION_SCREEN_OFF`, registered in `BiometricCipherPlugin.kt`.
- **Phase 3 (this phase):** iOS/macOS native handler — `ScreenLockStreamHandler.swift` shared via the `darwin/Classes/` directory using `#if os(iOS)` / `#elseif os(macOS)` compile-time guards, registered in `BiometricCipherPlugin.swift`.
- Phase 4: Windows native handler (`ScreenLockStreamHandler.cpp/.h`).
- Phase 5: Example app wiring (`ScreenLockService`, DI, `LockerBloc` integration).

Phase 3 is a pure Swift/native change inside `packages/biometric_cipher/darwin/`. It delivers the Apple platform side of the `EventChannel` contract established in Phase 1. The Dart subscription already exists; Phase 3 makes it emit events on iOS and macOS.

### Platform detection mechanisms for this phase

| Platform | Signal | API | Prompt shown? |
|----------|--------|-----|---------------|
| iOS | Data protection unavailable | `UIApplication.protectedDataWillBecomeUnavailableNotification` via `NotificationCenter` | No |
| macOS | Screen locked | `com.apple.screenIsLocked` distributed notification via `DistributedNotificationCenter` | No |

**Why `protectedDataWillBecomeUnavailableNotification` on iOS?**
This is a public, App Store-safe API that fires when data protection activates (device locking with passcode). The alternative (`com.apple.springboard.lockstate` Darwin notification) is a private API that risks App Store rejection.

**Why `DistributedNotificationCenter` on macOS?**
`com.apple.screenIsLocked` is a system-wide distributed notification. `DistributedNotificationCenter` is the correct mechanism for cross-process notifications on macOS, independent of the app's own lifecycle.

### Known messenger API difference

The existing `BiometricCipherPlugin.swift` already handles the iOS/macOS messenger API asymmetry:
- iOS: `registrar.messenger()` (method call)
- macOS: `registrar.messenger` (property access)

Phase 3 must apply the same `#if os(iOS)` / `#elseif os(macOS)` guard when constructing the `FlutterEventChannel`.

### Observer API

The target/selector (`#selector`) form is used for observer registration on both platforms, consistent with the spec and vision document.

### Affected files (Phase 3 only)

| File | Change |
|------|--------|
| `packages/biometric_cipher/darwin/Classes/ScreenLockStreamHandler.swift` | New file — `FlutterStreamHandler` implementation for iOS and macOS |
| `packages/biometric_cipher/darwin/Classes/BiometricCipherPlugin.swift` | Register `FlutterEventChannel("biometric_cipher/screen_lock")` in `register(with:)` |

---

## Goals

1. Create `ScreenLockStreamHandler.swift` in `packages/biometric_cipher/darwin/Classes/` implementing `FlutterStreamHandler`, with platform-conditional notification subscription:
   - iOS: `NotificationCenter` + `UIApplication.protectedDataWillBecomeUnavailableNotification`
   - macOS: `DistributedNotificationCenter` + `NSNotification.Name("com.apple.screenIsLocked")`
2. Wire observer registration to `onListen` and deregistration to `onCancel`, matching the `EventChannel` lifecycle (no orphaned observers).
3. Register the `EventChannel("biometric_cipher/screen_lock")` in `BiometricCipherPlugin.register(with:)` with the correct messenger accessor per platform.
4. Ensure the `ScreenLockStreamHandler` instance is retained by the event channel — no additional storage field is required in the plugin.
5. Pass `fvm flutter build macos --debug` (from `cd example`) with no build errors or warnings related to this change.
6. Produce no false-positive screen lock events during macOS full-screen transitions.

---

## User Stories

**As a library consumer on iOS**, I want `BiometricCipher.screenLockStream` to emit `true` when the device passcode lock activates (screen locks), so that `ScreenLockService` can trigger immediate locker lock without polling.

**As a library consumer on macOS**, I want `BiometricCipher.screenLockStream` to emit `true` when the user locks the screen (Cmd+Ctrl+Q, auto-lock, sleep lock), so that the locker transitions to `locked` state immediately.

**As an App Store reviewer**, I want the iOS implementation to use only public Apple APIs, so that there is no risk of rejection due to private API usage.

**As a native plugin maintainer**, I want iOS and macOS code to live in a single Swift file using `#if os(...)` compile-time guards, so that the shared `darwin/Classes/` structure is preserved and no duplication exists.

---

## Main Scenarios

### Scenario 1 — iOS screen lock while app is in foreground
- Locker is in `unlocked` state; the native subscription is active.
- User locks the device (power button press or auto-lock timeout with passcode enabled).
- iOS fires `UIApplication.protectedDataWillBecomeUnavailableNotification` on the main thread.
- `ScreenLockStreamHandler.onScreenLocked()` calls `eventSink?(true)` directly (no dispatch needed).
- The Dart `screenLockStream` emits `true`.
- (Phase 5 concern, but verifiable end-to-end) `ScreenLockService` triggers `LockerBloc` to lock.

### Scenario 2 — macOS screen lock while app is in foreground
- Locker is in `unlocked` state; the native subscription is active.
- User locks the screen (Cmd+Ctrl+Q, auto-lock, lid close with screen lock enabled).
- macOS fires `com.apple.screenIsLocked` via `DistributedNotificationCenter` on the main thread.
- `ScreenLockStreamHandler.onScreenLocked()` calls `eventSink?(true)` directly (no dispatch needed).
- The Dart `screenLockStream` emits `true`.

### Scenario 3 — macOS full-screen transition (no false positive)
- User enters or exits full-screen mode for the Flutter app.
- `com.apple.screenIsLocked` distributed notification is NOT fired.
- `ScreenLockStreamHandler.onScreenLocked()` is NOT called.
- No spurious lock event is emitted.

### Scenario 4 — Dart subscription cancelled and resumed
- Dart side cancels the `screenLockStream` subscription (e.g., locker locked, `stopListening()` called in Phase 5).
- `onCancel` fires: observer is removed from `NotificationCenter` / `DistributedNotificationCenter`; `eventSink` is set to `nil`.
- No events can be delivered after cancellation.
- Dart side subscribes again (e.g., locker unlocked, `startListening()` called).
- `onListen` fires: observer is re-registered; `eventSink` is set.
- Next screen lock event is delivered correctly.

### Scenario 5 — App suspended/backgrounded at time of screen lock
- App is in the background when the screen locks.
- The `EventChannel` event may not be delivered (Flutter engine suspended).
- This is acceptable: the existing `shouldLockOnResume` mechanism handles it on next app resume (see Phase 1 context).
- No error is thrown; `eventSink` may be `nil` or the event is silently dropped.

### Scenario 6 — iOS device without passcode
- User accesses `screenLockStream` on a device without a passcode.
- `protectedDataWillBecomeUnavailableNotification` never fires (data protection does not activate without a passcode).
- No events emitted; stream remains open with no error.
- This matches the security model: a device without a passcode cannot enforce data protection.

---

## Success / Metrics

| Criterion | How verified |
|-----------|-------------|
| `ScreenLockStreamHandler.swift` created in `darwin/Classes/` | File present at expected path |
| iOS build compiles without error (`#if os(iOS)` branch) | CI |
| macOS debug build compiles without error | `cd example && fvm flutter build macos --debug` |
| `BiometricCipherPlugin.register(with:)` registers `FlutterEventChannel("biometric_cipher/screen_lock")` | Code review |
| Correct messenger accessor used per platform (`registrar.messenger()` iOS, `registrar.messenger` macOS) | Code review — matches existing `FlutterMethodChannel` pattern in same method |
| Observer registered in `onListen`, removed in `onCancel` | Code review |
| `eventSink` set to `nil` in `onCancel` | Code review |
| Target/selector (`#selector`) form used for observer registration | Code review |
| macOS full-screen transition does NOT emit a lock event | Manual test on macOS hardware |
| Screen lock event emitted within reasonable latency on macOS (< 2 seconds) | Manual test: lock screen, observe locker state (end-to-end once Phase 5 complete) |
| No Swift compiler warnings introduced | Build output clean |
| No changes outside `packages/biometric_cipher/darwin/` | Diff scope |

---

## Constraints and Assumptions

- **Darwin-only scope:** Phase 3 touches only `packages/biometric_cipher/darwin/Classes/`. No Dart changes, no Android or Windows changes.
- **`#if os(iOS)` / `#elseif os(macOS)` guards:** The single Swift file must compile correctly for both targets using compile-time conditional compilation. No separate iOS-only or macOS-only files.
- **Messenger accessor asymmetry:** iOS uses `registrar.messenger()` (method); macOS uses `registrar.messenger` (property). The `FlutterEventChannel` initializer call in `register(with:)` must be guarded with `#if os(iOS)` / `#elseif os(macOS)`, consistent with the existing `FlutterMethodChannel` setup in the same method.
- **Instance retention:** `FlutterEventChannel.setStreamHandler(_:)` retains the stream handler for the channel's lifetime. No extra `private var` field is needed in `BiometricCipherPlugin` to hold the `ScreenLockStreamHandler` instance.
- **`onListen`/`onCancel` lifecycle:** Observer registration/deregistration is strictly tied to the EventChannel lifecycle callbacks. The `FlutterEventChannel` contract guarantees at most one active `onListen` without an intervening `onCancel`, so no defensive `removeObserver` call is required at the start of `onListen`.
- **Observer API:** Target/selector (`#selector`) form is used for `addObserver(_:selector:name:object:)` on both platforms. No block-based observer API is required.
- **Main-thread delivery:** Both `UIApplication.protectedDataWillBecomeUnavailableNotification` (iOS, via `NotificationCenter`) and `com.apple.screenIsLocked` (macOS, via `DistributedNotificationCenter`) are delivered on the main thread by OS guarantee. No `DispatchQueue.main.async` wrapper is needed in `onScreenLocked()`.
- **No Swift unit tests in this phase:** Native Swift tests for `ScreenLockStreamHandler` would require hardware/simulator and are out of scope for Phase 3. End-to-end verification is via macOS debug build.
- **iOS passcode dependency:** `protectedDataWillBecomeUnavailableNotification` only fires on devices with a passcode configured. This is documented behavior and acceptable for the feature.
- **macOS notification string is hardcoded:** `"com.apple.screenIsLocked"` is not available as a typed constant in any public Apple SDK. The string literal is the correct and standard approach.
- **No new Swift dependencies:** `NotificationCenter`, `DistributedNotificationCenter`, `UIKit`, `AppKit`, and `FlutterStreamHandler` are all part of the existing SDK and plugin targets. No new `Package.swift` or `podspec` changes needed.

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| `com.apple.screenIsLocked` string changes or becomes unavailable in future macOS versions | Low | High | This is a well-established notification used by security tools; no alternative public API exists. Document the dependency. |
| `protectedDataWillBecomeUnavailableNotification` not fired on iOS devices without passcode | Known | Low | Expected and documented behavior; the feature degrades gracefully (stream emits nothing, no error). |
| `registrar.messenger` vs `registrar.messenger()` confusion causes compile error | Low | Low | Pattern already established in existing `FlutterMethodChannel` setup in the same file; same guard applies. |
| macOS sandbox or entitlement blocks `DistributedNotificationCenter` | Low | High | `com.apple.screenIsLocked` is received by sandboxed apps; no special entitlement required. Verify during build. |

---

## Resolved Questions

1. **Main-thread dispatch in `onScreenLocked()`:** Both `UIApplication.protectedDataWillBecomeUnavailableNotification` (iOS) and `DistributedNotificationCenter` (macOS) deliver notifications on the main thread by OS guarantee. No `DispatchQueue.main.async` wrapper is needed.

2. **Defensive `removeObserver` in `onListen`:** Not required. The `FlutterEventChannel` contract guarantees that `onListen` is not called twice without an intervening `onCancel`. No defensive removal is needed.

3. **Build verification scope:** macOS only — `cd example && fvm flutter build macos --debug` is the required acceptance criterion. iOS build verification is handled by CI, not by Phase 3 acceptance.

4. **Observer API (retain cycle risk):** The target/selector (`#selector`) form is used, as specified in the vision document. `FlutterEventChannel.setStreamHandler(_:)` retains the handler; the notification center holds a weak reference to the observer target in standard `addObserver(_:selector:name:object:)` usage (the center does not retain the observer). No retain cycle exists.
