# Research: AW-2349 Phase 6 — Example App `ScreenLockService`

## Phase Scope

Phase 6 adds exactly one new file to the example app layer:

```
example/lib/core/services/screen_lock_service.dart
```

It introduces `ScreenLockService` (abstract class) and `ScreenLockServiceImpl` that wrap `BiometricCipher.screenLockStream` behind a callback interface mirroring `TimerService`. No other files are touched. DI wiring is out of scope (Phase 7). BLoC integration is out of scope (Phase 8).

---

## Resolved Questions

The PRD has no open questions. Scope is fully specified.

---

## Related Modules/Services

### `example/lib/core/services/timer_service.dart`

The canonical pattern to mirror. Key observations:

- Abstract class `TimerService` uses `implements` (not `extends`), no prefix.
- Implementation class `TimerServiceImpl` uses `Impl` suffix.
- Callback is a nullable `void Function()?` field named `_onLock`, set via a setter (`set onLockCallback`).
- Lifecycle methods: `startTimer()`, `stopTimer()`, `dispose()`.
- `dispose()` delegates to `_cancelTimer()` which nulls out the mutable resource (`_lockTimer`).
- Constructor uses named required parameter with `_field = field` initializer body pattern.

`ScreenLockService` must mirror this shape precisely, substituting `Timer` with `StreamSubscription<bool>?` and `startTimer`/`stopTimer` with `startListening`/`stopListening`.

### `packages/biometric_cipher/lib/biometric_cipher.dart`

`BiometricCipher` exposes:

```dart
Stream<bool> get screenLockStream => _instance.screenLockStream;
```

This getter delegates to `BiometricCipherPlatform.screenLockStream`. The stream emits `true` on each screen lock event. The payload value is discarded by the service — only the emission occurrence matters.

### `packages/biometric_cipher/lib/biometric_cipher_method_channel.dart`

The actual stream is a broadcast stream built as:

```dart
late final Stream<bool> screenLockStream = _screenLockEventChannel
    .receiveBroadcastStream()
    .map((event) => event as bool);
```

Using `late final` means it initializes on first access — no eager setup risk. No `configure()` call required before accessing `screenLockStream`.

### `packages/biometric_cipher/lib/biometric_cipher_platform_interface.dart`

The base class `BiometricCipherPlatform` provides a fallback:

```dart
Stream<bool> get screenLockStream => const Stream<bool>.empty();
```

This means on unsupported platforms the stream is inert — safe to subscribe to without special-casing.

---

## Current Endpoints and Contracts

### `BiometricCipher.screenLockStream` — `Stream<bool>`

- Type: `Stream<bool>` (broadcast, from `receiveBroadcastStream`)
- Emits: `true` on screen lock event
- Requires `configure()`: No
- Platforms: Android, iOS, macOS, Windows (returns empty stream on others)

### `TimerService` interface (for reference shape)

```dart
abstract class TimerService {
  set onLockCallback(void Function() onLock);
  Future<void> startTimer();
  void stopTimer();
  void dispose();
  // ... additional members specific to timer
}
```

`ScreenLockService` uses the same structural pattern (setter + start/stop/dispose) but is simpler — no `Future<void>` methods, no state getters.

---

## Services Directory Layout

```
example/lib/core/services/
└── timer_service.dart        ← existing; pattern to mirror
    (screen_lock_service.dart ← NEW in this phase)
```

`screen_lock_service.dart` sits alongside `timer_service.dart`. The directory currently has only one file.

---

## DI Wiring Context (awareness only — not in scope for Phase 6)

### `example/lib/di/factories/repository_factory.dart`

`RepositoryFactoryImpl`:
- Holds `TimerService? _timerService` (lazy-initialized in `init()`).
- Creates a `BiometricCipher` implicitly via `lockerRepository.configureBiometricCipher(...)` — but the `BiometricCipher` instance is currently owned inside `LockerRepositoryImpl`, not exposed as a top-level field on `RepositoryFactoryImpl`.

Phase 7 will need to expose a `BiometricCipher` instance from `RepositoryFactoryImpl` and instantiate `ScreenLockServiceImpl` with it. This is not a concern for Phase 6.

### `example/lib/di/factories/bloc_factory.dart`

`BlocFactoryImpl`:
- Accepts `TimerService` as a required constructor parameter and passes it to `LockerBloc`.
- Phase 7/8 will add `ScreenLockService` here similarly.

### `example/lib/di/dependency_scope.dart`

`DependencyScope` is a `StatefulWidget`-based inherited widget that provides `RepositoryFactory` and `BlocFactory` to the tree. No changes needed in this phase.

### `LockerBloc` — timer integration (reference for Phase 8)

How `TimerService` is wired in `LockerBloc` (relevant for Phase 8, documented for context):

```dart
_timerService.onLockCallback = _onTimerExpired;   // set in constructor
await _timerService.startTimer();                  // on unlock (_refreshUnlockedState)
_timerService.stopTimer();                         // on lock (_onLockerStateChanged)
_timerService.touch();                             // on activity (_onActivityDetected)
```

`ScreenLockService` will follow the same start-on-unlock / stop-on-lock pattern (Phase 8).

---

## Patterns Used

### Abstract class + Impl suffix

All service/repository interfaces in this codebase use no prefix for the abstract class and `Impl` suffix for the implementation:

- `TimerService` / `TimerServiceImpl`
- `LockerRepository` / `LockerRepositoryImpl`
- `EncryptedStorage` / `EncryptedStorageImpl`

`ScreenLockService` / `ScreenLockServiceImpl` follows this exact convention.

### Callback pattern (nullable setter)

```dart
void Function()? _onLock;

@override
set onLockCallback(void Function() onLock) => _onLock = onLock;
```

The callback is set post-construction (not in the constructor). Arrow syntax on the setter. Invoked as `_onLock?.call()` — null-safe, no guard needed.

### Subscription lifecycle pattern

`startListening()` must cancel any existing subscription before creating a new one (safe re-subscribe), matching how `TimerServiceImpl._scheduleTimer()` calls `_lockTimer?.cancel()` before creating a new `Timer`.

### `dispose()` delegating to `stopX()`

```dart
@override
void dispose() => _cancelTimer();   // in TimerServiceImpl
```

`ScreenLockServiceImpl.dispose()` calls `stopListening()` then nulls `_onScreenLocked`. The null assignment prevents stale callback references post-dispose.

### Required named constructor parameter

```dart
TimerServiceImpl({required LockerRepository lockerRepository})
    : _lockerRepository = lockerRepository;
```

`ScreenLockServiceImpl` uses the same style:

```dart
ScreenLockServiceImpl({required BiometricCipher biometricCipher})
    : _biometricCipher = biometricCipher;
```

### File naming

One type per file. File name matches the abstract class: `screen_lock_service.dart`. Both abstract and impl are in the same file (matching `timer_service.dart` which also co-locates both in one file).

### Import requirements

The new file requires:
- `import 'dart:async';` — for `StreamSubscription<bool>`
- `import 'package:biometric_cipher/biometric_cipher.dart';` — for `BiometricCipher`

The `biometric_cipher` package is a direct path dependency of `mfa_demo` in `example/pubspec.yaml`.

---

## Phase-Specific Limitations and Risks

| Risk | Notes |
|------|-------|
| `BiometricCipher` instance not yet surfaced from DI | Phase 6 only creates the class; Phase 7 wires it. The constructor requires it as a parameter — this is by design. No self-contained testability until Phase 7. |
| `StreamSubscription.cancel()` is async but not awaited | Dart guarantees no further events are delivered once `cancel()` is called, even without awaiting the returned `Future`. The null-safe callback `_onScreenLocked?.call()` provides an additional safety layer. This is low risk and matches idiomatic Flutter service patterns. |
| Broadcast stream vs single-subscription | `screenLockStream` from `MethodChannelBiometricCipher` is a broadcast stream (`receiveBroadcastStream()`). Multiple `listen()` calls are safe — no "already listened" error. The `startListening()` safe-cancel pattern is still correct. |
| `late final` in `MethodChannelBiometricCipher` | The stream is lazily initialized on first `.listen()` access. No concern for Phase 6 — deferred initialization is the correct behavior for EventChannel streams. |
| No tests in Phase 6 | Accepted per PRD constraint. Tests depend on being able to inject a mock `BiometricCipher` which requires the DI layer (Phase 7). |

---

## New Technical Questions

None. The implementation is fully specified by the PRD and phase task document. The `screen_lock_service.dart` contents are provided verbatim in `docs/phase/AW-2349/phase-6.md` Technical Details section.
