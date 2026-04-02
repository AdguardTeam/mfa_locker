# QA Plan: AW-2349 Phase 8 — BLoC Integration for Screen Lock Detection

Status: REVIEWED
Date: 2026-04-02

---

## Phase Scope

Phase 8 completes the end-to-end screen lock feature by wiring `ScreenLockService` into the
event-handling layer of `LockerBloc`. The prior phases delivered the native platform EventChannel
pipeline (phases 1–5), the Dart service (phase 6), and DI wiring + Freezed event declaration
(phase 7). Phase 8 activates the feature:

1. Register `on<_ScreenLocked>` event handler in `LockerBloc` constructor.
2. Set `_screenLockService.onScreenLockedCallback = _onScreenLockDetected` in the constructor.
3. Implement `_onScreenLockDetected` — the callback that adds the event when the locker is unlocked.
4. Implement `_onScreenLocked` — the event handler that calls `_lockerRepository.lock()`, with no
   `BiometricOperationState` guard.
5. Call `_screenLockService.startListening()` in `_refreshUnlockedState()` and
   `_onInitialEntrySubmitted()` alongside `_timerService.startTimer()`.
6. Call `_screenLockService.stopListening()` in `_onLockerStateChanged()` (case locked) alongside
   `_timerService.stopTimer()`.

Note from Phase 7 QA: the constructor parameter (`required ScreenLockService screenLockService`),
field declaration (`final ScreenLockService _screenLockService`), and `close()` dispose call
(`_screenLockService.dispose()`) were already present due to Phase 7 scope leakage. Phase 8 must
add only the remaining pieces.

Sole file in scope: `example/lib/features/locker/bloc/locker_bloc.dart`

---

## Implementation Status (observed)

### Task 8.1 — Register `on<_ScreenLocked>` and set callback

Observed in `locker_bloc.dart`:

- `on<_ScreenLocked>(_onScreenLocked);` at line 61 — present, placed after
  `on<_BiometricKeyInvalidationDetected>` (line 60). Correct position per plan.
- `_screenLockService.onScreenLockedCallback = _onScreenLockDetected;` at line 64 — present,
  placed after `_timerService.onLockCallback = _onTimerExpired;` (line 63). Correct position
  per plan.

Task 8.1: PASS.

### Task 8.2 — Implement `_onScreenLockDetected` callback and `_onScreenLocked` handler

`_onScreenLockDetected` (lines 1272–1276):
```dart
void _onScreenLockDetected() {
  if (!isClosed && state.status == LockerStatus.unlocked) {
    add(const LockerEvent.screenLocked());
  }
}
```
- Guards on `!isClosed` — correct, prevents adding events to a disposed BLoC.
- Guards on `state.status == LockerStatus.unlocked` — correct, filters spurious events when
  already locked.
- Adds `const LockerEvent.screenLocked()` — correct, matches the generated Freezed factory.

`_onScreenLocked` (lines 1283–1289):
```dart
Future<void> _onScreenLocked(
  _ScreenLocked event,
  Emitter<LockerState> emit,
) async {
  if (state.status != LockerStatus.unlocked) return;
  await _lockerRepository.lock();
}
```
- Status guard `!= LockerStatus.unlocked` — correct early return if not unlocked.
- No `BiometricOperationState` guard — correct, per the key design decision (physical device
  lock bypasses any in-progress biometric flow, unlike `_onLockRequested` which checks
  `biometricOperationState != BiometricOperationState.idle` at line 261).
- Calls `_lockerRepository.lock()` — correct.
- Doc comment is present and accurate.

Placement: both methods are immediately after `_onBiometricKeyInvalidationDetected` (line 1262)
and immediately before `_onTimerExpired` (line 1291). This clusters screen-lock and timer-based
auto-lock handlers together — correct per implementation notes.

Task 8.2: PASS.

### Task 8.3 — Start/stop listening on state transitions

`_onInitialEntrySubmitted` (line ~184–185):
- `await _timerService.startTimer();` at line 184.
- `_screenLockService.startListening();` at line 185 — present, placed immediately after.
- Correct: both services are started together when the locker first unlocks after initialization.

`_refreshUnlockedState` (lines ~1193–1194):
- `await _timerService.startTimer();` at line 1193.
- `_screenLockService.startListening();` at line 1194 — present, placed immediately after.
- Correct: both services are restarted when the locker transitions to unlocked from a locked state.

`_onLockerStateChanged` (lines ~1163–1164), case `RepositoryLockerState.locked`:
- `_timerService.stopTimer();` at line 1163.
- `_screenLockService.stopListening();` at line 1164 — present, placed immediately after.
- Correct: both services are stopped together when the locker transitions to locked.

Task 8.3: PASS.

### Task 8.4 — Dispose in `close()` (pre-existing, not Phase 8 scope)

`close()` (lines 70–76) already calls `_screenLockService.dispose()` at line 73 — present from
Phase 7 scope leakage. No new changes needed. Confirmed still present.

Task 8.4: N/A (pre-existing, PASS).

### Field and constructor ordering

Field declaration order (lines 23–25): `_lockerRepository`, `_screenLockService`, `_timerService`.
Constructor parameter order (lines 28–30): `lockerRepository`, `screenLockService`, `timerService`.

The plan specifies the field order as `_lockerRepository`, `_screenLockService`, `_timerService`.
Observed order matches the plan exactly.

**MINOR OBSERVATION — `_screenLockService` precedes `_timerService` in field order.**
This differs from the order in which callbacks are set in the constructor (timer callback is set
first at line 63, screen lock callback second at line 64). This is a cosmetic asymmetry, not a
defect. Field declaration order does not affect runtime behavior.

### `_timerService.dispose()` absent from `close()`

`LockerBloc.close()` calls `_screenLockService.dispose()` but does NOT call
`_timerService.dispose()` or `_timerService.stopTimer()`. Examining `TimerService` behavior:
`TimerService` is created and disposed by `RepositoryFactoryImpl` (Phase 7 scope), not by
`LockerBloc`. This is architecturally consistent: `TimerService` is owned by
`RepositoryFactoryImpl`, and `ScreenLockService` is owned by both `RepositoryFactoryImpl` (dispose
in factory) and `LockerBloc` (dispose in close). This was noted in Phase 7 QA (double-dispose is
idempotent and safe). No defect here, though the ownership model is asymmetric.

---

## Positive Scenarios

### PS-1: Screen lock triggers immediate lock when locker is unlocked

When the device screen locks while the app is in the foreground with the locker unlocked:
1. Native platform fires the screen lock notification.
2. The EventChannel delivers the event to `BiometricCipher.screenLockStream`.
3. `ScreenLockServiceImpl._subscription` receives it and calls `_onScreenLocked?.call()`.
4. `_onScreenLockDetected()` runs: `!isClosed` is true, `state.status == LockerStatus.unlocked`
   is true — `add(const LockerEvent.screenLocked())` is called.
5. `_onScreenLocked` handler runs: `state.status != LockerStatus.unlocked` is false (locker is
   unlocked) — `await _lockerRepository.lock()` is called.
6. The repository emits `RepositoryLockerState.locked`, triggering `_onLockerStateChanged`.
7. `_timerService.stopTimer()` and `_screenLockService.stopListening()` are called.
8. BLoC state transitions to `LockerStatus.locked`.

### PS-2: Screen lock bypasses `BiometricOperationState` guard

When the device screen locks while a biometric operation is in progress
(`biometricOperationState == BiometricOperationState.inProgress` or `awaitingResume`):
- `_onLockRequested` would return early (line 261 guard). Screen lock does not go through
  `_onLockRequested`.
- `_onScreenLocked` has no `BiometricOperationState` check — proceeds directly to
  `_lockerRepository.lock()`.
- The locker locks immediately regardless of in-progress biometric flow.

### PS-3: Screen lock event ignored when already locked

When `LockerEvent.screenLocked()` is added while `state.status == LockerStatus.locked`:
- `_onScreenLocked` runs: `state.status != LockerStatus.unlocked` is true — returns early.
- `_lockerRepository.lock()` is NOT called.
- No state change occurs.

### PS-4: Screen lock event ignored for non-`unlocked` statuses

For `LockerStatus.notInitialized`, `LockerStatus.settingInitialEntry`, `LockerStatus.locking`, etc.:
- `_onScreenLockDetected` callback: `state.status == LockerStatus.unlocked` is false — does not
  add the event. The event never reaches `_onScreenLocked`.
- If somehow the event is added directly (test or edge case), `_onScreenLocked` guard catches it.
- No spurious lock is triggered.

### PS-5: `startListening()` activated on both unlock paths

Path A — `_onInitialEntrySubmitted()` (first-time setup completing):
- After `await _timerService.startTimer()`, `_screenLockService.startListening()` is called.
- Both services become active simultaneously.

Path B — `_onLockerStateChanged()` dispatching to `_refreshUnlockedState()` (subsequent unlocks):
- After `await _timerService.startTimer()`, `_screenLockService.startListening()` is called.
- Both services become active simultaneously.

Both paths covered: screen lock detection is active whenever the locker is unlocked, regardless
of how it got unlocked.

### PS-6: `stopListening()` deactivates native subscription on lock

When `_onLockerStateChanged` processes `RepositoryLockerState.locked`:
- `_timerService.stopTimer()` is called first.
- `_screenLockService.stopListening()` is called immediately after.
- `ScreenLockServiceImpl.stopListening()` cancels the `_subscription` and sets it to null.
- The native EventChannel listener is no longer active.
- No CPU or memory cost while the locker is locked.

### PS-7: `startListening()` is idempotent — double-start is safe

`ScreenLockServiceImpl.startListening()` calls `_subscription?.cancel()` before creating a new
subscription. If `startListening()` is called twice (e.g., via two rapid unlock transitions),
the prior subscription is cancelled before a new one is created. No subscription leak.

### PS-8: `dispose()` in `close()` cleans up regardless of listening state

When `LockerBloc.close()` is called:
- If the locker is currently unlocked (i.e., `stopListening()` was not yet called), `dispose()`
  calls `stopListening()` internally, which cancels the subscription.
- If the locker is already locked (`stopListening()` was already called), the subscription is
  null — `stopListening()` is a no-op.
- `_onScreenLocked` callback reference is nulled out.
- No resource leak in either case.

### PS-9: Handler placement follows existing code conventions

`_onScreenLockDetected` and `_onScreenLocked` are placed between
`_onBiometricKeyInvalidationDetected` (line 1262) and `_onTimerExpired` (line 1291).
This groups the "auto-lock trigger" handlers together: timer expiry and screen lock both
cause unconditional locking. Consistent with implementation notes in the plan.

---

## Negative and Edge Cases

### NC-1: Screen lock fires when BLoC is already closed (`isClosed == true`)

`_onScreenLockDetected` checks `!isClosed` before adding the event. If the callback fires after
`LockerBloc.close()` has been called (e.g., race condition during app teardown), no event is
added and no exception is thrown. Safe.

However: `_screenLockService.dispose()` in `close()` cancels the subscription, which should
prevent further callbacks from firing. The `!isClosed` guard is a defensive second line of
protection for the brief window between `close()` start and `dispose()` completing.

### NC-2: `_onScreenLocked` handler races with `_onLockerStateChanged` locked transition

Scenario: `_onScreenLocked` calls `_lockerRepository.lock()`. Before the resulting
`RepositoryLockerState.locked` event is delivered to `_onLockerStateChanged`, another
`LockerEvent.screenLocked()` arrives and `_onScreenLocked` runs again.

Second invocation: `state.status != LockerStatus.unlocked` — at this point the state may still
show `unlocked` if the BLoC state has not yet been updated by `_onLockerStateChanged`. BLoC event
processing is sequential within a single BLoC instance (flutter_bloc processes one event at a
time), so the second `_onScreenLocked` will be queued and will execute after the first completes
and state has transitioned. The guard will then catch it.

However, `_onScreenLockDetected` could theoretically add the event multiple times before the
first `_onScreenLocked` runs, since the callback is synchronous and can fire again from the
`ScreenLockService` subscription before the BLoC event queue is drained. Since
`stopListening()` is only called after state transitions to locked (from within
`_onLockerStateChanged`), and that requires the repository lock to complete first, there is a
window where multiple `_ScreenLocked` events could be queued. All but the first will be
dropped by the `if (state.status != LockerStatus.unlocked) return;` guard once state has updated.
Functionally safe: at most one `lock()` call succeeds.

### NC-3: Platform delivers screen lock event while locker is locked (subscription is inactive)

When the locker is locked, `_screenLockService.stopListening()` has cancelled the subscription.
No native events can reach the BLoC. Even if the platform fires a screen lock notification,
no Dart code receives it. Correct behavior.

### NC-4: Screen lock fires during a long-running `_lockerRepository.lock()` call

`_onScreenLocked` is `async` and yields on `await _lockerRepository.lock()`. While the await
is in progress, BLoC state is still `LockerStatus.unlocked`. If another `_ScreenLocked` event
arrives from the queue during this time, it would be processed sequentially after the first
completes. By then, state would have transitioned to `locked`, and the second handler would
return early. No double-lock.

### NC-5: `_onScreenLockDetected` callback fires after `stopListening()` but before subscribe cancel confirms

`stopListening()` calls `_subscription?.cancel()` which is asynchronous at the StreamSubscription
level. There is a brief window where the callback could fire after `stopListening()` returns but
before the underlying stream subscription is fully cancelled. The `state.status == LockerStatus.unlocked`
guard in `_onScreenLockDetected` provides a safety net: if `stopListening()` was called from
`_onLockerStateChanged` (case locked), the state is already `LockerStatus.locked`, so the
callback guard blocks the event from being added.

### NC-6: Double `dispose()` — from `LockerBloc.close()` and `RepositoryFactoryImpl.dispose()`

As documented in Phase 7 QA: both call sites share the same `ScreenLockServiceImpl` instance.
`dispose()` calls `stopListening()` (null-safe cancel) and nulls the callback. Both operations
are idempotent. The second `dispose()` call is a no-op. Safe.

### NC-7: `startListening()` called before `onScreenLockedCallback` is set

The constructor sets `_screenLockService.onScreenLockedCallback = _onScreenLockDetected` at
line 64, before `_createSub()` which sets up the `RepositoryLockerState` subscription (and
therefore before any state-driven `startListening()` call). The callback is guaranteed to be
set before `startListening()` is ever invoked. Safe.

### NC-8: `_refreshUnlockedState` or `_onInitialEntrySubmitted` throws before `startListening()`

If `await _lockerRepository.getAllEntries()` throws, neither `startListening()` is reached nor
is the BLoC state updated to `unlocked`. The locker remains locked/in-progress and the screen
lock subscription is never started. This is correct: if unlock fails, there is nothing to
protect via screen lock detection.

Similarly, if `await _timerService.startTimer()` throws, `startListening()` is not called
(it comes after). The same line-ordering logic applies — partial unlock leaves no dangling
subscription.

### NC-9: `_screenLockService.dispose()` called in `close()` — `_timerService` is NOT disposed

`close()` only calls `_screenLockService.dispose()`. `_timerService` is not disposed here.
`TimerService` is managed by `RepositoryFactoryImpl`, which disposes it in `dispose()`. This is
consistent with the pre-existing architecture (timer service was never disposed in `close()`).
The asymmetry is pre-existing and out of Phase 8 scope.

### NC-10: Android — `ACTION_SCREEN_OFF` fires even when no lock screen is configured

The idea doc explicitly notes this is intentional: even without a device lock screen, the app
should protect its data when the screen turns off. This is a conservative security choice. No
defect; expected behavior.

### NC-11: iOS — engine suspended before `protectedDataWillBecomeUnavailable`

The idea doc documents this: if the app is already suspended when the device locks, the
EventChannel event may not be delivered. The existing `shouldLockOnResume` mechanism in
`TimerService` handles this fallback — on `AppLifecycleState.resumed`, the timer check catches
the elapsed time. Phase 8 does not change this fallback; it remains intact.

---

## Automated Tests Coverage

| Test | Location | Status |
|------|----------|--------|
| `screenLockStream` emits events from platform | `packages/biometric_cipher/test/biometric_cipher_test.dart` | Present — green (Phase 5) |
| `screenLockStream` multiple events emission | `packages/biometric_cipher/test/biometric_cipher_test.dart` | Present — green (Phase 5) |
| `screenLockStream` default platform returns empty stream | `packages/biometric_cipher/test/biometric_cipher_test.dart` | Present — green (Phase 5) |
| `ScreenLockServiceImpl` invokes callback on stream event | `example/test/core/services/screen_lock_service_test.dart` | Not present (deferred from Phase 6 per Phase 6 QA NC-6) |
| `ScreenLockServiceImpl` `stopListening()` prevents callback | `example/test/core/services/screen_lock_service_test.dart` | Not present |
| `ScreenLockServiceImpl` `dispose()` prevents callback | `example/test/core/services/screen_lock_service_test.dart` | Not present |
| `LockerBloc` locks when `screenLocked` event received in unlocked state | `example/test/features/locker/bloc/locker_bloc_test.dart` | Not present (no test directory exists) |
| `LockerBloc` ignores `screenLocked` event when already locked | `example/test/features/locker/bloc/locker_bloc_test.dart` | Not present |
| `LockerBloc` screen lock bypasses `BiometricOperationState` guard | `example/test/features/locker/bloc/locker_bloc_test.dart` | Not present |
| `LockerBloc` `startListening()` called on unlock | Unit test | Not present |
| `LockerBloc` `stopListening()` called on lock | Unit test | Not present |
| `fvm flutter analyze` passes with zero warnings/infos | Static analysis | Not executed during review session |

The `example/test/` directory does not exist — no unit tests for the example app exist at all.
The idea doc (section H) specifies test files for both `ScreenLockService` and `LockerBloc` screen
lock behavior, but these are not present. This is a gap in automated test coverage for the entire
Phase 8 feature.

The biometric_cipher plugin tests (Phase 5) remain green and are unaffected by Phase 8 changes.

---

## Manual Checks Needed

### MC-1: Static analysis — primary acceptance criterion

```
cd example && fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .
```

Must exit with code 0, zero diagnostics. Specifically verifies:
- `_ScreenLocked` private type is accessible from the handler registration (it is a Freezed
  generated private class — accessible within the same part file).
- No unused imports (all imports in `locker_bloc.dart` are exercised by the Phase 8 additions,
  including `screen_lock_service.dart` which was added in Phase 7).
- `on<_ScreenLocked>(_onScreenLocked)` compiles with the correct handler signature.
- `_onScreenLockDetected` is correctly typed as `void Function()` for the callback setter.
- `_onScreenLocked` has the correct `Future<void> Function(_ScreenLocked, Emitter<LockerState>)`
  signature expected by `on<T>()`.

### MC-2: Verify `_ScreenLocked` in the generated Freezed file

Confirm `locker_bloc.freezed.dart` contains:
- `class _ScreenLocked implements LockerEvent` (private, accessible within `locker_bloc.dart` via part).
- `const _ScreenLocked()` constructor.
- Correct `when`/`map` switch arms for `screenLocked`.

This was already verified in Phase 7 QA (Task 7.5: PASS), and the generated file has not been
regenerated since. Confirm no stale generation.

### MC-3: Dart format compliance

```
cd example && fvm dart format --line-length 120 --set-exit-if-changed .
```

All Phase 8 additions are in `locker_bloc.dart`. The callback/handler bodies are simple enough
to be auto-formatted correctly, but trailing commas on multi-line function calls must be confirmed.

### MC-4: Confirm no test files reference `LockerBloc(...)` without `screenLockService`

```
grep -r "LockerBloc(" example/test
```

No `example/test/` directory exists (confirmed by Glob), so no test compilation is at risk.
However, this means no automated regressions exist either — MC-4 is a N/A but note the absence.

### MC-5: Manual device/simulator test — Android screen lock

1. Build and run the example app on an Android device or emulator.
2. Initialize the locker with a password and unlock it (status = `LockerStatus.unlocked`).
3. Lock the device screen (power button or equivalent emulator shortcut).
4. Resume the app.
5. Expected: app is in locked state, requiring password/biometric to unlock.

### MC-6: Manual device/simulator test — iOS screen lock

1. Build and run the example app on a physical iOS device (iPhone with passcode) or simulator.
2. Initialize and unlock the locker.
3. Lock the device screen (side button on device; `xcrun simctl` lock on simulator).
4. Resume the app.
5. Expected: app is in locked state.

Note: `protectedDataWillBecomeUnavailableNotification` requires a device passcode to be
configured on iOS. On a simulator without passcode, the notification may not fire — behavior
will fall back to `shouldLockOnResume`.

### MC-7: Manual test — macOS screen lock

1. Build and run the example app on macOS.
2. Initialize and unlock the locker.
3. Lock the screen (Cmd+Ctrl+Q or auto-lock).
4. Unlock macOS.
5. Expected: example app is in locked state.

### MC-8: Manual test — Windows session lock

1. Build and run the example app on Windows.
2. Initialize and unlock the locker.
3. Lock the session (Win+L).
4. Unlock the Windows session.
5. Expected: example app is in locked state.

### MC-9: Manual test — screen lock when locker already locked

1. Start the app without unlocking.
2. Lock the device screen.
3. Unlock the device/session.
4. Expected: app state unchanged (still locked/notInitialized). No crash. No double lock attempt.

### MC-10: Manual test — screen lock during biometric prompt (bypass guard verification)

1. Unlock the locker, trigger a biometric operation (e.g., "Enable Biometrics" flow).
2. While the system biometric dialog is shown, lock the device screen via hardware/shortcut.
3. Expected: the locker transitions to locked state regardless of the in-progress biometric
   operation. The `BiometricOperationState` guard is NOT applied for screen lock events.
4. Compare with behavior when using manual "Lock" button, which should wait for biometric
   operation to complete.

---

## Risk Zone

| Risk | Likelihood | Impact | Assessment |
|------|------------|--------|------------|
| Static analysis not run / unknown status | Unknown (not executed in session) | High — blocks acceptance | MC-1 is mandatory before merge. Expected to pass; Phase 8 changes are structurally sound. |
| `ScreenLockService` unit tests absent | Certain | Medium — reduced confidence in service contract | `ScreenLockServiceImpl` tests specified in idea doc (section H) remain unwritten. Low regression risk since implementation mirrors the reviewed spec, but test debt is real. |
| `LockerBloc` screen lock BLoC tests absent | Certain | Medium — no automated guard for behavior regression | No `example/test/` directory exists. The three test cases specified in idea doc section H are unimplemented. |
| Multiple `_ScreenLocked` events queued before lock completes | Low — requires rapid-fire screen lock signals | Low — BLoC sequential event processing prevents double lock | Second and subsequent events are correctly dropped by the status guard. Safe. |
| `stopListening()` / subscription cancel race allows one spurious callback | Very Low — narrow timing window | Low — `state.status` guard blocks event dispatch | Defensive guard in `_onScreenLockDetected` provides the safety net. |
| iOS simulator without passcode — feature effectively untestable | Medium — iOS simulators often lack passcode | Low — runtime fallback via `shouldLockOnResume` is intact | Not a Phase 8 defect; inherent iOS platform constraint documented in idea doc. |
| `_timerService` not disposed in `close()` — asymmetric ownership | Certain (pre-existing) | Low — `TimerService` is disposed by `RepositoryFactoryImpl` | Pre-existing architectural pattern. Not a Phase 8 regression. |
| `BlocFactoryImpl` `const` constructor deviation (from Phase 7) | Certain — still unresolved | Low — no `const` call site exists | Carry-over from Phase 7 reservation 2. Should be fixed before release. |
| `_screenLockService` disposed twice (BLoC + factory) | Certain | None — idempotent | Explicitly verified as safe in Phase 7 QA. |

---

## Final Verdict

**RELEASE WITH RESERVATIONS**

Phase 8 delivers the complete BLoC integration for screen lock detection. All four remaining tasks
from the phase specification are correctly implemented:

- `on<_ScreenLocked>(_onScreenLocked)` is registered in the constructor.
- `_screenLockService.onScreenLockedCallback = _onScreenLockDetected` is set in the constructor.
- `_onScreenLockDetected` correctly guards on `!isClosed` and `status == unlocked`.
- `_onScreenLocked` correctly bypasses the `BiometricOperationState` guard, unlike `_onLockRequested`.
- `_screenLockService.startListening()` is called in both `_onInitialEntrySubmitted` and
  `_refreshUnlockedState`, immediately after `_timerService.startTimer()`.
- `_screenLockService.stopListening()` is called in `_onLockerStateChanged` (case locked),
  immediately after `_timerService.stopTimer()`.
- Handler and callback placement follow the existing code conventions and implementation notes.

**Reservations:**

1. **MC-1 (static analysis) not run during review.** `cd example && fvm flutter analyze
   --fatal-warnings --fatal-infos --no-pub .` must exit with code 0 before merge. Expected to
   pass; the implementation is structurally correct.

2. **No automated tests for Phase 8 behavior.** The `example/test/` directory does not exist.
   The `ScreenLockServiceImpl` unit tests and `LockerBloc` screen lock BLoC tests specified in
   idea doc section H are not present. This is a test debt risk for the entire AW-2349 feature.
   The three BLoC test cases (locks when unlocked, ignored when locked, bypasses biometric guard)
   are the most important to add before the next significant refactor of `LockerBloc`.

3. **`BlocFactoryImpl` `const` carry-over from Phase 7 (reservation 2).** The `const` keyword
   on `BlocFactoryImpl` was not removed per the Phase 7 PRD requirement. This is harmless today
   but should be corrected. It was documented in Phase 7 QA and remains unresolved.

4. **Manual platform tests (MC-5 through MC-10) are required** before this feature can be
   considered fully accepted. The screen lock detection is inherently a platform integration
   feature — the Dart/BLoC layer unit correctness confirmed above does not substitute for
   verifying that the EventChannel pipeline actually fires on physical devices.
