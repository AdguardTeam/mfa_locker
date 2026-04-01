# AW-2349 Phase 1 Plan: Dart Plugin Layer -- `screenLockStream`

**Status:** PLAN_APPROVED

## Phase Scope

Phase 1 establishes the Dart-side contract for screen lock detection inside the `biometric_cipher` plugin. It adds a `screenLockStream` getter (`Stream<bool>`) to three layers of the plugin (platform interface, method channel, public facade), updates the mock platform, and adds unit tests. No native code is touched. No example app changes.

All changes are scoped to `packages/biometric_cipher/`.

## Components

### 1. `BiometricCipherPlatform` (platform interface)

**File:** `packages/biometric_cipher/lib/biometric_cipher_platform_interface.dart`

Add a `screenLockStream` getter with a safe default:

```dart
/// Stream that emits `true` when the device screen is locked.
///
/// The stream uses an EventChannel to receive native screen lock events.
/// Returns an empty stream on platforms that do not support screen lock detection.
Stream<bool> get screenLockStream => Stream<bool>.empty();
```

Design notes:
- Uses `Stream<bool>.empty()` with explicit type parameter (not `const Stream.empty()`) to avoid type inference ambiguity. The explicit typed form is not `const`-eligible, but that is acceptable for a getter default.
- Does NOT throw `UnimplementedError` like the other methods -- an empty stream is a safe no-op for unsupported platforms.
- Requires adding `import 'dart:async';` since the file currently has no `dart:async` import and `Stream` may not be implicitly available in all analysis contexts.

### 2. `MethodChannelBiometricCipher` (method channel implementation)

**File:** `packages/biometric_cipher/lib/biometric_cipher_method_channel.dart`

Add a private `static const` EventChannel field and a `late final` stream:

```dart
static const _screenLockEventChannel = EventChannel('biometric_cipher/screen_lock');

@override
late final Stream<bool> screenLockStream = _screenLockEventChannel
    .receiveBroadcastStream()
    .map((event) => event as bool);
```

Design notes:
- `static const` EventChannel: makes the channel name a compile-time constant, referenceable in future native phases. Private (`_`) because it is an implementation detail of this class.
- `late final`: lazily initialized on first access, cached forever. Only one native subscription is created regardless of Dart listener count. `receiveBroadcastStream()` itself returns a broadcast stream supporting multiple listeners.
- No new imports needed: `EventChannel` is part of `flutter/services.dart`, already imported.
- Placement: after the existing `methodChannel` field, before the `@override` methods, following the class member order convention (static constants, then constructor fields).

### 3. `BiometricCipher` (public facade)

**File:** `packages/biometric_cipher/lib/biometric_cipher.dart`

Expose the stream via simple delegation:

```dart
/// Stream that emits `true` when the device screen is locked.
///
/// Uses platform-specific silent detection:
/// - Android: `ACTION_SCREEN_OFF` broadcast
/// - iOS: `protectedDataWillBecomeUnavailableNotification`
/// - macOS: `com.apple.screenIsLocked` distributed notification
/// - Windows: `WTS_SESSION_LOCK` session change event
///
/// Does NOT require [configure] to be called first.
Stream<bool> get screenLockStream => _instance.screenLockStream;
```

Design notes:
- No `_configured` guard. Consistent with `getTPMStatus`, `getBiometryStatus`, `generateKey`, `encrypt`, `deleteKey`, `isKeyValid` -- only `decrypt` has the guard.
- No tag/data validation -- the getter has no parameters.

### 4. `MockBiometricCipherPlatform` (test mock)

**File:** `packages/biometric_cipher/test/mock_biometric_cipher_platform.dart`

Add a broadcast `StreamController<bool>` field and override:

```dart
final screenLockStreamController = StreamController<bool>.broadcast();

@override
Stream<bool> get screenLockStream => screenLockStreamController.stream;
```

Design notes:
- `final` inline initialization, no constructor parameter. Matches the existing `isConfigured` field pattern.
- `StreamController<bool>.broadcast()` because the real stream from `receiveBroadcastStream()` is a broadcast stream -- the mock should mirror this.
- Requires adding `import 'dart:async';`.

### 5. Tests

**File:** `packages/biometric_cipher/test/biometric_cipher_test.dart`

Add a new `group('screenLockStream', ...)` inside the existing outer `'BiometricCipher tests'` group:

Test cases:
1. **Emits events from platform**: add `true` to `mockPlatform.screenLockStreamController`, verify `biometricCipher.screenLockStream` emits `true`.
2. **Works without configure**: access `screenLockStream` without calling `configure()` first, verify no exception is thrown.
3. **Multiple events**: add multiple `true` values, verify all are received.

A `tearDown` block should close the `screenLockStreamController` to avoid "stream not closed" warnings, though existing tests do not use `tearDown`.

## API Contract

### New public API surface

| Class | Member | Signature | Notes |
|-------|--------|-----------|-------|
| `BiometricCipherPlatform` | `screenLockStream` | `Stream<bool> get` | Default: `Stream<bool>.empty()` |
| `MethodChannelBiometricCipher` | `screenLockStream` | `late final Stream<bool>` | Via `EventChannel('biometric_cipher/screen_lock')` |
| `BiometricCipher` | `screenLockStream` | `Stream<bool> get` | Delegates to `_instance.screenLockStream` |

### EventChannel contract

| Property | Value |
|----------|-------|
| Channel name | `"biometric_cipher/screen_lock"` |
| Payload type | `bool` |
| Semantics | `true` = device screen locked |
| Direction | Native to Dart (one-way) |

## Data Flows

```
[Native OS event]                         (not implemented in Phase 1)
      |
      v
EventChannel("biometric_cipher/screen_lock")
      |
      v
MethodChannelBiometricCipher.screenLockStream
  late final = _screenLockEventChannel
      .receiveBroadcastStream()
      .map((event) => event as bool)
      |
      v
BiometricCipher.screenLockStream
  => _instance.screenLockStream
      |
      v
[Consumer code]                           (not implemented in Phase 1)
```

In Phase 1, the native end of the EventChannel has no handler, so no events flow. The Dart plumbing is fully wired and will begin emitting when native handlers are added in Phases 2-4.

## NFR

| Requirement | How met |
|-------------|---------|
| Zero runtime cost when unused | `late final` defers initialization until first access |
| No memory leaks | Broadcast stream + `late final` caching = single subscription |
| Backward compatible | New getter with safe default; no changes to existing API |
| Static analysis clean | Must pass `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` in `packages/biometric_cipher/` |
| Existing tests unbroken | `MockBiometricCipherPlatform` gains the new override; no existing method signatures change |

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| `Stream<bool>.empty()` is not `const`-eligible | Certain | Low | Acceptable; the getter is called once per platform interface instance. No performance concern. |
| `late final` prevents re-initialization in tests | Low | Low | Each test `setUp` creates a new `MockBiometricCipherPlatform` and new `BiometricCipher` instance; `late final` on `MethodChannelBiometricCipher` is never exercised in unit tests. |
| `dart:async` import needed in platform interface file | Certain | None | Straightforward addition. `Stream` type may already be available via transitive imports, but explicit import is best practice. |
| EventChannel name typo mismatching future native implementations | Low | High | Name is defined as `static const` in one place; native phases will reference this constant indirectly by documenting the identical string. |
| `MockBiometricCipherPlatform` compile error without override | Certain | None | The override is part of this phase's scope. Without it, existing tests would fail to compile. |

## Dependencies

- **No prior phases required.** Phase 1 is the first phase and has no dependencies.
- **Dart SDK >= 3.11.0** and **Flutter >= 3.41.0** (already satisfied by project constraints).
- **`plugin_platform_interface`** package (already a dependency of `biometric_cipher`).

## Implementation Order

1. **`biometric_cipher_platform_interface.dart`** -- add `screenLockStream` getter with default
2. **`biometric_cipher_method_channel.dart`** -- add `EventChannel` field + `late final` stream override
3. **`biometric_cipher.dart`** -- add public `screenLockStream` getter
4. **`mock_biometric_cipher_platform.dart`** -- add `StreamController<bool>` field + stream override
5. **`biometric_cipher_test.dart`** -- add `group('screenLockStream', ...)`
6. Run `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` from `packages/biometric_cipher/`
7. Run `fvm flutter test` from `packages/biometric_cipher/`

Steps 1-3 must be done together (or in order) because step 2 requires step 1's getter to override, and step 3 requires step 1's getter to delegate to. Step 4 must follow step 1 (mock must implement the new getter). Step 5 depends on step 4.

## Open Questions

None. All design decisions are fully resolved in the PRD and research documents.
