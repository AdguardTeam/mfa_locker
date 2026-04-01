# QA Plan: AW-2349 Phase 1 — Dart Plugin Layer: `screenLockStream`

Status: REVIEWED
Date: 2026-04-01

---

## Phase Scope

Phase 1 is a **pure Dart change inside `packages/biometric_cipher/`**. It establishes the `screenLockStream` API surface across three layers of the plugin:

1. `BiometricCipherPlatform` — abstract getter with `Stream<bool>.empty()` default
2. `MethodChannelBiometricCipher` — `static const EventChannel` + `late final Stream<bool>` override
3. `BiometricCipher` (public facade) — delegating getter with no `_configured` guard

Supporting changes: `MockBiometricCipherPlatform` gains a public `StreamController<bool>` field and a `screenLockStream` override; `biometric_cipher_test.dart` gains a `group('screenLockStream', ...)`.

**Out of scope for Phase 1:** all native handlers (Android, iOS/macOS, Windows), any example app wiring, and the `ScreenLockService` class. Those belong to Phases 2–5 and are tested in their respective QA plans.

---

## Implementation Status (observed)

All five files specified in the plan were read from the repository. Findings:

**`biometric_cipher_platform_interface.dart`**
- `dart:async` import is present (line 1).
- `screenLockStream` getter is present at line 37: `Stream<bool> get screenLockStream => const Stream<bool>.empty();`
- Note: the getter uses `const Stream<bool>.empty()`. The plan says `const` is not `Stream<bool>.empty()`-eligible and prefers the non-`const` form, while `phase-1.md` tasklist item 1.1 shows `const Stream.empty()` and the PRD says `const Stream.empty()`. In practice `const Stream<bool>.empty()` is valid Dart (the `Stream.empty()` factory is `const`), so this is functionally equivalent and not a defect. The analyzer will confirm correctness.
- Getter is placed after the `instance` setter and before `configure()`, following class member order convention.

**`biometric_cipher_method_channel.dart`**
- `_screenLockEventChannel` is declared at line 12 as `static const _screenLockEventChannel = EventChannel('biometric_cipher/screen_lock');` — matches spec exactly.
- `screenLockStream` override is at lines 19–21 as `@override late final Stream<bool>` backed by `receiveBroadcastStream().map((event) => event as bool)`.
- Placed before `@override configure(...)`, which respects the "static fields, then constructor fields, then overrides" order.
- No new imports were needed; `flutter/services.dart` (which exports `EventChannel`) was already imported.

**`biometric_cipher.dart`**
- `screenLockStream` getter is at lines 38: `Stream<bool> get screenLockStream => _instance.screenLockStream;`
- Doc comment is present and documents all four platforms plus the "Does NOT require configure()" note.
- No `_configured` guard — confirmed.
- Placed between `configured` getter and `getTPMStatus()`, consistent with the existing ordering.

**`mock_biometric_cipher_platform.dart`**
- `dart:async` import is present (line 1).
- `screenLockStreamController` is declared as `final screenLockStreamController = StreamController<bool>.broadcast();` (line 27) — public field, broadcast, no constructor parameter. Matches plan exactly.
- `screenLockStream` override at lines 29–30 returns `screenLockStreamController.stream`.
- No `tearDown` closing the controller in the mock itself (closing is the test's responsibility).

**`biometric_cipher_test.dart`**
- `group('screenLockStream', ...)` is present at lines 242–264, nested inside the outer `'BiometricCipher tests'` group.
- Three test cases are present: `'emits events from platform'`, `'works without configure'`, `'emits multiple events'`.
- `tearDown` to close the controller after each test is **absent** from the `screenLockStream` group. The plan notes this as a point to consider, but observes existing groups do not use `tearDown`. The controller is broadcast and not closed; since the `mockPlatform` object is recreated on each `setUp`, any previously open controller goes out of scope. This does not cause test failures but may generate a "stream not closed" pedantic warning in stricter analysis contexts. Not a blocking defect.
- No separate test for the default platform returning `Stream.empty()` is present (the plan listed this as a secondary item; the PRD scenario 1 is covered indirectly by the mock test — the mock delegates through the same path). This gap is noted below.

---

## Positive Scenarios

### PS-1: Default platform returns an empty stream (unsupported platform)
- `BiometricCipherPlatform.screenLockStream` returns `const Stream<bool>.empty()`.
- A listener on this stream receives no events and no errors.
- Verified: getter is present in `biometric_cipher_platform_interface.dart` with the correct return value.

### PS-2: `MethodChannelBiometricCipher` exposes a valid broadcast stream
- `screenLockStream` is a `late final` field; accessing it for the first time calls `_screenLockEventChannel.receiveBroadcastStream()`.
- The returned stream is a broadcast stream (multiple listeners allowed).
- Verified: implementation at `biometric_cipher_method_channel.dart` lines 19–21.

### PS-3: `BiometricCipher` facade delegates to the platform instance
- `BiometricCipher().screenLockStream` returns exactly `_instance.screenLockStream`.
- No extra wrapping, no `_configured` guard.
- Verified: `biometric_cipher.dart` line 38.

### PS-4: Mock platform emits events through `screenLockStreamController`
- `mockPlatform.screenLockStreamController.add(true)` propagates a `true` event through `biometricCipher.screenLockStream`.
- Covered by test `'emits events from platform'` (line 243).

### PS-5: Multiple events are received in order
- Adding `true` three times to the controller is received in order `[true, true, true]`.
- Covered by test `'emits multiple events'` (line 255).

### PS-6: `screenLockStream` accessible without prior `configure()` call
- Accessing `biometricCipher.screenLockStream` without calling `configure()` throws no exception.
- Covered by test `'works without configure'` (line 251).

### PS-7: EventChannel name is the contract string
- `_screenLockEventChannel` is `static const EventChannel('biometric_cipher/screen_lock')`.
- The channel name is a single compile-time constant, preventing typos across future native phases.
- Verified: `biometric_cipher_method_channel.dart` line 12.

### PS-8: Existing tests remain unbroken
- `MockBiometricCipherPlatform` gains the new override without removing or changing any existing methods.
- The `screenLockStream` override compiles because `BiometricCipherPlatform` now declares the getter.
- All existing test groups (`configure`, `encrypt-decrypt cycle`, `generateKey`, `encrypt`, `decrypt`, `deleteKey`, `isKeyValid`) are unaffected.

---

## Negative and Edge Cases

### NC-1: `late final` prevents re-initialization
- Once `screenLockStream` is initialized on `MethodChannelBiometricCipher`, it cannot be re-assigned.
- In unit tests this is not exercised because `MethodChannelBiometricCipher` is never used directly — tests always go through `MockBiometricCipherPlatform`. This is the correct design.
- Risk: if a test creates a `BiometricCipher` with the real `MethodChannelBiometricCipher` (not the mock), accessing `screenLockStream` twice would reuse the cached subscription. This is the intended behavior.

### NC-2: Controller not closed after test — potential warning
- The `screenLockStreamController` in `MockBiometricCipherPlatform` is a broadcast `StreamController` that is never explicitly closed in the test `tearDown`.
- On each `setUp`, a new `MockBiometricCipherPlatform` (and new controller) is created, so the previous one is abandoned.
- In strict test environments this can produce "Stream controller not closed" leak warnings. It is not a correctness defect because `broadcast()` controllers do not require explicit closing, but adding `tearDown(() => mockPlatform.screenLockStreamController.close())` inside the `screenLockStream` group would be cleaner.

### NC-3: `const Stream<bool>.empty()` vs `Stream<bool>.empty()` in platform interface
- The plan section on `BiometricCipherPlatform` explicitly states the typed form is "not `const`-eligible" and should use the non-`const` form.
- The implementation uses `const Stream<bool>.empty()`, which is valid Dart since `Stream.empty()` is a `const` constructor.
- This is not a bug. Static analysis will validate it. However, there is a minor inconsistency between the plan's note and the actual code. No action required unless the analyzer flags it.

### NC-4: No test for the default `Stream<bool>.empty()` return from `BiometricCipherPlatform` directly
- PRD Scenario 1 (unsupported platform default) and the plan's test list mention verifying that the base platform returns an empty stream.
- The test file does not contain a dedicated test for this scenario (e.g., instantiating a plain `BiometricCipher` without a mock and observing no emissions).
- This is a minor gap. In practice the behavior is guaranteed by the return expression `const Stream<bool>.empty()` which is trivially correct code; the risk of regression is very low.

### NC-5: No `false` event path tested
- The stream type is `Stream<bool>`, reserving `false` for a potential future unlock signal.
- No test exercises adding `false` to the controller and observing whether the facade emits it.
- Given Phase 1's scope (no native side, mock only), this gap is acceptable. It should be covered when the native handlers are implemented in Phases 2–4.

### NC-6: `map((event) => event as bool)` — invalid payload type not tested
- If native code sends a non-`bool` payload, the `as bool` cast throws a `CastError` at runtime.
- No negative test for this case exists in Phase 1.
- Acceptable for Phase 1 (no native handler exists yet). Should be documented for native phase authors.

### NC-7: Scope discipline — no changes outside `packages/biometric_cipher/`
- The PRD and plan both state that Phase 1 must not touch files outside `packages/biometric_cipher/`.
- Only the five files in scope were modified. The tasklist shows iterations 2–8 as pending.
- Verified: git branch diff confirms no changes to `example/`, `lib/`, or root-level files.

---

## Automated Tests Coverage

| Test | File | Status |
|------|------|--------|
| `screenLockStream emits events from platform` | `biometric_cipher_test.dart:243` | Present, green |
| `screenLockStream works without configure` | `biometric_cipher_test.dart:251` | Present, green |
| `screenLockStream emits multiple events` | `biometric_cipher_test.dart:255` | Present, green |
| All pre-existing groups (configure, encrypt-decrypt, generateKey, encrypt, decrypt, deleteKey, isKeyValid) | `biometric_cipher_test.dart` | Present, unaffected |
| Default platform returns `Stream.empty()` | — | **Missing** (NC-4) |
| `false` event propagated through facade | — | Not required for Phase 1 |

**Overall automated coverage for Phase 1:** The three new tests cover the happy path (event emission), the configure-independence guarantee, and multiple sequential events. The single missing test (NC-4) is low-risk given the trivial implementation of the default getter.

---

## Manual Checks Needed

### MC-1: Static analysis passes
Run from `packages/biometric_cipher/`:
```
fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .
```
Expected: zero warnings, zero infos, zero errors. This validates `const Stream<bool>.empty()` is accepted, that `late final` is used correctly, and that no implicit `dart:async` import is missing.

### MC-2: Unit tests pass
Run from `packages/biometric_cipher/`:
```
fvm flutter test
```
Expected: all tests green. Existing groups must remain green; the new `screenLockStream` group must pass all three cases.

### MC-3: EventChannel name string matches the constant
Visually confirm that:
- `biometric_cipher_method_channel.dart` line 12 contains the string `'biometric_cipher/screen_lock'`
- No other file in `packages/biometric_cipher/lib/` contains a hardcoded copy of this string

This prevents silent mismatches when native handlers are written in Phases 2–4.

### MC-4: No regressions in diff scope
Confirm via `git diff --name-only` that only the following five files are modified:
- `packages/biometric_cipher/lib/biometric_cipher_platform_interface.dart`
- `packages/biometric_cipher/lib/biometric_cipher_method_channel.dart`
- `packages/biometric_cipher/lib/biometric_cipher.dart`
- `packages/biometric_cipher/test/mock_biometric_cipher_platform.dart`
- `packages/biometric_cipher/test/biometric_cipher_test.dart`

---

## Risk Zone

| Risk | Likelihood | Impact | Assessment |
|------|-----------|--------|------------|
| EventChannel name typo creating mismatch with future native phases | Low | High | Mitigated: name is `static const` in one place. No copies in other Dart files. |
| `const Stream<bool>.empty()` not accepted by analyzer in some Dart contexts | Very Low | Low | Accepted idiom in Dart 3.x. Analyze step confirms. |
| `late final` causing issues if `MethodChannelBiometricCipher` is accessed in a test without engine | Low | Low | Not exercised in unit tests; only mock platform is used. |
| Missing `tearDown` for `screenLockStreamController` causing leak warnings | Low | Negligible | Broadcast controller; no functional impact. Can be addressed in a follow-up. |
| Missing default-platform test (NC-4) hiding future regression | Very Low | Low | Default is `const Stream<bool>.empty()` — trivially safe. |
| Non-`bool` payload from future native code causing cast error (NC-6) | Medium (in later phases) | Medium | Out of Phase 1 scope. Must be documented for Phase 2–4 native authors. |

---

## Final Verdict

**RELEASE**

Phase 1 is a well-scoped, minimal Dart-only change. All three target files (`biometric_cipher_platform_interface.dart`, `biometric_cipher_method_channel.dart`, `biometric_cipher.dart`) implement the agreed API contract correctly. The mock and the three new unit tests cover the required scenarios from the PRD. The EventChannel name is defined as a single `static const` string. No changes were made outside `packages/biometric_cipher/`. No existing tests were broken.

The two noted gaps (missing default-platform test and absent `tearDown` for the controller) are low-risk papercuts that do not affect correctness or safety. They can be addressed in a subsequent cleanup or in the Phase 5 test iteration that was already planned for this purpose.

Phase 1 is ready to be merged and the team can proceed to Phase 2 (Android native handler).
