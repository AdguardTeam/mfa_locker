# AW-2349 Phase 1 Research: Dart Plugin Layer — `screenLockStream`

## 1. Resolved Questions

| # | Question | Answer |
|---|----------|--------|
| 1 | EventChannel field visibility on `MethodChannelBiometricCipher` | Private, `static const _screenLockEventChannel` (underscore prefix, no `@visibleForTesting`) |
| 2 | MockBiometricCipherPlatform StreamController init style | `final` inline initialization: `final screenLockStreamController = StreamController<bool>.broadcast();` — matches `isConfigured`/`keys` field style (no constructor param) |
| 3 | `Stream<bool>.empty()` vs `const Stream.empty()` | Use `Stream<bool>.empty()` with explicit type parameter |

---

## 2. Phase Scope

Phase 1 is a pure Dart change inside `packages/biometric_cipher/` only. It:
- Adds `screenLockStream` to the platform interface with a safe default
- Adds `EventChannel` + `late final` stream implementation in the method channel class
- Exposes `screenLockStream` on the public `BiometricCipher` facade
- Adds mock field + tests in `packages/biometric_cipher/test/`

No native code (Kotlin, Swift, C++), no example app changes, no root-level lib/ changes.

---

## 3. Related Modules/Services

### Files to be modified (Phase 1)

| File | Current state |
|------|--------------|
| `packages/biometric_cipher/lib/biometric_cipher_platform_interface.dart` | 127 lines; abstract class with 7 methods, all throwing `UnimplementedError`; one `static const channelName = 'biometric_cipher'` |
| `packages/biometric_cipher/lib/biometric_cipher_method_channel.dart` | 121 lines; implements all 7 platform methods via `MethodChannel`; no `EventChannel` of any kind currently |
| `packages/biometric_cipher/lib/biometric_cipher.dart` | 108 lines; public facade; `_configured` bool guards `decrypt()`; no `_configured` guard on `getTPMStatus`, `getBiometryStatus`, `generateKey`, `encrypt`, `deleteKey`, `isKeyValid` |
| `packages/biometric_cipher/test/biometric_cipher_test.dart` | 257 lines; one outer group `'BiometricCipher tests'` wrapping 7 sub-groups; one separate group `'BiometricCipherExceptionCode'` |
| `packages/biometric_cipher/test/mock_biometric_cipher_platform.dart` | 148 lines; two public fields: `bool isConfigured = false` (simple field) and `Map<String, String> get keys` (getter backed by private `_storedKeys`) |

---

## 4. Current Endpoints and Contracts

### `BiometricCipherPlatform` (platform interface)

All current members are `Future<T>` methods throwing `UnimplementedError`:

```
configure({required ConfigData configData}) → Future<void>
getTPMStatus() → Future<TPMStatus>
getBiometryStatus() → Future<BiometricStatus>
generateKey({required String tag}) → Future<void>
encrypt({required String tag, required String data}) → Future<String?>
decrypt({required String tag, required String data}) → Future<String?>
deleteKey({required String tag}) → Future<void>
isKeyValid({required String tag}) → Future<bool>
```

Static members: `channelName = 'biometric_cipher'`, `instance` (get/set).

No `Stream` members exist yet. No `EventChannel` is imported in any of the three Dart plugin files.

### `MethodChannelBiometricCipher`

Single field: `@visibleForTesting final methodChannel = const MethodChannel(BiometricCipherPlatform.channelName)`.
No `EventChannel` import or usage. The `flutter/services.dart` import is already present (covers both `MethodChannel` and `EventChannel`).

### `BiometricCipher` (public API)

The `_configured` guard is applied only to `decrypt()`. All other public methods (`getTPMStatus`, `getBiometryStatus`, `generateKey`, `encrypt`, `deleteKey`, `isKeyValid`) delegate directly to `_instance` without checking `_configured`. The new `screenLockStream` must follow this same unchecked pattern.

The constructor signature is `BiometricCipher([BiometricCipherPlatform? instance])` — the optional positional param allows test injection.

---

## 5. Patterns Used

### Default method implementations in `BiometricCipherPlatform`

All existing platform interface methods use the `throw UnimplementedError(...)` pattern as the "default". For `screenLockStream`, the PRD specifies a non-throwing default (`Stream<bool>.empty()`) because returning an empty stream is safe for unsupported platforms.

### `static const` channel name

The `MethodChannel` is already declared as a `static const channelName = 'biometric_cipher'` on `BiometricCipherPlatform`. The new `EventChannel` should use the same convention: `static const _screenLockEventChannel = EventChannel('biometric_cipher/screen_lock')` on `MethodChannelBiometricCipher` (private, no `@visibleForTesting` needed).

### `late final` fields in the codebase

`late final` is used in `packages/biometric_cipher/example/lib/tpm_screen.dart` for `BiometricCipher` and `TextEditingController` instances. No existing `late final` stream fields exist in the plugin itself — Phase 1 introduces the first one.

### `MockBiometricCipherPlatform` field pattern

The two existing mock fields follow different patterns:
- `bool isConfigured = false` — simple public mutable field, inline initialization, no constructor param
- `Map<String, String> get keys` — read-only getter backed by private `_storedKeys`

The new `screenLockStreamController` must follow the **first** pattern: `final screenLockStreamController = StreamController<bool>.broadcast();` declared directly in the class body. No constructor param. Type is `StreamController<bool>` (not `StreamController<bool>?`).

### Test structure

The test file has one outer group `'BiometricCipher tests'` containing all feature sub-groups. A new `group('screenLockStream', ...)` must be added inside this outer group alongside existing groups (`configure`, `encrypt-decrypt cycle`, `generateKey`, etc.).

The `setUp` block in the outer group creates `MockBiometricCipherPlatform` and sets `BiometricCipherPlatform.instance = mockPlatform`. The `screenLockStream` tests can reuse this setup since `mockPlatform` is already available.

### `EventChannel.receiveBroadcastStream()` usage

No existing `EventChannel` usage exists anywhere in `packages/biometric_cipher/lib/`. The `flutter/services.dart` import in `biometric_cipher_method_channel.dart` already covers `EventChannel` (it is part of `flutter/services.dart`), so no new import is needed.

### `Stream<bool>.empty()` vs `const Stream.empty()`

The user confirmed: use `Stream<bool>.empty()` with an explicit type parameter. `const Stream.empty()` without a type parameter may not be inferred as `Stream<bool>` in all contexts (e.g., when the platform interface return type is `Stream<bool>`). The explicit typed form is unambiguous.

---

## 6. Phase-Specific Limitations and Risks

### Risk: `const Stream.empty()` type inference

The PRD notes that `const Stream.empty()` (without type parameter) may not be recognized as `Stream<bool>` in all Dart type contexts. The user-confirmed answer is to use `Stream<bool>.empty()`. Note that `Stream<bool>.empty()` is NOT `const` — it is a regular named constructor call returning a non-reusable empty stream instance. This is acceptable for a getter default.

### Risk: `EventChannel` import not yet present

`EventChannel` is part of `flutter/services.dart`, which is already imported in `biometric_cipher_method_channel.dart`. No new import is needed. The `biometric_cipher_platform_interface.dart` does NOT import `flutter/services.dart` and will not need it (the platform interface only declares a `Stream<bool>` return type, which requires only `dart:async`). The platform interface currently has no `dart:async` import — adding `Stream<bool>` as a return type will require `dart:async` import (or relying on implicit availability via Flutter SDK re-exports). To be safe, explicitly add `import 'dart:async';` to `biometric_cipher_platform_interface.dart`.

### Risk: `MockBiometricCipherPlatform` must implement `screenLockStream`

Once `screenLockStream` is added to `BiometricCipherPlatform`, `MockBiometricCipherPlatform` must override it or the analyzer will report an error (missing concrete implementation). The override implementation should return `screenLockStreamController.stream`.

### Risk: test stream cleanup

The `screenLockStreamController` in the mock is created inline as `final` — it is never explicitly closed in tests. For broadcast streams this is generally safe in unit tests, but best practice is to close the controller in `tearDown`. The existing tests do not have a `tearDown` block; adding one for the stream group is advisable to avoid "stream not closed" warnings.

### Risk: `late final` field re-assignment restriction

`late final` fields in Dart can only be assigned once. If the `MethodChannelBiometricCipher` instance is reused across multiple tests and `screenLockStream` is accessed in multiple test runs, the `late final` field will be initialized on first access and cannot be re-initialized. This is fine for production (intended caching behavior) but means tests that need a fresh stream must use a new `MethodChannelBiometricCipher` instance each time — which the existing `setUp` already does by creating a new `MockBiometricCipherPlatform` and assigning it to `BiometricCipherPlatform.instance`.

### Constraint: no `_configured` guard on `screenLockStream`

The `BiometricCipher.decrypt()` method checks `_configured` and throws a `configureError`. The new `screenLockStream` getter must NOT have this check. Looking at `biometric_cipher.dart`, this is straightforward: the implementation is `Stream<bool> get screenLockStream => _instance.screenLockStream;` with no guard, consistent with the unchecked methods.

### Constraint: analyze scope

Acceptance criterion is `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` run from `packages/biometric_cipher/`. Root-level analyze is not part of Phase 1 acceptance. The plugin's `analysis_options.yaml` should be checked if it differs from root.

---

## 7. New Technical Questions

None discovered during research. All design decisions are fully specified in the PRD and resolved by user answers.

---

## Appendix: File Locations

- `/Users/comrade77/Documents/Performix/Projects/mfa_locker/packages/biometric_cipher/lib/biometric_cipher_platform_interface.dart`
- `/Users/comrade77/Documents/Performix/Projects/mfa_locker/packages/biometric_cipher/lib/biometric_cipher_method_channel.dart`
- `/Users/comrade77/Documents/Performix/Projects/mfa_locker/packages/biometric_cipher/lib/biometric_cipher.dart`
- `/Users/comrade77/Documents/Performix/Projects/mfa_locker/packages/biometric_cipher/test/biometric_cipher_test.dart`
- `/Users/comrade77/Documents/Performix/Projects/mfa_locker/packages/biometric_cipher/test/mock_biometric_cipher_platform.dart`
- `/Users/comrade77/Documents/Performix/Projects/mfa_locker/packages/biometric_cipher/pubspec.yaml`
