# Iteration 4: Windows — `ScreenLockStreamHandler`

**Goal:** Detect session lock via `WTSRegisterSessionNotification` + `WM_WTSSESSION_CHANGE` / `WTS_SESSION_LOCK`.

## Context

Iteration 3 completed the iOS/macOS native implementation. This iteration provides the Windows C++/WinRT native implementation that pushes events through the same `EventChannel("biometric_cipher/screen_lock")` established in Iteration 1.

To detect session lock on Windows the plugin must:
1. Call `WTSRegisterSessionNotification(hwnd, NOTIFY_FOR_THIS_SESSION)` to subscribe to session change events.
2. Handle `WM_WTSSESSION_CHANGE` window messages with `wParam == WTS_SESSION_LOCK`.

The plugin accesses the window handle via `registrar->GetView()->GetNativeWindow()` and hooks into the window procedure via `RegisterTopLevelWindowProcDelegate`.

Key design points:
- `WTSRegisterSessionNotification` requires a valid HWND — use the Flutter window from the registrar.
- The handler is created in `RegisterWithRegistrar`, stored as a field in the plugin instance to prevent premature destruction.
- `WTSUnRegisterSessionNotification` and `UnregisterTopLevelWindowProcDelegate` are called in the destructor / `onCancel` to clean up resources.
- `#pragma comment(lib, "Wtsapi32.lib")` can be used in the `.cpp` or `Wtsapi32` linked via CMake `target_link_libraries`.
- Returns `std::nullopt` from the window proc delegate to allow other handlers to process the message.

## Tasks

- [x] **4.1** Create `ScreenLockStreamHandler` header
  - File: new — `packages/biometric_cipher/windows/include/biometric_cipher/handlers/screen_lock_stream_handler.h`
  - Class with `CreateStreamHandler()`, window proc delegate, register/unregister

- [x] **4.2** Create `ScreenLockStreamHandler` implementation
  - File: new — `packages/biometric_cipher/windows/handlers/screen_lock_stream_handler.cpp`
  - `RegisterWindowProc`: `WTSRegisterSessionNotification` + `RegisterTopLevelWindowProcDelegate`
  - `HandleWindowMessage`: check `WM_WTSSESSION_CHANGE` + `WTS_SESSION_LOCK`

- [x] **4.3** Register EventChannel in `BiometricCipherPlugin::RegisterWithRegistrar`
  - File: `packages/biometric_cipher/windows/biometric_cipher_plugin.cpp`
  - Create EventChannel, set stream handler, store in plugin instance

- [x] **4.4** Add `screen_lock_handler_` member to plugin header
  - File: `packages/biometric_cipher/windows/include/biometric_cipher/biometric_cipher_plugin.h`

- [x] **4.5** Update CMakeLists.txt
  - File: `packages/biometric_cipher/windows/CMakeLists.txt`
  - Add `handlers/screen_lock_stream_handler.cpp` to sources
  - Link `Wtsapi32` library

## Acceptance Criteria

**Verify:** `cd example && fvm flutter build windows --debug` (Windows only)

Functional criteria:
- On Windows, the locker transitions to `locked` state when `WTS_SESSION_LOCK` is received while the locker is `unlocked`.
- Screen lock detection does **not** trigger a biometric prompt or any user-visible system dialog.
- The native WTS listener is only active when `ScreenLockService.startListening()` has been called (i.e., locker is unlocked).

## Dependencies

- Iteration 1 complete (Dart-side EventChannel wired) ✅
- Iteration 2 complete (Android native handler) ✅
- Iteration 3 complete (iOS/macOS native handler) ✅

## Technical Details

### `screen_lock_stream_handler.h` (new file)

```cpp
#pragma once

#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/plugin_registrar_windows.h>
#include <windows.h>
#include <wtsapi32.h>

class ScreenLockStreamHandler {
public:
    explicit ScreenLockStreamHandler(flutter::PluginRegistrarWindows* registrar);
    ~ScreenLockStreamHandler();

    std::unique_ptr<flutter::StreamHandler<flutter::EncodableValue>> CreateStreamHandler();

private:
    flutter::PluginRegistrarWindows* registrar_;
    std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;
    int window_proc_delegate_id_ = -1;

    std::optional<LRESULT> HandleWindowMessage(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);
    void RegisterWindowProc();
    void UnregisterWindowProc();
};
```

### `screen_lock_stream_handler.cpp` (new file)

```cpp
#include "biometric_cipher/handlers/screen_lock_stream_handler.h"

#pragma comment(lib, "Wtsapi32.lib")

ScreenLockStreamHandler::ScreenLockStreamHandler(
    flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar) {}

ScreenLockStreamHandler::~ScreenLockStreamHandler() {
    UnregisterWindowProc();
}

std::unique_ptr<flutter::StreamHandler<flutter::EncodableValue>>
ScreenLockStreamHandler::CreateStreamHandler() {
    return std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
        // onListen
        [this](const flutter::EncodableValue* arguments,
               std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events)
            -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
            event_sink_ = std::move(events);
            RegisterWindowProc();
            return nullptr;
        },
        // onCancel
        [this](const flutter::EncodableValue* arguments)
            -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
            UnregisterWindowProc();
            event_sink_ = nullptr;
            return nullptr;
        });
}

void ScreenLockStreamHandler::RegisterWindowProc() {
    HWND hwnd = registrar_->GetView()->GetNativeWindow();
    WTSRegisterSessionNotification(hwnd, NOTIFY_FOR_THIS_SESSION);

    window_proc_delegate_id_ = registrar_->RegisterTopLevelWindowProcDelegate(
        [this](HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
            return HandleWindowMessage(hwnd, message, wparam, lparam);
        });
}

void ScreenLockStreamHandler::UnregisterWindowProc() {
    if (window_proc_delegate_id_ >= 0) {
        HWND hwnd = registrar_->GetView()->GetNativeWindow();
        WTSUnRegisterSessionNotification(hwnd);
        registrar_->UnregisterTopLevelWindowProcDelegate(window_proc_delegate_id_);
        window_proc_delegate_id_ = -1;
    }
}

std::optional<LRESULT> ScreenLockStreamHandler::HandleWindowMessage(
    HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
    if (message == WM_WTSSESSION_CHANGE && wparam == WTS_SESSION_LOCK) {
        if (event_sink_) {
            event_sink_->Success(flutter::EncodableValue(true));
        }
    }
    return std::nullopt;  // Let other handlers process the message
}
```

### Changes to `biometric_cipher_plugin.cpp` (task 4.3)

Add include and registration in `RegisterWithRegistrar`:

```cpp
#include "biometric_cipher/handlers/screen_lock_stream_handler.h"

// In RegisterWithRegistrar, after method channel setup:
auto screen_lock_handler = std::make_unique<ScreenLockStreamHandler>(
    registrar_windows);

auto screen_lock_channel =
    std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
        registrar->messenger(),
        "biometric_cipher/screen_lock",
        &flutter::StandardMethodCodec::GetInstance());

screen_lock_channel->SetStreamHandler(
    screen_lock_handler->CreateStreamHandler());

// Store in plugin instance to prevent premature destruction
plugin->screen_lock_handler_ = std::move(screen_lock_handler);
```

### Changes to `biometric_cipher_plugin.h` (task 4.4)

Add include and member:

```cpp
#include "biometric_cipher/handlers/screen_lock_stream_handler.h"

// In BiometricCipherPlugin class:
std::unique_ptr<ScreenLockStreamHandler> screen_lock_handler_;
```

### Changes to `CMakeLists.txt` (task 4.5)

Add source file and library link:

```cmake
# Add to add_library sources:
handlers/screen_lock_stream_handler.cpp

# Add library link:
target_link_libraries(${PLUGIN_NAME} PRIVATE Wtsapi32)
```

## Implementation Notes

- The `handlers/` subdirectory under both `windows/` and `windows/include/biometric_cipher/` is new — create it alongside the files.
- `WTSRegisterSessionNotification` requires the `Wtsapi32` library. Prefer `target_link_libraries` in CMake over `#pragma comment(lib, ...)` for consistency with the existing build system.
- `registrar_windows` is the `flutter::PluginRegistrarWindows*` cast from `registrar` — check the existing `biometric_cipher_plugin.cpp` for the pattern already used.
- The `window_proc_delegate_id_` initialized to `-1` serves as a sentinel for "not registered" — guard `UnregisterWindowProc` with `>= 0` check.
- Look at the existing `biometric_cipher_plugin.cpp` to understand the exact variable name used for `registrar_windows` and the method channel setup pattern before wiring task 4.3.

## Code Review Fixes

- [x] **Task 6: Add `namespace biometric_cipher` to `ScreenLockStreamHandler`**
  - Wrap `ScreenLockStreamHandler` class in `namespace biometric_cipher { ... }` in both the header (`.h`) and implementation (`.cpp`) files
  - Every other header in `packages/biometric_cipher/windows/include/biometric_cipher/` uses `namespace biometric_cipher`; the new handler should be consistent
  - Acceptance criteria:
    - `screen_lock_stream_handler.h` wraps its class declaration in `namespace biometric_cipher { ... }`
    - `screen_lock_stream_handler.cpp` wraps its method definitions in `namespace biometric_cipher { ... }`
    - The code compiles without errors (verify on Windows or by inspection that all references resolve correctly)

- [x] **Task 7: Synchronize main tasklist with Phase 4 completion**
  - Update `docs/tasklist-2349.md` to mark tasks 4.1-4.5 as `[x]` (checked)
  - Update the Progress Report table to show Iteration 4 as `:green_circle: Done`
  - Acceptance criteria:
    - All five Phase 4 task checkboxes in `docs/tasklist-2349.md` are `[x]`
    - Progress Report row for Iteration 4 shows `:green_circle: Done`
