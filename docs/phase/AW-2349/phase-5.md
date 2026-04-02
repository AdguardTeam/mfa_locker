# Iteration 5: Plugin tests

**Goal:** Unit tests for `screenLockStream` in the Dart plugin layer.

## Context

Iterations 1–4 added the Dart-side `EventChannel` and all four native `ScreenLockStreamHandler` implementations (Android, iOS/macOS, Windows). This iteration adds plugin-level Dart unit tests for the `screenLockStream` API.

The existing `biometric_cipher` test setup uses a `MockBiometricCipherPlatform` that is registered as the platform instance in `setUp`. The new tests follow the same pattern: add a `StreamController<bool>` to the mock platform, override `screenLockStream`, and verify that `BiometricCipher.screenLockStream` forwards events from the platform stream.

Key design points:
- `BiometricCipherPlatform` has a default `screenLockStream` implementation that returns `const Stream.empty()` — test the default too.
- `MethodChannelBiometricCipher.screenLockStream` uses `late final` — in unit tests, the mock platform is used, not the method channel.
- Tests are located in `packages/biometric_cipher/test/` alongside the existing test file.

## Tasks

- [ ] **5.1** Add `screenLockStream` to mock platform
  - File: `packages/biometric_cipher/test/mock_biometric_cipher_platform.dart`
  - Add `StreamController<bool>` field and override `screenLockStream`

- [ ] **5.2** Add `screenLockStream` test group
  - File: `packages/biometric_cipher/test/biometric_cipher_test.dart`
  - Test: emits events from platform stream
  - Test: default platform returns empty stream

## Acceptance Criteria

**Verify:** `cd packages/biometric_cipher && fvm flutter test`

Functional criteria:
- `BiometricCipher.screenLockStream` emits `true` when the mock platform's `StreamController` emits `true`.
- The default `BiometricCipherPlatform` implementation (`screenLockStream`) returns a stream that emits no events.

## Dependencies

- Iteration 1 complete (Dart-side `screenLockStream` added to platform interface, method channel, and public API) ✅
- Iterations 2–4 complete (native handlers — not required for Dart unit tests, but confirm overall plugin state) ✅

## Technical Details

### Changes to `mock_biometric_cipher_platform.dart` (task 5.1)

Add a `StreamController<bool>` and override `screenLockStream` in the existing mock class:

```dart
final screenLockStreamController = StreamController<bool>.broadcast();

@override
Stream<bool> get screenLockStream => screenLockStreamController.stream;
```

Make sure to close the controller in `tearDown` to avoid resource leaks between tests.

### New test group in `biometric_cipher_test.dart` (task 5.2)

```dart
group('screenLockStream', () {
  test('emits events from platform', () async {
    // Use mock platform that controls a StreamController<bool>
    final controller = StreamController<bool>.broadcast();
    mockPlatform.screenLockStreamController = controller;

    final events = <bool>[];
    final subscription = biometricCipher.screenLockStream.listen(events.add);

    controller.add(true);
    await Future<void>.delayed(Duration.zero);

    expect(events, [true]);

    await subscription.cancel();
    await controller.close();
  });

  test('default platform returns empty stream', () async {
    // Reset to default platform (not the mock)
    BiometricCipherPlatform.instance = BiometricCipherPlatform();

    final events = <bool>[];
    final subscription = BiometricCipherPlatform.instance.screenLockStream.listen(events.add);

    await Future<void>.delayed(Duration.zero);

    expect(events, isEmpty);
    await subscription.cancel();
  });
});
```

> **Note:** Check how the existing test file is structured (what `biometricCipher` and `mockPlatform` variables are set up in `setUp`) and follow the same pattern. The mock platform's controller field may need a different approach if the existing mock doesn't already have a mutable field pattern.

## Implementation Notes

- The existing `mock_biometric_cipher_platform.dart` may already extend `BiometricCipherPlatform` using `implements` or `extends` — add `screenLockStream` as an override in whichever pattern is already used.
- `StreamController<bool>.broadcast()` is preferred over a single-subscription controller so the test stream behaves like the real `receiveBroadcastStream()` from `MethodChannelBiometricCipher`.
- `await Future<void>.delayed(Duration.zero)` yields the event loop, allowing the stream listener to process events synchronously added to the controller.
- Close the `StreamController` after each test to prevent "StreamController was not closed" errors.
