# AW-2349 Phase 1 Summary: Dart Plugin Layer — `screenLockStream`

**Ticket:** AW-2349
**Phase:** 1 of 8
**Status:** Released
**Date:** 2026-04-01
**Branch:** `feature/AW-2349-autolock-mfa` <!-- cspell:ignore autolock -->

---

## What Was Done

Phase 1 adds the Dart-side foundation for screen lock detection inside the `biometric_cipher` plugin. It establishes a `screenLockStream` getter (`Stream<bool>`) through the three layers of the plugin and wires up the test infrastructure. No native code was touched — the native handlers for Android, iOS/macOS, and Windows are the subjects of Phases 2–4.

All changes are confined to `packages/biometric_cipher/`. No files in `lib/`, `example/`, or the repo root were modified.

---

## Why This Was Needed

MFA spec Section 8 requires the app to lock immediately when the device screen is locked. The existing auto-lock mechanism only handles two cases: timer expiration (`TimerService`) and background timeout on app resume (`shouldLockOnResume`). There was no path for detecting a lock event while the app is actively in the foreground.

The full solution (AW-2349) adds a native `EventChannel` to the `biometric_cipher` plugin. Phase 1 establishes the agreed channel name, the Dart type contract, and the public API surface that all subsequent phases depend on.

---

## Files Changed

| File | Change |
|------|--------|
| `packages/biometric_cipher/lib/biometric_cipher_platform_interface.dart` | Added `screenLockStream` getter with `const Stream<bool>.empty()` default |
| `packages/biometric_cipher/lib/biometric_cipher_method_channel.dart` | Added `static const EventChannel` field and `late final Stream<bool>` override |
| `packages/biometric_cipher/lib/biometric_cipher.dart` | Added public `screenLockStream` getter delegating to the platform instance |
| `packages/biometric_cipher/test/mock_biometric_cipher_platform.dart` | Added public `StreamController<bool>.broadcast()` field and `screenLockStream` override |
| `packages/biometric_cipher/test/biometric_cipher_test.dart` | Added `group('screenLockStream', ...)` with three test cases |

No files were created; no files outside `packages/biometric_cipher/` were touched.

---

## Key Design Decisions

### EventChannel name as a `static const` field

The channel name `"biometric_cipher/screen_lock"` is declared as a `static const` field on `MethodChannelBiometricCipher`:

```dart
static const _screenLockEventChannel = EventChannel('biometric_cipher/screen_lock');
```

Keeping it as a single compile-time constant prevents typo mismatches between the Dart layer and the native handlers added in Phases 2–4. Native authors reference this string when registering their handlers.

### `late final` for the stream field

The stream field on `MethodChannelBiometricCipher` is `late final`:

```dart
@override
late final Stream<bool> screenLockStream = _screenLockEventChannel
    .receiveBroadcastStream()
    .map((event) => event as bool);
```

This means the native subscription is created only when the stream is first accessed, and then cached. No matter how many Dart listeners subscribe, only one native subscription is opened. `receiveBroadcastStream()` returns a broadcast stream, so multiple Dart listeners work correctly.

### Safe default for unsupported platforms

`BiometricCipherPlatform` (the abstract base) returns `const Stream<bool>.empty()` rather than throwing `UnimplementedError`. This means platforms that have not yet added a native handler silently emit nothing, rather than crashing. The behavior is correct for Phase 1, where no native handler exists anywhere.

### No `_configured` guard

`BiometricCipher.screenLockStream` can be accessed without calling `configure()` first. Screen lock detection is an OS-initiated, passive event with no dependency on biometric authentication. This is consistent with how `getTPMStatus`, `getBiometryStatus`, `generateKey`, `encrypt`, `deleteKey`, and `isKeyValid` work — only `decrypt` carries the configuration guard.

### `Stream<bool>` type

The stream is typed as `Stream<bool>` rather than `Stream<void>`. This reserves the `false` value for a potential future unlock signal, and it matches the raw `EventChannel` payload type. In practice, only `true` (device locked) is emitted by native handlers.

### Mock uses a public `StreamController<bool>.broadcast()` field

The mock platform follows the existing convention in the file (public fields for test-observable state). The controller is broadcast to mirror the real implementation's broadcast stream behavior.

---

## Data Flow

```
[Native OS screen lock event]         <-- not active in Phase 1; wired in Phases 2-4
        |
        v
EventChannel("biometric_cipher/screen_lock")
        |
        v
MethodChannelBiometricCipher.screenLockStream
  (late final, initialized on first access)
  = _screenLockEventChannel
      .receiveBroadcastStream()
      .map((event) => event as bool)
        |
        v
BiometricCipher.screenLockStream
  => _instance.screenLockStream
        |
        v
[Consumer code]                       <-- wired in Phase 5 (example app)
```

In Phase 1, the native end of the channel has no handler registered. The stream is open and valid; it emits no events until a native handler is added in a subsequent phase.

---

## Test Coverage

Three new test cases were added inside the existing `'BiometricCipher tests'` group in `biometric_cipher_test.dart`:

| Test | What it verifies |
|------|-----------------|
| `emits events from platform` | Adding `true` to `mockPlatform.screenLockStreamController` propagates to `biometricCipher.screenLockStream` |
| `works without configure` | Accessing `screenLockStream` without calling `configure()` does not throw |
| `emits multiple events` | Three sequential `true` additions are all received in order |

All pre-existing test groups (`configure`, `encrypt-decrypt cycle`, `generateKey`, `encrypt`, `decrypt`, `deleteKey`, `isKeyValid`) remain green.

**Known gaps (accepted for Phase 1):**
- No dedicated test for the default platform returning `Stream<bool>.empty()` directly (NC-4 in QA). The implementation is a one-liner with a trivially safe return expression.
- The `screenLockStreamController` is not explicitly closed in a `tearDown`. Broadcast controllers do not require explicit closing; the mock is recreated on each `setUp`. No functional impact.
- No test for the `false` value path or invalid payload casting — deferred to the native phases.

---

## QA Verdict

**RELEASE** — all acceptance criteria met. The QA review (dated 2026-04-01) confirmed:
- All three target files implement the agreed API contract.
- The EventChannel name is a single `static const` string.
- No changes outside `packages/biometric_cipher/`.
- No existing tests broken.
- Static analysis passes with zero warnings/infos.

---

## What Comes Next

| Phase | Scope |
|-------|-------|
| Phase 2 | Android native handler (`ScreenLockStreamHandler.kt` using `ACTION_SCREEN_OFF` `BroadcastReceiver`) |
| Phase 3 | iOS/macOS native handler (`ScreenLockStreamHandler.swift` using `protectedDataWillBecomeUnavailableNotification` / `com.apple.screenIsLocked`) |
| Phase 4 | Windows native handler (`ScreenLockStreamHandler.cpp/.h` using `WTS_SESSION_LOCK`) |
| Phase 5 | Example app wiring (`ScreenLockService`, DI, `LockerBloc` integration) |

The Dart plumbing from Phase 1 requires no changes when native handlers are added. Each native phase only needs to register a stream handler for `"biometric_cipher/screen_lock"` and push `true` when the OS signals a lock.

---

## Reference Documents

- PRD: `docs/prd/AW-2349-phase-1.prd.md`
- Plan: `docs/plan/AW-2349-phase-1.md`
- Tasklist: `docs/phase/AW-2349/phase-1.md`
- QA: `docs/qa/AW-2349-phase-1.md`
- Idea/context: `docs/idea-2349.md`
