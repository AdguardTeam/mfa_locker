# Iteration 7: Example app — DI wiring + event

**Goal:** Wire `ScreenLockService` through DI and add `screenLocked` Freezed event.

## Context

Iteration 6 created `ScreenLockServiceImpl` in `example/lib/core/services/screen_lock_service.dart`. This iteration wires it into the existing factory-based DI graph and declares the Freezed event that `LockerBloc` will handle in Iteration 8.

The example app DI pattern is: `RepositoryFactory` creates services → `BlocFactory` injects them into BLoCs → `main.dart` connects the factories. `ScreenLockService` follows the same path as `TimerService` already uses today.

Key design points:
- `ScreenLockServiceImpl` reuses the `BiometricCipher` instance already created in `RepositoryFactoryImpl` — no second instance needed.
- `RepositoryFactory.dispose()` must call `_screenLockService.dispose()` to release the stream subscription.
- `BlocFactoryImpl` receives `ScreenLockService` as a constructor parameter (mirrors `TimerService`).
- `LockerEvent.screenLocked()` is a zero-argument Freezed factory — same style as existing events.
- Code generation (`make g`) is required after adding the new Freezed factory.

## Tasks

- [ ] **7.1** Add `ScreenLockService` to `RepositoryFactory`
  - File: `example/lib/di/factories/repository_factory.dart`
  - Create in `init()`, expose via getter, dispose in `dispose()`

- [ ] **7.2** Pass `ScreenLockService` through `BlocFactory`
  - File: `example/lib/di/factories/bloc_factory.dart`
  - Add constructor parameter, pass to `LockerBloc`

- [ ] **7.3** Wire in `main.dart`
  - File: `example/lib/main.dart`
  - Pass `repositoryFactory.screenLockService` to `BlocFactoryImpl`

- [ ] **7.4** Add `screenLocked` event
  - File: `example/lib/features/locker/bloc/locker_event.dart`
  - Add `const factory LockerEvent.screenLocked() = _ScreenLocked;`

- [ ] **7.5** Run code generation
  - `cd example && make g`

## Acceptance Criteria

**Verify:** `cd example && fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .`

Functional criteria:
- `RepositoryFactory` exposes `ScreenLockService` via a getter.
- `RepositoryFactory.dispose()` disposes the service.
- `BlocFactoryImpl` constructor accepts `ScreenLockService` and passes it to `LockerBloc`.
- `main.dart` passes `repositoryFactory.screenLockService` when constructing `BlocFactoryImpl`.
- `LockerEvent.screenLocked()` is declared and code-generated without errors.

## Dependencies

- Iteration 6 complete (`ScreenLockService` interface and `ScreenLockServiceImpl` created) ✅

## Technical Details

### Changes to `repository_factory.dart` (task 7.1)

Abstract interface — add getter:

```dart
import 'package:mfa_demo/core/services/screen_lock_service.dart';

abstract class RepositoryFactory {
  // ... existing members ...
  ScreenLockService get screenLockService;
}
```

`RepositoryFactoryImpl` — add field, create in `init()`, expose via getter, dispose:

```dart
late final ScreenLockService _screenLockService;

@override
ScreenLockService get screenLockService => _screenLockService;

// In init():
_screenLockService = ScreenLockServiceImpl(
  biometricCipher: _biometricCipher,
);

// In dispose():
_screenLockService.dispose();
```

The `_biometricCipher` field already exists in `RepositoryFactoryImpl` — reuse it.

### Changes to `bloc_factory.dart` (task 7.2)

```dart
import 'package:mfa_demo/core/services/screen_lock_service.dart';

class BlocFactoryImpl implements BlocFactory {
  BlocFactoryImpl({
    required LockerRepository lockerRepository,
    required TimerService timerService,
    required ScreenLockService screenLockService,  // new
  })  : _lockerRepository = lockerRepository,
        _timerService = timerService,
        _screenLockService = screenLockService;    // new

  final ScreenLockService _screenLockService;      // new

  @override
  LockerBloc get lockerBloc => LockerBloc(
        lockerRepository: _lockerRepository,
        timerService: _timerService,
        screenLockService: _screenLockService,     // new
      );
}
```

### Changes to `main.dart` (task 7.3)

Wherever `BlocFactoryImpl` is constructed, add the new parameter:

```dart
BlocFactoryImpl(
  lockerRepository: repositoryFactory.lockerRepository,
  timerService: repositoryFactory.timerService,
  screenLockService: repositoryFactory.screenLockService,  // new
)
```

### Changes to `locker_event.dart` (task 7.4)

Add inside the `LockerEvent` Freezed union, following the existing event style (zero-arg, `const factory`):

```dart
/// Device screen was locked. Triggers immediate locker lock.
const factory LockerEvent.screenLocked() = _ScreenLocked;
```

### Code generation (task 7.5)

```bash
cd example && make g
```

This regenerates `locker_event.freezed.dart` and `locker_event.g.dart` (or whichever generated files exist). Confirm the build completes without errors.

## Implementation Notes

- Check `example/lib/di/factories/repository_factory.dart` for the `_biometricCipher` field name and the exact `init()` / `dispose()` patterns before editing — follow what exists.
- Check `bloc_factory.dart` for the existing constructor parameter ordering and field declaration order — insert `ScreenLockService` after `TimerService` in both.
- The `LockerBloc` constructor will fail compilation until Iteration 8 adds the `screenLockService` parameter — that's expected. The compile error is resolved in Iteration 8.
- If `LockerBloc` constructor doesn't accept `screenLockService` yet, add only the `BlocFactory` and `RepositoryFactory` changes in this iteration and defer the `BlocFactory` → `LockerBloc` wiring to Iteration 8.
