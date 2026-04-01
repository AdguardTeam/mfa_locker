# AW-2349 Phase 4 Plan: Windows -- `ScreenLockStreamHandler`

**Status:** PLAN_APPROVED

## Phase Scope

Phase 4 delivers the Windows native side of the `EventChannel("biometric_cipher/screen_lock")` contract. It creates two new C++ files (header + implementation) and modifies three existing files in `packages/biometric_cipher/windows/`.

The Dart-side `EventChannel` wiring was completed in Phase 1. Android native handler was completed in Phase 2. iOS/macOS native handler was completed in Phase 3. This phase adds the Windows handler so that `BiometricCipher.screenLockStream` emits events on Windows when the user locks their session.

All changes are scoped to `packages/biometric_cipher/windows/`. No Dart, Android, iOS, or macOS changes.

## Components

### 1. `ScreenLockStreamHandler` (new)

**Header:** `packages/biometric_cipher/windows/include/biometric_cipher/handlers/screen_lock_stream_handler.h`
**Implementation:** `packages/biometric_cipher/windows/handlers/screen_lock_stream_handler.cpp`

A C++ class that detects Windows session lock events via `WTSRegisterSessionNotification` + `WM_WTSSESSION_CHANGE` and forwards them through the Flutter `EventChannel` sink.

**Class interface:**

- `explicit ScreenLockStreamHandler(flutter::PluginRegistrarWindows* registrar)` -- stores registrar pointer for HWND and window proc delegate access.
- `~ScreenLockStreamHandler()` -- calls `UnregisterWindowProc()` for deterministic cleanup.
- `CreateStreamHandler()` -- returns a `std::unique_ptr<flutter::StreamHandler<flutter::EncodableValue>>` wrapping `StreamHandlerFunctions` with `onListen` and `onCancel` lambdas that capture `this`.

**Private members:**

- `flutter::PluginRegistrarWindows* registrar_` -- non-owning pointer to the registrar (lifetime guaranteed by Flutter engine).
- `std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_` -- set in `onListen`, nulled in `onCancel`.
- `int window_proc_delegate_id_ = -1` -- sentinel for "not registered"; used by `UnregisterWindowProc` guard.

**Private methods:**

- `RegisterWindowProc()` -- calls `WTSRegisterSessionNotification(hwnd, NOTIFY_FOR_THIS_SESSION)` and `RegisterTopLevelWindowProcDelegate` with a lambda that delegates to `HandleWindowMessage`.
- `UnregisterWindowProc()` -- guarded by `window_proc_delegate_id_ >= 0`; calls `WTSUnRegisterSessionNotification(hwnd)` and `UnregisterTopLevelWindowProcDelegate`; resets sentinel to `-1`.
- `HandleWindowMessage(HWND, UINT, WPARAM, LPARAM)` -- checks `message == WM_WTSSESSION_CHANGE && wparam == WTS_SESSION_LOCK`; if true and `event_sink_` is non-null, calls `event_sink_->Success(flutter::EncodableValue(true))`. Returns `std::nullopt` to allow other window proc delegates to process the message.

**Design decisions:**

- **No namespace** -- `ScreenLockStreamHandler` is declared outside `namespace biometric_cipher`, matching the PRD spec. It is still accessible from within the namespace in `biometric_cipher_plugin.cpp` via the included header.
- **`#pragma once`** instead of traditional include guards -- consistent with all existing headers under `include/biometric_cipher/`.
- **No `#pragma comment(lib, "Wtsapi32.lib")`** -- linking is done exclusively via `target_link_libraries` in CMakeLists.txt, per user decision overriding the task doc code sample.
- **`this` capture in lambda** -- safe because `ScreenLockStreamHandler` is owned by `BiometricCipherPlugin` and lives as long as the plugin. `UnregisterTopLevelWindowProcDelegate` is called before destruction (enforced by destructor).
- **No `GetView()` null guard** -- `onListen` only fires after the Flutter engine is fully initialized, so `GetView()` returns a valid pointer.
- **Defensive `if (event_sink_)` check** in `HandleWindowMessage` -- prevents null dereference from unexpected call order, though the guard should never trigger under normal operation.

### 2. `BiometricCipherPlugin` (modified)

**Header:** `packages/biometric_cipher/windows/biometric_cipher_plugin.h`
**Implementation:** `packages/biometric_cipher/windows/biometric_cipher_plugin.cpp`

Changes to the existing plugin class:

- **New public member field** in `biometric_cipher_plugin.h`: `std::unique_ptr<ScreenLockStreamHandler> screen_lock_handler_`. This is public because `RegisterWithRegistrar` is a static method that needs to assign to `plugin->screen_lock_handler_` after construction. All existing member fields are private; this intentionally breaks that convention to avoid a constructor refactor (per PRD rationale).
- **New include** in `biometric_cipher_plugin.h`: `#include "include/biometric_cipher/handlers/screen_lock_stream_handler.h"`.
- **EventChannel registration** in `RegisterWithRegistrar` in `biometric_cipher_plugin.cpp`: constructs `ScreenLockStreamHandler`, creates `EventChannel`, sets stream handler, assigns handler to `plugin->screen_lock_handler_` -- all before `registrar->AddPlugin(std::move(plugin))`.

The registration code is inserted between `plugin` construction (line 41) and `registrar->AddPlugin(std::move(plugin))` (line 48). The `registrar` parameter is already typed as `flutter::PluginRegistrarWindows*` -- no cast needed.

### 3. `CMakeLists.txt` (modified)

**File:** `packages/biometric_cipher/windows/CMakeLists.txt`

Two changes:

- Add `"handlers/screen_lock_stream_handler.cpp"` to `PLUGIN_SOURCES` list (after line 80, before the closing parenthesis on line 81). This uses a subdirectory prefix because the file does not live at the `windows/` root.
- Add `target_link_libraries(${PLUGIN_NAME} PRIVATE Wtsapi32)` after the existing `target_link_libraries` block (after line 112). `Wtsapi32` is a standard Windows SDK library.

Note: `Wtsapi32` must also be linked for the test runner if the test sources compile against `PLUGIN_SOURCES`. Since `screen_lock_stream_handler.cpp` includes `<wtsapi32.h>`, the test runner link step (line 163) must also include `Wtsapi32`. Add it to the existing `target_link_libraries(${TEST_RUNNER} PRIVATE windowsapp ncrypt)` line.

## API Contract

### EventChannel (unchanged from Phase 1)

| Property | Value |
|----------|-------|
| Channel name | `"biometric_cipher/screen_lock"` |
| Payload type | `bool` |
| Semantics | `true` = device session locked |
| Direction | Native to Dart (one-way) |

### Windows detection mechanism (new in Phase 4)

| Component | Value |
|-----------|-------|
| Registration API | `WTSRegisterSessionNotification(hwnd, NOTIFY_FOR_THIS_SESSION)` |
| Window message | `WM_WTSSESSION_CHANGE` |
| Lock signal | `wParam == WTS_SESSION_LOCK` |
| Unlock signal | Ignored (`WTS_SESSION_UNLOCK` -- not forwarded) |

### Public API surface

No new public API in Phase 4. The Dart-side API was established in Phase 1. This phase provides the native backing that causes the API to emit events on Windows.

## Data Flows

```
Windows OS locks session (Win+L, auto-lock, display sleep with lock)
    |
    v
WM_WTSSESSION_CHANGE delivered to Flutter window message queue (main thread)
    |
    v
RegisterTopLevelWindowProcDelegate lambda fires HandleWindowMessage()
    |
    v
wParam == WTS_SESSION_LOCK? -- No --> return std::nullopt (pass to other handlers)
    |
    Yes
    v
event_sink_ non-null? -- No --> return std::nullopt (no Dart listener active)
    |
    Yes
    v
event_sink_->Success(flutter::EncodableValue(true))
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

The WTS listener is registered when the Dart side calls `listen()` on the stream (triggers `onListen` -> `RegisterWindowProc`), and unregistered when the subscription is cancelled (triggers `onCancel` -> `UnregisterWindowProc`). No WTS events are processed when no Dart listener is active.

`WM_WTSSESSION_CHANGE` is delivered on the message pump thread, which is the Flutter main thread on Windows. No thread marshalling is needed.

## NFR

| Requirement | How met |
|-------------|---------|
| Zero runtime cost when unused | WTS listener registered only in `onListen`, unregistered in `onCancel`. No polling, no background threads. |
| No resource leaks | `WTSUnRegisterSessionNotification` and `UnregisterTopLevelWindowProcDelegate` called in both `onCancel` and destructor. `window_proc_delegate_id_ >= 0` sentinel prevents double-unregistration. |
| No false positives | Only `WTS_SESSION_LOCK` is forwarded. `WTS_SESSION_UNLOCK`, `WTS_CONSOLE_CONNECT`, and other session change events are ignored. |
| No user-visible prompts | WTS session notification is a silent OS-level hook -- no biometric prompt, no system dialog, no permission request. |
| Deterministic cleanup | Destructor calls `UnregisterWindowProc()` guaranteeing cleanup even if `onCancel` is not called (e.g., engine shutdown). |
| Build system clean | `cd example && fvm flutter build windows --debug` compiles without errors or warnings related to this change. |
| Latency | `WM_WTSSESSION_CHANGE` is delivered synchronously via the message pump. Event reaches Dart within one message pump cycle (< 2 seconds in practice). |

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Plugin header location mismatch: task 4.4 references `include/biometric_cipher/biometric_cipher_plugin.h` but actual file is at `windows/biometric_cipher_plugin.h` | Known | Medium | The `screen_lock_handler_` member and handler include must be added to `windows/biometric_cipher_plugin.h`. Verified by reading the actual file. |
| Include path resolution for `handlers/screen_lock_stream_handler.cpp` | Low | Medium | The `.cpp` file in `windows/handlers/` includes its header as `"include/biometric_cipher/handlers/screen_lock_stream_handler.h"`. CMake adds `CMAKE_CURRENT_SOURCE_DIR` (`windows/`) to the include search path, so the include resolves correctly even from the subdirectory. |
| Double-unregistration if `onCancel` fires and then destructor fires | Low | Low | `window_proc_delegate_id_ >= 0` guard in `UnregisterWindowProc` prevents double-unregistration. After `UnregisterWindowProc`, sentinel is reset to `-1`. |
| `WM_WTSSESSION_CHANGE` not received for Fast User Switching | Low | Low | `NOTIFY_FOR_THIS_SESSION` only notifies for the current session's events. This is the desired behavior. |
| `Wtsapi32.lib` not available in build environment | Very Low | High | `Wtsapi32` is a standard Windows SDK library available in all supported Visual Studio versions. No additional install required. |
| Test runner link failure | Medium | Low | Adding `handlers/screen_lock_stream_handler.cpp` to `PLUGIN_SOURCES` means the test runner also compiles it. The test runner must link `Wtsapi32` to resolve symbols. Add it to the test runner's `target_link_libraries`. |
| App minimized/suspended when session locks | Low | Low | Windows still delivers `WM_WTSSESSION_CHANGE` to the window's message queue. Whether Dart processes it depends on engine state. Existing `shouldLockOnResume` in `TimerService` handles missed events on next resume. |

## Dependencies

- **Phase 1 complete** -- Dart-side `EventChannel` wiring (`screenLockStream` getter on `BiometricCipherPlatform`, `MethodChannelBiometricCipher`, and `BiometricCipher`).
- **Phase 2 complete** -- Android native handler (establishes the EventChannel pattern; not a code dependency).
- **Phase 3 complete** -- iOS/macOS native handler (confirms the multi-platform EventChannel contract).
- **No external dependencies** -- `WTSRegisterSessionNotification`, `WM_WTSSESSION_CHANGE`, `Wtsapi32.lib` are all part of the standard Windows SDK.
- **No Dart changes** -- the Dart `screenLockStream` API already exists and will automatically receive events once the native handler is in place.

## Implementation Order

1. **Create directories** -- `packages/biometric_cipher/windows/handlers/` and `packages/biometric_cipher/windows/include/biometric_cipher/handlers/`
2. **Create `screen_lock_stream_handler.h`** (task 4.1) -- handler class declaration
3. **Create `screen_lock_stream_handler.cpp`** (task 4.2) -- handler implementation (no `#pragma comment`, linking via CMake)
4. **Modify `biometric_cipher_plugin.h`** (task 4.4) -- add include and `screen_lock_handler_` public member field
5. **Modify `biometric_cipher_plugin.cpp`** (task 4.3) -- add include and `EventChannel` + handler registration in `RegisterWithRegistrar`
6. **Modify `CMakeLists.txt`** (task 4.5) -- add source file to `PLUGIN_SOURCES`, link `Wtsapi32` for both plugin and test runner

Steps 2-3 create the new files. Steps 4-5 modify the plugin to wire the handler. Step 6 updates the build system. Build verification requires a Windows machine: `cd example && fvm flutter build windows --debug`.

## Open Questions

None. All design decisions are fully resolved in the PRD and research documents.
