# AW-2349-phase-1: Screen Lock Detection — Dart Plugin Layer (`screenLockStream`)

Status: DRAFT

## Context / Idea

MFA spec Section 8 requires: "if the device is locked (lock screen) → lock immediately." The current implementation only locks via timer expiration (`TimerService`) or background timeout (`shouldLockOnResume` on `AppLifecycleState.resumed`). There is no detection of the device screen being actively locked while the app is in the foreground.

The full feature (AW-2349) adds native screen lock detection across Android, iOS, macOS, and Windows, wired through a new `EventChannel` in the `biometric_cipher` plugin into the example app's `LockerBloc`. The implementation is split into sequential phases:

- **Phase 1 (this phase):** Dart plugin layer — `screenLockStream` API surface on `BiometricCipherPlatform`, `MethodChannelBiometricCipher`, and `BiometricCipher`. No native handlers yet.
- Phase 2: Android native handler (`ScreenLockStreamHandler.kt` + `BroadcastReceiver`).
- Phase 3: iOS/macOS native handler (`ScreenLockStreamHandler.swift`).
- Phase 4: Windows native handler (`ScreenLockStreamHandler.cpp/.h`).
- Phase 5: Example app wiring (`ScreenLockService`, DI, `LockerBloc` integration).

Phase 1 is a pure Dart change inside `packages/biometric_cipher/`. It establishes the `EventChannel` name (`"biometric_cipher/screen_lock"`), the `Stream<bool>` contract, and the default fallback for unsupported platforms — with no dependency on any prior phase.

### Affected files (Phase 1 only)

| File | Change |
|------|--------|
| `packages/biometric_cipher/lib/biometric_cipher_platform_interface.dart` | Add `screenLockStream` getter with empty-stream default |
| `packages/biometric_cipher/lib/biometric_cipher_method_channel.dart` | Add `EventChannel` constant + `late final` `screenLockStream` impl |
| `packages/biometric_cipher/lib/biometric_cipher.dart` | Expose `screenLockStream` on public `BiometricCipher` class |
| `packages/biometric_cipher/test/biometric_cipher_test.dart` | Add `screenLockStream` test group |
| `packages/biometric_cipher/test/mock_biometric_cipher_platform.dart` | Add `screenLockStream` support to mock |

---

## Goals

1. Define the `screenLockStream` contract as a `Stream<bool>` on `BiometricCipherPlatform` with a safe default (`const Stream.empty()`) for unsupported/unimplemented platforms.
2. Implement `screenLockStream` in `MethodChannelBiometricCipher` using `EventChannel('biometric_cipher/screen_lock')` with `receiveBroadcastStream()` — lazily initialized via `late final`.
3. Expose `screenLockStream` on the public `BiometricCipher` facade, explicitly documenting that it does not require `configure()`.
4. Pass static analysis (`fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .`) on `packages/biometric_cipher/`.
5. Add unit tests for the new API surface that verify the stream contract through the mock platform.

---

## User Stories

**As a library consumer** (future phases / example app), I want a `Stream<bool>` available on `BiometricCipher` that emits `true` when the device screen is locked, so that I can subscribe to it without knowing the platform-specific channel details.

**As a platform implementer** (native phase authors), I want the `EventChannel` name (`"biometric_cipher/screen_lock"`) and stream type (`Stream<bool>`) to be established in Dart before I implement the native side, so that the native registration can reference an agreed-upon channel name.

**As a test author**, I want the mock platform to carry a controllable `screenLockStream` so that I can exercise the full stream path in unit tests without native code.

---

## Main Scenarios

### Scenario 1 — Unsupported platform (default behavior)
- Consumer accesses `BiometricCipher().screenLockStream`.
- Platform interface returns `const Stream.empty()` (the default implementation).
- Consumer's `listen()` never fires.
- No errors, no crashes.

### Scenario 2 — Supported platform, no native handler yet (Phase 1 runtime state)
- `MethodChannelBiometricCipher.screenLockStream` is accessed.
- `EventChannel.receiveBroadcastStream()` is called and the `late final` field is initialized.
- No native side has registered a stream handler, so no events are emitted.
- The stream is open and valid; native handlers added in later phases will emit into it.

### Scenario 3 — Multiple Dart listeners
- Two parts of the app subscribe to `BiometricCipher().screenLockStream` simultaneously.
- Because `receiveBroadcastStream()` is used and cached via `late final`, only one native subscription is created.
- Both Dart listeners receive events when the native side fires.

### Scenario 4 — Unit test with mock platform
- `MockBiometricCipherPlatform` exposes a `StreamController<bool>` that backs `screenLockStream`.
- Test calls `streamController.add(true)`.
- `BiometricCipher.screenLockStream` emits `true` to the listener.
- Test verifies the event is received.

### Scenario 5 — `configure()` independence
- Consumer accesses `BiometricCipher().screenLockStream` without ever calling `configure()`.
- No `BiometricCipherException` with `configureError` is thrown.
- Stream is accessible and emits normally.

---

## Success / Metrics

| Criterion | How verified |
|-----------|-------------|
| `screenLockStream` added to `BiometricCipherPlatform` with `Stream.empty()` default | Code review / analyze |
| `MethodChannelBiometricCipher` implements `screenLockStream` via `EventChannel('biometric_cipher/screen_lock')` | Code review / analyze |
| `BiometricCipher.screenLockStream` delegates to `_instance.screenLockStream` with no `_configured` guard | Code review |
| `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` passes with zero warnings/infos | CI analyze step |
| Unit tests for `screenLockStream` added to `biometric_cipher_test.dart` | Test file present, tests pass |
| `MockBiometricCipherPlatform.screenLockStream` is controllable in tests | Code review / tests green |
| No changes outside `packages/biometric_cipher/` | Diff scope |

---

## Constraints and Assumptions

- **Dart-only scope:** Phase 1 touches no native code (Kotlin, Swift, C++). Native handlers are out of scope.
- **EventChannel name is fixed:** `"biometric_cipher/screen_lock"` — must be identical in Dart and all future native implementations.
- **Stream type is `Stream<bool>`:** Only emits `true` (lock event). Unlock detection is handled by existing `AppLifecycleState.resumed` logic. The `false` value is reserved but not used.
- **`late final` initialization:** `MethodChannelBiometricCipher.screenLockStream` must be `late final` to lazily create and cache the native subscription — exactly one native subscription regardless of listener count.
- **No `_configured` guard:** Unlike `decrypt()`, `screenLockStream` must be accessible without prior `configure()` call. The doc comment on `BiometricCipher.screenLockStream` must state this explicitly.
- **Default is `const Stream.empty()`:** The platform interface provides a non-throwing default, making all platforms safe even before native support is added.
- **Plugin analyze scope:** Acceptance criterion is `fvm flutter analyze` scoped to `packages/biometric_cipher/` only. Root-level analyze is not part of Phase 1 acceptance.
- **Existing tests must remain green:** No regressions to the existing `biometric_cipher_test.dart` test groups (`configure`, `encrypt-decrypt cycle`, `generateKey`, `encrypt`, `decrypt`, `deleteKey`, `isKeyValid`).

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| `late final` field initialization order causes issues if accessed before engine is ready | Low | Medium | `late final` defers until first access; no eager initialization risk |
| Mock platform not updated to include `screenLockStream`, causing test compilation failure | Medium | Low | Phase 1 tasks explicitly include updating `MockBiometricCipherPlatform` |
| EventChannel name typo mismatching future native implementations | Low | High | Channel name `"biometric_cipher/screen_lock"` defined as a `static const` in `MethodChannelBiometricCipher`, referenced by name in native phases |
| `receiveBroadcastStream()` behavior differs between Flutter versions | Low | Low | Flutter version is pinned at 3.41.4 via `.ci-flutter-version` |
| `const Stream.empty()` default not recognized as `Stream<bool>` in all Dart type contexts | Low | Low | Explicit type parameter `Stream<bool>.empty()` or cast may be needed; verify during implementation |

---

## Open Questions

1. **Mock platform design for `screenLockStream`:** The idea doc shows `mockPlatform.screenLockStreamController = controller` — should `MockBiometricCipherPlatform` expose a `StreamController<bool>` as a public field, or should the field be set via a constructor parameter? The existing mock uses public fields (e.g., `isConfigured`, `keys`) — is a public `StreamController` field consistent with the mock's style?

2. **Test file location for `screenLockStream` tests:** The idea doc places them in `packages/biometric_cipher/test/biometric_cipher_test.dart` as a new `group('screenLockStream', ...)`. Is this preferred over a separate `screen_lock_stream_test.dart` file? (The one-type-per-file convention applies to types, not test groups — but a separate file would improve discoverability.)

3. **`Stream<bool>` vs `Stream<void>`:** The stream only ever emits `true`. Should the type be `Stream<void>` to better express the semantic (an event with no payload), or is `Stream<bool>` preferred because it aligns with what the native `EventChannel` carries (a boolean value) and leaves room for a hypothetical `false` (unlock) event?

4. **`static const` vs `late static const` for EventChannel name:** Should `_screenLockEventChannel` be a `static const EventChannel(...)` field on `MethodChannelBiometricCipher`, or defined inline in the `late final` initializer? A `static const` field makes the channel name referenceable for testing.
