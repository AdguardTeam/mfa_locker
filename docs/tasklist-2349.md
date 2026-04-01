# Tasklist: Lock Application on Device Screen Lock (AW-2349)

Companion to: `docs/idea-2349.md`, `docs/vision-2349.md`

---

## Progress Report

| # | Iteration | Status | Notes |
|---|-----------|--------|-------|
| 1 | Dart plugin: `screenLockStream` | :green_circle: Done | |
| 2 | Android: `ScreenLockStreamHandler` | :green_circle: Done | |
| 3 | iOS/macOS: `ScreenLockStreamHandler` | :white_circle: Pending | |
| 4 | Windows: `ScreenLockStreamHandler` | :white_circle: Pending | |
| 5 | Plugin tests | :white_circle: Pending | |
| 6 | Example app: `ScreenLockService` | :white_circle: Pending | |
| 7 | Example app: DI wiring + event | :white_circle: Pending | |
| 8 | Example app: BLoC integration | :white_circle: Pending | |
**Current Phase:** 2

---

## Iteration 1 — Dart plugin: `screenLockStream`

**Goal:** Add `screenLockStream` getter through the Dart plugin layer — platform interface, method channel, and public API.

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

**Verify:** `cd packages/biometric_cipher && fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .`

---

## Iteration 2 — Android: `ScreenLockStreamHandler`

**Goal:** Detect `ACTION_SCREEN_OFF` via `BroadcastReceiver` and push events through EventChannel.

- [x] **2.1** Create `ScreenLockStreamHandler`
  - File: new — `packages/biometric_cipher/android/src/main/kotlin/com/adguard/cryptowallet/biometric_cipher/handlers/ScreenLockStreamHandler.kt`
  - `BroadcastReceiver` for `ACTION_SCREEN_OFF`, registered with application context
  - `onListen`: register receiver, `onCancel`: unregister receiver

- [x] **2.2** Register EventChannel in `BiometricCipherPlugin.onAttachedToEngine`
  - File: `packages/biometric_cipher/android/src/main/kotlin/com/adguard/cryptowallet/biometric_cipher/BiometricCipherPlugin.kt`
  - Create `EventChannel("biometric_cipher/screen_lock")`, set stream handler
  - Store references as class fields

- [x] **2.3** Clean up in `onDetachedFromEngine`
  - Same file — set stream handler to null, nullify references

**Verify:** `cd example && fvm flutter build apk --debug`

---

## Iteration 3 — iOS/macOS: `ScreenLockStreamHandler`

**Goal:** Detect screen lock via platform-specific notifications — `protectedDataWillBecomeUnavailable` (iOS) and `com.apple.screenIsLocked` (macOS).

- [ ] **3.1** Create `ScreenLockStreamHandler`
  - File: new — `packages/biometric_cipher/darwin/Classes/ScreenLockStreamHandler.swift`
  - `FlutterStreamHandler` with `#if os(iOS)` / `#elseif os(macOS)` guards
  - iOS: `NotificationCenter` + `protectedDataWillBecomeUnavailableNotification`
  - macOS: `DistributedNotificationCenter` + `com.apple.screenIsLocked`
  - `onListen`: add observer, `onCancel`: remove observer

- [ ] **3.2** Register EventChannel in `BiometricCipherPlugin.register(with:)`
  - File: `packages/biometric_cipher/darwin/Classes/BiometricCipherPlugin.swift`
  - Create `FlutterEventChannel(name: "biometric_cipher/screen_lock")`, set stream handler

**Verify:** `cd example && fvm flutter build macos --debug`

---

## Iteration 4 — Windows: `ScreenLockStreamHandler`

**Goal:** Detect session lock via `WTSRegisterSessionNotification` + `WM_WTSSESSION_CHANGE` / `WTS_SESSION_LOCK`.

- [ ] **4.1** Create `ScreenLockStreamHandler` header
  - File: new — `packages/biometric_cipher/windows/include/biometric_cipher/handlers/screen_lock_stream_handler.h`
  - Class with `CreateStreamHandler()`, window proc delegate, register/unregister

- [ ] **4.2** Create `ScreenLockStreamHandler` implementation
  - File: new — `packages/biometric_cipher/windows/handlers/screen_lock_stream_handler.cpp`
  - `RegisterWindowProc`: `WTSRegisterSessionNotification` + `RegisterTopLevelWindowProcDelegate`
  - `HandleWindowMessage`: check `WM_WTSSESSION_CHANGE` + `WTS_SESSION_LOCK`

- [ ] **4.3** Register EventChannel in `BiometricCipherPlugin::RegisterWithRegistrar`
  - File: `packages/biometric_cipher/windows/biometric_cipher_plugin.cpp`
  - Create EventChannel, set stream handler, store in plugin instance

- [ ] **4.4** Add `screen_lock_handler_` member to plugin header
  - File: `packages/biometric_cipher/windows/include/biometric_cipher/biometric_cipher_plugin.h`

- [ ] **4.5** Update CMakeLists.txt
  - File: `packages/biometric_cipher/windows/CMakeLists.txt`
  - Add `handlers/screen_lock_stream_handler.cpp` to sources
  - Link `Wtsapi32` library

**Verify:** `cd example && fvm flutter build windows --debug` (Windows only)

---

## Iteration 5 — Plugin tests

**Goal:** Unit tests for `screenLockStream` in the Dart plugin layer.

- [ ] **5.1** Add `screenLockStream` to mock platform
  - File: `packages/biometric_cipher/test/mock_biometric_cipher_platform.dart`
  - Add `StreamController<bool>` and override `screenLockStream`

- [ ] **5.2** Add `screenLockStream` test group
  - File: `packages/biometric_cipher/test/biometric_cipher_test.dart`
  - Test: emits events from platform stream
  - Test: default platform returns empty stream

**Verify:** `cd packages/biometric_cipher && fvm flutter test`

---

## Iteration 6 — Example app: `ScreenLockService`

**Goal:** Create `ScreenLockService` wrapping the platform stream — mirrors `TimerService` pattern.

- [ ] **6.1** Create `ScreenLockService` interface and implementation
  - File: new — `example/lib/core/services/screen_lock_service.dart`
  - Abstract: `onScreenLockedCallback` setter, `startListening()`, `stopListening()`, `dispose()`
  - Impl: subscribes to `BiometricCipher.screenLockStream`, invokes callback on event

**Verify:** `cd example && fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .`

---

## Iteration 7 — Example app: DI wiring + event

**Goal:** Wire `ScreenLockService` through DI and add `screenLocked` Freezed event.

- [ ] **7.1** Add `ScreenLockService` to `RepositoryFactory`
  - File: `example/lib/di/factories/repository_factory.dart`
  - Create in `init()`, expose via getter, dispose in `dispose()`

- [ ] **7.2** Pass `ScreenLockService` through `BlocFactory`
  - File: `example/lib/di/factories/bloc_factory.dart`
  - Add constructor parameter, pass to `LockerBloc`

- [ ] **7.3** Wire in `main.dart`
  - File: `example/lib/main.dart`
  - Pass `repositoryFactory.screenLockService` to `BlocFactoryImpl`

- [ ] **7.4** Add `screenLocked` event
  - File: `example/lib/features/locker/bloc/locker_event.dart`
  - Add `const factory LockerEvent.screenLocked() = _ScreenLocked;`

- [ ] **7.5** Run code generation
  - `cd example && make g`

**Verify:** `cd example && fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .`

---

## Iteration 8 — Example app: BLoC integration

**Goal:** Wire `ScreenLockService` into `LockerBloc` — detect screen lock, lock immediately, bypass biometric guard.

- [ ] **8.1** Add `ScreenLockService` field and constructor parameter
  - File: `example/lib/features/locker/bloc/locker_bloc.dart`
  - Inject service, register `on<_ScreenLocked>` handler, set callback

- [ ] **8.2** Implement `_onScreenLockDetected` callback and `_onScreenLocked` handler
  - Same file — callback adds event if unlocked; handler calls `_lockerRepository.lock()`
  - Bypasses `BiometricOperationState` guard (physical lock = unconditional)

- [ ] **8.3** Start/stop listening on state transitions
  - Same file — `startListening()` where `_timerService.startTimer()` is called
  - `stopListening()` where `_timerService.stopTimer()` is called

- [ ] **8.4** Dispose in `close()`
  - Same file — `_screenLockService.dispose()` alongside timer cleanup

**Verify:** `cd example && fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .`

---

## Files Affected

### New files (5)

| File | Iteration |
|------|-----------|
| `packages/biometric_cipher/android/…/handlers/ScreenLockStreamHandler.kt` | 2 |
| `packages/biometric_cipher/darwin/Classes/ScreenLockStreamHandler.swift` | 3 |
| `packages/biometric_cipher/windows/include/…/handlers/screen_lock_stream_handler.h` | 4 |
| `packages/biometric_cipher/windows/handlers/screen_lock_stream_handler.cpp` | 4 |
| `example/lib/core/services/screen_lock_service.dart` | 6 |

### Modified files (15)

| File | Iteration |
|------|-----------|
| `packages/biometric_cipher/lib/biometric_cipher_platform_interface.dart` | 1 |
| `packages/biometric_cipher/lib/biometric_cipher_method_channel.dart` | 1 |
| `packages/biometric_cipher/lib/biometric_cipher.dart` | 1 |
| `packages/biometric_cipher/android/…/BiometricCipherPlugin.kt` | 2 |
| `packages/biometric_cipher/darwin/Classes/BiometricCipherPlugin.swift` | 3 |
| `packages/biometric_cipher/windows/biometric_cipher_plugin.cpp` | 4 |
| `packages/biometric_cipher/windows/include/…/biometric_cipher_plugin.h` | 4 |
| `packages/biometric_cipher/windows/CMakeLists.txt` | 4 |
| `packages/biometric_cipher/test/mock_biometric_cipher_platform.dart` | 5 |
| `packages/biometric_cipher/test/biometric_cipher_test.dart` | 5 |
| `example/lib/di/factories/repository_factory.dart` | 7 |
| `example/lib/di/factories/bloc_factory.dart` | 7 |
| `example/lib/main.dart` | 7 |
| `example/lib/features/locker/bloc/locker_event.dart` | 7 |
| `example/lib/features/locker/bloc/locker_bloc.dart` | 8 |
