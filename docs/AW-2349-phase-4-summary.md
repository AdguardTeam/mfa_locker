# AW-2349 Phase 4 Summary: Windows Native — `ScreenLockStreamHandler` (C++)

**Ticket:** AW-2349
**Phase:** 4 of 8
**Status:** Released
**Date:** 2026-04-01
**Branch:** `feature/AW-2349-autolock-mfa` <!-- cspell:ignore autolock -->

---

## What Was Done

Phase 4 adds the Windows C++ native side of the `EventChannel("biometric_cipher/screen_lock")` contract. It creates two new C++ files (a header and an implementation) and modifies three existing files in `packages/biometric_cipher/windows/`. With Phase 4 in place, `BiometricCipher.screenLockStream` emits `true` on Windows when the user locks their session.

All changes are confined to `packages/biometric_cipher/windows/`. No Dart files, no Android files, no Apple platform files, no example app files, and no test files were modified.

A post-implementation code review produced two follow-up fixes tracked as Tasks 6 and 7: wrapping `ScreenLockStreamHandler` in `namespace biometric_cipher` for consistency with all other headers in the plugin, and syncing the main tasklist to show Phase 4 complete.

---

## Why This Was Needed

Phase 1 established the Dart `EventChannel` wiring, Phase 2 delivered the Android handler, and Phase 3 delivered the iOS/macOS handler. Without Phase 4, `BiometricCipher.screenLockStream` would emit nothing on Windows — the Dart channel was open but had no native sender on that platform.

Windows session lock detection uses a fundamentally different mechanism from the other platforms. There is no notification center or broadcast receiver. Instead, the Windows Terminal Services API must be used:

1. `WTSRegisterSessionNotification(hwnd, NOTIFY_FOR_THIS_SESSION)` tells the OS to deliver `WM_WTSSESSION_CHANGE` window messages to the Flutter window when the current user's session state changes.
2. A `RegisterTopLevelWindowProcDelegate` hook intercepts those window messages before the default procedure processes them.
3. When `wParam == WTS_SESSION_LOCK`, a `true` value is pushed through the Flutter `EventSink`.

Using `NOTIFY_FOR_THIS_SESSION` (rather than `NOTIFY_FOR_ALL_SESSIONS`) means the handler only fires for the current user's own session lock — not for lock events in other concurrent remote desktop sessions on the same machine.

---

## Files Changed

| File | Change |
|------|--------|
| `packages/biometric_cipher/windows/include/biometric_cipher/handlers/screen_lock_stream_handler.h` | **New file** — `ScreenLockStreamHandler` class declaration in `namespace biometric_cipher` |
| `packages/biometric_cipher/windows/handlers/screen_lock_stream_handler.cpp` | **New file** — `ScreenLockStreamHandler` implementation in `namespace biometric_cipher` |
| `packages/biometric_cipher/windows/biometric_cipher_plugin.cpp` | Added `EventChannel("biometric_cipher/screen_lock")` registration in `RegisterWithRegistrar` |
| `packages/biometric_cipher/windows/biometric_cipher_plugin.h` | Added `#include` for the handler header and `screen_lock_handler_` public member field |
| `packages/biometric_cipher/windows/CMakeLists.txt` | Added `handlers/screen_lock_stream_handler.cpp` to `PLUGIN_SOURCES`; linked `Wtsapi32` for both the plugin and test runner targets |
| `docs/tasklist-2349.md` | Code Review Fix Task 7: all Phase 4 checkboxes marked `[x]`, progress table updated to Done |
| `docs/phase/AW-2349/phase-4.md` | New phase document |

Two new directories were created: `packages/biometric_cipher/windows/handlers/` and `packages/biometric_cipher/windows/include/biometric_cipher/handlers/`. The header placement under `include/biometric_cipher/handlers/` mirrors the existing layout convention for all other headers in this plugin.

---

## Key Design Decisions

### `WTSRegisterSessionNotification` + `RegisterTopLevelWindowProcDelegate`

Windows does not expose a notification center or message bus that Dart can directly observe. The only supported path for session change events is the Win32 window message pump. The handler registers a WTS notification listener on the Flutter window's HWND and hooks into the window procedure via `RegisterTopLevelWindowProcDelegate`. The delegate returns `std::nullopt` for all messages, including the ones it handles, so that other registered delegates and the default window procedure continue to receive them.

### Handler lifetime tied to the plugin instance

`ScreenLockStreamHandler` is owned by a `std::unique_ptr<ScreenLockStreamHandler> screen_lock_handler_` public member field on `BiometricCipherPlugin`. It is constructed in the static `RegisterWithRegistrar` method (where the registrar is available) and assigned to `plugin->screen_lock_handler_` before `registrar->AddPlugin(std::move(plugin))`. Making the field public is a pragmatic necessity of the static factory pattern — it avoids adding a constructor parameter or setter to the plugin class. All other member fields on the plugin are private; this is the only exception.

### WTS listener lifetime tied to the Dart stream subscription

`WTSRegisterSessionNotification` and `RegisterTopLevelWindowProcDelegate` are called in `onListen` (when the Dart side subscribes to the stream) via `RegisterWindowProc()`. `WTSUnRegisterSessionNotification` and `UnregisterTopLevelWindowProcDelegate` are called in `onCancel` (when the subscription is cancelled) via `UnregisterWindowProc()`. The destructor also calls `UnregisterWindowProc()` as a safety net for engine shutdown paths where `onCancel` may not fire. A sentinel value (`window_proc_delegate_id_ = -1`) guards against double-unregistration: `UnregisterWindowProc()` only proceeds when the id is `>= 0` and resets it to `-1` afterwards.

### CMake-only linking of `Wtsapi32`

The phase document's reference code included `#pragma comment(lib, "Wtsapi32.lib")`. The actual implementation omits this pragma and links `Wtsapi32` exclusively through `target_link_libraries` in `CMakeLists.txt`. This is consistent with how all other Windows system libraries (`ncrypt`, `windowsapp`) are handled in this plugin. `Wtsapi32` is added to both the plugin target and the test runner target (line 167), because `PLUGIN_SOURCES` — which now includes `handlers/screen_lock_stream_handler.cpp` — is compiled directly into the test binary.

### `namespace biometric_cipher` (Code Review Fix, Task 6)

The initial implementation placed `ScreenLockStreamHandler` outside any namespace, matching the original spec. A post-implementation code review found that every other header under `windows/include/biometric_cipher/` uses `namespace biometric_cipher`. Both the header and the implementation were updated to wrap `ScreenLockStreamHandler` in the namespace. The `biometric_cipher_plugin.cpp` already operates inside `namespace biometric_cipher { ... }`, so the bare class name continues to resolve correctly there.

### Copy constructor and assignment operator deleted

The header explicitly deletes the copy constructor and copy assignment operator. This goes beyond the original spec, which did not specify these deletions. The class holds a `unique_ptr<EventSink>` (inherently non-copyable) and a raw HWND-tied registrar pointer, so copying would be semantically incorrect. Making the deletions explicit prevents accidental misuse and self-documents the class's ownership semantics.

### No `GetView()` null guard

`RegisterWindowProc()` calls `registrar_->GetView()->GetNativeWindow()` without checking whether `GetView()` returns null. The PRD resolved that no null guard is needed: `onListen` only fires after the Flutter engine is fully initialized, so `GetView()` is guaranteed to return a valid pointer at that point. The same call in `UnregisterWindowProc()` carries a small theoretical risk if called during an unusual teardown sequence where the view is already destroyed; this is accepted as low-risk given the normal Flutter plugin lifecycle.

---

## Data Flow (after Phase 4)

```
Windows OS locks session (Win+L, auto-lock, screen timeout with lock)
    |
    v
WM_WTSSESSION_CHANGE delivered to Flutter window message queue (main thread)
    |
    v
RegisterTopLevelWindowProcDelegate lambda fires HandleWindowMessage()
    |
    v
wParam == WTS_SESSION_LOCK?  -- No --> return std::nullopt (pass to other handlers)
    |
    Yes
    v
event_sink_ non-null?  -- No --> return std::nullopt (no Dart listener active)
    |
    Yes
    v
event_sink_->Success(flutter::EncodableValue(true))
    |
    v
EventChannel("biometric_cipher/screen_lock")
    |
    v
MethodChannelBiometricCipher.screenLockStream (Dart, wired in Phase 1)
    |
    v
BiometricCipher.screenLockStream
```

`WM_WTSSESSION_CHANGE` is delivered on the Windows message pump thread, which is the Flutter main thread. No thread marshalling is needed before calling `event_sink_->Success(...)`.

---

## Channel Name Consistency

The string `"biometric_cipher/screen_lock"` is used identically across all four platform layers:

| Platform | File |
|----------|------|
| Dart | `biometric_cipher_method_channel.dart` (Phase 1) |
| Android | `BiometricCipherPlugin.kt` (Phase 2) |
| iOS/macOS | `BiometricCipherPlugin.swift` (Phase 3) |
| Windows | `biometric_cipher_plugin.cpp` (Phase 4) |

A mismatch in any of these strings would cause the stream to silently emit nothing on that platform.

---

## Edge Cases and Accepted Limitations

**`WTSRegisterSessionNotification` return value not checked.** `RegisterWindowProc()` discards the `BOOL` return value. If the call fails silently (e.g., in a constrained or unusual environment), the window proc delegate is registered but `WM_WTSSESSION_CHANGE` messages are never received. The stream remains open with no events and no error. Graceful degradation: the timer-based and resume-based lock mechanisms remain active. No diagnostic logging is emitted.

**`GetView()->GetNativeWindow()` in `UnregisterWindowProc`.** Re-fetching the HWND during unregistration (rather than caching it at registration time) is a minor risk during unusual plugin teardown sequences. Under normal Flutter engine shutdown ordering, the registrar and view are still valid at the time `UnregisterWindowProc()` is called from the destructor.

**App minimized or message loop stalled.** `WM_WTSSESSION_CHANGE` is a window message delivered via the message pump. If the UI thread is blocked on a long synchronous operation, the event is deferred until the pump resumes. For the security-critical path (locker unlocked → screen locked), the app is expected to be responsive. The existing `shouldLockOnResume` mechanism handles missed events on next app resume.

**Remote Desktop / Fast User Switching.** `NOTIFY_FOR_THIS_SESSION` restricts delivery to the current user's own session. `WTS_REMOTE_DISCONNECT` events (user disconnects RDP without locking) are not forwarded — `HandleWindowMessage` checks `WTS_SESSION_LOCK` only. This is the correct behavior for the PRD requirement (standard Win+L / auto-lock path). RDP disconnect locking is not covered.

**No `onListen`-before-`onCancel` guard.** If `onListen` were called twice without an intervening `onCancel`, `WTSRegisterSessionNotification` would register twice and the window proc delegate would be added a second time, producing duplicate events. The `FlutterEventChannel` contract guarantees this cannot happen under normal operation. No defensive guard is added at the start of `onListen`, matching the same decision made in Phase 2 (Android) and Phase 3 (iOS/macOS).

---

## Test Coverage

Phase 4 adds no new automated tests. All new code is C++ and can only be exercised in a live Windows process with a valid HWND and a WTS-capable session. Native C++ unit tests for `ScreenLockStreamHandler` are not planned anywhere in the ticket — `WTSRegisterSessionNotification` requires a real Windows session and cannot be mocked without abstracting the entire Windows API surface.

| Layer | Status |
|-------|--------|
| Dart plugin tests (`biometric_cipher_test.dart`) | Carried forward from Phase 1; exercise the mock platform, not the C++ handler |
| Native C++ unit tests for `ScreenLockStreamHandler` | Not present — accepted gap per plan |
| Windows debug build (`fvm flutter build windows --debug`) | Primary acceptance criterion; requires Windows machine |
| Session lock smoke test (MC-2) | Manual verification required on Windows hardware or VM |
| Existing Windows C++ unit tests | Unaffected by Phase 4; `Wtsapi32` now linked for the test runner target |

---

## QA Verdict

**RELEASE WITH RESERVATIONS** — the QA review (dated 2026-04-01) confirmed that all five deliverables and both code review fixes are fully and correctly implemented:

- `screen_lock_stream_handler.h` is present at the correct path, inside `namespace biometric_cipher`, with the copy constructor and assignment operator explicitly deleted, all required includes present, and private members and methods matching the spec.
- `screen_lock_stream_handler.cpp` is present at the correct path, inside `namespace biometric_cipher`, with no `#pragma comment`, correct WTS registration and unregistration lifecycle, `std::nullopt` passthrough, and the `if (event_sink_)` defensive guard in `HandleWindowMessage`.
- `biometric_cipher_plugin.cpp` creates the `EventChannel`, calls `SetStreamHandler`, and moves handler ownership to `plugin->screen_lock_handler_` before `AddPlugin`.
- `biometric_cipher_plugin.h` includes the handler header and declares the `screen_lock_handler_` public member.
- `CMakeLists.txt` adds the source file to `PLUGIN_SOURCES` and links `Wtsapi32` for both the plugin and test runner targets.

The reservation is **MC-1 + MC-2**: the Windows debug build and session lock smoke test must be confirmed on a Windows machine before the branch is fully validated. All new code is Windows-only and cannot be compiled or functionally verified on the macOS development machine used for this review.

---

## What Comes Next

| Phase | Scope |
|-------|-------|
| Phase 5 | Plugin Dart unit tests — add `screenLockStream` to the mock platform, add test group in `biometric_cipher_test.dart` |
| Phase 6 | Example app `ScreenLockService` — new `screen_lock_service.dart` wrapping `BiometricCipher.screenLockStream`, mirroring `TimerService` |
| Phase 7 | Example app DI wiring — `RepositoryFactory`, `BlocFactory`, `main.dart`, `LockerEvent.screenLocked` + code generation |
| Phase 8 | Example app `LockerBloc` integration — `screenLocked` handler, start/stop listening on unlock/lock state transitions, `dispose()` |

No changes to the Dart plugin layer, the Android implementation, or the iOS/macOS implementation are expected in the remaining phases.

---

## Reference Documents

- Phase document / tasklist: `docs/phase/AW-2349/phase-4.md`
- PRD: `docs/prd/AW-2349-phase-4.prd.md`
- Plan: `docs/plan/AW-2349-phase-4.md`
- QA: `docs/qa/AW-2349-phase-4.md`
- Idea/context: `docs/idea-2349.md`
- Vision: `docs/vision-2349.md`
- Phase 3 summary: `docs/AW-2349-phase-3-summary.md`
- Phase 2 summary: `docs/AW-2349-phase-2-summary.md`
- Phase 1 summary: `docs/AW-2349-phase-1-summary.md`
