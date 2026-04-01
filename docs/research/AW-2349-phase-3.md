# Research: AW-2349 Phase 3 — iOS/macOS ScreenLockStreamHandler

## Resolved Questions

1. **FlutterEventChannel retention:** Let go — rely on the Flutter engine. No static/instance property needed. The local `screenLockChannel` variable in `register(with:)` can be released after calling `setStreamHandler`. The handler instance is retained by the channel internally.

2. **Messenger accessor pattern:** Follow the existing `#if os(iOS)` / `#elseif os(macOS)` guards already present in `BiometricCipherPlugin.swift`. iOS uses `registrar.messenger()` (method call); macOS uses `registrar.messenger` (property). Matches exactly the `FlutterMethodChannel` setup in the same `register(with:)` method.

3. **Build gate:** Local macOS build is sufficient. Verify with `cd example && fvm flutter build macos --debug`. No CI or additional environment constraints.

4. No other implementation details or constraints.

---

## Phase Scope

Phase 3 delivers the iOS/macOS native side of screen lock detection. It adds one new file and modifies one existing file:

- **New:** `packages/biometric_cipher/darwin/Classes/ScreenLockStreamHandler.swift`
- **Modified:** `packages/biometric_cipher/darwin/Classes/BiometricCipherPlugin.swift` — register the `FlutterEventChannel` with name `"biometric_cipher/screen_lock"` in `register(with:)`

The Dart-side `EventChannel` (Phase 1) and Android handler (Phase 2) are already complete and do not change.

---

## Related Modules/Services

### `packages/biometric_cipher/darwin/Classes/BiometricCipherPlugin.swift`

The entry point. `register(with registrar:)` is a `static func`. It currently:

1. Creates a `FlutterMethodChannel(name: "biometric_cipher")` with the platform-specific messenger.
2. Creates a `BiometricCipherPlugin` instance.
3. Calls `registrar.addMethodCallDelegate(instance, channel: channel)`.

Phase 3 appends the `FlutterEventChannel` registration after those three lines, with the local variable going out of scope immediately.

The messenger accessor diverges by platform (lines 26 and 28 of `BiometricCipherPlugin.swift`):

```swift
#if os(iOS)
    let channel = FlutterMethodChannel(name: "biometric_cipher", binaryMessenger: registrar.messenger())
#elseif os(macOS)
    let channel = FlutterMethodChannel(name: "biometric_cipher", binaryMessenger: registrar.messenger)
#endif
```

The same `#if` / `#elseif` pattern must be applied when constructing the `FlutterEventChannel`.

### `packages/biometric_cipher/darwin/Classes/` — existing files

```
AppConstants.swift
BiometricCipherPlugin.swift
Errors/
    AuthenticationError.swift
    BaseError.swift
    KeychainServiceError.swift
    SecureEnclaveManagerError.swift
    SecureEnclavePluginError.swift
Managers/
    AuthenticationManager.swift
    SecureEnclaveManager.swift
Protocols/
    KeychainServiceProtocol.swift
    LAContextFactoryProtocol.swift
    LAContextProtocol.swift
    SecureEnclaveManagerProtocol.swift
Services/
    Base64Codec.swift
    KeychainService.swift
    LAContextFactory.swift
```

`ScreenLockStreamHandler.swift` will be placed at the top level of `Classes/` (same level as `BiometricCipherPlugin.swift` and `AppConstants.swift`), not inside a subdirectory. No subdirectory (`Handlers/`) exists yet, and the phase spec places it directly at `darwin/Classes/ScreenLockStreamHandler.swift`.

### Android reference implementation

`packages/biometric_cipher/android/src/main/kotlin/.../handlers/ScreenLockStreamHandler.kt` provides the structural pattern:
- Stores `eventSink` / `events` reference on `onListen`, nulls it on `onCancel`.
- Registers the system observer in `onListen`, unregisters in `onCancel`.
- Sends `true` (boolean) via the sink when the lock event fires.

The Swift implementation mirrors this structure with `FlutterStreamHandler` (iOS/macOS) instead of `EventChannel.StreamHandler` (Android).

### Android plugin registration pattern

`BiometricCipherPlugin.kt` shows what Phase 3 replicates on the Darwin side — creates an `EventChannel` locally, calls `setStreamHandler`, and stores refs as instance fields. The Darwin version does **not** need instance fields because `register(with:)` is `static` and the channel retains the handler.

---

## Current Endpoints and Contracts

The EventChannel name `"biometric_cipher/screen_lock"` is already established on the Dart side (Phase 1). The Dart consumer listens for boolean `true` values on this channel; the handler must call `eventSink?(true)` when a lock event fires.

No change to the existing MethodChannel `"biometric_cipher"` or its methods.

---

## Patterns Used

### `FlutterStreamHandler` protocol

Requires two methods:
```swift
func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError?
func onCancel(withArguments arguments: Any?) -> FlutterError?
```

The `@escaping FlutterEventSink` closure is stored as an instance property and called with event values. Both methods return `FlutterError?` — return `nil` for success.

### Import pattern for shared darwin code

`BiometricCipherPlugin.swift` uses:
```swift
#if os(iOS)
import Flutter
#elseif os(macOS)
import Cocoa
import FlutterMacOS
#endif
```

`ScreenLockStreamHandler.swift` needs the platform-specific notification APIs:
- iOS: `import UIKit` (for `UIApplication.protectedDataWillBecomeUnavailableNotification`)
- macOS: `import AppKit` (for `DistributedNotificationCenter`)
- Both need the Flutter import for `FlutterStreamHandler` and `FlutterEventSink`.

### Notification center pattern

iOS uses `NotificationCenter.default` (app-local, main bundle only).  
macOS uses `DistributedNotificationCenter.default()` (system-wide, required for `com.apple.screenIsLocked`).

The observer/selector pattern (`addObserver(_:selector:name:object:)`) is standard Objective-C bridging compatible with `@objc` Swift methods.

### `NSObject` subclass requirement

The `addObserver(_:selector:name:object:)` API requires the observer to be an `NSObject` subclass so that `#selector(...)` can be used. All existing plugin classes (`BiometricCipherPlugin`, managers, services) inherit from `NSObject`. `ScreenLockStreamHandler` must do the same.

---

## Build / Project Structure

### Podspec — shared darwin

`packages/biometric_cipher/darwin/biometric_cipher.podspec` is the canonical podspec used by both iOS and macOS targets:
```ruby
s.source_files = 'Classes/**/*'
s.ios.dependency 'Flutter'
s.osx.dependency 'FlutterMacOS'
s.ios.deployment_target = '12.0'
s.osx.deployment_target = '10.14'
s.swift_version = '5.0'
```

`source_files = 'Classes/**/*'` — any `.swift` file placed anywhere inside `darwin/Classes/` is automatically included. No podspec modification is needed.

The platform-specific podspecs (`ios/biometric_cipher.podspec`, `macos/biometric_cipher.podspec`) point to their own `Classes/` directories (these appear to be older/separate paths that symlink or duplicate the darwin directory). The shared `darwin/` tree is what matters for the unified build.

### Xcode workspaces for manual verification

```
packages/biometric_cipher/example/ios/Runner.xcworkspace
packages/biometric_cipher/example/macos/Runner.xcworkspace
```

### Acceptance build command

```bash
cd example && fvm flutter build macos --debug
```

---

## Phase-Specific Limitations and Risks

1. **`registrar.messenger` vs `registrar.messenger()` divergence is load-bearing.** Getting this wrong compiles on one platform but fails on the other. The existing `FlutterMethodChannel` lines 26–28 of `BiometricCipherPlugin.swift` are the reference — copy that pattern exactly for the `FlutterEventChannel`.

2. **`DistributedNotificationCenter` entitlement on macOS Sandbox.** The macOS App Sandbox may restrict listening to certain distributed notifications. `com.apple.screenIsLocked` is a well-known notification and is generally observable without special entitlements in sandboxed apps, but this should be verified during the build/manual test phase. If the notification does not fire in a sandboxed build, an entitlement addition may be required.

3. **`removeObserver(self)` scope.** On iOS, `NotificationCenter.default.removeObserver(self)` removes all observers registered by `self`, which is correct here because only one observer is added. On macOS, `DistributedNotificationCenter.default().removeObserver(self)` behaves the same way. If in future a second observer is added to the same handler, this broad removal should be narrowed to remove by name.

4. **Thread safety of `eventSink`.** `onListen` and `onCancel` are called on the platform's main thread by Flutter. The notification callbacks (`onScreenLocked`) are delivered on the thread the notification was posted from. For `DistributedNotificationCenter`, delivery is typically on the main thread when not suspended. For `NotificationCenter`, delivery matches the poster's thread. If there is any doubt, the `eventSink?(true)` call should be dispatched to the main thread via `DispatchQueue.main.async`. The phase spec does not currently require this guard, but it is a low-risk addition.

5. **No `ScreenLockStreamHandler` in existing darwin `Classes/`.** The file does not exist yet. No risk of naming conflict.

6. **Xcode does not require manual file registration.** Because the podspec uses `Classes/**/*`, dropped-in `.swift` files are picked up automatically by CocoaPods. No `.xcodeproj` manual group/reference addition is needed.

---

## New Technical Questions

None discovered during research. All implementation details are clear from the existing code and the user's answers.
