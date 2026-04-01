# AW-2349 Phase 3 Summary: iOS/macOS Native — `ScreenLockStreamHandler.swift`

**Ticket:** AW-2349
**Phase:** 3 of 8
**Status:** Released
**Date:** 2026-04-01
**Branch:** `feature/AW-2349-autolock-mfa` <!-- cspell:ignore autolock -->

---

## What Was Done

Phase 3 adds the Apple-platform native side of the `EventChannel("biometric_cipher/screen_lock")` contract. It creates one new Swift file and modifies one existing Swift file, both inside `packages/biometric_cipher/darwin/Classes/`. With Phase 3 in place, `BiometricCipher.screenLockStream` begins emitting events when the screen is locked on iOS and macOS.

All changes are confined to `packages/biometric_cipher/darwin/Classes/`. No Dart files, no Android files, no Windows files, no example app files, and no test files were modified.

---

## Why This Was Needed

Phase 1 established the Dart `EventChannel` wiring and Phase 2 delivered the Android handler. Without Phase 3, `BiometricCipher.screenLockStream` would still emit nothing on Apple platforms — the channel was open but had no native sender.

iOS and macOS use different OS-level mechanisms to signal a screen lock:

- **iOS** uses `UIApplication.protectedDataWillBecomeUnavailableNotification`, a public App Store-safe API that fires when the device's data protection activates as it locks with a passcode. The alternative private Darwin notification (`com.apple.springboard.lockstate`) was rejected because it would risk App Store review failure.
- **macOS** uses `com.apple.screenIsLocked`, a system-wide distributed notification fired by Cmd+Ctrl+Q, auto-lock, and sleep-with-lock. `DistributedNotificationCenter` is the correct cross-process mechanism; `NotificationCenter` would not receive this system-wide post.

Both are delivered on the main thread by OS guarantee, so no manual thread dispatch is needed in the handler.

---

## Files Changed

| File | Change |
|------|--------|
| `packages/biometric_cipher/darwin/Classes/ScreenLockStreamHandler.swift` | **New file** — `FlutterStreamHandler` implementation for iOS and macOS |
| `packages/biometric_cipher/darwin/Classes/BiometricCipherPlugin.swift` | Added `FlutterEventChannel("biometric_cipher/screen_lock")` registration in `register(with:)` |

No new directories were created. The existing `darwin/Classes/` directory is already shared between iOS and macOS targets; the podspec picks up new files automatically via `s.source_files = 'Classes/**/*'`.

---

## Key Design Decisions

### Single file with compile-time platform guards

iOS and macOS share one `ScreenLockStreamHandler.swift` file using `#if os(iOS)` / `#elseif os(macOS)` guards. This matches the pattern already established in `BiometricCipherPlugin.swift` and avoids duplicating the `FlutterStreamHandler` boilerplate into separate per-platform files.

### Import style: `import Cocoa` on macOS

The plan documents showed `import AppKit`. The actual file uses `import Cocoa`, which is the umbrella framework for macOS that re-exports `AppKit`, `Foundation`, and more. `import Cocoa` is the idiomatic macOS choice and is functionally equivalent. The QA review confirmed this is not a defect.

### `NSObject` superclass required for `#selector`

`ScreenLockStreamHandler` inherits from `NSObject`. This is a Swift requirement: the target/selector API (`addObserver(_:selector:name:object:)`) relies on the Objective-C runtime's `#selector` mechanism, which requires the observer to be an `NSObject` subclass. The block-based observer API was not used because it introduces retain cycle complexity that the selector form avoids cleanly.

### Observer lifecycle tied to `onListen` / `onCancel`

The notification observer is registered in `onListen` (when the Dart side calls `listen()` on the stream) and removed in `onCancel` (when the subscription is cancelled). No observer runs when no Dart listener is active — zero runtime cost when the feature is not in use. `removeObserver(self)` is called without a specific notification name, which removes all observations on the instance. This is safe because `ScreenLockStreamHandler` registers only one observer per activation.

### No instance field needed in `BiometricCipherPlugin`

`FlutterEventChannel.setStreamHandler(_:)` retains the passed handler for the channel's lifetime. The `FlutterEventChannel` itself is retained by the Flutter engine's registrar. Unlike the Android handler (which required explicit nullable fields in the plugin class), the Apple platform model provides retention through the event channel, so no `private var screenLockHandler` field was added to `BiometricCipherPlugin`.

### Messenger accessor asymmetry

The iOS registrar exposes the binary messenger as a method (`registrar.messenger()`); macOS exposes it as a property (`registrar.messenger`). This asymmetry was already present in the `FlutterMethodChannel` setup in the same method. Phase 3 applies identical `#if os(iOS)` / `#elseif os(macOS)` guards for the `FlutterEventChannel` initializer. A mismatch would be a Swift compilation error, not a silent runtime issue.

### Channel name string is a hardcoded literal

`"biometric_cipher/screen_lock"` appears at two places in `BiometricCipherPlugin.swift` (lines 28 and 34, inside the iOS and macOS branches respectively). The string must match the Dart-side `static const EventChannel('biometric_cipher/screen_lock')` from Phase 1 and the Android `"biometric_cipher/screen_lock"` string from Phase 2. A mismatch would cause the stream to silently emit nothing on Apple platforms.

### `com.apple.screenIsLocked` is a hardcoded string literal

No public typed constant for this notification name exists in any Apple SDK. The hardcoded string is the standard approach used across the macOS security ecosystem. The risk of this string changing in a future macOS version is documented as Low likelihood / High impact with no alternative public API available.

---

## Data Flow (after Phase 3)

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
  MethodChannelBiometricCipher.screenLockStream   <-- wired in Phase 1
        |
        v
  BiometricCipher.screenLockStream

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
  MethodChannelBiometricCipher.screenLockStream   <-- wired in Phase 1
        |
        v
  BiometricCipher.screenLockStream
```

The Windows handler is still absent (Phase 4). On Windows the stream remains open but emits nothing.

---

## Edge Cases and Accepted Limitations

**iOS devices without a passcode.** `protectedDataWillBecomeUnavailableNotification` only fires when data protection activates, which requires a passcode. On a device without a passcode, the observer is registered but never called. The stream remains open with no events and no error. This is expected: a device without a passcode cannot meaningfully "lock" in a data-protection sense, and biometric authentication itself requires a passcode.

**iOS Simulator.** The iOS Simulator does not simulate data protection or passcode lock. `protectedDataWillBecomeUnavailableNotification` never fires in the simulator. End-to-end iOS verification requires a physical device. CI compilation of the `#if os(iOS)` branch is the acceptance boundary for this phase.

**App backgrounded or suspended at screen lock time.** If the Flutter engine is suspended when the notification fires, the `EventChannel` event may not reach Dart. This is the accepted edge case across the entire ticket — the existing `shouldLockOnResume` mechanism in `LockerBloc` catches it when the app resumes.

**macOS full-screen transitions.** `com.apple.screenIsLocked` is a dedicated screen lock notification unrelated to app lifecycle, Mission Control, or display sleep. Full-screen transitions do not post this notification; no false lock events are produced.

**`removeObserver(self)` removes all observers for the instance.** The broad removal is safe today because `ScreenLockStreamHandler` registers only one observer. If future code adds additional observers on the same instance, `onCancel` would inadvertently remove them. This is noted as a maintainability concern for future phases.

---

## Test Coverage

Phase 3 adds no automated tests of its own. All new code is Swift and requires a simulator or physical device to exercise functionally. The acceptance criterion is successful compilation.

| Layer | Status |
|-------|--------|
| Dart plugin tests (`biometric_cipher_test.dart`) | Carried forward from Phase 1; exercise the mock, not the Swift handler |
| Native Swift unit tests for `ScreenLockStreamHandler` | Not present — out of scope for the entire ticket per plan |
| `fvm flutter build macos --debug` (macOS compilation) | Required manual verification (primary acceptance criterion) |
| `fvm flutter build ios --debug --no-codesign` (iOS compilation) | CI or manual — validates the `#if os(iOS)` branch |
| macOS screen lock smoke test (MC-4) | Required manual verification before merge |

---

## QA Verdict

**RELEASE WITH RESERVATIONS** — the QA review (dated 2026-04-01) confirmed that both tasks in Phase 3 are fully implemented as specified:

- `ScreenLockStreamHandler.swift` is present in `darwin/Classes/` with the correct `NSObject, FlutterStreamHandler` class declaration, correct notification center and notification name for each platform, observer registration in `onListen`, observer removal and `eventSink = nil` in `onCancel`, and `@objc private func onScreenLocked()` delivering `eventSink?(true)`.
- `BiometricCipherPlugin.swift` registers `FlutterEventChannel("biometric_cipher/screen_lock")` with the correct messenger accessor (`registrar.messenger()` on iOS, `registrar.messenger` on macOS), calls `setStreamHandler(ScreenLockStreamHandler())` outside the platform guard (correct, since `screenLockChannel` is defined in both branches), and adds no new stored properties to the plugin class.
- No changes outside `packages/biometric_cipher/darwin/Classes/`.
- No existing plugin functionality removed or broken.

The reservation is **MC-1 + MC-4**: the macOS debug build and screen lock smoke test must be confirmed passing before the branch is fully validated. **MC-2** (iOS no-codesign build) should also pass to confirm the iOS branch compiles cleanly.

---

## What Comes Next

| Phase | Scope |
|-------|-------|
| Phase 4 | Windows native handler (`ScreenLockStreamHandler.cpp/.h` using `WTS_SESSION_LOCK` session change events via `WTSRegisterSessionNotification` + `WM_WTSSESSION_CHANGE`) |
| Phase 5 | Example app wiring — `ScreenLockService`, DI registration, `LockerBloc` integration (`screenLocked` event, start/stop listening on unlock/lock state transitions) |

No changes to the Dart plugin layer, the Android implementation, or the iOS/macOS implementation are expected when Phase 4 lands.

---

## Reference Documents

- Plan/Tasklist: `docs/phase/AW-2349/phase-3.md`
- PRD: `docs/prd/AW-2349-phase-3.prd.md`
- QA: `docs/qa/AW-2349-phase-3.md`
- Idea/context: `docs/idea-2349.md`
- Vision: `docs/vision-2349.md`
- Phase 2 summary: `docs/AW-2349-phase-2-summary.md`
- Phase 1 summary: `docs/AW-2349-phase-1-summary.md`
