# Iteration 8: Example app — BLoC integration

**Goal:** Wire `ScreenLockService` into `LockerBloc` — detect screen lock, lock immediately, bypass biometric guard.

## Context

Iteration 7 wired `ScreenLockService` through DI (`RepositoryFactory` → `BlocFactory` → `LockerBloc` constructor). As part of resolving an unused-field warning during code review, some Phase 8 scope was pulled into Phase 7:

- `_screenLockService` field is **already declared** in `LockerBloc`
- Constructor parameter `required ScreenLockService screenLockService` is **already added**
- `_screenLockService.dispose()` in `close()` is **already implemented**

What remains for this iteration:
- Register the `on<_ScreenLocked>` event handler in the constructor
- Set `_screenLockService.onScreenLockedCallback = _onScreenLockDetected` in the constructor
- Implement `_onScreenLockDetected` (the callback that adds the event)
- Implement `_onScreenLocked` (the event handler that calls `lock()`)
- Call `_screenLockService.startListening()` / `_screenLockService.stopListening()` alongside `_timerService` start/stop calls

Key design decision from the idea doc (Section G): The `_onScreenLocked` handler **bypasses** the `BiometricOperationState` guard that `_onLockRequested` enforces. A physical device lock is an explicit security action — the OS has already dismissed any biometric dialog. The app must lock immediately regardless of in-progress biometric flows.

### Existing `_timerService` start/stop locations (reference for task 8.3)

- **`startListening()`** alongside `await _timerService.startTimer()` at:
  - `_refreshUnlockedState()` — line ~1189 (called when `RepositoryLockerState.unlocked` transition occurs)
  - `_onInitialEntrySubmitted()` — line ~182 (after init completes and locker unlocks)
- **`stopListening()`** alongside `_timerService.stopTimer()` at:
  - `_onLockerStateChanged()` — line ~1160, inside `case RepositoryLockerState.locked`

## Tasks

- [ ] **8.1** Register `on<_ScreenLocked>` handler and set callback in constructor
  - File: `example/lib/features/locker/bloc/locker_bloc.dart`
  - Add `on<_ScreenLocked>(_onScreenLocked);` after the existing `on<_BiometricKeyInvalidationDetected>` registration
  - Add `_screenLockService.onScreenLockedCallback = _onScreenLockDetected;` after `_timerService.onLockCallback = _onTimerExpired;`

- [ ] **8.2** Implement `_onScreenLockDetected` callback and `_onScreenLocked` handler
  - Same file
  - `_onScreenLockDetected`: checks `!isClosed && state.status == LockerStatus.unlocked`, then `add(const LockerEvent.screenLocked())`
  - `_onScreenLocked`: checks `state.status != LockerStatus.unlocked` (return early if already locked), then `await _lockerRepository.lock()`
  - **No** `BiometricOperationState` guard — screen lock is unconditional

- [ ] **8.3** Start/stop listening on state transitions
  - Same file
  - Add `_screenLockService.startListening()` in `_refreshUnlockedState()` after `await _timerService.startTimer()`
  - Add `_screenLockService.startListening()` in `_onInitialEntrySubmitted()` after `await _timerService.startTimer()`
  - Add `_screenLockService.stopListening()` in `_onLockerStateChanged()` after `_timerService.stopTimer()` (in the `case RepositoryLockerState.locked` branch)

- [ ] **8.4** ~~Dispose in `close()`~~ — **Already done** in Phase 7 (pulled in to resolve unused-field warning)
  - `_screenLockService.dispose()` is already present in `close()` alongside `_lockerStateSubscription?.cancel()`

**Verify:** `cd example && fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .`

## Acceptance Criteria

Functional criteria:
- `LockerBloc` locks immediately when `LockerEvent.screenLocked()` is received while `status == LockerStatus.unlocked`.
- Screen lock event is ignored when status is already `locked`, `notInitialized`, or any non-`unlocked` state.
- Screen lock bypasses the `BiometricOperationState` guard (unlike `_onLockRequested`).
- `startListening()` is called whenever the locker transitions to `unlocked`; `stopListening()` is called when it transitions to `locked`.
- Native listener is inactive when locker is locked (zero CPU cost).

## Dependencies

- Iteration 7 complete (`ScreenLockService` wired through DI, `screenLocked` Freezed event generated) ✅
- `_screenLockService` field, constructor parameter, and `dispose()` already in `LockerBloc` ✅

## Technical Details

### Callback + handler (`locker_bloc.dart`)

```dart
/// Called by [ScreenLockService] when the device screen is locked.
void _onScreenLockDetected() {
  if (!isClosed && state.status == LockerStatus.unlocked) {
    add(const LockerEvent.screenLocked());
  }
}

/// Handles the screen lock event.
///
/// Bypasses the [BiometricOperationState] guard — a physical device lock
/// is an explicit security action that overrides any in-progress biometric flow.
/// The OS has already dismissed the biometric dialog.
Future<void> _onScreenLocked(
  _ScreenLocked event,
  Emitter<LockerState> emit,
) async {
  if (state.status != LockerStatus.unlocked) return;
  await _lockerRepository.lock();
}
```

### Constructor additions

After the existing `on<_BiometricKeyInvalidationDetected>` line, add:
```dart
on<_ScreenLocked>(_onScreenLocked);
```

After `_timerService.onLockCallback = _onTimerExpired;`, add:
```dart
_screenLockService.onScreenLockedCallback = _onScreenLockDetected;
```

### Start/stop listening in `_refreshUnlockedState()`

```dart
Future<void> _refreshUnlockedState(Emitter<LockerState> emit) async {
  // ...
  await _timerService.startTimer();
  _screenLockService.startListening();  // add this line
  // ...
}
```

### Start/stop listening in `_onInitialEntrySubmitted()`

```dart
await _timerService.startTimer();
_screenLockService.startListening();  // add this line
```

### Stop listening in `_onLockerStateChanged()` (case locked)

```dart
case RepositoryLockerState.locked when previousStatus != LockerStatus.locked:
  _timerService.stopTimer();
  _screenLockService.stopListening();  // add this line
  // ...
```

## Implementation Notes

- Place `_onScreenLockDetected` and `_onScreenLocked` near the timer-related handlers (`_onTimerExpired`, wherever that is) for logical grouping.
- Check `locker_bloc.dart` for the field declaration order: `_lockerRepository`, `_screenLockService`, `_timerService` — ensure any new private fields follow the same order convention.
- No new imports needed — `ScreenLockService` is already imported (was wired in Phase 7).
- No code generation needed — `_ScreenLocked` event was already generated in Phase 7 (task 7.5).
