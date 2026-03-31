# Vision: Lock Application on Device Screen Lock (AW-2349)

---

## 1. Technologies

| Layer | Technology | Purpose |
|-------|-----------|---------|
| **Dart ↔ Native bridge** | Flutter `EventChannel` | Stream native OS lock events to Dart |
| **Android** | `BroadcastReceiver` + `ACTION_SCREEN_OFF` | Detect screen off |
| **iOS** | `NotificationCenter` + `protectedDataWillBecomeUnavailableNotification` | Detect device lock |
| **macOS** | `DistributedNotificationCenter` + `com.apple.screenIsLocked` | Detect screen lock |
| **Windows** | `WTSRegisterSessionNotification` + `WM_WTSSESSION_CHANGE` | Detect session lock |
| **Host plugin** | `biometric_cipher` (existing) | Houses the EventChannel alongside existing MethodChannel |
| **App layer** | `LockerBloc` + callback service (existing patterns) | Receives lock signal, calls `lock()` |

No new dependencies, no new plugins, no new packages. Everything extends what already exists.

---

## 2. Development Principles

- **KISS** — One EventChannel, one service, one BLoC event. No abstractions beyond what's needed.
- **Extend, don't create** — Add to `biometric_cipher` plugin, not a new plugin. Add to `LockerBloc`, not a new BLoC.
- **Follow existing patterns** — `ScreenLockService` mirrors `TimerService` (callback interface, start/stop lifecycle, DI injection). No new architectural patterns.
- **Event-driven, not polling** — OS pushes events through EventChannel. Zero CPU cost when idle.
- **Security-first** — Screen lock bypasses the biometric operation guard. Physical device lock = unconditional app lock.
- **Detect only lock, not unlock** — Unlock already handled by `AppLifecycleState.resumed` + `shouldLockOnResume`. No duplicate work.

---

## 3. Project Structure

New and modified files only:

```
packages/biometric_cipher/
├── lib/
│   ├── biometric_cipher.dart                    # + screenLockStream getter
│   ├── biometric_cipher_method_channel.dart     # + EventChannel impl
│   └── biometric_cipher_platform_interface.dart # + screenLockStream abstract
├── android/…/handlers/
│   └── ScreenLockStreamHandler.kt               # NEW — BroadcastReceiver
├── darwin/Classes/
│   └── ScreenLockStreamHandler.swift            # NEW — iOS/macOS observer
├── windows/
│   ├── handlers/screen_lock_stream_handler.cpp  # NEW — WTS handler impl
│   └── include/…/handlers/screen_lock_stream_handler.h # NEW — WTS handler decl
└── test/
    └── biometric_cipher_test.dart               # + screenLockStream tests

example/
├── lib/
│   ├── core/services/
│   │   └── screen_lock_service.dart             # NEW — wraps platform stream
│   ├── di/factories/
│   │   ├── repository_factory.dart              # + create service
│   │   └── bloc_factory.dart                    # + inject service
│   ├── features/locker/bloc/
│   │   ├── locker_event.dart                    # + screenLocked event
│   │   └── locker_bloc.dart                     # + handler, start/stop
│   └── main.dart                                # + wire DI
└── test/core/services/
    └── screen_lock_service_test.dart            # NEW

```

**6 new files, 10 modified files.** Minimal footprint.

---

## 4. Project Architecture

### Data flow

```
┌─────────────────────────────────────────────────┐
│                   Native OS                      │
│  Android: ACTION_SCREEN_OFF                      │
│  iOS: protectedDataWillBecomeUnavailable         │
│  macOS: com.apple.screenIsLocked                 │
│  Windows: WTS_SESSION_LOCK                       │
└────────────────────┬────────────────────────────┘
                     │ OS notification
                     ▼
┌─────────────────────────────────────────────────┐
│       ScreenLockStreamHandler (native)           │
│       EventSink.success(true)                    │
└────────────────────┬────────────────────────────┘
                     │ EventChannel
                     ▼
┌─────────────────────────────────────────────────┐
│       BiometricCipher.screenLockStream           │
│       Stream<bool>                               │
└────────────────────┬────────────────────────────┘
                     │ subscribe
                     ▼
┌─────────────────────────────────────────────────┐
│       ScreenLockService                          │
│       onScreenLockedCallback()                   │
└────────────────────┬────────────────────────────┘
                     │ callback
                     ▼
┌─────────────────────────────────────────────────┐
│       LockerBloc                                 │
│       add(LockerEvent.screenLocked())            │
│       → _lockerRepository.lock()                 │
└─────────────────────────────────────────────────┘
```

### Key decisions

- **No new abstractions** — `ScreenLockService` is the only new Dart class in the app layer.
- **Same DI path** — injected via existing `RepositoryFactory` → `BlocFactory` → `LockerBloc`.
- **Lifecycle tied to locker state** — listening starts on unlock, stops on lock. Native listener inactive when locker is locked.
- **Bypasses biometric guard** — `_onScreenLocked` does not check `BiometricOperationState`. Physical device lock = unconditional app lock.

---

## 5. Data Model

No new data models. No new state fields. The feature adds only:

| Element | Type | Description |
|---------|------|-------------|
| `screenLockStream` | `Stream<bool>` | Emits `true` on device lock. One-way, fire-and-forget. |
| `LockerEvent.screenLocked()` | Freezed event | Added to existing `LockerEvent` sealed class. |
| `ScreenLockService` | Interface + impl | Callback-based, stateless. Mirrors `TimerService` pattern. |

The screen lock event is transient — it arrives, triggers `lock()`, and is gone. No persistent storage changes.

---

## 6. Workflows

### 6.1. Main flow: screen lock detection

```
1. Locker unlocks
   → ScreenLockService.startListening()
   → native receiver/observer registered

2. User locks device screen

3. OS fires native notification
   → ScreenLockStreamHandler pushes true through EventSink

4. ScreenLockService receives event
   → calls onScreenLockedCallback

5. LockerBloc adds LockerEvent.screenLocked()

6. _onScreenLocked handler calls _lockerRepository.lock()
   → MFALocker.lock() erases meta cache, emits LockerState.locked

7. ScreenLockService.stopListening()
   → native listener unregistered
```

### 6.2. Fallback: Flutter engine suspended

```
1. App is in background/suspended when device locks
2. EventChannel event may not be delivered
3. On next app resume → AppLifecycleState.resumed fires
4. _onAppResumed() checks shouldLockOnResume → timer expired → locks
   (existing behavior, unchanged)
```

### 6.3. Edge case: rapid lock/unlock

```
1. User rapidly presses power button (lock → unlock → lock)
2. Multiple true events may fire
3. First event → MFALocker.lock() succeeds
4. Subsequent events → MFALocker.lock() is a no-op (already locked)
5. No race conditions
```

---

## 7. Logging Approach

**No new logging.** The feature is a single boolean event flowing through existing infrastructure.

- The native handlers are trivial one-liners — no diagnostic value in logging them.
- `ScreenLockService` is a thin stream wrapper — nothing to log.
- `LockerBloc` state changes (`LockerState.locked`) are already observable via BLoC state inspection.
- The event carries no payload — nothing sensitive to accidentally leak.

If debugging "why did the app lock?" is needed during development, the BLoC state transition from `unlocked` → `locked` is sufficient. The trigger (timer vs screen lock vs manual) can be distinguished by setting a breakpoint in the respective handler.
