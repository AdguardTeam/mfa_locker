# Iteration 6: Example app — `ScreenLockService`

**Goal:** Create `ScreenLockService` wrapping the platform stream — mirrors `TimerService` pattern.

## Context

Iterations 1–5 completed the full plugin layer: Dart-side `EventChannel`, all four native `ScreenLockStreamHandler` implementations (Android, iOS/macOS, Windows), and plugin-level unit tests. This iteration brings the feature into the example app by creating the `ScreenLockService` abstraction that bridges the plugin stream to `LockerBloc`.

`ScreenLockService` is the only new Dart class added to the app layer. It is intentionally minimal: a callback interface + subscription management, identical in shape to the existing `TimerService`. No new architectural patterns introduced.

Key design points:
- **Mirrors `TimerService`**: `onScreenLockedCallback` setter + `startListening()` / `stopListening()` / `dispose()` lifecycle.
- **Lifecycle tied to locker state**: `startListening()` is called on unlock, `stopListening()` on lock. Native listener is inactive when locker is locked — zero CPU cost at rest.
- **Single subscription**: `startListening()` cancels any existing subscription before creating a new one (safe to call multiple times).
- **No new dependencies**: Consumes `BiometricCipher.screenLockStream` — the `BiometricCipher` instance already exists in `RepositoryFactoryImpl`.

## Tasks

- [x] **6.1** Create `ScreenLockService` interface and implementation
  - File: new — `example/lib/core/services/screen_lock_service.dart`
  - Abstract: `onScreenLockedCallback` setter, `startListening()`, `stopListening()`, `dispose()`
  - Impl: subscribes to `BiometricCipher.screenLockStream`, invokes callback on event

## Acceptance Criteria

**Verify:** `cd example && fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .`

Functional criteria:
- `ScreenLockServiceImpl` subscribes to `BiometricCipher.screenLockStream` when `startListening()` is called.
- `stopListening()` cancels the subscription — subsequent stream events do not invoke the callback.
- `dispose()` cancels the subscription and clears the callback reference.
- Calling `startListening()` a second time replaces the previous subscription (no double-fire).

## Dependencies

- Iteration 1 complete (Dart-side `BiometricCipher.screenLockStream` API) ✅
- Iterations 2–4 complete (native handlers on all platforms) ✅
- Iteration 5 complete (plugin tests) ✅

## Technical Details

### `screen_lock_service.dart` (new file)

```dart
import 'dart:async';

import 'package:biometric_cipher/biometric_cipher.dart';

abstract class ScreenLockService {
  /// Set the callback to be invoked when the device screen is locked.
  set onScreenLockedCallback(void Function() onLock);

  /// Start listening for screen lock events.
  void startListening();

  /// Stop listening for screen lock events.
  void stopListening();

  /// Dispose of resources.
  void dispose();
}

class ScreenLockServiceImpl implements ScreenLockService {
  ScreenLockServiceImpl({required BiometricCipher biometricCipher})
      : _biometricCipher = biometricCipher;

  final BiometricCipher _biometricCipher;
  StreamSubscription<bool>? _subscription;
  void Function()? _onScreenLocked;

  @override
  set onScreenLockedCallback(void Function() onLock) => _onScreenLocked = onLock;

  @override
  void startListening() {
    _subscription?.cancel();
    _subscription = _biometricCipher.screenLockStream.listen((_) {
      _onScreenLocked?.call();
    });
  }

  @override
  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
  }

  @override
  void dispose() {
    stopListening();
    _onScreenLocked = null;
  }
}
```

The `BiometricCipher` instance (`_biometricCipher`) is already created in `RepositoryFactoryImpl` for biometric operations. `ScreenLockServiceImpl` reuses it — no second instance needed.

### Data flow (this iteration's scope)

```
BiometricCipher.screenLockStream  ←  EventChannel  ←  native ScreenLockStreamHandler
        │
        │ .listen()
        ▼
ScreenLockServiceImpl._subscription
        │
        │ _onScreenLocked?.call()
        ▼
[callback set by LockerBloc in Iteration 8]
```

## Implementation Notes

- File goes in `example/lib/core/services/` alongside the existing `timer_service.dart`.
- The abstract class name is `ScreenLockService` (no prefix), implementation is `ScreenLockServiceImpl` — follows the project convention (no prefix for interface, `Impl` suffix for main implementation).
- No code generation required for this file — pure Dart, no Freezed or build_runner.
- Iteration 7 (DI wiring) will create `ScreenLockServiceImpl` in `RepositoryFactoryImpl` and wire it through `BlocFactory`. Iteration 8 (BLoC integration) will set the callback and call `startListening()`/`stopListening()`. This iteration only creates the service class itself.
