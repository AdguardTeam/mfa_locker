# QA Plan: AW-2349 Phase 6 — Example App `ScreenLockService`

Status: REVIEWED
Date: 2026-04-02

---

## Phase Scope

Phase 6 adds exactly one new file to the example app layer:

```
example/lib/core/services/screen_lock_service.dart
```

This file contains two types in a single file:

- `ScreenLockService` — abstract class defining the callback setter and lifecycle interface
- `ScreenLockServiceImpl` — implementation that subscribes to `BiometricCipher.screenLockStream`

No other files are created or modified in Phase 6. DI wiring (Phase 7), BLoC integration (Phase 8), and unit tests are explicitly out of scope. The service is a standalone class with no active consumers at this phase boundary.

---

## Implementation Status (observed)

### Task 6.1 — `screen_lock_service.dart` (new file)

File path: `example/lib/core/services/screen_lock_service.dart`

Findings:

**File location and naming:** File is present at `example/lib/core/services/screen_lock_service.dart`, alongside the existing `timer_service.dart`. Correct directory and filename.

**Imports:** Two imports are present at lines 1 and 3:
- `import 'dart:async';` — required for `StreamSubscription<bool>`.
- `import 'package:biometric_cipher/biometric_cipher.dart';` — required for `BiometricCipher`.

Both imports match the spec exactly.

**`ScreenLockService` abstract class (lines 6–18):** The class is named `ScreenLockService` (no prefix per convention) and carries a doc comment `"Service responsible for listening to device screen lock events."`. All four required members are present with matching signatures:
- `set onScreenLockedCallback(void Function() onLock)` (line 8)
- `void startListening()` (line 11)
- `void stopListening()` (line 14)
- `void dispose()` (line 17)

**`ScreenLockServiceImpl` class member order (lines 20–51):**

The plan specifies: constructor field → constructor → other private fields → public methods. The actual implementation order is:

1. `final BiometricCipher _biometricCipher;` (line 21) — constructor field
2. `ScreenLockServiceImpl({required BiometricCipher biometricCipher}) : _biometricCipher = biometricCipher;` (lines 23–24) — constructor
3. `StreamSubscription<bool>? _subscription;` (line 26) — other private field
4. `void Function()? _onScreenLocked;` (line 27) — other private field
5. Public methods: `set onScreenLockedCallback` (lines 29–30), `startListening()` (lines 33–38), `stopListening()` (lines 41–44), `dispose()` (lines 47–50)

**Convention deviation — field ordering:** The plan and `docs/conventions.md` define class member order as: static constants → constructor fields → constructor → other private fields → public methods. The actual code places the constructor field `_biometricCipher` at line 21, which is before the constructor (line 23), as required. This is correct. The `_subscription` and `_onScreenLocked` fields are placed after the constructor at lines 26–27, classified as "other private fields". The ordering matches the convention.

**`startListening()` (lines 33–38):**
```dart
_subscription?.cancel();
_subscription = _biometricCipher.screenLockStream.listen((_) {
  _onScreenLocked?.call();
});
```
Cancels any existing subscription before creating a new one — safe re-subscribe contract satisfied. Stream event payload (`bool`) is discarded via `_` parameter. Callback is null-safely invoked.

**`stopListening()` (lines 41–44):**
```dart
_subscription?.cancel();
_subscription = null;
```
Null-safe cancel, then assigns null. Idempotent — calling on a null subscription is a no-op.

**`dispose()` (lines 47–50):**
```dart
stopListening();
_onScreenLocked = null;
```
Delegates to `stopListening()` (subscription cancelled + nulled), then nulls the callback reference. Memory leak prevention confirmed.

**No `@override` on callback setter setter in abstract class:** The abstract class does not carry `@override` (it defines the interface). The impl carries `@override` on all four members at lines 29, 32, 40, 46. Correct.

**File contains two types:** The `ScreenLockService` abstract class and `ScreenLockServiceImpl` are both in a single file, which is a deliberate exception to the "one type per file" rule sanctioned by the plan ("Abstract class + Impl in a single file"). This mirrors the pattern of `timer_service.dart`, which also contains both `TimerService` and `TimerServiceImpl` in one file. Consistent and acceptable.

**`TimerService` pattern mirroring:** The structural mapping is faithful:

| `TimerService` member | `ScreenLockService` member |
|----------------------|---------------------------|
| `set onLockCallback` | `set onScreenLockedCallback` |
| `startTimer()` | `startListening()` |
| `stopTimer()` | `stopListening()` |
| `dispose()` | `dispose()` |
| `_lockTimer` (`Timer?`) | `_subscription` (`StreamSubscription<bool>?`) |
| `_onLock` (`void Function()?`) | `_onScreenLocked` (`void Function()?`) |

**Static analysis:** The acceptance criterion (`cd example && fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .`) has not been run during this review session (no Dart MCP tool invocation). This must be verified as part of the acceptance process.

---

## Positive Scenarios

### PS-1: File present at exact specified path

`example/lib/core/services/screen_lock_service.dart` exists. It is placed alongside `timer_service.dart` in the correct directory. Filename matches the primary type name in snake_case per convention.

### PS-2: Abstract interface defines all four required members

`ScreenLockService` exposes exactly the four members specified in PRD and plan: `onScreenLockedCallback` setter, `startListening()`, `stopListening()`, `dispose()`. No extra public members are added that could widen the interface contract before Phase 7 consumers are defined.

### PS-3: Constructor takes `required BiometricCipher biometricCipher`

`ScreenLockServiceImpl` requires a `BiometricCipher` instance via the named constructor parameter. No default is provided. Phase 7 (DI layer) is responsible for passing the existing `_biometricCipher` instance from `RepositoryFactoryImpl`. This prevents accidental construction without a concrete cipher instance.

### PS-4: Normal subscription lifecycle (Scenario 1 from PRD)

`startListening()` calls `_biometricCipher.screenLockStream.listen(...)`, storing the subscription. A stream emission invokes `_onScreenLocked?.call()`. `stopListening()` cancels and nulls the subscription. Any subsequent stream emission after `stopListening()` does not invoke the callback.

### PS-5: Double `startListening()` call is safe (Scenario 2 from PRD)

`startListening()` always calls `_subscription?.cancel()` before `_biometricCipher.screenLockStream.listen(...)`. A second `startListening()` call cancels the first subscription before creating a new one. Only one active subscription exists at any time — no double-fire on stream events.

### PS-6: `stopListening()` before `startListening()` is a safe no-op (Scenario 3 from PRD)

`_subscription` is declared as `StreamSubscription<bool>?` and initialized to `null` (no default assignment in the field declaration). `_subscription?.cancel()` on a null reference is a Dart null-safe no-op. No exception is thrown.

### PS-7: `dispose()` fully cleans up (Scenario 4 from PRD)

`dispose()` calls `stopListening()` (cancels subscription, sets `_subscription = null`) then sets `_onScreenLocked = null`. After `dispose()`: the subscription is gone (no further stream event delivery), the callback reference is cleared (no stale closure preventing GC), the instance is effectively inert. This satisfies the memory safety NFR from the plan.

### PS-8: Stream event with no callback set is a safe no-op (Scenario 5 from PRD)

`_onScreenLocked` is never set in the constructor — it is only assignable via the `onScreenLockedCallback` setter. `_onScreenLocked?.call()` inside the `listen` callback is null-safe. If the caller starts listening without setting a callback, stream events are silently ignored with no exception.

### PS-9: `BiometricCipher.screenLockStream` does not require `configure()` first

The `BiometricCipher.screenLockStream` getter (line 38 of `biometric_cipher.dart`) has no `_configured` guard — it delegates directly to `_instance.screenLockStream`. `ScreenLockServiceImpl.startListening()` can therefore be called at any time, independently of whether the biometric cipher has been configured. This is the intended design (lock detection is independent of biometric operations).

### PS-10: `StreamSubscription<bool>` type matches `BiometricCipher.screenLockStream`

`BiometricCipher.screenLockStream` returns `Stream<bool>`. `listen()` on a `Stream<bool>` returns `StreamSubscription<bool>`. The declared field type `StreamSubscription<bool>?` is an exact match. No implicit casts or type mismatches exist.

### PS-11: No code generation required

The file is pure Dart with no `@freezed`, no `part` directives, no `build_runner` annotations. The service is immediately compilable without running `make g` or `make in`.

### PS-12: `TimerService.dispose()` pattern consistency

`TimerServiceImpl.dispose()` calls `_cancelTimer()` (which cancels and nulls `_lockTimer`). `ScreenLockServiceImpl.dispose()` calls `stopListening()` (which cancels and nulls `_subscription`). Then both null their respective callback fields. The disposal pattern is identical in structure, fulfilling the "mirrors `TimerService`" requirement.

---

## Negative and Edge Cases

### NC-1: `StreamSubscription.cancel()` is asynchronous — stale event delivery

`_subscription?.cancel()` returns a `Future<void>` that is not awaited. There is a theoretical window where a stream event arrives after `cancel()` is called but before the subscription is fully torn down. In practice, Dart's `StreamSubscription.cancel()` guarantees that no further events will be delivered after the returned future completes, and in the case of a single-subscriber stream the event pipeline drains synchronously. The callback is additionally guarded by `_onScreenLocked?.call()` — if `dispose()` has been called and nulled the callback, even a racing event invocation is a no-op. Risk: very low. The PRD and plan explicitly accept this behavior.

### NC-2: `startListening()` called after `dispose()` — zombie subscription

After `dispose()`, `_onScreenLocked` is null and `_subscription` is null. If a caller (erroneously) calls `startListening()` after `dispose()`, a new subscription is created on `_biometricCipher.screenLockStream`. Stream events will be received but `_onScreenLocked?.call()` is a no-op because the callback is null. This means the subscription leaks (no one will ever cancel it again unless `stopListening()` or `dispose()` is called again). Phase 6 has no consumers, so this is not an immediately exercisable risk. Phase 8 will be responsible for ensuring `startListening()` is never called on a disposed service. No defensive guard exists in the current implementation.

### NC-3: `onScreenLockedCallback` set after `startListening()` is called

The callback setter and `startListening()` are independent operations. If a caller calls `startListening()` first, then sets the callback, the subscription is already active. Any stream events that arrive in the window between `startListening()` and the callback assignment are delivered to the `listen` closure, which calls `_onScreenLocked?.call()` — a null-safe no-op since the callback is not yet set. Once the callback is set, subsequent events are delivered normally. This is correct behavior, not a defect, and is consistent with the `TimerService` pattern.

### NC-4: `onScreenLockedCallback` set multiple times — last-write-wins

The setter `_onScreenLocked = onLock` overwrites any previously set callback. There is no notification to the previous callback holder. Phase 8 sets the callback exactly once (the LockerBloc's `_onScreenLockDetected` method); setting it multiple times is not a planned scenario. If it were, only the last-set callback would be invoked. No defensive guard is needed for Phase 6's scope.

### NC-5: `startListening()` called multiple times with callback changes between calls

```
service.onScreenLockedCallback = callbackA;
service.startListening();
service.onScreenLockedCallback = callbackB;
service.startListening();  // cancels first, creates new subscription
// stream event → callbackB is invoked, not callbackA
```

The double-`startListening()` contract (NC-1 scenario from the PRD) is satisfied: the first subscription is cancelled. The latest callback assignment (`callbackB`) is the active one. Correct behavior.

### NC-6: No unit tests exist for `ScreenLockServiceImpl` in this phase

The PRD explicitly states: "No tests in this phase." No test file exists at `example/test/core/services/screen_lock_service_test.dart`. The idea document (section H) specifies three test cases for `ScreenLockServiceImpl` (invoke callback, stopListening prevents callback, dispose cleans up), but these are deferred. The service's correctness is validated by code review in this phase. Unit tests will be added when the service is injectable via a mock (Phase 7+) or as a standalone unit if the scope is widened. This is an accepted gap per plan.

### NC-7: `BiometricCipher` instance shared with other operations — no thread isolation concern

`ScreenLockServiceImpl` holds a reference to the same `BiometricCipher` instance used for encrypt/decrypt/configure. It only calls `_biometricCipher.screenLockStream` (a getter, no state mutation). Multiple concurrent accesses to the `screenLockStream` getter are safe because the `late final` on `MethodChannelBiometricCipher.screenLockStream` ensures a single `Stream<bool>` instance is created. Dart isolates are single-threaded; no race conditions are possible for Dart state.

### NC-8: Two `ScreenLockService` types in one file — potential `prefer-match-file-name` lint

The `conventions.md` "one type per file" rule states: "File name must match the primary type it contains." Two types (`ScreenLockService` and `ScreenLockServiceImpl`) are in `screen_lock_service.dart`. The project's linter configuration must either exempt this pattern or treat `ScreenLockService` as the primary type. This is the same arrangement used by `timer_service.dart` (contains `TimerService` and `TimerServiceImpl`), so the linter configuration has already accepted this pattern. No new risk is introduced.

### NC-9: Static analysis not run during review

The primary acceptance criterion (`cd example && fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .`) has not been executed during this review. If there are import resolution issues (e.g., `biometric_cipher` not in `example/pubspec.yaml`), naming violations, or unused import warnings, they would only surface at analysis time. Based on the existing `timer_service.dart` pattern and the fact that `biometric_cipher` is already a path dependency of the example app (used by the existing biometric features), analysis is expected to pass.

---

## Automated Tests Coverage

| Test | File | Status |
|------|------|--------|
| `screenLockStream` emits events from platform | `packages/biometric_cipher/test/biometric_cipher_test.dart` | Present — green (Phase 5 deliverable) |
| `screenLockStream` works without `configure()` | `packages/biometric_cipher/test/biometric_cipher_test.dart` | Present — green (Phase 5 deliverable) |
| `screenLockStream` emits multiple events | `packages/biometric_cipher/test/biometric_cipher_test.dart` | Present — green (Phase 5 deliverable) |
| `screenLockStream` default platform returns empty stream | `packages/biometric_cipher/test/biometric_cipher_test.dart` | Present — green (Phase 5 deliverable) |
| `ScreenLockServiceImpl` invokes callback on stream event | `example/test/core/services/screen_lock_service_test.dart` | **Not present** (deferred to Phase 7+) |
| `ScreenLockServiceImpl` stopListening prevents callback | `example/test/core/services/screen_lock_service_test.dart` | **Not present** (deferred to Phase 7+) |
| `ScreenLockServiceImpl` dispose cleans up | `example/test/core/services/screen_lock_service_test.dart` | **Not present** (deferred to Phase 7+) |
| `ScreenLockServiceImpl` double startListening no double-fire | `example/test/core/services/screen_lock_service_test.dart` | **Not present** (deferred to Phase 7+) |
| Flutter analyze (example/) passes with zero warnings | `cd example && fvm flutter analyze ...` | **Not executed** (must be verified manually) |

The plugin-layer `screenLockStream` tests (Phase 5 deliverable) are in place and green. They validate the `BiometricCipher` → mock platform layer, which `ScreenLockServiceImpl` depends on at runtime. The service-level tests are an accepted absence for this phase per the PRD constraints.

---

## Manual Checks Needed

### MC-1: Static analysis passes with zero warnings and infos

Run from the repository root or directly in `example/`:
```
cd example && fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .
```
Expected: exits with code 0, no warnings, no infos. This validates:
- Import resolution for `dart:async` and `package:biometric_cipher/biometric_cipher.dart`.
- `ScreenLockServiceImpl implements ScreenLockService` is satisfied (all four abstract members are overridden).
- `StreamSubscription<bool>` type inference is correct.
- No unused imports, no type inference errors.
- `prefer-match-file-name` does not fire (the `timer_service.dart` precedent confirms the linter accepts this pattern).

### MC-2: File scope verification — no unintended modifications

Run:
```
git diff --name-only
```
Expected: only `example/lib/core/services/screen_lock_service.dart` is new. No other files in `example/lib/`, `lib/`, `packages/`, `docs/` should be modified by Phase 6 work. Confirm no accidental changes to `timer_service.dart`, `repository_factory.dart`, `bloc_factory.dart`, or any BLoC files.

### MC-3: Pattern consistency with `timer_service.dart`

Visually compare `screen_lock_service.dart` against `timer_service.dart`:
- Both have an abstract class and a concrete `Impl` in one file.
- Both have a nullable `void Function()?` callback field assigned via a setter.
- Both have start/stop/dispose lifecycle methods.
- Both cancel/null their resource in `stopListening()`/`stopTimer()` and additionally null the callback in `dispose()`.

Expected: the structural pattern is identical except for field types (`StreamSubscription<bool>?` vs `Timer?`) and method names (`startListening` vs `startTimer`, etc.).

### MC-4: `example/pubspec.yaml` already includes `biometric_cipher`

Confirm that `biometric_cipher` appears as a path dependency in `example/pubspec.yaml`. Since existing biometric functionality in the example app already imports from this package, it is expected to be present. If absent, the `import 'package:biometric_cipher/biometric_cipher.dart'` line would fail analysis.

### MC-5: Dart format compliance

Run from the `example/` directory:
```
fvm dart format --line-length 120 --set-exit-if-changed .
```
Expected: exits with code 0 (no formatting changes needed). The file uses trailing commas on the multi-line constructor initializer list (line 23–24), consistent with the `trailing_commas` convention. The file content matches the spec's reference implementation exactly.

---

## Risk Zone

| Risk | Likelihood | Impact | Assessment |
|------|-----------|--------|------------|
| Static analysis fails due to import resolution or override mismatch | Very Low | Medium — blocks acceptance criterion | Both imports are standard path dependencies used elsewhere in the example app; all four abstract members are implemented. Expected to pass. Verify with MC-1. |
| No unit tests for `ScreenLockServiceImpl` — correctness relies on code review only | Certain (by design) | Low — service is not wired into any consumer in this phase | Accepted gap per PRD. All five PRD scenarios are verified by code inspection. Tests deferred to Phase 7+. |
| `startListening()` called after `dispose()` creates a leaked subscription | Low — no consumer exists in Phase 6 | Low — Phase 8 lifecycle wiring must guard against this | No defensive guard in the implementation. Phase 8 is responsible for correct lifecycle management. Noted for Phase 8 QA. |
| Two types in one file triggers `prefer-match-file-name` lint | Very Low — same pattern as `timer_service.dart` is already accepted | Low | If lint fires, it would fail MC-1. The `timer_service.dart` precedent makes this very unlikely. |
| Callback setter has a different parameter name (`onLock`) from the internal field (`_onScreenLocked`) | None | None | The setter parameter `onLock` is a local name; `_onScreenLocked = onLock` assigns it correctly. This is a naming style choice, not a defect. |
| Phase 7/8 consumers not yet wired — service is untestable end-to-end | Certain (by design) | None for Phase 6 | The phase is scoped to a single file. End-to-end verification is deferred to Phase 7 (DI) and Phase 8 (BLoC integration). |

---

## Final Verdict

**RELEASE WITH RESERVATIONS**

Phase 6 delivers a correct and minimal `ScreenLockService` / `ScreenLockServiceImpl` pair at the specified path. The implementation matches the PRD, plan, and reference code exactly. All five PRD functional scenarios are satisfied by the code:

1. Normal subscription lifecycle — `startListening()` subscribes, stream event invokes callback, `stopListening()` cancels subscription.
2. Double `startListening()` — first subscription is cancelled before second is created; no double-fire.
3. `stopListening()` before `startListening()` — null-safe no-op, no exception.
4. `dispose()` — calls `stopListening()`, nulls callback; instance is inert afterwards.
5. No callback set, stream emits — `_onScreenLocked?.call()` is a safe null-guarded no-op.

The `TimerService` pattern is faithfully mirrored. Class member ordering matches `docs/conventions.md`. Imports are correct. No code generation is required. No unintended files are modified.

The reservation is **MC-1 (static analysis)**. This is the designated acceptance criterion from the PRD and plan. It has not been executed during this review session. Until `cd example && fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` exits with code 0, the phase cannot be considered fully accepted.

Secondary reservation: **no unit tests for `ScreenLockServiceImpl`** (NC-6). This is an accepted absence explicitly stated in the PRD, not a defect. However, it means that behavioral correctness (especially the subscription lifecycle and the safe re-subscribe guarantee) rests solely on code review for this phase. Tests are expected in Phase 7 or as a standalone addition before the full feature merge.

Phase 6 is ready to proceed to Phase 7 (DI wiring) once MC-1 (analyzer) and MC-2 (scope verification) are confirmed.
