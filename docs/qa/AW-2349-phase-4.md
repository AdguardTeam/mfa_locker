# QA Plan: AW-2349 Phase 4 — Windows Native: `ScreenLockStreamHandler` (C++)

Status: REVIEWED
Date: 2026-04-01

---

## Phase Scope

Phase 4 delivers the Windows C++ native side of the `EventChannel("biometric_cipher/screen_lock")` contract established in Phase 1 and validated on Android (Phase 2) and iOS/macOS (Phase 3). It introduces five deliverables:

1. **New file:** `packages/biometric_cipher/windows/include/biometric_cipher/handlers/screen_lock_stream_handler.h` — class declaration for `biometric_cipher::ScreenLockStreamHandler`, wrapped in `namespace biometric_cipher`.
2. **New file:** `packages/biometric_cipher/windows/handlers/screen_lock_stream_handler.cpp` — implementation: `WTSRegisterSessionNotification`, `RegisterTopLevelWindowProcDelegate`, `WM_WTSSESSION_CHANGE` / `WTS_SESSION_LOCK` handling, and symmetric unregistration.
3. **Modified file:** `packages/biometric_cipher/windows/biometric_cipher_plugin.cpp` — creates `ScreenLockStreamHandler`, wires `FlutterEventChannel`, stores the handler in the plugin instance.
4. **Modified file:** `packages/biometric_cipher/windows/biometric_cipher_plugin.h` — includes the handler header, declares `std::unique_ptr<ScreenLockStreamHandler> screen_lock_handler_` as a public member.
5. **Modified file:** `packages/biometric_cipher/windows/CMakeLists.txt` — adds `handlers/screen_lock_stream_handler.cpp` to `PLUGIN_SOURCES`; links `Wtsapi32` via `target_link_libraries`.

Additionally, a post-implementation **Code Review Fix** (tracked as Tasks 6 and 7 in the phase document) was applied:
- Task 6: `ScreenLockStreamHandler` class and its method definitions are wrapped in `namespace biometric_cipher` in both `.h` and `.cpp`, consistent with every other header under `windows/include/biometric_cipher/`.
- Task 7: Main tasklist updated to reflect Phase 4 completion (all checkboxes `[x]`, progress table row updated to Done).

**Out of scope for Phase 4:** Plugin Dart unit tests (Phase 5), example app `ScreenLockService` (Phase 6), DI wiring (Phase 7), BLoC integration (Phase 8). No Dart files, no Android files, no Apple files are modified in this phase.

---

## Implementation Status (observed)

### Task 4.1 — Header file `screen_lock_stream_handler.h`

File path: `packages/biometric_cipher/windows/include/biometric_cipher/handlers/screen_lock_stream_handler.h`

Findings:

- File is present inside the new `handlers/` subdirectory under `windows/include/biometric_cipher/`, matching the spec.
- `#pragma once` guard present (line 1).
- All required includes are present: `<flutter/event_channel.h>`, `<flutter/event_stream_handler_functions.h>`, `<flutter/plugin_registrar_windows.h>`, `<windows.h>`, `<wtsapi32.h>` (lines 3–7).
- **Code Review Fix (Task 6) applied:** class is wrapped in `namespace biometric_cipher { ... }` (lines 9 and 31). This is consistent with every other header in the `windows/include/biometric_cipher/` tree.
- Class declaration has `explicit` constructor, `~ScreenLockStreamHandler()`, `CreateStreamHandler()` returning `std::unique_ptr<flutter::StreamHandler<flutter::EncodableValue>>`.
- **Added beyond spec:** copy constructor and copy assignment operator are explicitly deleted (`= delete`) at lines 16–17. This is a correct and welcome addition — `unique_ptr<EventSink>` is not copyable, so the implicit deletes would be compiler-generated anyway; making them explicit prevents accidental misuse.
- Private members: `registrar_` (raw pointer, non-owning), `event_sink_` (`unique_ptr`), `window_proc_delegate_id_` initialized to `-1` (sentinel pattern).
- Private methods: `HandleWindowMessage`, `RegisterWindowProc`, `UnregisterWindowProc` — all as specified.

### Task 4.2 — Implementation file `screen_lock_stream_handler.cpp`

File path: `packages/biometric_cipher/windows/handlers/screen_lock_stream_handler.cpp`

Findings:

- Include path: `"include/biometric_cipher/handlers/screen_lock_stream_handler.h"` (line 1). This uses a path relative to the `windows/` source directory (`${CMAKE_CURRENT_SOURCE_DIR}`), which is listed as a private include directory in CMakeLists.txt line 108. This resolves correctly.
- **`#pragma comment(lib, "Wtsapi32.lib")` is absent.** The spec's reference code included this pragma; the implementation correctly omits it in favor of the CMake `target_link_libraries(${PLUGIN_NAME} PRIVATE ... Wtsapi32)` approach, which is consistent with how all other system libraries (`ncrypt`, `windowsapp`, etc.) are linked in this plugin.
- **Code Review Fix (Task 6) applied:** all method definitions are wrapped in `namespace biometric_cipher { ... }` (lines 3 and 62).
- Constructor body: stores `registrar` in `registrar_` (line 7). Correct — no other initialization needed since `window_proc_delegate_id_` is initialized in the header.
- Destructor calls `UnregisterWindowProc()` (line 10). Ensures WTS deregistration on plugin teardown even if `onCancel` was not called.
- `CreateStreamHandler()` returns `StreamHandlerFunctions` with two lambdas:
  - `onListen` lambda: assigns `event_sink_` from `std::move(events)`, then calls `RegisterWindowProc()`. Returns `nullptr` (no error). Correct.
  - `onCancel` lambda: calls `UnregisterWindowProc()`, nulls `event_sink_`. Returns `nullptr`. Correct.
- `RegisterWindowProc()`:
  - Retrieves HWND via `registrar_->GetView()->GetNativeWindow()` (line 34).
  - Calls `WTSRegisterSessionNotification(hwnd, NOTIFY_FOR_THIS_SESSION)` (line 35).
  - Calls `registrar_->RegisterTopLevelWindowProcDelegate(...)` with a lambda capturing `this` (lines 37–40), stores the returned delegate id in `window_proc_delegate_id_`.
- `UnregisterWindowProc()`:
  - Guards on `window_proc_delegate_id_ >= 0` (line 44). Sentinel check correct.
  - Re-fetches HWND (line 45). Relies on the registrar still being valid at teardown — acceptable within the plugin lifecycle.
  - Calls `WTSUnRegisterSessionNotification(hwnd)` (line 46).
  - Calls `registrar_->UnregisterTopLevelWindowProcDelegate(window_proc_delegate_id_)` (line 47).
  - Resets sentinel to `-1` (line 48). Prevents double-unregister.
- `HandleWindowMessage()`:
  - Checks `message == WM_WTSSESSION_CHANGE && wparam == WTS_SESSION_LOCK` (line 54).
  - If true and `event_sink_` is set, calls `event_sink_->Success(flutter::EncodableValue(true))` (line 56).
  - Returns `std::nullopt` unconditionally (line 59). This allows other window proc delegates to continue processing the message. Correct per spec.

### Task 4.3 — EventChannel registered in `BiometricCipherPlugin::RegisterWithRegistrar`

File path: `packages/biometric_cipher/windows/biometric_cipher_plugin.cpp`

Findings:

- `#include "include/biometric_cipher/handlers/screen_lock_stream_handler.h"` is present at line 4.
- In `RegisterWithRegistrar` (lines 50–60):
  - `ScreenLockStreamHandler` is constructed with `registrar` (the `flutter::PluginRegistrarWindows*` parameter) directly — not a separate `registrar_windows` cast. The function signature takes `flutter::PluginRegistrarWindows*` directly, so no cast is needed here. This is correct.
  - `FlutterEventChannel` is created with `registrar->messenger()`, channel name `"biometric_cipher/screen_lock"`, and `flutter::StandardMethodCodec::GetInstance()` (lines 52–55).
  - `SetStreamHandler` is called with the result of `screen_lock_handler->CreateStreamHandler()` (lines 57–58).
  - `plugin->screen_lock_handler_ = std::move(screen_lock_handler)` (line 60) stores ownership in the plugin instance before `registrar->AddPlugin(std::move(plugin))` (line 62). This prevents premature destruction of the handler. Correct.
  - Order: `screen_lock_channel` is a local `unique_ptr` created after `SetStreamHandler` is called; it goes out of scope at the end of `RegisterWithRegistrar`. The Flutter event channel object is owned by the engine's messenger for the duration of the plugin's lifetime once `SetStreamHandler` has been called. Local `unique_ptr` destruction is safe.

### Task 4.4 — `screen_lock_handler_` member in plugin header

File path: `packages/biometric_cipher/windows/biometric_cipher_plugin.h`

Findings:

- `#include "include/biometric_cipher/handlers/screen_lock_stream_handler.h"` is present at line 5.
- `std::unique_ptr<ScreenLockStreamHandler> screen_lock_handler_` declared as a **public** member (line 40), with a comment: "Prevent premature destruction; assigned in `RegisterWithRegistrar` (static)."
- The member being `public` (rather than `private`) is a pragmatic choice necessitated by the static factory pattern: `RegisterWithRegistrar` constructs the plugin via `std::make_unique<BiometricCipherPlugin>()` and then assigns to `plugin->screen_lock_handler_`. A `public` member is the simplest approach; the alternative would be a friend declaration or a setter method. Assessment: acceptable for this design pattern, consistent with how similar patterns work in Flutter plugin examples.

### Task 4.5 — CMakeLists.txt updated

File path: `packages/biometric_cipher/windows/CMakeLists.txt`

Findings:

- `"handlers/screen_lock_stream_handler.cpp"` is listed as the last entry in `PLUGIN_SOURCES` (line 81).
- `Wtsapi32` is linked via `target_link_libraries(${PLUGIN_NAME} PRIVATE ... Wtsapi32)` (line 115), grouped with `flutter`, `flutter_wrapper_plugin`, `windowsapp`, and `ncrypt`.
- `Wtsapi32` is also correctly added to the test runner link libraries (line 167), ensuring the test binary links without linker errors related to `WTSRegisterSessionNotification`.
- No `#pragma comment(lib, "Wtsapi32.lib")` in the source files (verified by grep — no matches). CMake-only linking is used throughout. Consistent with project conventions.

### Code Review Fix — Task 6 (namespace)

Applied in both `.h` (lines 9, 31) and `.cpp` (lines 3, 62). Every other header under `windows/include/biometric_cipher/` uses `namespace biometric_cipher`. The new handler is now consistent. No residual unqualified `ScreenLockStreamHandler` references outside the namespace remain.

### Code Review Fix — Task 7 (tasklist sync)

`docs/tasklist-2349.md` has been updated: all five Phase 4 checkboxes (`4.1`–`4.5`) are marked `[x]`, and the progress table row for Iteration 4 shows `:green_circle: Done`. The current phase marker reads `**Current Phase:** 4`.

---

## Positive Scenarios

### PS-1: New files present at the correct paths

Both `handlers/screen_lock_stream_handler.h` (under `windows/include/biometric_cipher/handlers/`) and `handlers/screen_lock_stream_handler.cpp` (under `windows/handlers/`) are present. The `handlers/` subdirectory is new under both `windows/include/biometric_cipher/` and `windows/`; the files are placed correctly alongside their peers.

### PS-2: `namespace biometric_cipher` applied consistently

Both the header and implementation wrap `ScreenLockStreamHandler` in `namespace biometric_cipher`. This is consistent with every other header in `windows/include/biometric_cipher/`. The `biometric_cipher_plugin.cpp`, which already uses `using biometric_cipher::MethodName` and `using biometric_cipher::ArgumentName`, references `ScreenLockStreamHandler` as a bare name after the `namespace biometric_cipher {` block begins at line 32 — resolution is correct.

### PS-3: `WTSRegisterSessionNotification` called with `NOTIFY_FOR_THIS_SESSION`

`NOTIFY_FOR_THIS_SESSION` restricts session change notifications to the current user session only (as opposed to `NOTIFY_FOR_ALL_SESSIONS`). This is the correct flag for a per-user security application and avoids receiving lock events from other concurrent Windows sessions.

### PS-4: `WM_WTSSESSION_CHANGE` + `WTS_SESSION_LOCK` filter is exact

`HandleWindowMessage` checks both `message == WM_WTSSESSION_CHANGE` and `wparam == WTS_SESSION_LOCK`. Other `WM_WTSSESSION_CHANGE` sub-events (`WTS_SESSION_UNLOCK`, `WTS_REMOTE_CONNECT`, etc.) are correctly ignored. Only the lock event emits `true` through the event sink.

### PS-5: `EventChannel` carries `true` as a `flutter::EncodableValue(bool)`

`event_sink_->Success(flutter::EncodableValue(true))` sends a Dart `bool` value `true`. On the Dart side, `MethodChannelBiometricCipher.screenLockStream` maps incoming events via `.map((event) => event as bool)`. The C++ `bool` value encodes as a Dart `bool`; the cast is safe.

### PS-6: `EventChannel` channel name matches across all platform layers

The string `"biometric_cipher/screen_lock"` is used in:
- `biometric_cipher_plugin.cpp` line 54 (Windows, Phase 4)
- `BiometricCipherPlugin.kt` line 71 (Android, Phase 2)
- `BiometricCipherPlugin.swift` lines 28 and 34 (iOS/macOS, Phase 3)
- `biometric_cipher_method_channel.dart` line 12 (Dart, Phase 1)

All four match exactly. A mismatch would cause the Windows stream to silently produce no events.

### PS-7: Ownership lifetime is correct — handler survives `RegisterWithRegistrar`

`screen_lock_handler` is moved into `plugin->screen_lock_handler_` before `plugin` is moved into `registrar->AddPlugin(...)`. The plugin is retained by the registrar for the process lifetime. Therefore `ScreenLockStreamHandler` is alive as long as the plugin is alive, and the `[this]` captures inside `CreateStreamHandler`'s lambdas remain valid.

### PS-8: `UnregisterWindowProc` called in destructor for leak-free teardown

`~ScreenLockStreamHandler()` calls `UnregisterWindowProc()`. If the Dart stream is never cancelled (e.g., app terminates without an explicit `onCancel`), the WTS registration is still cleaned up during plugin destruction. Combined with the `window_proc_delegate_id_ >= 0` guard, double-unregistration is impossible.

### PS-9: Copy and assignment deleted on `ScreenLockStreamHandler`

The explicit `= delete` declarations in the header prevent accidental copying of an object that holds a raw HWND reference and a `unique_ptr<EventSink>`. This is a correctness improvement over the spec which did not specify these deletions.

### PS-10: `std::nullopt` return allows message chain to continue

`HandleWindowMessage` returns `std::nullopt` regardless of whether it handled the message. `RegisterTopLevelWindowProcDelegate` processes delegates in registration order; returning `std::nullopt` correctly passes the message to subsequent handlers (including other plugins or the Flutter engine's own message processing).

### PS-11: `#pragma comment` absent — CMake-only Wtsapi32 linking

No `#pragma comment(lib, "Wtsapi32.lib")` is present in the `.cpp` file. `Wtsapi32` is linked exclusively via `target_link_libraries` in CMakeLists.txt (lines 115 and 167). This is consistent with how all other Windows system libraries are handled in this plugin.

### PS-12: Test runner also links `Wtsapi32`

`PLUGIN_SOURCES` includes `handlers/screen_lock_stream_handler.cpp`, and `TEST_RUNNER` uses `${PLUGIN_SOURCES}` directly. `Wtsapi32` is explicitly added to the test runner's `target_link_libraries` (line 167). This ensures the test binary links successfully without linker errors from the WTS API calls compiled into the handler.

### PS-13: No user-visible prompts or permission requests

`WTSRegisterSessionNotification` and the window message hook require no user-facing dialog, biometric prompt, or UAC elevation. The detection is entirely silent, matching the PRD requirement (idea-2349.md table, "Prompt shown? No").

### PS-14: Existing plugin functionality is not regressed

`biometric_cipher_plugin.cpp` retains all pre-existing `HandleMethodCall` routing and all async coroutines unchanged. The new code in `RegisterWithRegistrar` (lines 50–61) is additive only. All pre-existing method channel operations (`configure`, `getTPMStatus`, `getBiometryStatus`, `generateKeyPair`, `deleteKey`, `encrypt`, `decrypt`, `isKeyValid`) continue to route through the same `HandleMethodCall` switch.

---

## Negative and Edge Cases

### NC-1: `WTSRegisterSessionNotification` call result is not checked

`RegisterWindowProc()` calls `WTSRegisterSessionNotification(hwnd, NOTIFY_FOR_THIS_SESSION)` and discards the `BOOL` return value (line 35). If the call fails (e.g., the HWND is invalid, or Wtsapi32 is unavailable in a constrained environment), the handler silently registers the window proc delegate but will never receive `WM_WTSSESSION_CHANGE` messages — the stream remains open with no events, no error. This is a graceful degradation: the app will not crash, and the existing timer-based and resume-based lock mechanisms remain active. However, there is no diagnostic indication of the failure. Assessment: low risk for standard desktop Windows environments; acceptable for the current phase. A future improvement could log a warning or emit an error event.

### NC-2: `GetNativeWindow()` called in `UnregisterWindowProc` after the view may be torn down

`UnregisterWindowProc()` calls `registrar_->GetView()->GetNativeWindow()` (line 45) to obtain the HWND for `WTSUnRegisterSessionNotification`. During normal shutdown, the destructor is called as part of plugin teardown while the registrar is still valid. However, if `UnregisterWindowProc` is called during `onCancel` at a point where the view has already been destroyed (an edge case in plugin teardown ordering), `GetView()` could return a null or dangling pointer. Assessment: unlikely in practice given the Flutter plugin lifecycle, but there is no null check on `GetView()`. Consistent with the reference implementation in the spec. Low risk; no defensive guard is present.

### NC-3: Dart stream cancelled while a lock message is in flight

If `onCancel` is invoked (setting `event_sink_ = nullptr`) concurrently with `HandleWindowMessage` executing on the UI thread, there is a potential TOCTOU window. However, Flutter's `RegisterTopLevelWindowProcDelegate` callbacks execute on the Windows message loop (main thread), and `onCancel` is also called on the main thread via the Flutter engine. Therefore both operations are serialized by the message loop. No race condition exists. This is the same thread-safety guarantee that Android's `Handler(Looper.getMainLooper())` provides.

### NC-4: `onListen` called a second time without an intervening `onCancel` (theoretical double-register)

If `onListen` were called twice, `WTSRegisterSessionNotification` would register twice (duplicate notifications), and `RegisterTopLevelWindowProcDelegate` would add a second delegate (double event delivery). The `FlutterEventChannel` contract guarantees `onCancel` precedes any second `onListen`; this scenario cannot occur under normal Flutter operation. No defensive guard exists at the start of `onListen`. Assessment: consistent with Phase 2 (Android) and Phase 3 (iOS/macOS) design decisions. Acceptable given the Flutter contract.

### NC-5: `window_proc_delegate_id_` double-unregister protection

`UnregisterWindowProc()` is called from both `onCancel` (stream cancelled) and `~ScreenLockStreamHandler()` (plugin destroyed). The `window_proc_delegate_id_ >= 0` guard followed by resetting to `-1` (line 48) ensures idempotent behavior. The destructor calling `UnregisterWindowProc()` after `onCancel` has already done so is safe.

### NC-6: No screen lock if app is minimized or the message loop is stalled

`WM_WTSSESSION_CHANGE` is delivered as a window message to the registered HWND's message loop. If the Flutter Windows application's message loop is stalled (e.g., a long synchronous operation on the UI thread), delivery of the lock event is deferred until the loop processes messages. For the expected use case (locker unlocked, user locks screen), the app should be responsive. This is an accepted platform behavior, not a defect.

### NC-7: App suspended / process suspended before session lock message is processed

If Windows suspends the process (or the Flutter engine suspends the Dart isolate) before the `WM_WTSSESSION_CHANGE` message is dispatched, the event may be delayed or lost. The existing `shouldLockOnResume` mechanism (established in prior phases) handles this fallback case. The screen lock detection via Windows WTS provides the *eager* path; the resume-based check provides the safety net. This is the accepted edge case documented across idea-2349.md and vision-2349.md.

### NC-8: Remote Desktop / Terminal Services session lock behavior

`NOTIFY_FOR_THIS_SESSION` means the plugin only receives notifications for the current user's session. On a machine where multiple RDP sessions are active, a lock in session 2 does not trigger the handler in session 1. This is the correct behavior. However, on a machine accessed via RDP where the user disconnects (which may send `WTS_SESSION_LOCK` or `WTS_REMOTE_DISCONNECT` depending on configuration), the behavior depends on Windows session management policy. `HandleWindowMessage` only checks `WTS_SESSION_LOCK`, so `WTS_REMOTE_DISCONNECT` is ignored. Assessment: acceptable; RDP disconnect locking is not covered by the PRD.

### NC-9: `screen_lock_channel` local variable goes out of scope at end of `RegisterWithRegistrar`

The `std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> screen_lock_channel` (lines 52–55) is a local variable in `RegisterWithRegistrar`. It is destroyed when the function returns. The `FlutterEventChannel` / `flutter::EventChannel` object's `SetStreamHandler` registers the handler with the binary messenger, which retains it independently. The local `unique_ptr` destruction does not invalidate the channel registration. This is correct and mirrors the pattern used for `channel` (the method channel) in the same function.

### NC-10: No native C++ unit tests for `ScreenLockStreamHandler`

The existing `TEST_SOURCES` in CMakeLists.txt cover service and repository tests but do not include a test for `ScreenLockStreamHandler`. `WTSRegisterSessionNotification` and `RegisterTopLevelWindowProcDelegate` are OS-provided APIs that cannot easily be mocked at the C++ unit test level without abstracting the Windows API surface. Native C++ unit tests are out of scope for this phase and for the ticket as a whole (Phase 5 adds Dart plugin tests; no native C++ tests for the stream handler are planned). Manual verification via `fvm flutter build windows --debug` is the acceptance criterion.

### NC-11: `EventChannel` uses `StandardMethodCodec` not `StandardMessageCodec`

The `FlutterEventChannel` is created with `&flutter::StandardMethodCodec::GetInstance()` (line 55). The Dart side (`MethodChannelBiometricCipher`) uses `EventChannel('biometric_cipher/screen_lock')` which defaults to `StandardMethodCodec` in Flutter. The codec is consistent across the bridge. Note: the Android and iOS implementations do not specify a codec explicitly (they use the default, which is `StandardMethodCodec` on all platforms). Phase 1 established `StandardMethodCodec` on the Dart side and all native implementations follow suit.

---

## Automated Tests Coverage

| Test | File | Status |
|------|------|--------|
| Windows debug build — no compilation errors | `cd example && fvm flutter build windows --debug` | Manual verification required (primary acceptance criterion; Windows-only) |
| `screenLockStream` Dart plugin tests (from Phase 1) | `packages/biometric_cipher/test/biometric_cipher_test.dart` | Present, green — exercise mock platform, not C++ handler |
| Native C++ unit tests for `ScreenLockStreamHandler` | — | **Not present** (no plans to add; WTS API not mockable without further abstraction) |
| `onListen` / `onCancel` lifecycle via EventChannel | — | **Not present** in this phase; Dart-side coverage deferred to Phase 5 |
| All pre-existing Dart plugin tests | `packages/biometric_cipher/test/biometric_cipher_test.dart` | Unaffected by Phase 4 changes |
| Existing Windows C++ unit tests (`biometric_cipher_service_test.cpp` etc.) | `packages/biometric_cipher/windows/test/` | Unaffected by Phase 4; `Wtsapi32` now linked for test runner (CMakeLists.txt line 167) |

**Overall automated coverage for Phase 4:** No automated test additions of this phase's own. All new code is C++ and is only exercisable via a real Windows process with a live WTS-capable session. Compilation correctness (the primary acceptance criterion) is validated by the Windows debug build. Runtime behavior must be manually verified on Windows hardware or a Windows VM. Phase 5 will add Dart-layer plugin tests.

---

## Manual Checks Needed

### MC-1: Windows debug build passes without errors or warnings

Run from the `example/` directory on a Windows machine:
```
fvm flutter build windows --debug
```
Expected: build exits with code 0. No C++ compilation errors or linker errors related to `ScreenLockStreamHandler`, `WTSRegisterSessionNotification`, or `Wtsapi32`. This validates:
- `handlers/screen_lock_stream_handler.cpp` compiles and links correctly.
- `namespace biometric_cipher` resolution is correct across `.h` and `.cpp`.
- `Wtsapi32` is linked via CMake (no pragma needed).
- All includes resolve: `<flutter/event_channel.h>`, `<flutter/event_stream_handler_functions.h>`, `<wtsapi32.h>`, etc.
- `biometric_cipher_plugin.h` includes the handler header without circular dependency issues.

### MC-2: Session lock smoke test — event emitted when Windows session is locked

On Windows hardware or a Windows VM:
1. Run the `example` app in debug mode: `fvm flutter run -d windows`.
2. Add a temporary `print` or `debugPrint` to the Dart subscription on `BiometricCipher.screenLockStream` (or observe via Dart DevTools), since full end-to-end lock behavior is not wired until Phases 6–8.
3. Lock the Windows session via `Win+L`, Ctrl+Alt+Del → Lock, or auto-lock timeout.
4. Observe: `WM_WTSSESSION_CHANGE` with `WTS_SESSION_LOCK` is received by the handler; `event_sink_->Success(true)` fires; the Dart stream emits `true`; the debug output shows the event within 2 seconds of session lock.
5. Unlock the session, observe no error or crash in the app.

### MC-3: Session unlock — no spurious event emitted

After locking (MC-2), unlock the session. Confirm that `WTS_SESSION_UNLOCK` does not produce an event on `screenLockStream` (the filter in `HandleWindowMessage` only matches `WTS_SESSION_LOCK`).

### MC-4: EventChannel channel name string matches exactly across all layers

Confirm:
- `biometric_cipher_plugin.cpp` line 54: `"biometric_cipher/screen_lock"`
- `BiometricCipherPlugin.kt` (Android): `"biometric_cipher/screen_lock"`
- `BiometricCipherPlugin.swift` (Apple): `"biometric_cipher/screen_lock"` (both iOS and macOS branches)
- `biometric_cipher_method_channel.dart`: `'biometric_cipher/screen_lock'`

All four match (verified by grep during this review). Visually re-confirm on the actual running build.

### MC-5: Subscribe → cancel → re-subscribe cycle (no crash, correct re-registration)

1. Ensure the Dart `screenLockStream` subscription is active (a temporary subscriber suffices for this phase).
2. Cancel the subscription. Verify `onCancel` fires: `UnregisterWindowProc()` is called, WTS is unregistered, delegate id resets to `-1`.
3. Re-subscribe. Verify `onListen` fires: `WTSRegisterSessionNotification` is called again, a new delegate id is assigned.
4. Lock the session. Verify the event is received on the re-subscribed stream.

### MC-6: Existing biometric and Windows Hello functionality unaffected

Run the example app on Windows and verify:
- Password-based unlock works.
- Windows Hello (biometric) unlock works.
- Key generation, encryption, decryption, key deletion operations succeed.
- Lock via timer still fires.
- No regressions in `HandleMethodCall` routing.

### MC-7: No changes outside Phase 4 scope

Confirm via `git diff --name-only` (relative to the Phase 3 state) that only the following files are added or modified:
- `packages/biometric_cipher/windows/include/biometric_cipher/handlers/screen_lock_stream_handler.h` (new)
- `packages/biometric_cipher/windows/handlers/screen_lock_stream_handler.cpp` (new)
- `packages/biometric_cipher/windows/biometric_cipher_plugin.cpp` (modified)
- `packages/biometric_cipher/windows/biometric_cipher_plugin.h` (modified)
- `packages/biometric_cipher/windows/CMakeLists.txt` (modified)
- `docs/tasklist-2349.md` (modified — Code Review Fix Task 7)
- `docs/phase/AW-2349/phase-4.md` (new — phase documentation)

No Dart files, no Android files, no Apple platform files, no example app files should be modified.

---

## Risk Zone

| Risk | Likelihood | Impact | Assessment |
|------|-----------|--------|------------|
| `WTSRegisterSessionNotification` return value is not checked; silent failure leaves stream open with no events | Low (standard desktop environment) | Low (graceful degradation; timer and resume-based locks remain active) | Acceptable. A future logging improvement is noted. |
| `GetView()->GetNativeWindow()` called in `UnregisterWindowProc` when the view may already be torn down | Very Low (Flutter plugin lifecycle normally ensures orderly teardown) | Medium (null dereference / crash during teardown) | No null guard on `GetView()`. Consistent with the reference implementation. Low risk in practice. |
| No return-value check on `WTSRegisterSessionNotification` means no distinction between "registered successfully" and "failed silently" | Low | Low | Graceful degradation. Noted for future improvement. |
| `screen_lock_channel` local variable destruction after `SetStreamHandler` — event channel ownership | None (resolved) | None | Flutter engine retains the channel registration independently; local `unique_ptr` destruction is safe. Verified by inspection. |
| `screen_lock_handler_` is a `public` member (not `private`) in `BiometricCipherPlugin` | Low (internal plugin code, no external callers) | Low | Pragmatic requirement of the static factory pattern. No external code can inadvertently modify it outside the plugin. |
| `onListen` called twice without `onCancel` — double WTS registration | Very Low (prevented by FlutterEventChannel contract) | Medium (double event delivery) | No defensive guard. Same design decision as Phases 2 and 3. Acceptable. |
| Windows session variations (RDP, fast user switch) — `WTS_SESSION_LOCK` may not fire in all lock scenarios | Low-Medium | Low (fallback via shouldLockOnResume) | Documented known limitation. PRD acceptance criteria cover the standard `Win+L` / auto-lock path. |
| No native C++ unit tests for `ScreenLockStreamHandler` | Certain | Medium (no regression coverage for WTS wiring) | Accepted. WTS API not mockable without abstraction. Manual MC-1 and MC-2 are required. Phase 5 adds Dart coverage. |
| Windows-only acceptance criterion — cannot be verified on macOS (current dev environment) | Certain (macOS dev machine) | Medium | Phase 4 build verification requires a Windows machine or VM. All other platforms were verifiable on macOS. |

---

## Final Verdict

**RELEASE WITH RESERVATIONS**

Phase 4 delivers a correct and complete Windows C++ native implementation of `ScreenLockStreamHandler`. The implementation closely follows the specification with two notable improvements: (1) copy constructor and assignment operator are explicitly deleted, preventing misuse; (2) `#pragma comment(lib, "Wtsapi32.lib")` is absent, with `Wtsapi32` linked exclusively via CMake `target_link_libraries`, consistent with the existing project build convention. The Code Review Fixes (Task 6: namespace, Task 7: tasklist) are both applied correctly.

All five required files (two new, three modified) are in place and structurally correct:
- `screen_lock_stream_handler.h` — present at correct path, `namespace biometric_cipher`, copy deleted, all API declarations match spec.
- `screen_lock_stream_handler.cpp` — present, `namespace biometric_cipher`, no pragma, correct WTS registration/unregistration lifecycle, `std::nullopt` passthrough.
- `biometric_cipher_plugin.cpp` — EventChannel created, stream handler wired, ownership transferred to plugin instance before `AddPlugin`.
- `biometric_cipher_plugin.h` — handler header included, `screen_lock_handler_` member declared.
- `CMakeLists.txt` — source file added to `PLUGIN_SOURCES`, `Wtsapi32` linked for both plugin and test runner targets.

The channel name `"biometric_cipher/screen_lock"` is consistent with all three previously validated layers (Dart, Android, iOS/macOS).

The reservation is **MC-1 + MC-2 (Windows build and session lock smoke test)**: the entire phase is Windows-only code and cannot be compiled or functionally verified on the macOS development machine used for this review. Before merging:
- **MC-1** (Windows debug build) must pass — this is the designated acceptance criterion from the phase document.
- **MC-2** (session lock smoke test) must confirm that locking the session with `Win+L` causes `event_sink_->Success(true)` to emit a `true` event through the Dart stream.
- **MC-3** (no spurious unlock event) should be confirmed alongside MC-2.

Without these verifications there is no assurance that:
- The C++ code compiles without errors on the Windows toolchain.
- `WTSRegisterSessionNotification` is called successfully with a valid HWND.
- The `WM_WTSSESSION_CHANGE` / `WTS_SESSION_LOCK` path is exercised end-to-end.
- The `EncodableValue(true)` payload decodes correctly as a Dart `bool` through `StandardMethodCodec`.

The absence of native C++ unit tests (NC-10) is an accepted gap per the project plan; no phase covers native Windows tests for this handler.

Phase 4 is ready to proceed to Phase 5 (plugin Dart unit tests) once MC-1, MC-2, and MC-3 are confirmed passing on Windows.
