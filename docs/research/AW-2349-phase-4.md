# Research: AW-2349 Phase 4 — Windows `ScreenLockStreamHandler`

## 1. Resolved Questions

### Q1: `#pragma comment` vs CMake for Wtsapi32 linking
**Answer:** Omit `#pragma comment(lib, "Wtsapi32.lib")` entirely from the `.cpp` file. Use only
`target_link_libraries(${PLUGIN_NAME} PRIVATE Wtsapi32)` in `CMakeLists.txt`. The phase-4 task
doc still shows `#pragma comment` — ignore it; the user's answer overrides it.

### Q2: Plugin header path
**Answer:** The real header is `packages/biometric_cipher/windows/biometric_cipher_plugin.h` (at
the `windows/` root, not under `include/biometric_cipher/`). The `screen_lock_handler_` member
field must be added there.

### Q3: Any other constraints
**Answer:** None beyond what is in the PRD.

---

## 2. Phase Scope

Phase 4 is a pure C++ change inside `packages/biometric_cipher/windows/`. It implements the
Windows side of the `EventChannel("biometric_cipher/screen_lock")` established in Phase 1 (Dart).
No changes are required outside `packages/biometric_cipher/windows/`.

New files to create:
- `packages/biometric_cipher/windows/include/biometric_cipher/handlers/screen_lock_stream_handler.h`
- `packages/biometric_cipher/windows/handlers/screen_lock_stream_handler.cpp`

Existing files to modify:
- `packages/biometric_cipher/windows/biometric_cipher_plugin.h`
- `packages/biometric_cipher/windows/biometric_cipher_plugin.cpp`
- `packages/biometric_cipher/windows/CMakeLists.txt`

---

## 3. Related Modules/Services

### Windows plugin root — actual file layout

All source `.cpp` files live directly under `packages/biometric_cipher/windows/` (no `src/`
subdirectory). Headers live under `packages/biometric_cipher/windows/include/biometric_cipher/`
with sub-namespaces mirroring the domain: `common/`, `data/`, `enums/`, `errors/`, `repositories/`,
`services/`, `storages/`, `wrappers/`. There is no existing `handlers/` subdirectory yet on either
side — it must be created for both the header (`include/biometric_cipher/handlers/`) and the source
(`handlers/`).

Key existing files:

| File | Role |
|------|------|
| `windows/biometric_cipher_plugin.h` | `BiometricCipherPlugin` class declaration (actual header — NOT under `include/`) |
| `windows/biometric_cipher_plugin.cpp` | Plugin implementation; contains `RegisterWithRegistrar` |
| `windows/biometric_cipher_plugin_c_api.cpp` | C API bridge that calls `RegisterWithRegistrar` |
| `windows/CMakeLists.txt` | Build system; defines `PLUGIN_SOURCES` list |

### Prior phase implementations (for pattern reference)

| Platform | File |
|----------|------|
| Android (Phase 2) | `packages/biometric_cipher/android/src/main/kotlin/com/adguard/cryptowallet/biometric_cipher/handlers/ScreenLockStreamHandler.kt` |
| iOS/macOS (Phase 3) | `packages/biometric_cipher/darwin/Classes/ScreenLockStreamHandler.swift` |
| Android plugin | `packages/biometric_cipher/android/src/main/kotlin/com/adguard/cryptowallet/biometric_cipher/BiometricCipherPlugin.kt` |
| iOS/macOS plugin | `packages/biometric_cipher/darwin/Classes/BiometricCipherPlugin.swift` |

---

## 4. Current Endpoints and Contracts

The Dart EventChannel name is `"biometric_cipher/screen_lock"` (established in Phase 1). The
Windows handler must emit a single `bool` value (`true`) when a session lock occurs. No other
events are sent (unlock is ignored).

The method channel `"biometric_cipher"` and all its existing methods are unaffected.

---

## 5. Patterns Used

### 5.1 Include path convention (Windows)

Source `.cpp` files include headers using the `"include/biometric_cipher/..."` prefix relative to
the `windows/` directory. Examples:

```cpp
// argument_parser.cpp
#include "include/biometric_cipher/common/argument_parser.h"

// windows_hello_repository_impl.cpp
#include "include/biometric_cipher/repositories/windows_hello_repository_impl.h"
```

The new `handlers/screen_lock_stream_handler.cpp` must use the same pattern:

```cpp
#include "include/biometric_cipher/handlers/screen_lock_stream_handler.h"
```

Headers under `include/biometric_cipher/` use `#pragma once` (no traditional include guards).

### 5.2 `RegisterWithRegistrar` pattern (existing)

From `biometric_cipher_plugin.cpp` lines 33–48:

```cpp
// static
void BiometricCipherPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar)
{
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "biometric_cipher",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<BiometricCipherPlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}
```

Key observations:
- The parameter type is already `flutter::PluginRegistrarWindows*` — no cast is needed.
- The plugin is created via default constructor `BiometricCipherPlugin()`.
- `registrar->AddPlugin(std::move(plugin))` is the last call.
- The `ScreenLockStreamHandler` must be constructed and assigned to `plugin->screen_lock_handler_`
  **before** `AddPlugin` is called (since `AddPlugin` moves the unique_ptr away).

### 5.3 Plugin header structure (actual header)

From `biometric_cipher_plugin.h` lines 1–76:
- Header guard macro: `FLUTTER_PLUGIN_BIOMETRIC_CIPHER_PLUGIN_H_`
- All members are inside `namespace biometric_cipher`
- Class `BiometricCipherPlugin` extends `flutter::Plugin`
- Existing private fields (lines 69–71): `m_Argument_parser`, `m_ConfigStorage`, `m_SecureService`
- No existing `screen_lock_handler_` field — must be added

The new public member field goes in the `public:` section (per PRD spec — public for access from
`RegisterWithRegistrar` without a setter):

```cpp
// Add to includes at top of biometric_cipher_plugin.h:
#include "include/biometric_cipher/handlers/screen_lock_stream_handler.h"

// Add inside BiometricCipherPlugin class (public section):
std::unique_ptr<ScreenLockStreamHandler> screen_lock_handler_;
```

Note: `ScreenLockStreamHandler` lives outside `namespace biometric_cipher`, so in the header the
type is referenced as `::ScreenLockStreamHandler` or just `ScreenLockStreamHandler` (if declared
before the namespace). The include of the handler header at the top of the plugin header covers
the forward declaration.

### 5.4 CMakeLists.txt `PLUGIN_SOURCES` list

From `CMakeLists.txt` lines 67–81:

```cmake
list(APPEND PLUGIN_SOURCES
  "string_util.cpp"
  "method_name.cpp"
  "argument_name.cpp"
  "error_codes.cpp"
  "tpm_status.cpp"
  "biometry_status.cpp"
  "argument_parser.cpp"
  "config_storage.cpp"
  "windows_hello_repository_impl.cpp"
  "windows_tpm_repository_impl.cpp"
  "winrt_encrypt_repository_impl.cpp"
  "biometric_cipher_service.cpp"
  "biometric_cipher_plugin.cpp"
)
```

All existing entries are bare filenames (flat, no subdirectory prefix). The new entry uses a
subdirectory prefix because the file lives in `handlers/`:

```cmake
"handlers/screen_lock_stream_handler.cpp"
```

### 5.5 `target_link_libraries` pattern

From `CMakeLists.txt` lines 107–112:

```cmake
target_link_libraries(${PLUGIN_NAME} PRIVATE 
  flutter 
  flutter_wrapper_plugin 
  windowsapp
  ncrypt
)
```

The new `Wtsapi32` entry is added as a separate `target_link_libraries` call (consistent with how
the WIL library is linked on line 106):

```cmake
target_link_libraries(${PLUGIN_NAME} PRIVATE Wtsapi32)
```

Alternatively it can be appended to the existing block — either is valid CMake.

### 5.6 EventChannel + StreamHandler registration (Android reference)

From `BiometricCipherPlugin.kt` lines 68–75:

```kotlin
val streamHandler = ScreenLockStreamHandler(flutterPluginBinding.applicationContext)
val eventChannel = EventChannel(
    flutterPluginBinding.binaryMessenger,
    "biometric_cipher/screen_lock",
)
eventChannel.setStreamHandler(streamHandler)
screenLockEventChannel = eventChannel
screenLockStreamHandler = streamHandler
```

The Windows C++ equivalent (from phase-4 task doc):

```cpp
auto screen_lock_handler = std::make_unique<ScreenLockStreamHandler>(registrar);
auto screen_lock_channel =
    std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
        registrar->messenger(),
        "biometric_cipher/screen_lock",
        &flutter::StandardMethodCodec::GetInstance());
screen_lock_channel->SetStreamHandler(screen_lock_handler->CreateStreamHandler());
plugin->screen_lock_handler_ = std::move(screen_lock_handler);
```

Note: `screen_lock_channel` is a local `unique_ptr`. The Flutter Windows plugin system retains
ownership of the channel via the stream handler registration — the local `unique_ptr` can be
destroyed when `RegisterWithRegistrar` returns.

### 5.7 `namespace biometric_cipher` scope for `ScreenLockStreamHandler`

The existing plugin class is inside `namespace biometric_cipher` (both `.h` and `.cpp`). The new
`ScreenLockStreamHandler` class is declared in its own header with no namespace (matching the
PRD spec). Inside `biometric_cipher_plugin.cpp`, the code in `RegisterWithRegistrar` is already
inside `namespace biometric_cipher { ... }`, so `ScreenLockStreamHandler` can be referenced
without qualification as long as its header is included.

---

## 6. Phase-Specific Limitations and Risks

### 6.1 `biometric_cipher_plugin.h` is NOT under `include/biometric_cipher/`
The task-4.4 entry in the phase doc says `include/biometric_cipher/biometric_cipher_plugin.h` —
that path does not exist. The actual file is `windows/biometric_cipher_plugin.h` (confirmed by
directory scan and user answer). Adding `screen_lock_handler_` to the wrong path would break
compilation.

### 6.2 `#pragma comment` must be omitted
The task doc code sample for `screen_lock_stream_handler.cpp` shows `#pragma comment(lib,
"Wtsapi32.lib")` on line 96. Per user answer this line must NOT be present. Linking is done
exclusively via `target_link_libraries` in CMakeLists.txt.

### 6.3 `handlers/` subdirectories do not yet exist
Neither `windows/handlers/` nor `windows/include/biometric_cipher/handlers/` exist. Both must be
created as part of creating the new files.

### 6.4 `screen_lock_handler_` placement — public vs private
The PRD requires `screen_lock_handler_` to be a **public** member field (not private) because
`RegisterWithRegistrar` is a static method that accesses `plugin->screen_lock_handler_` after
constructing the plugin object. All current member fields in `BiometricCipherPlugin` are private;
this new field breaks that convention intentionally (per PRD rationale — avoids constructor
refactor or setter).

### 6.5 `std::unique_ptr<ScreenLockStreamHandler>` forward declaration in header
Including `screen_lock_stream_handler.h` in `biometric_cipher_plugin.h` creates a transitive
dependency. The handler header includes `<flutter/plugin_registrar_windows.h>` and `<wtsapi32.h>`
which are already in scope for the plugin header. No circular dependency risk.

### 6.6 `window_proc_delegate_id_` type
`RegisterTopLevelWindowProcDelegate` returns an `int` id. The field is declared as `int
window_proc_delegate_id_ = -1`. The `UnregisterWindowProc` guard `>= 0` prevents
double-unregistration in both the `onCancel` callback and the destructor.

### 6.7 `WM_WTSSESSION_CHANGE` message constant requires `<wtsapi32.h>`
The constant `WTS_SESSION_LOCK` and function `WTSRegisterSessionNotification` are declared in
`<wtsapi32.h>`. This header must be included in `screen_lock_stream_handler.h` (not just the
`.cpp`). The PRD spec already shows it in the header includes.

### 6.8 No C++ unit tests
WTS registration requires a real Windows session and HWND. No unit test can be written for this
handler (confirmed in PRD constraints). Acceptance is via Windows debug build + manual test.

---

## 7. New Technical Questions

None discovered during research. All decisions are fully specified in the PRD and confirmed by the
user's answers above.

---

## Appendix: Exact File Paths

| Path | Status |
|------|--------|
| `packages/biometric_cipher/windows/biometric_cipher_plugin.h` | Exists — add `screen_lock_handler_` public field and handler header include |
| `packages/biometric_cipher/windows/biometric_cipher_plugin.cpp` | Exists — add EventChannel registration in `RegisterWithRegistrar` (after line 41, before line 48) |
| `packages/biometric_cipher/windows/CMakeLists.txt` | Exists — add `"handlers/screen_lock_stream_handler.cpp"` to `PLUGIN_SOURCES` (after line 80); add `target_link_libraries(${PLUGIN_NAME} PRIVATE Wtsapi32)` after line 112 |
| `packages/biometric_cipher/windows/include/biometric_cipher/handlers/screen_lock_stream_handler.h` | New file — create directory `handlers/` under `include/biometric_cipher/` |
| `packages/biometric_cipher/windows/handlers/screen_lock_stream_handler.cpp` | New file — create directory `handlers/` under `windows/` |
