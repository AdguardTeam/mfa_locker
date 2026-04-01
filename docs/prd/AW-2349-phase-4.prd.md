# AW-2349-phase-4: Screen Lock Detection — Windows Native Handler (`ScreenLockStreamHandler`)

Status: PRD_READY

## Context / Idea

MFA spec Section 8 requires: "if the device is locked (lock screen) → lock immediately." The full feature (AW-2349) adds native screen lock detection across Android, iOS, macOS, and Windows by extending the `biometric_cipher` plugin with an `EventChannel("biometric_cipher/screen_lock")`.

The implementation is split into sequential phases:

- Phase 1 (complete): Dart plugin layer — `screenLockStream` API surface established on `BiometricCipherPlatform`, `MethodChannelBiometricCipher`, and `BiometricCipher`.
- Phase 2 (complete): Android native handler — `ScreenLockStreamHandler.kt` with `BroadcastReceiver` for `ACTION_SCREEN_OFF`, registered in `BiometricCipherPlugin.kt`.
- Phase 3 (complete): iOS/macOS native handler — `ScreenLockStreamHandler.swift` shared via `darwin/Classes/` using `#if os(iOS)` / `#elseif os(macOS)` compile-time guards, registered in `BiometricCipherPlugin.swift`.
- **Phase 4 (this phase):** Windows native handler — `ScreenLockStreamHandler` in C++ using WTS session notifications, registered in `BiometricCipherPlugin::RegisterWithRegistrar`.
- Phase 5: Example app wiring (`ScreenLockService`, DI, `LockerBloc` integration).

Phase 4 is a pure C++ change inside `packages/biometric_cipher/windows/`. It delivers the Windows side of the `EventChannel` contract established in Phase 1. The Dart subscription already exists; Phase 4 makes it emit events on Windows when the user locks their session.

### Windows detection mechanism

| Platform | Signal | API | Prompt shown? |
|----------|--------|-----|---------------|
| Windows | Session locked | `WTSRegisterSessionNotification` + `WM_WTSSESSION_CHANGE` / `WTS_SESSION_LOCK` | No |

**How it works:** The plugin registers a session notification listener on the Flutter window HWND using `WTSRegisterSessionNotification(hwnd, NOTIFY_FOR_THIS_SESSION)`. It hooks into the window procedure via `RegisterTopLevelWindowProcDelegate` to intercept `WM_WTSSESSION_CHANGE` messages. When `wParam == WTS_SESSION_LOCK`, the handler pushes `true` through the `EventSink`. Cleanup calls `WTSUnRegisterSessionNotification` and `UnregisterTopLevelWindowProcDelegate`.

### Structural notes (observed from current codebase)

The existing `biometric_cipher_plugin.h` lives at `packages/biometric_cipher/windows/biometric_cipher_plugin.h` (not under `include/biometric_cipher/`). The current `BiometricCipherPlugin::RegisterWithRegistrar` creates the plugin via default constructor and does not store the registrar pointer. The `ScreenLockStreamHandler` is therefore constructed in `RegisterWithRegistrar` (where the registrar is available) and assigned directly to the plugin's `screen_lock_handler_` public member field after construction, before `AddPlugin` is called. This matches the spec and avoids any need for a constructor refactor or setter.

The spec describes the header at `packages/biometric_cipher/windows/include/biometric_cipher/handlers/screen_lock_stream_handler.h` and the implementation at `packages/biometric_cipher/windows/handlers/screen_lock_stream_handler.cpp`, mirroring the existing `include/biometric_cipher/` directory layout for other plugin components. This is consistent with the existing pattern where headers live under `include/biometric_cipher/` and source files at the `windows/` root.

### Affected files (Phase 4 only)

| File | Change |
|------|--------|
| `packages/biometric_cipher/windows/include/biometric_cipher/handlers/screen_lock_stream_handler.h` | New file — `ScreenLockStreamHandler` class declaration |
| `packages/biometric_cipher/windows/handlers/screen_lock_stream_handler.cpp` | New file — `ScreenLockStreamHandler` implementation |
| `packages/biometric_cipher/windows/biometric_cipher_plugin.cpp` | Register `EventChannel("biometric_cipher/screen_lock")` in `RegisterWithRegistrar`; construct handler and assign to `plugin->screen_lock_handler_` |
| `packages/biometric_cipher/windows/biometric_cipher_plugin.h` | Add `screen_lock_handler_` public member field to `BiometricCipherPlugin` |
| `packages/biometric_cipher/windows/CMakeLists.txt` | Add `handlers/screen_lock_stream_handler.cpp` to `PLUGIN_SOURCES`; add `target_link_libraries(${PLUGIN_NAME} PRIVATE Wtsapi32)` |

---

## Goals

1. Create `screen_lock_stream_handler.h` in `packages/biometric_cipher/windows/include/biometric_cipher/handlers/` declaring the `ScreenLockStreamHandler` class with `CreateStreamHandler()`, window proc delegate fields, and `RegisterWindowProc()` / `UnregisterWindowProc()` private methods.
2. Create `screen_lock_stream_handler.cpp` in `packages/biometric_cipher/windows/handlers/` implementing:
   - `RegisterWindowProc`: calls `WTSRegisterSessionNotification(hwnd, NOTIFY_FOR_THIS_SESSION)` and `RegisterTopLevelWindowProcDelegate`.
   - `UnregisterWindowProc`: calls `WTSUnRegisterSessionNotification` and `UnregisterTopLevelWindowProcDelegate` when `window_proc_delegate_id_ >= 0`.
   - `HandleWindowMessage`: checks `WM_WTSSESSION_CHANGE` + `WTS_SESSION_LOCK`; checks `if (event_sink_)` before calling `event_sink_->Success(flutter::EncodableValue(true))`.
   - `CreateStreamHandler`: returns a `StreamHandlerFunctions` that calls `RegisterWindowProc` in `onListen` and `UnregisterWindowProc` in `onCancel`.
3. Register the `EventChannel("biometric_cipher/screen_lock")` in `BiometricCipherPlugin::RegisterWithRegistrar`, constructing the `ScreenLockStreamHandler` and assigning it to `plugin->screen_lock_handler_` before `AddPlugin`.
4. Add `screen_lock_handler_` as a public member field to `BiometricCipherPlugin` in `biometric_cipher_plugin.h` to keep ownership within the plugin lifetime.
5. Add `handlers/screen_lock_stream_handler.cpp` to `PLUGIN_SOURCES` in `CMakeLists.txt` and link `Wtsapi32` via `target_link_libraries(${PLUGIN_NAME} PRIVATE Wtsapi32)`.
6. Pass `cd example && fvm flutter build windows --debug` (Windows only) with no build errors or warnings related to this change.

---

## User Stories

**As a library consumer on Windows**, I want `BiometricCipher.screenLockStream` to emit `true` when the user locks their Windows session (Win+L, auto-lock, display sleep with lock), so that `ScreenLockService` can trigger an immediate locker lock without polling.

**As a native plugin maintainer**, I want the Windows handler to follow the same `handlers/` subdirectory pattern established by the other platform implementations, so that the codebase is consistent and navigable.

**As a plugin lifecycle owner**, I want `WTSUnRegisterSessionNotification` and `UnregisterTopLevelWindowProcDelegate` called deterministically in the destructor and in `onCancel`, so that no window proc delegate or WTS listener outlives its intended scope.

---

## Main Scenarios

### Scenario 1 — Windows session lock while app is in foreground
- Locker is in `unlocked` state; the native subscription is active (Phase 5 will start it on unlock).
- User locks the session (Win+L, screen timeout with lock, or equivalent).
- Windows delivers `WM_WTSSESSION_CHANGE` with `wParam == WTS_SESSION_LOCK` to the Flutter window procedure.
- The registered `TopLevelWindowProcDelegate` fires `HandleWindowMessage`.
- `event_sink_` is non-null; `event_sink_->Success(flutter::EncodableValue(true))` is called.
- The Dart `screenLockStream` emits `true`.
- (Phase 5 concern, but verifiable end-to-end) `ScreenLockService` triggers `LockerBloc` to lock.

### Scenario 2 — Dart subscription cancelled and resumed
- Dart side cancels the `screenLockStream` subscription.
- `onCancel` fires: `UnregisterWindowProc()` is called; `event_sink_` is set to `nullptr`; `window_proc_delegate_id_` is reset to `-1`.
- No events can be delivered after cancellation.
- Dart side subscribes again.
- `onListen` fires: `event_sink_` is set; `RegisterWindowProc()` is called.
- Next session lock event is delivered correctly.

### Scenario 3 — Plugin destruction without explicit cancel
- `BiometricCipherPlugin` is destroyed (e.g., engine shutdown).
- `ScreenLockStreamHandler` destructor calls `UnregisterWindowProc()`.
- `window_proc_delegate_id_ >= 0` guard prevents double-unregistration if `onCancel` was already called.
- No resource leak.

### Scenario 4 — Session unlock (WTS_SESSION_UNLOCK) received
- User unlocks the session; `WM_WTSSESSION_CHANGE` arrives with `wParam == WTS_SESSION_UNLOCK`.
- `HandleWindowMessage` checks `wParam == WTS_SESSION_LOCK` — condition is false.
- No event emitted. The handler returns `std::nullopt`, allowing other delegates to process the message.

### Scenario 5 — App in background / minimised at time of lock
- App window exists but is minimised; Flutter engine may be paused.
- Windows still delivers `WM_WTSSESSION_CHANGE` to the window's message queue.
- Whether the Dart event is delivered depends on Flutter engine state.
- Acceptable: the existing `shouldLockOnResume` mechanism in `TimerService` handles missed events on next resume (Phase 1 context).

### Scenario 6 — Multiple rapid lock/unlock cycles
- User rapidly locks and unlocks the session.
- Multiple `WTS_SESSION_LOCK` messages may arrive.
- First event locks the Dart side; subsequent events: `event_sink_` may still be non-null if `onCancel` has not yet fired.
- Events delivered; Dart-side `MFALocker.lock()` is idempotent (already locked — no-op).

---

## Success / Metrics

| Criterion | How verified |
|-----------|-------------|
| `screen_lock_stream_handler.h` created at `windows/include/biometric_cipher/handlers/` | File present at expected path |
| `screen_lock_stream_handler.cpp` created at `windows/handlers/` | File present at expected path |
| `handlers/` subdirectories created under both `windows/` and `windows/include/biometric_cipher/` | Directory structure |
| Windows debug build compiles without error | `cd example && fvm flutter build windows --debug` |
| `BiometricCipherPlugin::RegisterWithRegistrar` registers `EventChannel("biometric_cipher/screen_lock")` | Code review |
| `ScreenLockStreamHandler` constructed in `RegisterWithRegistrar` and assigned to `plugin->screen_lock_handler_` | Code review |
| `screen_lock_handler_` is a public member field in `BiometricCipherPlugin` | Code review |
| `WTSRegisterSessionNotification` called with `NOTIFY_FOR_THIS_SESSION` in `RegisterWindowProc` | Code review |
| `WTSUnRegisterSessionNotification` called in `UnregisterWindowProc` | Code review |
| `window_proc_delegate_id_` sentinel (`-1`) used correctly; guarded in `UnregisterWindowProc` | Code review |
| `if (event_sink_)` check present in `HandleWindowMessage` before calling `Success` | Code review |
| `std::nullopt` returned from window proc delegate to pass message to other handlers | Code review |
| `Wtsapi32` linked via `target_link_libraries(${PLUGIN_NAME} PRIVATE Wtsapi32)` in `CMakeLists.txt` | Code review |
| `handlers/screen_lock_stream_handler.cpp` added to `PLUGIN_SOURCES` in `CMakeLists.txt` | Code review |
| Session lock event emitted on Windows (< 2 seconds latency) | Manual test: lock session, observe Dart stream (end-to-end once Phase 5 complete) |
| No changes outside `packages/biometric_cipher/windows/` | Diff scope |

---

## Constraints and Assumptions

- **Windows-only scope:** Phase 4 touches only `packages/biometric_cipher/windows/`. No Dart changes, no Android, iOS, or macOS changes.
- **`flutter::PluginRegistrarWindows*` availability:** The registrar passed to `RegisterWithRegistrar` is already typed as `flutter::PluginRegistrarWindows*` in the existing code — no cast is needed.
- **Header location:** The new header follows the existing pattern: `windows/include/biometric_cipher/handlers/screen_lock_stream_handler.h`. The `handlers/` subdirectory under both `windows/handlers/` and `windows/include/biometric_cipher/handlers/` is new and must be created.
- **Plugin constructor ownership pattern (resolved):** The `ScreenLockStreamHandler` is constructed in `RegisterWithRegistrar` and assigned directly to `plugin->screen_lock_handler_` (public member field) after the plugin is constructed and before `AddPlugin` is called. This matches the spec without requiring a constructor refactor or setter.
- **`Wtsapi32` linking (resolved):** `target_link_libraries(${PLUGIN_NAME} PRIVATE Wtsapi32)` is the required approach, consistent with the existing CMake-based build system. `#pragma comment(lib, "Wtsapi32.lib")` is not used.
- **`GetView()` null guard (resolved):** No null guard is needed in `RegisterWindowProc`. `onListen` only fires after the Flutter engine is fully initialized, so `GetView()` is guaranteed non-null.
- **`event_sink_` check in `HandleWindowMessage` (resolved):** The `if (event_sink_)` check is retained as a defensive guard. It matches the spec code and prevents any potential null dereference from unexpected call order.
- **`WM_WTSSESSION_CHANGE` requires `#include <wtsapi32.h>`:** This header defines `WTS_SESSION_LOCK`, `WTS_SESSION_UNLOCK`, and related constants, in addition to the `WTSRegisterSessionNotification` function prototype.
- **`std::optional<LRESULT>` return type:** `RegisterTopLevelWindowProcDelegate` expects a delegate returning `std::optional<LRESULT>`. Returning `std::nullopt` allows subsequent delegates and the default proc to handle the message; returning a value short-circuits further processing.
- **Main-thread delivery:** `WM_WTSSESSION_CHANGE` is delivered on the message pump thread, which is the Flutter main thread on Windows. No thread marshalling is needed before calling `event_sink_->Success(...)`.
- **`window_proc_delegate_id_` initialised to `-1`:** Serves as a sentinel for "not registered". `UnregisterWindowProc` guards on `>= 0` to prevent calling `UnregisterTopLevelWindowProcDelegate` with an invalid id.
- **No C++ unit tests for `ScreenLockStreamHandler`:** WTS registration requires a real Windows session and HWND. Unit testing via Google Test is impractical; acceptance is via Windows debug build and manual session lock test.
- **`RegisterTopLevelWindowProcDelegate` lambda capture:** The lambda captures `this`. The `ScreenLockStreamHandler` instance is owned by `BiometricCipherPlugin` and lives as long as the plugin. As long as `UnregisterTopLevelWindowProcDelegate` is called before destruction (enforced by the destructor), the capture is safe.

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Plugin header location mismatch: spec references `include/biometric_cipher/biometric_cipher_plugin.h` but actual file is at `windows/biometric_cipher_plugin.h` | Known | Medium | The `screen_lock_handler_` member must be added to the actual header at `windows/biometric_cipher_plugin.h`. The include path in `screen_lock_stream_handler.h` need not reference the plugin header at all. |
| Double-unregistration if `onCancel` fires and then destructor fires | Low | Low | `window_proc_delegate_id_ >= 0` guard in `UnregisterWindowProc` prevents double-unregistration. |
| `WM_WTSSESSION_CHANGE` not received for Fast User Switching (different session) | Low | Low | `NOTIFY_FOR_THIS_SESSION` only notifies for the current session's events. This is the desired behavior — only lock when the current user's session is locked, not when another user logs in. |
| `Wtsapi32.lib` not available in the build environment | Very Low | High | `Wtsapi32` is a standard Windows SDK library available in all supported Visual Studio versions. No additional install required. |

---

## Resolved Questions

1. **Plugin constructor ownership pattern:** `screen_lock_handler_` is a public member field on `BiometricCipherPlugin`. The handler is constructed in `RegisterWithRegistrar` and assigned directly via `plugin->screen_lock_handler_` after plugin construction, before `AddPlugin` is called. No constructor refactor or setter is needed.

2. **`Wtsapi32` linking:** `target_link_libraries(${PLUGIN_NAME} PRIVATE Wtsapi32)` in `CMakeLists.txt` is the required approach, consistent with the existing CMake-based build system.

3. **`GetView()` null guard:** No guard is needed. `onListen` only fires after the Flutter engine is fully initialized, so `GetView()` is guaranteed non-null at that point.

4. **`event_sink_` check in `HandleWindowMessage`:** The `if (event_sink_)` check is retained as a defensive pattern. It matches the spec code and is a safe, low-cost guard.

---

## Open Questions

None.
