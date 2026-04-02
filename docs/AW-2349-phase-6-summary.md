# AW-2349 Phase 6 Summary: Example App — `ScreenLockService`

**Ticket:** AW-2349
**Phase:** 6 of 8
**Status:** Released
**Date:** 2026-04-02
**Branch:** `feature/AW-2349-autolock-mfa` <!-- cspell:ignore autolock -->

---

## What Was Done

Phase 6 adds a single new Dart file to the example app layer:

```
example/lib/core/services/screen_lock_service.dart
```

The file contains two types: the `ScreenLockService` abstract class and its `ScreenLockServiceImpl` concrete implementation. The service wraps `BiometricCipher.screenLockStream` behind a callback interface, bridging the plugin's `EventChannel` to whatever consumer wires it in (the `LockerBloc`, in the upcoming Phase 8).

No other files were created or modified in this phase. DI wiring, BLoC integration, and unit tests are all explicitly deferred to Phases 7 and 8.

---

## Why This Was Needed

Phases 1–5 built the complete plugin layer: the Dart `EventChannel` API (`screenLockStream`), native stream handlers on Android (Kotlin `BroadcastReceiver`), iOS/macOS (Swift `NSNotificationCenter`/`DistributedNotificationCenter`), and Windows (C++ `WTSRegisterSessionNotification`), plus plugin-level unit tests. The plugin can now detect screen lock events on all four platforms and surface them as a `Stream<bool>`.

The example app's architecture (UI → BLoC → Repository → MFALocker) requires a service layer abstraction between the raw plugin stream and the BLoC. Phase 6 creates that abstraction in the form of `ScreenLockService`, following exactly the same pattern as the already-existing `TimerService`. Without this class in place, Phase 7 (DI wiring) and Phase 8 (BLoC integration) have nothing to inject or use.

---

## Files Changed

| File | Change |
|------|--------|
| `example/lib/core/services/screen_lock_service.dart` | **New file** — `ScreenLockService` abstract class + `ScreenLockServiceImpl` |

---

## API

### `ScreenLockService` (abstract class)

```dart
abstract class ScreenLockService {
  set onScreenLockedCallback(void Function() onLock);
  void startListening();
  void stopListening();
  void dispose();
}
```

### `ScreenLockServiceImpl`

```dart
class ScreenLockServiceImpl implements ScreenLockService {
  ScreenLockServiceImpl({required BiometricCipher biometricCipher});
}
```

The constructor takes a `required BiometricCipher biometricCipher` parameter. The `BiometricCipher` instance already exists in `RepositoryFactoryImpl` (used for biometric encrypt/decrypt operations). Phase 7 will pass that existing instance to `ScreenLockServiceImpl` — no second plugin instance is created.

---

## Key Design Decisions

### Mirrors `TimerService` exactly

`ScreenLockService` is designed to be structurally identical to `TimerService`. A developer who understands one service immediately understands the other. The mapping is:

| `TimerService` | `ScreenLockService` | Notes |
|----------------|---------------------|-------|
| `set onLockCallback` | `set onScreenLockedCallback` | Nullable `void Function()?` internally |
| `startTimer()` | `startListening()` | Sync — no async init needed |
| `stopTimer()` | `stopListening()` | Cancels subscription, sets to null |
| `dispose()` | `dispose()` | Calls stop, nulls callback |
| `_lockTimer` (`Timer?`) | `_subscription` (`StreamSubscription<bool>?`) | Mutable resource |
| `_onLock` (`void Function()?`) | `_onScreenLocked` (`void Function()?`) | Nullable callback via setter |

Both abstract class and `Impl` class live in one file (matching `timer_service.dart`), which is a sanctioned exception to the one-type-per-file rule for the service pattern.

### Lifecycle tied to locker state

`startListening()` is designed to be called from `LockerBloc` on unlock; `stopListening()` is called on lock. When the locker is in its locked state, the native platform subscription is inactive, meaning there is zero CPU overhead at rest. This matches the `TimerService` lifecycle, where the timer only runs while the locker is unlocked.

### Safe re-subscribe

`startListening()` always cancels any existing `_subscription` before creating a new one. This prevents double-fire if the caller happens to call `startListening()` twice without an intervening `stopListening()`. After `stopListening()`, subsequent stream events are not delivered. After `dispose()`, the callback reference is nulled, preventing stale closure retention.

### Stream payload discarded

`BiometricCipher.screenLockStream` emits `Stream<bool>`. The `bool` value (`true` on lock) is intentionally ignored inside the `listen` callback via the `_` parameter. Only the occurrence of the event matters — the callback is `void Function()`, carrying no payload. This keeps the consumer API maximally simple and matches the "lock immediately" semantics of the MFA spec.

### No code generation

The file is pure Dart. No Freezed annotations, no `part` directives, no `build_runner` pass needed. The service is compilable immediately.

---

## Data Flow (Phase 6's scope)

```
BiometricCipher.screenLockStream  <--  EventChannel  <--  native ScreenLockStreamHandler
        |
        | .listen((_) { ... })    [created in startListening()]
        v
ScreenLockServiceImpl._subscription
        |
        | _onScreenLocked?.call()
        v
[callback — not wired until Phase 8]
```

At the Phase 6 boundary, `ScreenLockService` exists as a standalone class with no active consumers. The data flow terminates at the null-safe callback invocation.

---

## Behavioral Contracts Verified

All five functional scenarios from the PRD are satisfied by the implementation:

1. **Normal lifecycle** — `startListening()` subscribes; stream event invokes callback; `stopListening()` cancels and nulls the subscription.
2. **Double `startListening()`** — first subscription cancelled before second is created; only one callback per event (no double-fire).
3. **`stopListening()` before `startListening()`** — `_subscription` is `null`; `?.cancel()` is a null-safe no-op; no exception.
4. **`dispose()` cleanup** — calls `stopListening()`, then nulls `_onScreenLocked`; instance is inert; no memory leak.
5. **No callback set, stream emits** — `_onScreenLocked?.call()` is a safe null-guarded no-op; no exception.

---

## Accepted Gaps

**No unit tests for `ScreenLockServiceImpl`.** The PRD explicitly defers unit tests to Phase 7 or later. In Phase 6 the service has no injectable mock consumer, so tests cannot be usefully exercised end-to-end through DI. Correctness is validated by code review against the five PRD scenarios above. The idea document (Section H) specifies three test cases (invoke callback, `stopListening` prevents callback, `dispose` cleans up) that are expected to be added in Phase 7 or before the final merge.

**Static analysis not confirmed in review session.** The QA report (dated 2026-04-02) notes that `cd example && fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` was not executed during the review session. The implementation uses only standard path dependencies already present in `example/pubspec.yaml`, follows the exact same structure as `timer_service.dart`, and makes no use of code generation. Analysis is expected to pass, but must be confirmed before the branch is merged.

---

## QA Verdict

**RELEASE WITH RESERVATIONS**

The QA review confirmed:
- File is at the correct path alongside `timer_service.dart`.
- Both imports (`dart:async`, `package:biometric_cipher/biometric_cipher.dart`) are present and correct.
- All four abstract members are defined in `ScreenLockService` with matching signatures.
- `ScreenLockServiceImpl` member order follows `docs/conventions.md`: constructor field → constructor → other private fields → public methods.
- `startListening()` cancels before re-subscribing; `stopListening()` is idempotent; `dispose()` nulls the callback.
- The `TimerService` pattern is faithfully mirrored in structure.
- No unintended files were modified.

The reservations are MC-1 (static analysis must be run and pass with zero warnings) and the accepted absence of unit tests (NC-6, deferred per PRD).

Phase 6 is ready to proceed to Phase 7 (DI wiring) once the static analysis check is confirmed.

---

## What Comes Next

| Phase | Scope |
|-------|-------|
| Phase 7 | DI wiring — instantiate `ScreenLockServiceImpl` in `RepositoryFactoryImpl`, thread it through `BlocFactory`, add `LockerEvent.screenLocked`, run code generation |
| Phase 8 | `LockerBloc` integration — `screenLocked` event handler, call `startListening()`/`stopListening()` on unlock/lock state transitions, `dispose()` |

---

## Reference Documents

- Phase document / tasklist: `docs/phase/AW-2349/phase-6.md`
- PRD: `docs/prd/AW-2349-phase-6.prd.md`
- Plan: `docs/plan/AW-2349-phase-6.md`
- QA: `docs/qa/AW-2349-phase-6.md`
- Idea/context: `docs/idea-2349.md`
- Phase 5 summary: (not yet created)
- Phase 4 summary: `docs/AW-2349-phase-4-summary.md`
- Phase 3 summary: `docs/AW-2349-phase-3-summary.md`
- Phase 2 summary: `docs/AW-2349-phase-2-summary.md`
- Phase 1 summary: `docs/AW-2349-phase-1-summary.md`
