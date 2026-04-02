# AW-2349-phase-6: Screen Lock Detection — Example App `ScreenLockService`

Status: PRD_READY

## Context / Idea

MFA spec Section 8 requires: "if the device is locked (lock screen) → lock immediately." The full feature (AW-2349) adds native screen lock detection across Android, iOS, macOS, and Windows via an `EventChannel` in the `biometric_cipher` plugin, then wires it through the example app's architecture.

Phases 1–5 are complete:
- **Phase 1:** Dart plugin layer — `screenLockStream` on `BiometricCipherPlatform`, `MethodChannelBiometricCipher`, and `BiometricCipher`.
- **Phase 2:** Android native handler (`ScreenLockStreamHandler.kt` + `BroadcastReceiver` for `ACTION_SCREEN_OFF`).
- **Phase 3:** iOS/macOS native handler (`ScreenLockStreamHandler.swift` using `protectedDataWillBecomeUnavailableNotification` / `com.apple.screenIsLocked`).
- **Phase 4:** Windows native handler (`ScreenLockStreamHandler.cpp/.h` using `WTS_SESSION_LOCK`).
- **Phase 5:** Plugin-level unit tests for `screenLockStream`.

**Phase 6 (this phase)** introduces the single new Dart class in the example app layer: `ScreenLockService`. This service wraps `BiometricCipher.screenLockStream` behind a callback interface identical in shape to the existing `TimerService`. It is the bridge between the plugin stream and `LockerBloc` (which is wired in Phase 7/8).

The `ScreenLockService` class is intentionally minimal — it has no business logic of its own. Its entire purpose is lifecycle management of the stream subscription and callback delivery. It reuses the `BiometricCipher` instance already created in `RepositoryFactoryImpl`.

### Affected files (Phase 6 only)

| File | Change |
|------|--------|
| `example/lib/core/services/screen_lock_service.dart` | **NEW** — `ScreenLockService` abstract class + `ScreenLockServiceImpl` |

No other files are modified in this phase.

---

## Goals

1. Create `example/lib/core/services/screen_lock_service.dart` containing the `ScreenLockService` abstract class and its `ScreenLockServiceImpl` implementation.
2. `ScreenLockService` API mirrors `TimerService`: `onScreenLockedCallback` setter, `startListening()`, `stopListening()`, `dispose()`.
3. `ScreenLockServiceImpl` subscribes to `BiometricCipher.screenLockStream` in `startListening()` and cancels the subscription in `stopListening()` / `dispose()`.
4. Calling `startListening()` a second time safely replaces the existing subscription (no double-fire).
5. `dispose()` cancels the subscription and nulls the callback reference, leaving the instance inert.
6. Pass `cd example && fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` with zero warnings or infos.

---

## User Stories

**As a future DI wiring author (Phase 7)**, I want a `ScreenLockService` interface and `ScreenLockServiceImpl` class available in `example/lib/core/services/`, so that I can instantiate and inject it into `LockerBloc` without needing to interact with the plugin `EventChannel` directly.

**As a future BLoC integration author (Phase 8)**, I want to set `screenLockService.onScreenLockedCallback` and call `startListening()` / `stopListening()`, so that the locker locks immediately when the device screen locks.

**As a developer reviewing the code**, I want `ScreenLockService` to follow the same pattern as `TimerService`, so that the codebase stays consistent and the new service requires no new architectural concepts to understand.

---

## Main Scenarios

### Scenario 1 — Normal subscription lifecycle
- `ScreenLockServiceImpl` is created with a `BiometricCipher` instance.
- Caller sets `onScreenLockedCallback`.
- Caller calls `startListening()`.
- Native screen lock fires → stream emits `true` → `_onScreenLocked?.call()` is invoked.
- Caller calls `stopListening()`.
- A subsequent stream emission does **not** invoke the callback.

### Scenario 2 — Double `startListening()` call (safe re-subscribe)
- Caller calls `startListening()` twice in a row.
- The first subscription is cancelled before the second is created.
- Only one callback invocation occurs per stream event (no double-fire).

### Scenario 3 — `stopListening()` before any `startListening()`
- Caller calls `stopListening()` without having called `startListening()`.
- `_subscription` is `null`; `cancel()` is a no-op on `null`.
- No exception is thrown.

### Scenario 4 — `dispose()` cleanup
- Caller sets a callback, calls `startListening()`, then calls `dispose()`.
- `dispose()` calls `stopListening()` (subscription cancelled) and sets `_onScreenLocked = null`.
- Subsequent stream events are not delivered and the callback reference is gone (no memory leak).

### Scenario 5 — No callback set, stream emits
- Caller calls `startListening()` without ever setting `onScreenLockedCallback`.
- Stream emits `true`.
- `_onScreenLocked?.call()` is a safe no-op (null-safe call).
- No exception is thrown.

---

## Success / Metrics

| Criterion | How verified |
|-----------|-------------|
| `screen_lock_service.dart` file created in `example/lib/core/services/` | File present in diff |
| `ScreenLockService` abstract class defines `onScreenLockedCallback` setter, `startListening()`, `stopListening()`, `dispose()` | Code review |
| `ScreenLockServiceImpl` constructor takes `required BiometricCipher biometricCipher` | Code review |
| `startListening()` cancels any existing subscription before creating a new one | Code review / unit test |
| `stopListening()` cancels the subscription and sets it to `null` | Code review / unit test |
| `dispose()` calls `stopListening()` and nulls `_onScreenLocked` | Code review / unit test |
| `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` (scoped to `example/`) passes | CI analyze step |
| No changes outside `example/lib/core/services/screen_lock_service.dart` | Diff scope |

---

## Constraints and Assumptions

- **Single file scope:** Phase 6 adds exactly one new file. DI wiring (`repository_factory.dart`, `bloc_factory.dart`, `main.dart`) is out of scope — that is Phase 7.
- **No tests in this phase:** Unit tests for `ScreenLockServiceImpl` are specified in the idea document but are not assigned to Phase 6. They are created when the service is exercisable through a DI-injected mock (Phase 7+) or as a standalone unit if Phase 6 scope is widened.
- **`BiometricCipher` is a required dependency:** `ScreenLockServiceImpl` takes `required BiometricCipher biometricCipher` — no default is provided. The caller (DI layer, Phase 7) is responsible for passing the existing instance.
- **No code generation:** The file is pure Dart with no Freezed, build_runner, or generated code.
- **`import 'dart:async'` required:** `StreamSubscription<bool>` is used from `dart:async`.
- **Follows `TimerService` pattern:** Abstract class with no prefix (`ScreenLockService`), implementation with `Impl` suffix (`ScreenLockServiceImpl`) — per project conventions.
- **Stream subscription type is `StreamSubscription<bool>?`:** Matches `BiometricCipher.screenLockStream` which is `Stream<bool>`.
- **Callback type is `void Function()`:** The stream event payload (`bool`) is discarded in the callback — only the occurrence matters, not the value. This matches the design intent (lock event is fire-and-forget, no payload needed by the caller).
- **`_onScreenLocked` is nullable:** Not set in constructor; set via the callback setter after construction. `dispose()` nulls it to prevent stale references.
- **Analyze scope:** Acceptance criterion runs analyze on `example/` only, not on the root package or `packages/biometric_cipher/`.

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| `subscription.cancel()` is asynchronous — a stale event could arrive between cancel and null assignment | Low | Low | Dart `StreamSubscription.cancel()` prevents future event delivery even if the future is not awaited; callback is null-safe |
| Naming divergence from `TimerService` makes the pattern harder to follow | Low | Low | PRD explicitly calls out the mirroring requirement; code review enforces it |
| File placed in wrong directory | Low | Low | Phase task specifies `example/lib/core/services/screen_lock_service.dart` explicitly |
| `BiometricCipher.screenLockStream` accessed before the engine is ready | Very Low | Low | `late final` stream initialization in `MethodChannelBiometricCipher` defers until first access; no eager initialization |

---

## Open Questions

_(none — scope is fully specified by the phase task description and the technical details in `docs/idea-2349.md` Section E)_
