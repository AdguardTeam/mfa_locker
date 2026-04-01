# AW-2349 Phase 2 Summary: Android Native — `ScreenLockStreamHandler`

**Ticket:** AW-2349
**Phase:** 2 of 8
**Status:** Released
**Date:** 2026-04-01
**Branch:** `feature/AW-2349-autolock-mfa` <!-- cspell:ignore autolock -->

---

## What Was Done

Phase 2 adds the Android native implementation that feeds events into the `EventChannel("biometric_cipher/screen_lock")` established in Phase 1. When the device screen turns off on Android, a `BroadcastReceiver` catches the `ACTION_SCREEN_OFF` intent and pushes `true` through the EventChannel to the Dart stream.

All changes are confined to `packages/biometric_cipher/android/`. No Dart files, no iOS/macOS/Windows files, no example app files, and no test files were modified.

---

## Why This Was Needed

Phase 1 wired the Dart side of the EventChannel — the `screenLockStream` getter existed and the channel was named. Without a native handler, no events would ever flow through it. Phase 2 provides the Android half of that bridge: a `BroadcastReceiver` that fires synchronously when the OS turns the screen off.

`ACTION_SCREEN_OFF` is chosen over `KeyguardManager.isKeyguardLocked()` deliberately: it fires the instant the screen turns off with no polling and no latency, and it triggers even on devices with no configured lock screen — which is the conservative, security-first behavior the MFA spec requires.

---

## Files Changed

| File | Change |
|------|--------|
| `packages/biometric_cipher/android/src/main/kotlin/com/adguard/cryptowallet/biometric_cipher/handlers/ScreenLockStreamHandler.kt` | **New file** — `EventChannel.StreamHandler` backed by a `BroadcastReceiver` for `ACTION_SCREEN_OFF` |
| `packages/biometric_cipher/android/src/main/kotlin/com/adguard/cryptowallet/biometric_cipher/BiometricCipherPlugin.kt` | Added `EventChannel` registration in `onAttachedToEngine` and cleanup in `onDetachedFromEngine` |

The `handlers/` directory is new. It sits alongside the pre-existing `SecureMethodCallHandler.kt` and `SecureMethodCallHandlerImpl.kt` files.

---

## Key Design Decisions

### Application context, not activity context

The `BroadcastReceiver` is registered with `flutterPluginBinding.applicationContext`. The activity may not exist when the screen turns off — using the activity context would risk a `NullPointerException` or a context that has already been torn down. Application context is stable for the process lifetime.

### Dynamic receiver registration only

`ACTION_SCREEN_OFF` is a protected broadcast. Android has never allowed it to be received via manifest registration — only via `registerReceiver()` at runtime. This aligns naturally with the EventChannel lifecycle: the receiver is registered in `onListen` and unregistered in `onCancel`. When the Dart stream has no listeners, there is no native receiver running.

### `EventChannel.StreamHandler` lifecycle pattern

`ScreenLockStreamHandler` implements `EventChannel.StreamHandler` directly:

- `onListen`: creates a new `BroadcastReceiver` inline, registers it with the application context, and stores the reference in `this.receiver`.
- `onCancel`: calls `applicationContext.unregisterReceiver(it)` via a safe-call on the nullable `receiver` field, then nullifies it.

This ensures a receiver is only active while at least one Dart listener is subscribed, and prevents a double-unregister crash if `onCancel` is called before `onListen`.

### Plugin-level field retention

`BiometricCipherPlugin` stores both the `EventChannel` and the `ScreenLockStreamHandler` as nullable class fields (`screenLockEventChannel`, `screenLockStreamHandler`). Holding the reference prevents the handler from being garbage-collected between `onAttachedToEngine` and `onDetachedFromEngine`. In `onDetachedFromEngine`, `setStreamHandler(null)` is called first (which triggers `onCancel` on any active subscription and causes the `BroadcastReceiver` to unregister), then both fields are nullified.

### Channel name string matches Phase 1 exactly

The string `"biometric_cipher/screen_lock"` appears as a literal in `BiometricCipherPlugin.kt`. This is unavoidable — Kotlin cannot import Dart constants. The string matches the `static const` field in `MethodChannelBiometricCipher` established in Phase 1. A mismatch would cause the stream to silently emit no events.

---

## Data Flow (after Phase 2)

```
Android OS: ACTION_SCREEN_OFF broadcast
        |
        v
ScreenLockStreamHandler.onReceive()
  events?.success(true)
        |
        v
EventChannel("biometric_cipher/screen_lock")
        |
        v
MethodChannelBiometricCipher.screenLockStream   <-- wired in Phase 1
        |
        v
BiometricCipher.screenLockStream
        |
        v
[Consumer code]                                 <-- wired in Phase 5
```

iOS/macOS and Windows native handlers are still absent (Phases 3–4). On those platforms the stream remains open but emits nothing.

---

## Edge Cases and Accepted Limitations

**App backgrounded when screen turns off.** The `BroadcastReceiver` is registered with the application context and will receive `ACTION_SCREEN_OFF` even when the Flutter engine is suspended. However, the EventChannel event may not be delivered to Dart while the engine is suspended. This is an accepted edge case: the existing `shouldLockOnResume` mechanism catches it when the app resumes — the timer will have expired and the locker locks via `_onAppResumed`.

**Screen off without a configured lock screen.** `ACTION_SCREEN_OFF` fires unconditionally — no check for `KeyguardManager.isKeyguardLocked()`. This is intentional. The MFA spec requires locking on every screen-off, even on unprotected devices.

**No native-side unit tests.** Android JVM/instrumented tests for `ScreenLockStreamHandler` are not part of this phase. The acceptance criterion for Phase 2 is a successful `fvm flutter build apk --debug`. Runtime behavior must be manually verified on a device or emulator (pressing the power button with the example app open). Dart-layer plugin tests are deferred to Phase 5.

**`onListen` double-call guard.** If `onListen` were called twice without an intervening `onCancel`, the first `BroadcastReceiver` would be overwritten and leaked. The Flutter EventChannel protocol guarantees this cannot happen — `onCancel` is always called before a second `onListen`. No defensive guard was added inside `onListen`; this is the accepted implementation per the QA review.

---

## Test Coverage

Phase 2 adds no automated tests. The coverage picture is:

| Layer | Status |
|-------|--------|
| Dart plugin tests (`biometric_cipher_test.dart`) | Carried forward from Phase 1; exercise the mock, not the Kotlin handler |
| Kotlin unit tests for `ScreenLockStreamHandler` | Not present — deferred to Phase 5 |
| `fvm flutter build apk --debug` (compilation check) | Required manual verification |
| End-to-end device smoke test (MC-3) | Required manual verification before merge |

---

## QA Verdict

**RELEASE WITH RESERVATIONS** — the QA review (dated 2026-04-01) confirmed:

- `ScreenLockStreamHandler.kt` is present in the new `handlers/` directory with the correct package declaration.
- All five imports are present; the class correctly implements `EventChannel.StreamHandler`.
- `onListen` registers the `BroadcastReceiver` using application context; `onCancel` unregisters safely.
- `BiometricCipherPlugin.kt` stores handler and channel as class fields; `onAttachedToEngine` setup and `onDetachedFromEngine` cleanup match the specification.
- Channel name string matches the Dart `static const` from Phase 1.
- No changes outside `packages/biometric_cipher/android/`.
- No existing Kotlin or Dart code removed or broken.

The reservation is MC-3: the Android APK build confirms compilation, but actual `ACTION_SCREEN_OFF` delivery and Dart-stream propagation must be verified on a physical device or emulator before the branch is fully validated.

---

## What Comes Next

| Phase | Scope |
|-------|-------|
| Phase 3 | iOS/macOS native handler (`ScreenLockStreamHandler.swift` using `protectedDataWillBecomeUnavailableNotification` on iOS and `com.apple.screenIsLocked` on macOS) |
| Phase 4 | Windows native handler (`ScreenLockStreamHandler.cpp/.h` using `WTS_SESSION_LOCK`) |
| Phase 5 | Plugin Dart tests + example app wiring (`ScreenLockService`, DI, `LockerBloc` integration) |

No changes to the Dart plugin layer or the Android implementation are expected when Phases 3–5 land.

---

## Reference Documents

- Plan/Tasklist: `docs/phase/AW-2349/phase-2.md`
- QA: `docs/qa/AW-2349-phase-2.md`
- Idea/context: `docs/idea-2349.md`
- Vision: `docs/vision-2349.md`
- Phase 1 summary: `docs/AW-2349-phase-1-summary.md`
