# QA Plan: AW-2349 Phase 3 — iOS/macOS Native: `ScreenLockStreamHandler.swift`

Status: REVIEWED
Date: 2026-04-01

---

## Phase Scope

Phase 3 delivers the Apple-platform native side of the `EventChannel("biometric_cipher/screen_lock")` contract established in Phase 1 and validated on Android in Phase 2. It consists of exactly two files, both inside `packages/biometric_cipher/darwin/Classes/`:

1. **New file:** `ScreenLockStreamHandler.swift` — a `FlutterStreamHandler` implementation that uses `#if os(iOS)` / `#elseif os(macOS)` compile-time guards to observe the correct platform notification and forward `true` through the EventChannel sink.
2. **Modified file:** `BiometricCipherPlugin.swift` — registers `FlutterEventChannel("biometric_cipher/screen_lock")` in `register(with:)` using the platform-appropriate messenger accessor.

Platform detection mechanisms:
- **iOS:** `NotificationCenter.default` + `UIApplication.protectedDataWillBecomeUnavailableNotification`
- **macOS:** `DistributedNotificationCenter.default()` + `NSNotification.Name("com.apple.screenIsLocked")`

**Out of scope for Phase 3:** Windows handler (Phase 4), plugin unit tests (Phase 5), example app wiring (Phases 6–8). No Dart changes, no Android changes, no test files are modified in this phase.

---

## Implementation Status (observed)

### Task 3.1 — `ScreenLockStreamHandler.swift` (new file)

File path: `packages/biometric_cipher/darwin/Classes/ScreenLockStreamHandler.swift`

Findings:

- File is present alongside the pre-existing plugin files in `darwin/Classes/`.
- Compile-time import guards are correct at lines 1–7:
  - iOS branch: `import Flutter` + `import UIKit` (combined via `#if os(iOS)`).
  - macOS branch: `import Cocoa` + `import FlutterMacOS` (via `#elseif os(macOS)`).
  - Note: the plan and idea documents show `import Flutter` (iOS) and `import AppKit` (macOS). The actual file uses `import UIKit` (iOS) and `import Cocoa` (macOS). `Cocoa` is the umbrella framework for macOS that re-exports `AppKit`, `Foundation`, and more, so this is functionally equivalent and the idiomatic choice for macOS Swift. Not a defect.
- Class `ScreenLockStreamHandler: NSObject, FlutterStreamHandler` — `NSObject` superclass is required for `#selector` usage; `FlutterStreamHandler` is the correct Flutter contract. Both present (line 13).
- `private var eventSink: FlutterEventSink?` — nullable optional, initialized to `nil` implicitly (line 15).
- `onListen(withArguments:eventSink:)` (lines 17–37):
  - Sets `eventSink = events` before the platform guard — correct, avoids duplication inside the `#if` block.
  - iOS branch (lines 20–26): calls `NotificationCenter.default.addObserver(_:selector:name:object:)` with `self`, `#selector(onScreenLocked)`, `UIApplication.protectedDataWillBecomeUnavailableNotification`, and `object: nil`.
  - macOS branch (lines 27–33): calls `DistributedNotificationCenter.default().addObserver(_:selector:name:object:)` with `self`, `#selector(onScreenLocked)`, `NSNotification.Name("com.apple.screenIsLocked")`, and `object: nil`.
  - Returns `nil` (no error) — correct.
  - Target/selector form is used on both platforms, matching the spec.
- `onCancel(withArguments:)` (lines 39–48):
  - iOS branch: `NotificationCenter.default.removeObserver(self)` — removes all observers for `self`.
  - macOS branch: `DistributedNotificationCenter.default().removeObserver(self)` — removes all observers for `self`.
  - `eventSink = nil` — set after the platform guard, before `return nil`. Correct.
  - Returns `nil` (no error) — correct.
- `@objc private func onScreenLocked()` (lines 50–52): calls `eventSink?(true)` — optional chaining ensures no crash if `eventSink` is nil. The `@objc` attribute is required for `#selector` resolution with Objective-C runtime. Present.
- Implementation matches the spec in `docs/phase/AW-2349/phase-3.md` and `docs/idea-2349.md` in all functional aspects.

### Task 3.2 — EventChannel registered in `BiometricCipherPlugin.register(with:)`

File path: `packages/biometric_cipher/darwin/Classes/BiometricCipherPlugin.swift`

Findings:

- `register(with registrar:)` method (lines 24–42) contains both the pre-existing `FlutterMethodChannel` setup and the new `FlutterEventChannel` setup, all inside a single `#if os(iOS)` / `#elseif os(macOS)` block.
- iOS branch (lines 25–30):
  - `FlutterMethodChannel` uses `registrar.messenger()` (method call) — unchanged from Phase 2.
  - `FlutterEventChannel` uses `registrar.messenger()` (method call) — matches the iOS messenger accessor pattern.
- macOS branch (lines 31–37):
  - `FlutterMethodChannel` uses `registrar.messenger` (property access) — unchanged from Phase 2.
  - `FlutterEventChannel` uses `registrar.messenger` (property access) — matches the macOS messenger accessor pattern.
- EventChannel name string: `"biometric_cipher/screen_lock"` (lines 28 and 34) — exactly matches the Dart-side `static const EventChannel('biometric_cipher/screen_lock')` from Phase 1.
- `screenLockChannel.setStreamHandler(ScreenLockStreamHandler())` (line 38) — called outside the `#if` block, which is correct since `screenLockChannel` is defined in both branches. The `ScreenLockStreamHandler` instance is created inline and passed to `setStreamHandler`. `FlutterEventChannel.setStreamHandler(_:)` retains the handler for the channel's lifetime — no extra field needed in the plugin.
- `let instance = BiometricCipherPlugin()` and `registrar.addMethodCallDelegate(instance, channel: channel)` (lines 40–41) are unchanged from before Phase 3.
- No new instance fields were added to `BiometricCipherPlugin` — matches the design decision that instance retention is handled by the event channel.

**Both tasks in Phase 3 are fully implemented as specified.**

---

## Positive Scenarios

### PS-1: `ScreenLockStreamHandler.swift` file is present at the correct path

File `packages/biometric_cipher/darwin/Classes/ScreenLockStreamHandler.swift` is present in the `darwin/Classes/` directory alongside `BiometricCipherPlugin.swift` and `AppConstants.swift`. The `darwin/biometric_cipher.podspec` uses `s.source_files = 'Classes/**/*'` which automatically picks up the new file for both iOS and macOS pod targets without any podspec changes.

### PS-2: iOS branch uses `NotificationCenter.default` with the correct notification name

`onListen` registers `self` as an observer for `UIApplication.protectedDataWillBecomeUnavailableNotification` on `NotificationCenter.default`. This is a public, App Store-safe API that fires when data protection activates as the device locks (with passcode enabled). No private API is used.

### PS-3: macOS branch uses `DistributedNotificationCenter.default()` with the correct notification name

`onListen` registers `self` as an observer for `NSNotification.Name("com.apple.screenIsLocked")` on `DistributedNotificationCenter.default()`. This is the correct mechanism for receiving cross-process system notifications on macOS. The notification string is a well-known literal since no typed public SDK constant exists.

### PS-4: `onScreenLocked()` delivers `true` to the event sink without dispatch wrapping

`eventSink?(true)` is called directly in `onScreenLocked()`. No `DispatchQueue.main.async` wrapper is needed because:
- iOS: `protectedDataWillBecomeUnavailableNotification` is posted on the main thread by the OS.
- macOS: `DistributedNotificationCenter` delivers on the main run loop by default.
This matches the documented PRD constraint and avoids unnecessary threading complexity.

### PS-5: `onCancel` removes the observer and nils the sink

When the Dart subscription is cancelled, `onCancel` calls `removeObserver(self)` on the appropriate notification center, then sets `eventSink = nil`. After this point, no events can be delivered: the notification center no longer holds a reference to the handler as an observer, and the event sink is nil.

### PS-6: Messenger accessor asymmetry is correctly handled in `register(with:)`

The `FlutterEventChannel` initializer uses `registrar.messenger()` on iOS (method call) and `registrar.messenger` on macOS (property access), following the exact same `#if os(iOS)` / `#elseif os(macOS)` guard that was already used for the `FlutterMethodChannel` in the same method. A mismatch here would cause a Swift compilation error, so any regression would be caught immediately at build time.

### PS-7: `ScreenLockStreamHandler` instance is retained without an extra plugin field

`FlutterEventChannel.setStreamHandler(_:)` retains the passed handler. The `screenLockChannel` local variable holds the event channel, which is itself retained by the Flutter engine's registrar for the plugin's lifetime. No `private var screenLockHandler: ScreenLockStreamHandler?` field is needed in `BiometricCipherPlugin`. This matches the design decision and keeps the plugin class unchanged from a stored-property perspective.

### PS-8: EventChannel channel name string matches the Phase 1 Dart constant

The string `"biometric_cipher/screen_lock"` appears at lines 28 and 34 of `BiometricCipherPlugin.swift`. This is identical to `'biometric_cipher/screen_lock'` in `MethodChannelBiometricCipher` from Phase 1. A mismatch would cause the stream to silently produce no events on Apple platforms.

### PS-9: No user-visible prompts or permission requests

Neither `NotificationCenter` nor `DistributedNotificationCenter` observation requires any system permission, biometric prompt, or user-facing dialog. The screen lock event is detected entirely silently. This matches the PRD requirement and the `#selector`-based observer API (no block-based callback with capture-related prompts).

### PS-10: `subscribe → lock → subscribe` lifecycle round-trip

When `onListen` fires, the observer is registered and `eventSink` is set. When `onCancel` fires, the observer is removed and `eventSink` is niled. A subsequent `onListen` call re-registers the observer and re-sets `eventSink`. The `FlutterEventChannel` contract guarantees `onCancel` fires before any subsequent `onListen`, so no double-registration can occur under normal use.

### PS-11: Existing plugin functionality is not regressed

`BiometricCipherPlugin.swift` retains all pre-existing `handle(_:result:)` routing, all private methods (`configure`, `getTPMStatus`, `getBiometryStatus`, `generateKeyPair`, `deleteKey`, `encrypt`, `decrypt`, `isKeyValid`), all `SecureEnclaveManager` and `LAContextFactory` fields, and the `init()` override. No pre-existing code was modified beyond adding the `screenLockChannel` lines inside `register(with:)`.

---

## Negative and Edge Cases

### NC-1: iOS device without a passcode — `protectedDataWillBecomeUnavailableNotification` never fires

On a device without a passcode configured, data protection never activates, so the notification is never posted. The `onListen` observer is registered but will never be called. The Dart stream remains open with no events and no error. This is documented, expected behavior. The feature degrades gracefully: without a passcode there is no meaningful "screen lock" in a data-protection sense. Acceptable per PRD Scenario 6.

### NC-2: iOS Simulator does not fire `protectedDataWillBecomeUnavailableNotification`

The iOS Simulator does not simulate data protection or the passcode lock mechanism. `protectedDataWillBecomeUnavailableNotification` never fires in the simulator. End-to-end verification on iOS requires a physical device. This is a known platform limitation documented in the Phase 3 plan. The macOS build and manual test (`fvm flutter build macos --debug`) is the primary acceptance criterion; iOS is verified by CI compilation only for this phase.

### NC-3: `onCancel` called before `onListen` (no active observer)

If `onCancel` is called when `eventSink` is nil and no observer has been registered (e.g., an edge case in the Flutter engine lifecycle), `removeObserver(self)` on `NotificationCenter` / `DistributedNotificationCenter` is a no-op when `self` was never added. Apple's `NotificationCenter` does not throw if `removeObserver` is called for an unregistered observer. No crash. This is correct defensive behavior.

### NC-4: `onListen` called a second time without an intervening `onCancel` (theoretical double-register)

If `onListen` were called twice, `addObserver(_:selector:name:object:)` would register `self` twice, causing `onScreenLocked` to be called twice per screen lock event (double delivery). This is not possible under the Flutter `FlutterEventChannel` contract, which guarantees `onCancel` precedes any second `onListen`. No defensive `removeObserver` call exists at the start of `onListen`. Assessment: not a production defect. The contract prevents this. Consistent with the Phase 2 Android assessment (NC-3 there).

### NC-5: App is backgrounded or suspended when the screen locks

If the Flutter engine is suspended when the lock notification fires:
- **iOS:** `protectedDataWillBecomeUnavailableNotification` may or may not be delivered while the engine is suspended; `eventSink?(true)` may silently drop the event.
- **macOS:** `DistributedNotificationCenter` delivers on the main run loop; if the Flutter run loop is suspended, the delivery is deferred until the app resumes (or dropped). The event may not reach Dart.

This is the accepted edge case documented across the PRD, idea, and vision files. The existing `shouldLockOnResume` mechanism (`_onAppResumed` in `LockerBloc`) catches this on next app resume. No action required in Phase 3.

### NC-6: macOS full-screen transition — no false positive

`com.apple.screenIsLocked` is a system-level distributed notification tied specifically to the screen saver / lock screen activation. Full-screen transitions, Mission Control, app lifecycle changes, and display sleep do not post this notification. The PRD explicitly documents this as a verified non-issue (Scenario 3). No false lock events are expected.

### NC-7: `removeObserver(self)` removes all observers for `self`, not just the screen lock one

`NotificationCenter.default.removeObserver(self)` (and the macOS equivalent) removes all observations registered for `self` as the observer — not just the screen lock notification. In the current implementation, `ScreenLockStreamHandler` registers only one observer (for the screen lock notification), so this broad removal is safe. If future code adds additional observers to the same instance, `onCancel` would inadvertently remove them. For now this is correct and matches the implementation intent, but it is worth noting for future maintainers. Assessment: low risk, acceptable for Phase 3.

### NC-8: `NSNotification.Name("com.apple.screenIsLocked")` is a hardcoded string literal

No typed public SDK constant for this notification name exists. The string literal is the correct and standard approach (widely used by macOS security tools). A future macOS version could theoretically change this string, but it is a well-established notification used across the ecosystem. The PRD documents this risk as Low likelihood / High impact with no alternative public API. The hardcoded string is the only available option.

### NC-9: No native Swift unit tests in Phase 3

Native Swift tests for `ScreenLockStreamHandler` require simulator or hardware and are explicitly out of scope for Phase 3. The acceptance criterion is compilation (`fvm flutter build macos --debug`) plus a manual macOS smoke test. Plugin-level Dart tests are deferred to Phase 5.

### NC-10: No changes outside `packages/biometric_cipher/darwin/Classes/`

Per the PRD scope constraint, only the two files in `darwin/Classes/` are touched. No Dart files, no Android files, no Windows files, no example app files, and no test files are modified. This constraint is met by the implementation.

### NC-11: Import style difference — `import UIKit` vs `import Flutter` ordering

The actual implementation imports `Flutter` and `UIKit` together under `#if os(iOS)` in a single block (lines 2–3 of `ScreenLockStreamHandler.swift`), whereas the reference code in the plan shows them in a different order. Import ordering has no runtime effect. Both `UIKit` and `Flutter` (mapped to `FlutterMacOS` on macOS as `import FlutterMacOS`) are needed and present. Not a defect.

---

## Automated Tests Coverage

| Test | File | Status |
|------|------|--------|
| macOS debug build — no compilation errors | `cd example && fvm flutter build macos --debug` | Manual verification required (acceptance criterion) |
| iOS compilation — `#if os(iOS)` branch | `cd example && fvm flutter build ios --debug --no-codesign` | CI — manual if no CI available |
| `screenLockStream` Dart plugin tests (from Phase 1) | `packages/biometric_cipher/test/biometric_cipher_test.dart` | Present, green — exercise mock, not Swift handler |
| Native Swift unit tests for `ScreenLockStreamHandler` | — | **Not present** (deferred to Phase 5, requires simulator/hardware) |
| `onListen` / `onCancel` lifecycle via EventChannel | — | **Not present** in this phase; covered by Phase 5 |
| All pre-existing Dart plugin tests | `packages/biometric_cipher/test/biometric_cipher_test.dart` | Unaffected by Phase 3 changes |

**Overall automated coverage for Phase 3:** This phase contains no automated test additions of its own — all new code is Swift and requires simulator or physical device to exercise functionally. Compilation correctness (the primary acceptance criterion) is verified by the macOS build. Runtime behavior must be manually verified. Phase 5 will address the test gap for the Dart layer; native Swift tests remain out of scope for the entire ticket.

---

## Manual Checks Needed

### MC-1: macOS debug build passes without errors or warnings

Run from the `example/` directory:
```
fvm flutter build macos --debug
```
Expected: build succeeds with exit code 0, no Swift compilation errors, no Swift compiler warnings related to the new `ScreenLockStreamHandler.swift` or the modified `BiometricCipherPlugin.swift`. This validates:
- `ScreenLockStreamHandler` compiles under the macOS target (`#elseif os(macOS)` branch).
- `DistributedNotificationCenter`, `NSNotification.Name`, and `FlutterStreamHandler` all resolve correctly.
- `BiometricCipherPlugin.register(with:)` compiles with the new `FlutterEventChannel` lines.
- `registrar.messenger` (property, macOS) is used correctly and does not produce a type error.
- `ScreenLockStreamHandler()` is visible from `BiometricCipherPlugin.swift` (same module — no import needed).

### MC-2: iOS compilation check (no-codesign)

Run from the `example/` directory:
```
fvm flutter build ios --debug --no-codesign
```
Expected: build succeeds. This validates:
- `ScreenLockStreamHandler` compiles under the iOS target (`#if os(iOS)` branch).
- `UIApplication.protectedDataWillBecomeUnavailableNotification` resolves (requires `UIKit` import).
- `registrar.messenger()` (method call, iOS) is used correctly.
- No `import Flutter` vs `import FlutterMacOS` confusion between targets.

### MC-3: EventChannel channel name string matches exactly across layers

Visually confirm that:
- `BiometricCipherPlugin.swift` lines 28 and 34 both contain `"biometric_cipher/screen_lock"`.
- `biometric_cipher_method_channel.dart` (Phase 1) contains `'biometric_cipher/screen_lock'`.
- `BiometricCipherPlugin.kt` (Phase 2) contains `"biometric_cipher/screen_lock"`.

All three strings must be identical. A mismatch would cause the stream to silently produce no events on the mismatched platform.

### MC-4: macOS screen lock smoke test — event emitted within latency target

On macOS hardware (cannot be verified in a simulator for this notification):
1. Run `example` app in debug mode.
2. Unlock the locker with a password.
3. Add a temporary `print` to the Dart subscription on `BiometricCipher.screenLockStream` (or observe via Dart DevTools) to confirm event delivery. (Full end-to-end lock behavior requires Phases 5–8 wiring; only stream emission is tested here.)
4. Lock the screen using Cmd+Ctrl+Q (fast user switch lock) or system auto-lock.
5. Observe: `com.apple.screenIsLocked` distributed notification fires; `ScreenLockStreamHandler.onScreenLocked()` is called; `eventSink?(true)` pushes `true` to the Dart stream; the debug output shows the event within 2 seconds of screen lock.
6. Unlock the screen, observe no error in the app.

### MC-5: macOS full-screen transition — no false lock event

On macOS:
1. Run the example app.
2. Enter full-screen mode (green button or Ctrl+Cmd+F).
3. Exit full-screen mode.
4. Verify: no spurious `true` event was emitted on `screenLockStream` during the full-screen transition.

### MC-6: Subscribe → cancel → re-subscribe cycle (no crash, correct re-registration)

1. Ensure the Dart `screenLockStream` subscription is active (locker in unlocked state once Phase 5 is complete; for this phase, a manual temporary subscriber suffices).
2. Cancel the subscription. Verify `onCancel` is invoked (add a debug log temporarily if needed) and no crash occurs.
3. Re-subscribe. Verify `onListen` is invoked and the observer is re-registered.
4. Lock the screen. Verify the event is received on the new subscription.

### MC-7: No changes outside `packages/biometric_cipher/darwin/Classes/`

Confirm via `git diff --name-only` that only the following two files are added/modified relative to the Phase 2 state:
- `packages/biometric_cipher/darwin/Classes/ScreenLockStreamHandler.swift` (new)
- `packages/biometric_cipher/darwin/Classes/BiometricCipherPlugin.swift` (modified)

No Dart files, no Android files, no Windows files, no example app files, and no test files should appear in the diff for Phase 3 changes.

### MC-8: Existing biometric and secure enclave functionality unaffected on macOS and iOS

Run the example app on macOS (and iOS if available) and verify:
- Password-based unlock works.
- Biometric (Touch ID / Face ID) unlock works.
- Key generation, encryption, decryption, key deletion operations all succeed without error.
- Lock via timer still fires.
- Lock on background resume still fires.

---

## Risk Zone

| Risk | Likelihood | Impact | Assessment |
|------|-----------|--------|------------|
| `com.apple.screenIsLocked` string changes in a future macOS version | Low | High | Well-established notification used across the security ecosystem. No public typed constant exists. Hardcoded string is the only available approach. Document the dependency. |
| macOS sandbox blocks `DistributedNotificationCenter` for `com.apple.screenIsLocked` | Low | High | This notification is received by sandboxed apps without special entitlements. Verify during MC-1 (build) and MC-4 (smoke test). |
| `protectedDataWillBecomeUnavailableNotification` not fired on iOS without passcode | Known | Low | Expected, documented behavior. Stream remains open with no events; degrades gracefully (NC-1). |
| `removeObserver(self)` removes more than the screen lock observer if future code adds more observers on the same instance | Low | Medium | Current implementation registers only one observer per `ScreenLockStreamHandler`. Risk applies only if the class is extended in future phases. Document for maintainers. |
| iOS functional verification requires physical device — no simulator support | Certain (simulator limitation) | Low | Known constraint. iOS CI compilation check validates the `#if os(iOS)` branch. End-to-end iOS verification deferred to Phase 5 manual QA. macOS covers the Apple platform smoke test. |
| No native Swift unit tests for `ScreenLockStreamHandler` | Certain | Medium | Accepted — Phase 5 will add Dart coverage. Full native Swift tests require simulator and are out of scope for the entire ticket. Manual MC-4 and MC-5 are required before merging. |
| Double observer registration if `onListen` is called twice | Very Low | Medium | Prevented by `FlutterEventChannel` contract. No defensive guard exists. Consistent with Phase 2 (same design decision). Acceptable. |
| Messenger accessor mismatch (`registrar.messenger()` vs `registrar.messenger`) causes compile error | None | None (caught at build) | Already handled by the `#if os(iOS)` / `#elseif os(macOS)` guard. A regression would be a Swift compiler error, not a runtime bug. |
| Phase 3 scope creep (changes outside `darwin/Classes/`) | None observed | High | git diff shows only the two expected files. Constraint met. |

---

## Final Verdict

**RELEASE WITH RESERVATIONS**

Phase 3 delivers a correct, minimal Apple-platform native implementation that matches the specification in all observable respects. The `ScreenLockStreamHandler.swift` file is present at the correct path, implements `FlutterStreamHandler` with `NSObject` superclass, uses the correct platform-conditional notification center and notification name for each platform, ties observer registration and removal to the `onListen` / `onCancel` lifecycle, and delivers `true` events via optional chaining on `eventSink`. The `BiometricCipherPlugin.swift` modification correctly registers `FlutterEventChannel("biometric_cipher/screen_lock")` with the platform-appropriate messenger accessor, and does not require a new stored field on the plugin class.

The import style (`import Cocoa` on macOS instead of `import AppKit`) is the idiomatic macOS umbrella framework choice and is functionally equivalent to what the plan specifies.

The reservation is **MC-1 + MC-4 (macOS build and smoke test)**: compilation confirms the Swift code is structurally correct, but the `DistributedNotificationCenter` delivery and propagation to the Dart stream must be verified on macOS hardware before the branch can be considered fully validated. Additionally, **MC-2 (iOS no-codesign build)** should be run to confirm the `#if os(iOS)` branch compiles cleanly. Without these verifications there is no assurance that:
- The macOS sandbox does not block `com.apple.screenIsLocked` receipt.
- The event channel binary messenger wiring functions correctly end-to-end on Apple platforms.
- The `DistributedNotificationCenter` fires within the 2-second latency target.

The absence of automated native Swift tests (NC-9) is an accepted gap per the project plan. Phase 5 will add Dart-layer plugin tests; full native Swift tests are not planned for any phase.

Phase 3 is ready to proceed to Phase 4 (Windows) once MC-1 (macOS build), MC-2 (iOS build), and MC-4 (macOS screen lock smoke test) are confirmed passing.
