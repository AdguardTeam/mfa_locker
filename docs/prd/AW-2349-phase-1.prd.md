# AW-2349-phase-1: Screen Lock Detection — Dart Plugin Layer (`screenLockStream`)

Status: PRD_READY

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
| `packages/biometric_cipher/lib/biometric_cipher_method_channel.dart` | Add `static const` `EventChannel` field + `late final` `screenLockStream` impl |
| `packages/biometric_cipher/lib/biometric_cipher.dart` | Expose `screenLockStream` on public `BiometricCipher` class |
| `packages/biometric_cipher/test/biometric_cipher_test.dart` | Add `group('screenLockStream', ...)` inside existing test file |
| `packages/biometric_cipher/test/mock_biometric_cipher_platform.dart` | Add public `StreamController<bool>` field backing `screenLockStream` |

---

## Goals

1. Define the `screenLockStream` contract as a `Stream<bool>` on `BiometricCipherPlatform` with a safe default (`const Stream.empty()`) for unsupported/unimplemented platforms.
2. Implement `screenLockStream` in `MethodChannelBiometricCipher` using a `static const EventChannel('biometric_cipher/screen_lock')` field with `receiveBroadcastStream()` — lazily initialized via `late final`.
3. Expose `screenLockStream` on the public `BiometricCipher` facade, explicitly documenting that it does not require `configure()`.
4. Pass static analysis (`fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .`) on `packages/biometric_cipher/`.
5. Add unit tests for the new API surface inside the existing `biometric_cipher_test.dart` that verify the stream contract through the mock platform.

---

## User Stories

**As a library consumer** (future phases / example app), I want a `Stream<bool>` available on `BiometricCipher` that emits `true` when the device screen is locked, so that I can subscribe to it without knowing the platform-specific channel details.

**As a platform implementer** (native phase authors), I want the `EventChannel` name (`"biometric_cipher/screen_lock"`) and stream type (`Stream<bool>`) to be established in Dart before I implement the native side, so that the native registration can reference an agreed-upon channel name via the `static const` field.

**As a test author**, I want the mock platform to carry a controllable `screenLockStream` backed by a public `StreamController<bool>` field, so that I can exercise the full stream path in unit tests without native code.

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
- `MockBiometricCipherPlatform` exposes a public `StreamController<bool>` field (consistent with existing mock fields such as `isConfigured` and `keys`).
- Test calls `mockPlatform.screenLockStreamController.add(true)`.
- `BiometricCipher.screenLockStream` emits `true` to the listener.
- Test verifies the event is received inside the existing `biometric_cipher_test.dart` under a new `group('screenLockStream', ...)`.

### Scenario 5 — `configure()` independence
- Consumer accesses `BiometricCipher().screenLockStream` without ever calling `configure()`.
- No `BiometricCipherException` with `configureError` is thrown.
- Stream is accessible and emits normally.

---

## Success / Metrics

| Criterion | How verified |
|-----------|-------------|
| `screenLockStream` added to `BiometricCipherPlatform` with `Stream.empty()` default | Code review / analyze |
| `MethodChannelBiometricCipher` implements `screenLockStream` via `static const EventChannel('biometric_cipher/screen_lock')` | Code review / analyze |
| `BiometricCipher.screenLockStream` delegates to `_instance.screenLockStream` with no `_configured` guard | Code review |
| `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` passes with zero warnings/infos | CI analyze step |
| `group('screenLockStream', ...)` added to `biometric_cipher_test.dart`; all tests pass | Test file present, tests green |
| `MockBiometricCipherPlatform` has a public `StreamController<bool>` field backing `screenLockStream` | Code review / tests green |
| No changes outside `packages/biometric_cipher/` | Diff scope |

---

## Constraints and Assumptions

- **Dart-only scope:** Phase 1 touches no native code (Kotlin, Swift, C++). Native handlers are out of scope.
- **EventChannel name is fixed:** `"biometric_cipher/screen_lock"` — must be identical in Dart and all future native implementations.
- **Stream type is `Stream<bool>`:** Matches the raw `EventChannel` payload type and reserves `false` for a potential future unlock signal. Only `true` (lock event) is emitted in practice.
- **`static const` EventChannel field:** The `EventChannel` is declared as a `static const` field on `MethodChannelBiometricCipher` so the channel name is referenceable by name in tests and native phases.
- **`late final` initialization:** `MethodChannelBiometricCipher.screenLockStream` must be `late final` to lazily create and cache the native subscription — exactly one native subscription regardless of listener count.
- **No `_configured` guard:** Unlike `decrypt()`, `screenLockStream` must be accessible without prior `configure()` call. The doc comment on `BiometricCipher.screenLockStream` must state this explicitly.
- **Default is `const Stream.empty()`:** The platform interface provides a non-throwing default, making all platforms safe even before native support is added.
- **Mock field style:** `MockBiometricCipherPlatform` exposes a public `StreamController<bool>` field for `screenLockStream`, consistent with the existing pattern of public fields (`isConfigured`, `keys`). No constructor parameter is needed.
- **Test placement:** `screenLockStream` tests are added as a new `group('screenLockStream', ...)` inside the existing `biometric_cipher_test.dart`. A separate test file is not created.
- **Plugin analyze scope:** Acceptance criterion is `fvm flutter analyze` scoped to `packages/biometric_cipher/` only. Root-level analyze is not part of Phase 1 acceptance.
- **Existing tests must remain green:** No regressions to the existing `biometric_cipher_test.dart` test groups (`configure`, `encrypt-decrypt cycle`, `generateKey`, `encrypt`, `decrypt`, `deleteKey`, `isKeyValid`).

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| `late final` field initialization order causes issues if accessed before engine is ready | Low | Medium | `late final` defers until first access; no eager initialization risk |
| EventChannel name typo mismatching future native implementations | Low | High | Channel name defined as a `static const` field on `MethodChannelBiometricCipher`; native phases reference it by this constant |
| `receiveBroadcastStream()` behavior differs between Flutter versions | Low | Low | Flutter version is pinned at 3.41.4 via `.ci-flutter-version` |
| `const Stream.empty()` default not recognized as `Stream<bool>` in all Dart type contexts | Low | Low | Explicit type parameter `Stream<bool>.empty()` or cast may be needed; verify during implementation |

---

## Resolved Questions

1. **Mock platform design for `screenLockStream`:** Resolved — use a public `StreamController<bool>` field on `MockBiometricCipherPlatform`, consistent with the existing pattern of public fields (`isConfigured`, `keys`). No constructor parameter.

2. **Test file location for `screenLockStream` tests:** Resolved — add a new `group('screenLockStream', ...)` inside the existing `biometric_cipher_test.dart`. Do not create a separate file.

3. **`Stream<bool>` vs `Stream<void>`:** Resolved — use `Stream<bool>`. This matches the raw `EventChannel` payload type and reserves the `false` value for a potential future unlock signal.

4. **`static const` vs inline EventChannel definition:** Resolved — declare `EventChannel` as a `static const` field on `MethodChannelBiometricCipher`. This makes the channel name referenceable by name in tests and in future native phases.

## Open Questions

_(none)_
