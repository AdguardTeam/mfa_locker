# Plan: AW-2349 Phase 6 -- Example App `ScreenLockService`

Status: PLAN_APPROVED

## Phase Scope

Phase 6 creates exactly one new file in the example app layer:

```
example/lib/core/services/screen_lock_service.dart
```

This file contains:
- `ScreenLockService` -- abstract class defining the callback + lifecycle interface
- `ScreenLockServiceImpl` -- implementation that subscribes to `BiometricCipher.screenLockStream`

No other files are created or modified. DI wiring (Phase 7), BLoC integration (Phase 8), and tests are out of scope.

## Components

| Component | Change | Notes |
|-----------|--------|-------|
| `example/lib/core/services/screen_lock_service.dart` | NEW | Abstract class + Impl in a single file |

### Unchanged but referenced
| Component | Role |
|-----------|------|
| `packages/biometric_cipher/lib/biometric_cipher.dart` | Provides `screenLockStream` getter (Phase 1) |
| `example/lib/core/services/timer_service.dart` | Pattern reference -- `ScreenLockService` mirrors this shape |

## API Contract

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
  // implements all four members above
}
```

### Mapping to `TimerService` pattern

| TimerService | ScreenLockService | Notes |
|-------------|-------------------|-------|
| `set onLockCallback` | `set onScreenLockedCallback` | Nullable `void Function()?` internally |
| `startTimer()` -> `Future<void>` | `startListening()` -> `void` | Sync -- no async initialization needed |
| `stopTimer()` -> `void` | `stopListening()` -> `void` | Cancels subscription, sets to null |
| `dispose()` -> `void` | `dispose()` -> `void` | Calls `stopListening()`, nulls callback |
| `_lockTimer` (`Timer?`) | `_subscription` (`StreamSubscription<bool>?`) | Mutable resource managed by start/stop |
| `_onLock` (`void Function()?`) | `_onScreenLocked` (`void Function()?`) | Nullable callback, set via setter |

### Key behavioral contracts

1. **Safe re-subscribe**: `startListening()` cancels any existing `_subscription` before creating a new one.
2. **Idempotent stop**: `stopListening()` on a null `_subscription` is a no-op (no exception).
3. **dispose nulls callback**: After `dispose()`, `_onScreenLocked` is null, preventing stale references.
4. **Stream payload discarded**: The `bool` value from `screenLockStream` is ignored -- only the emission occurrence matters.
5. **Null-safe callback invocation**: `_onScreenLocked?.call()` -- safe when no callback is set.

## Data Flows

```
BiometricCipher.screenLockStream   <--  EventChannel  <--  native ScreenLockStreamHandler
        |
        | .listen((_) { ... })
        v
ScreenLockServiceImpl._subscription
        |
        | _onScreenLocked?.call()
        v
[callback -- not connected until Phase 8]
```

In Phase 6, the service is a standalone class with no consumers. The data flow terminates at the callback invocation. Phase 7 will wire it into DI, and Phase 8 will connect the callback to `LockerBloc`.

## NFR

| Requirement | Target |
|-------------|--------|
| Static analysis | Zero warnings/infos: `cd example && fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` |
| Code conventions | Follows all rules from `docs/conventions.md` and `docs/code-style-guide.md` |
| Line length | 120 characters max |
| No code generation | Pure Dart -- no Freezed, no build_runner |
| Memory safety | `dispose()` nulls callback reference to prevent leaks |
| Thread safety | Single-subscription pattern -- `startListening()` always cancels before re-subscribing |

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| `StreamSubscription.cancel()` is async -- stale event could arrive between cancel and null assignment | Low | Low | Dart guarantees `cancel()` prevents future event delivery even without awaiting the `Future`; callback is null-safe (`?.call()`) |
| File placed in wrong directory or with wrong name | Low | Low | PRD and phase task both specify `example/lib/core/services/screen_lock_service.dart` explicitly |
| Naming divergence from `TimerService` pattern | Low | Low | PRD explicitly requires mirroring; plan documents the exact mapping |
| Class unused until Phase 7/8 -- analyzer may warn about unused imports in the future | None | None | No imports of this class exist yet; analyzer only checks files that exist |

## Dependencies

### On previous phases
- **Phase 1** (complete): `BiometricCipher.screenLockStream` getter exists in `packages/biometric_cipher/lib/biometric_cipher.dart`
- **Phases 2-4** (complete): Native `ScreenLockStreamHandler` implementations on all platforms
- **Phase 5** (complete): Plugin-level unit tests for `screenLockStream`

### On external systems
- `biometric_cipher` package is a path dependency of `mfa_demo` (`example/pubspec.yaml`) -- already configured

### Required by future phases
- **Phase 7**: Will import `ScreenLockService` / `ScreenLockServiceImpl` for DI wiring in `RepositoryFactoryImpl` and `BlocFactoryImpl`
- **Phase 8**: Will set `onScreenLockedCallback` and call `startListening()`/`stopListening()` from `LockerBloc`

## Implementation Steps

### 6.1 Create `example/lib/core/services/screen_lock_service.dart`

1. Add `import 'dart:async';` for `StreamSubscription<bool>`
2. Add `import 'package:biometric_cipher/biometric_cipher.dart';` for `BiometricCipher`
3. Define `ScreenLockService` abstract class with four members:
   - `set onScreenLockedCallback(void Function() onLock)`
   - `void startListening()`
   - `void stopListening()`
   - `void dispose()`
4. Define `ScreenLockServiceImpl implements ScreenLockService`:
   - Constructor: `ScreenLockServiceImpl({required BiometricCipher biometricCipher})`
   - Private fields: `_biometricCipher` (final), `_subscription` (nullable), `_onScreenLocked` (nullable)
   - Class member order per conventions: constructor field (`_biometricCipher`) -> constructor -> other private fields (`_subscription`, `_onScreenLocked`) -> public methods (setter, `startListening`, `stopListening`, `dispose`)
5. Run analyze on example app to verify zero warnings/infos

### Verification

```bash
cd example && fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .
```

## Open Questions

None. The scope is fully specified by the PRD, research document, and phase task description. The implementation is a single file with well-defined behavior mirroring an existing pattern (`TimerService`).
