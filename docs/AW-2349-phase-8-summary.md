# AW-2349 Phase 8 Summary: BLoC Integration for Screen Lock Detection

**Ticket:** AW-2349
**Phase:** 8 of 8
**Status:** Released with reservations
**Date:** 2026-04-02
**Branch:** `feature/AW-2349-autolock-mfa` <!-- cspell:ignore autolock -->

---

## What Was Done

Phase 8 activates the end-to-end screen lock detection feature by completing the `LockerBloc` integration. The native platform pipeline (phases 1–5), the Dart service (phase 6), and the DI wiring plus Freezed event declaration (phase 7) were all already in place. This phase adds the final missing pieces: registering the event handler, implementing the callback and handler methods, and wiring `startListening()` / `stopListening()` to the locker lifecycle state transitions.

One source file was modified:

| File | Change |
|------|--------|
| `example/lib/features/locker/bloc/locker_bloc.dart` | Added `on<_ScreenLocked>` registration, `onScreenLockedCallback` assignment, `_onScreenLockDetected` callback, `_onScreenLocked` handler, and `startListening()` / `stopListening()` calls on state transitions |

No new files were created. No code generation was needed — the `_ScreenLocked` generated class was already present from Phase 7.

---

## Why This Was Needed

Phases 1–7 built everything except the behavioral wiring in `LockerBloc` itself:
- The native stream was delivering screen lock events to Dart.
- `ScreenLockService` was subscribed and had a callback mechanism.
- The `LockerEvent.screenLocked()` Freezed event existed.
- `LockerBloc` already stored `_screenLockService`, accepted it in the constructor, and disposed it in `close()`.

What was missing was the connection between these pieces: no handler was registered for `_ScreenLocked`, the callback was never set, and `startListening()` / `stopListening()` were never called. Without Phase 8, screen lock events would be silently dropped by `flutter_bloc` and the native listener would never be activated. The feature was wired but inert.

---

## Files Changed

### `example/lib/features/locker/bloc/locker_bloc.dart`

**Constructor additions (task 8.1)**

Two lines were added at the end of the constructor body:

- `on<_ScreenLocked>(_onScreenLocked);` — placed immediately after the existing `on<_BiometricKeyInvalidationDetected>` registration, following the declaration order of event handlers.
- `_screenLockService.onScreenLockedCallback = _onScreenLockDetected;` — placed immediately after `_timerService.onLockCallback = _onTimerExpired;`, grouping the two auto-lock service callback assignments together.

**Callback `_onScreenLockDetected` (task 8.2)**

A synchronous callback, placed after `_onBiometricKeyInvalidationDetected` and before `_onTimerExpired`, grouping all auto-lock trigger handlers in one area of the file:

```dart
void _onScreenLockDetected() {
  if (!isClosed && state.status == LockerStatus.unlocked) {
    add(const LockerEvent.screenLocked());
  }
}
```

The `!isClosed` guard prevents adding events to a disposed BLoC during app teardown. The `state.status == LockerStatus.unlocked` guard prevents the event from being enqueued when the locker is already locked, covering the window between when `stopListening()` is called and when the native subscription is fully cancelled.

**Event handler `_onScreenLocked` (task 8.2)**

An async BLoC event handler, placed immediately after `_onScreenLockDetected`:

```dart
Future<void> _onScreenLocked(
  _ScreenLocked event,
  Emitter<LockerState> emit,
) async {
  if (state.status != LockerStatus.unlocked) return;
  await _lockerRepository.lock();
}
```

The critical design decision here: this handler has no `BiometricOperationState` guard. `_onLockRequested` (the manual lock handler) checks `biometricOperationState != BiometricOperationState.idle` at line 261 and returns early if a biometric flow is in progress. `_onScreenLocked` does not. A physical device lock is an explicit OS-level security action — the OS has already dismissed any biometric dialog, and the app must lock immediately regardless of any in-progress biometric operation.

**`startListening()` / `stopListening()` calls (task 8.3)**

The native subscription lifecycle is tied to the locker's unlock/lock state transitions, mirroring the `_timerService.startTimer()` / `stopTimer()` calls that already existed:

- `_screenLockService.startListening()` added in `_onInitialEntrySubmitted()` at line 185, immediately after `await _timerService.startTimer()` at line 184. This is the first-time setup path — when the user sets their first entry and the locker unlocks for the first time.
- `_screenLockService.startListening()` added in `_refreshUnlockedState()` at line 1194, immediately after `await _timerService.startTimer()` at line 1193. This covers all subsequent unlock events (e.g., unlocking with password or biometrics from the locked screen).
- `_screenLockService.stopListening()` added in `_onLockerStateChanged()` at line 1164, inside `case RepositoryLockerState.locked`, immediately after `_timerService.stopTimer()` at line 1163.

These three call sites together ensure the native listener is active only while the locker is unlocked and inactive at all other times.

**`dispose()` in `close()` (task 8.4 — pre-existing)**

`_screenLockService.dispose()` was already present in `close()` from Phase 7 scope leakage and required no changes.

---

## Key Design Decision: Bypassing the BiometricOperationState Guard

`LockerBloc` uses a `biometricOperationState` field to track in-progress biometric flows. The manual lock handler (`_onLockRequested`) checks this guard and refuses to lock while a biometric operation is in progress — this prevents the lock screen from appearing while the system biometric dialog is open, which would confuse the user.

Screen lock detection does not apply this guard. The reasoning: when the OS locks the device screen, it dismisses any system biometric dialogs before doing so. The biometric operation is already terminated by the OS. Continuing to protect an already-dismissed dialog would leave the app unlocked after the device screen is locked, which violates the MFA spec requirement (section 8: "if the device is locked (lock screen) → lock immediately").

This is documented in the docstring on `_onScreenLocked` and in the idea doc (section G).

---

## Lifecycle Diagram

```
LockerBloc unlocked
  ├─ _onInitialEntrySubmitted   ──► _timerService.startTimer()
  │                                 _screenLockService.startListening()  ← native listener ON
  └─ _refreshUnlockedState      ──► _timerService.startTimer()
                                    _screenLockService.startListening()  ← native listener ON

Device screen locked
  └─ [native OS notification]
       ↓ EventChannel
  ScreenLockService._subscription fires
       ↓ callback
  _onScreenLockDetected()
    checks !isClosed && status == unlocked
       ↓ add event
  _onScreenLocked()
    checks status == unlocked
       ↓ await _lockerRepository.lock()
  _onLockerStateChanged() ── case locked ──► _timerService.stopTimer()
                                              _screenLockService.stopListening()  ← native listener OFF
```

---

## QA Findings

### All tasks passed

- Task 8.1 (register handler + set callback): PASS — both lines confirmed in constructor.
- Task 8.2 (implement callback + handler): PASS — both methods implemented with correct guards and the `BiometricOperationState` bypass.
- Task 8.3 (start/stop listening): PASS — all three call sites present in correct positions.
- Task 8.4 (dispose in `close()`): N/A — pre-existing from Phase 7.

### Minor observation: field declaration vs. callback assignment order asymmetry

Field declaration order in `locker_bloc.dart` is `_lockerRepository`, `_screenLockService`, `_timerService`. Constructor callback assignment order is `_timerService.onLockCallback` first (line 63), then `_screenLockService.onScreenLockedCallback` (line 64). This cosmetic asymmetry has no runtime effect.

### Automated test coverage gap

The `example/test/` directory does not exist. No automated tests exist for `ScreenLockServiceImpl` or for the `LockerBloc` screen lock behavior. The idea doc (section H) specifies unit tests for both; these were not written. The test debt items considered most important before the next significant refactor:

1. `LockerBloc` locks when `LockerEvent.screenLocked()` is received while status is `unlocked`.
2. `LockerBloc` ignores `LockerEvent.screenLocked()` when status is already `locked`.
3. `LockerBloc` screen lock bypasses `BiometricOperationState` guard (unlike `lockRequested`).

The plugin-layer tests from Phase 5 (`biometric_cipher_test.dart` — `screenLockStream` group) remain green and are unaffected.

---

## Deviations from Plan

None. Phase 8 implemented exactly the tasks listed in the phase specification. The constructor injection and `dispose()` call that were described as Phase 8 work were already present due to Phase 7 scope leakage (documented in the Phase 7 summary), and Phase 8 correctly added only the remaining pieces.

The two carry-over issues from Phase 7 (the `const` keyword not removed from `BlocFactoryImpl`, and the absence of example app unit tests) remain open and are carried forward as release reservations.

---

## Release Reservations

1. **Static analysis (`cd example && fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .`) not run during review.** This is the primary acceptance criterion and must pass before merge. The implementation is structurally correct and expected to pass.

2. **No automated tests for Phase 8 behavior.** The `example/test/` directory does not exist. The three `LockerBloc` screen lock test cases and the three `ScreenLockServiceImpl` service tests specified in the idea doc remain unwritten. This is test debt for the entire AW-2349 feature, not specific to Phase 8.

3. **`BlocFactoryImpl` `const` keyword carry-over (Phase 7).** The `const` keyword was not removed from the `BlocFactoryImpl` constructor per the PRD requirement. No `const` call site exists, so this is harmless today but should be corrected.

4. **Manual platform tests required.** Screen lock detection is an end-to-end native integration. The Dart/BLoC layer correctness confirmed by code review does not substitute for device-level verification. Platform tests on Android (MC-5), iOS (MC-6), macOS (MC-7), Windows (MC-8), and cross-state edge cases (MC-9, MC-10) are required before the feature is considered fully accepted.

---

## Feature Completion (AW-2349)

Phase 8 is the final phase of AW-2349. The complete screen lock detection pipeline is now wired end to end:

| Layer | Delivered in |
|-------|-------------|
| Dart plugin API (`screenLockStream`) | Phase 1 |
| Android native (`ACTION_SCREEN_OFF`) | Phase 2 |
| iOS/macOS native (notification observers) | Phase 3 |
| Windows native (`WTS_SESSION_LOCK`) | Phase 4 |
| Plugin-layer Dart tests | Phase 5 |
| `ScreenLockService` (app layer) | Phase 6 |
| DI wiring + `LockerEvent.screenLocked()` | Phase 7 |
| `LockerBloc` handler + lifecycle wiring | Phase 8 |

When the device screen locks while the app is in the foreground with the locker unlocked, the locker now transitions to locked state immediately, satisfying MFA spec section 8 ("if the device is locked → lock immediately"). The existing `shouldLockOnResume` mechanism in `TimerService` remains intact as a fallback for the case where the app is already suspended when the device locks.

---

## Reference Documents

- Phase specification: `docs/phase/AW-2349/phase-8.md`
- QA: `docs/qa/AW-2349-phase-8.md`
- Idea/context: `docs/idea-2349.md`
- Vision: `docs/vision-2349.md`
- Tasklist: `docs/tasklist-2349.md`
- Phase 7 summary: `docs/AW-2349-phase-7-summary.md`
