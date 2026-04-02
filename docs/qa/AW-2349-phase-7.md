# QA Plan: AW-2349 Phase 7 — DI Wiring + `screenLocked` Event

Status: REVIEWED
Date: 2026-04-02

---

## Phase Scope

Phase 7 wires `ScreenLockService` (created in Phase 6) through the example app's factory-based DI
graph and declares the `LockerEvent.screenLocked()` Freezed event. It does NOT implement the BLoC
handler (Phase 8 scope).

Specifically, Phase 7 must:

1. Add a `BiometricCipher` field and `ScreenLockService` field to `RepositoryFactoryImpl`, expose
   via a getter on both the abstract interface and the impl, instantiate both in `init()`, and call
   `_screenLockService.dispose()` in `dispose()`.
2. Add `ScreenLockService` as a required constructor parameter and private field to `BlocFactoryImpl`
   (store it, but do NOT pass to `LockerBloc(...)` — that is Phase 8).
3. Wire `repositoryFactory.screenLockService` into `BlocFactoryImpl(...)` construction in `main.dart`.
4. Declare `const factory LockerEvent.screenLocked() = _ScreenLocked;` in `locker_event.dart`.
5. Run `make g` to regenerate Freezed output.
6. Pass `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` with zero issues.

Files in scope (Phase 7 only):
- `example/lib/di/factories/repository_factory.dart`
- `example/lib/di/factories/bloc_factory.dart`
- `example/lib/main.dart`
- `example/lib/features/locker/bloc/locker_event.dart`
- `example/lib/features/locker/bloc/locker_bloc.freezed.dart` (generated)

---

## Implementation Status (observed)

### Task 7.1 — `repository_factory.dart`

File reviewed at `example/lib/di/factories/repository_factory.dart`.

- Import `package:biometric_cipher/biometric_cipher.dart` — present (line 1).
- Import `package:mfa_demo/core/services/screen_lock_service.dart` — present (line 3).
- `ScreenLockService get screenLockService` on abstract `RepositoryFactory` — present (line 13).
- `late final BiometricCipher _biometricCipher` field — present (line 30).
- `late final ScreenLockService _screenLockService` field — present (line 31).
- `ScreenLockService get screenLockService => _screenLockService` on impl — present (line 47).
- `init()` instantiates `_biometricCipher = BiometricCipher()` before `_screenLockService` — present
  (lines 52–53).
- `init()` instantiates `_screenLockService = ScreenLockServiceImpl(biometricCipher: _biometricCipher)`
  — present (line 53).
- `init()` initialization order: `_timerService` (line 51) → `_biometricCipher` (line 52) →
  `_screenLockService` (line 53) → `configureBiometricCipher(...)` (lines 56–64). Correct.
- `dispose()` calls `_screenLockService.dispose()` before `await _lockerRepository?.dispose()` —
  present (line 70). Called after `_timerService?.dispose()` (line 69). Correct.

Task 7.1: PASS.

### Task 7.2 — `bloc_factory.dart`

File reviewed at `example/lib/di/factories/bloc_factory.dart`.

- Import `package:mfa_demo/core/services/screen_lock_service.dart` — present (line 1).
- `required ScreenLockService screenLockService` constructor parameter — present (line 23), placed
  after `timerService` (line 22). Parameter order: `lockerRepository`, `timerService`,
  `screenLockService`. Correct per plan.
- `final ScreenLockService _screenLockService` field — present (line 18), after `_timerService`
  (line 17). Field order: `_lockerRepository`, `_timerService`, `_screenLockService`. Correct per
  plan.
- Initializer list includes `_screenLockService = screenLockService` — present (line 26). Correct.

**DEVIATION — `const` not removed:** The PRD (Constraint section) and plan (Design decisions) both
explicitly state that `const` must be removed from `BlocFactoryImpl` because adding `ScreenLockService`
(an abstract interface) is not `const`-compatible. The constructor declaration reads
`const BlocFactoryImpl({...})` at line 20. In practice, Dart permits `const` constructors that accept
abstract-typed fields as long as the class has only final fields and no constructor body — and
Dart does currently allow this. However, the PRD explicitly calls out removing `const` as a
required change. The `const` keyword is still present. Whether this causes a compile error depends on
Dart's `const` canonicalization rules at the call site (since no call site uses `const`, it is
currently harmless).

**DEVIATION — `_screenLockService` passed to `LockerBloc(...)` (Phase 8 scope):** The `lockerBloc`
getter at lines 29–33 passes `screenLockService: _screenLockService` to `LockerBloc(...)`. The PRD
and plan are unambiguous: "do NOT pass `_screenLockService` to `LockerBloc(...)` in the `lockerBloc`
getter. `LockerBloc` does not accept this parameter yet — that is Phase 8 scope." However, `LockerBloc`
already accepts `screenLockService` (see Task 7.2-related LockerBloc deviation below), so this does
not produce a compile error. It does represent scope leakage into Phase 8.

Task 7.2: PASS WITH DEVIATIONS (2 deviations, detail below).

### Task 7.3 — `main.dart`

File reviewed at `example/lib/main.dart`.

- `BlocFactoryImpl(...)` at lines 39–43 passes `screenLockService: repositoryFactory.screenLockService`
  — present (line 41). Correct.
- Argument order: `lockerRepository` (line 40), `screenLockService` (line 41), `timerService`
  (line 42). The plan specifies no strict call-site parameter order (named parameters in Dart are
  order-independent), so this is acceptable.

Task 7.3: PASS.

### Task 7.4 — `locker_event.dart`

File reviewed at `example/lib/features/locker/bloc/locker_event.dart`.

- `const factory LockerEvent.screenLocked() = _ScreenLocked;` — present (line 123), as the last
  event in the sealed class.
- Doc comment `/// Device screen was locked. Triggers immediate locker lock.` — present (line 122).
- Style matches existing zero-argument events (same `const factory` pattern, same `= _PrivateName`
  part).

Task 7.4: PASS.

### Task 7.5 — Code generation

`locker_bloc.freezed.dart` is present and regenerated. Verification:

- `_ScreenLocked` class is present (confirmed by grep showing `class _ScreenLocked implements
  LockerEvent`).
- `const _ScreenLocked()` constructor is generated.
- `LockerEvent.screenLocked()` string representation is generated.
- `map`, `maybeMap`, `when`, `maybeWhen`, `mapOrNull`, `whenOrNull` all include `screenLocked` case.

Task 7.5: PASS.

### Out-of-scope changes detected in `locker_bloc.dart`

**Phase 8 scope bled into Phase 7.** The `locker_bloc.dart` file — which is explicitly listed as a
Phase 8 file — has been modified during this phase:

1. `ScreenLockService` import added (`package:mfa_demo/core/services/screen_lock_service.dart`,
   line 11).
2. `final ScreenLockService _screenLockService` field added (line 24).
3. `required ScreenLockService screenLockService` constructor parameter added (line 29).
4. `_screenLockService = screenLockService` in initializer list (line 32).
5. `_screenLockService.dispose()` called in `close()` (line 71).

These are all Phase 8 changes. The Phase 8 handler (`on<_ScreenLocked>` registration,
`_onScreenLocked` callback, `startListening()`/`stopListening()` wiring) is NOT yet present —
only the field injection and dispose call are included.

This creates a partial Phase 8 implementation: `LockerBloc` receives and stores `ScreenLockService`
and disposes it, but does not start/stop listening or handle the `screenLocked` event. The app will
compile and run correctly, but screen lock events arriving while the locker is unlocked will be
silently ignored (no handler registered, no `startListening()` called). This is not a Phase 7
regression — existing behavior is unchanged — but it is a scope deviation.

---

## Positive Scenarios

### PS-1: Normal app startup — DI chain executes correctly

`main()` calls `repositoryFactory.init()`, which:
- Creates `_timerService`, `_biometricCipher`, and `_screenLockService` in that order.
- `_screenLockService` receives a valid `_biometricCipher` instance.

`BlocFactoryImpl(...)` receives `repositoryFactory.screenLockService`, which returns the
`_screenLockService` instance created in `init()`. The `_screenLockService` field is stored.

`LockerBloc` receives `screenLockService` from `BlocFactoryImpl.lockerBloc` getter. Field is
stored in `_screenLockService`.

The DI chain is correct and complete. All late-final fields are initialized before any getter is
accessed.

### PS-2: `ScreenLockService` getter on `RepositoryFactory` interface is fulfilled

`RepositoryFactory` declares `ScreenLockService get screenLockService` and
`RepositoryFactoryImpl` implements it. The getter returns `_screenLockService`, which is a
`late final` field set in `init()`. Accessing the getter before calling `init()` throws
`LateInitializationError` — the expected failure mode for misuse.

### PS-3: Disposal order is correct and complete

`repositoryFactory.dispose()` executes:
1. `_timerService?.dispose()` — stops the timer (existing).
2. `_screenLockService.dispose()` — synchronous; cancels stream subscription and nulls callback
   (new).
3. `await _lockerRepository?.dispose()` — async repository teardown (existing).

`LockerBloc.close()` also calls `_screenLockService.dispose()`. With the Phase 7 partial
implementation, `LockerBloc` disposes the service on BLoC close, and then `RepositoryFactory`
disposes it again on app teardown. `ScreenLockServiceImpl.dispose()` is idempotent (calls
`stopListening()` which is a null-safe no-op on a null subscription), so double disposal is safe.

### PS-4: `LockerEvent.screenLocked()` is declared and code-generated

The Freezed factory `const factory LockerEvent.screenLocked() = _ScreenLocked` is present in
`locker_event.dart`. The generated class `_ScreenLocked` in `locker_bloc.freezed.dart` provides
correct `==`, `hashCode`, `toString`, `map`, `when`, and their nullable variants. The event is
immediately usable in Phase 8 handler registration without further code changes to the Freezed files.

### PS-5: Scope of file changes does not exceed specification

The 4 specified source files plus the generated file are modified. However, `locker_bloc.dart` is
also modified (Phase 8 scope leakage). See deviation detail in the Implementation Status section.

### PS-6: `BiometricCipher` instantiation order in `init()`

`_biometricCipher = BiometricCipher()` is assigned before `_screenLockService =
ScreenLockServiceImpl(biometricCipher: _biometricCipher)`. Since `_biometricCipher` is `late final`,
reading it after assignment is safe. The initialization order satisfies the dependency.

### PS-7: No compile errors from `const` on `BlocFactoryImpl`

The `const` keyword remains on `BlocFactoryImpl`. Since all fields are `final` and typed as abstract
interfaces (not `const`-incompatible concrete types), Dart accepts this constructor declaration. No
call site uses `const BlocFactoryImpl(...)`, so there are no canonicalization issues. The app
compiles.

### PS-8: `LockerBloc` accepts `screenLockService` without breaking existing event handling

`LockerBloc` now requires `screenLockService` but none of the existing 21 event handlers or the
timer-based auto-lock logic are changed. All existing event registrations remain. The new field
is stored and the service is disposed on `close()`, but no new handler is registered. Existing
behavior is fully preserved.

---

## Negative and Edge Cases

### NC-1: `screenLockService` getter accessed before `init()` — `LateInitializationError`

If code attempts to access `repositoryFactory.screenLockService` before calling
`repositoryFactory.init()`, a `LateInitializationError` is thrown on the `_screenLockService`
field. This is a different error type from the `StateError` thrown by `timerService` getter.

Per the PRD and plan, this inconsistency is a known and accepted design difference between the
`_timerService` (nullable + `StateError` guard) and `_screenLockService`/`_biometricCipher`
(`late final`). `init()` is always called in `main.dart` before `BlocFactoryImpl` construction,
so this is not an exercisable risk in production.

### NC-2: `_screenLockService.dispose()` called twice — double-dispose safety

`LockerBloc.close()` calls `_screenLockService.dispose()`. Then `repositoryFactory.dispose()` also
calls `_screenLockService.dispose()`. Both share the same `ScreenLockServiceImpl` instance.

`ScreenLockServiceImpl.dispose()` calls `stopListening()` (which does `_subscription?.cancel()` then
`_subscription = null`) then sets `_onScreenLocked = null`. Both operations are null-safe and
idempotent. Double-dispose is safe. No exception is thrown.

### NC-3: `on<_ScreenLocked>` not registered — `screenLocked` event goes to BLoC default handler

`LockerEvent.screenLocked()` can now be dispatched to `LockerBloc`. However, no `on<_ScreenLocked>`
handler is registered (Phase 8 scope). In `flutter_bloc`, dispatching an event with no registered
handler does not throw — it is silently dropped. Screen lock events during Phase 7 testing (before
Phase 8 is applied) will be silently ignored. This is expected and not a defect.

### NC-4: `startListening()` never called — screen lock stream subscription never opened

`ScreenLockService.startListening()` is never called anywhere in Phase 7 implementation (the full
Phase 8 wiring is absent). The `ScreenLockServiceImpl` instance is alive (held by both
`RepositoryFactoryImpl` and `LockerBloc`) but passive — it never subscribes to
`BiometricCipher.screenLockStream`. No native events are received. This is expected by the Phase 7
spec, but it means the feature is entirely inert.

### NC-5: Field ordering deviation in `RepositoryFactoryImpl` — `late final` vs nullable inconsistency

`_timerService` remains `TimerService?` (nullable with `StateError` guard), while `_biometricCipher`
and `_screenLockService` are `late final`. This is inconsistent within the same class. The PRD
acknowledges this as intentional. Static analysis will not flag it. Future readers of the code may
find the mixed pattern confusing.

### NC-6: `BlocFactoryImpl` `const` constructor with abstract-typed field — potential future issue

Keeping `const` on `BlocFactoryImpl` when it holds `final ScreenLockService _screenLockService` is
currently accepted by the Dart compiler because no `const BlocFactoryImpl(...)` call exists. If a
future caller adds `const BlocFactoryImpl(...)`, Dart will reject it at the call site (since
`ScreenLockService` implementations are not `const`-constructable). The PRD explicitly stated to
remove `const` to prevent this. The deviation is low-risk today but should be corrected.

### NC-7: Scope leakage — `locker_bloc.dart` modified before Phase 8 gate

`locker_bloc.dart` now accepts `screenLockService` but does not implement the handler, callback, or
`startListening()`/`stopListening()` wiring. This creates an incomplete Phase 8 state in the tree.
Phase 8 will need to add the missing handler parts without re-adding the constructor parameter
and field (which are already present). The Phase 8 developer must be aware that the constructor
injection is already done to avoid duplicate field declarations.

### NC-8: `LockerBloc` dispose calls `_screenLockService.dispose()` without preceding `stopListening()`

`ScreenLockServiceImpl.dispose()` calls `stopListening()` internally, so this is safe. However,
the documented dispose contract from the plan specifies that Phase 8 should call both
`_screenLockService.stopListening()` and `_screenLockService.dispose()` at shutdown (or just
`dispose()` since it delegates). Only `dispose()` is called in `close()`. No issue — but
`startListening()` is never called either, so the subscription is always null at this point.

### NC-9: `ScreenLockService` onScreenLockedCallback never set in `LockerBloc`

`_screenLockService.onScreenLockedCallback` is never set in `LockerBloc` (Phase 8 scope). Even
after Phase 8 calls `startListening()`, no callback will fire. The callback must be set before
`startListening()` for events to invoke the LockerBloc. Phase 8 must set the callback in the
constructor, as specified in `docs/idea-2349.md` section G.

---

## Automated Tests Coverage

| Test | File | Status |
|------|------|--------|
| `screenLockStream` emits events from platform | `packages/biometric_cipher/test/biometric_cipher_test.dart` | Present — green (Phase 5 deliverable) |
| `screenLockStream` works without `configure()` | `packages/biometric_cipher/test/biometric_cipher_test.dart` | Present — green (Phase 5 deliverable) |
| `screenLockStream` emits multiple events | `packages/biometric_cipher/test/biometric_cipher_test.dart` | Present — green (Phase 5 deliverable) |
| `screenLockStream` default platform returns empty stream | `packages/biometric_cipher/test/biometric_cipher_test.dart` | Present — green (Phase 5 deliverable) |
| `ScreenLockServiceImpl` invokes callback on stream event | `example/test/core/services/screen_lock_service_test.dart` | Not present (deferred, per Phase 6 QA NC-6) |
| DI wiring — `repositoryFactory.screenLockService` flows to `BlocFactoryImpl` | Integration test | Not present |
| DI wiring — `RepositoryFactory.dispose()` calls `_screenLockService.dispose()` | Integration test | Not present |
| `LockerEvent.screenLocked()` is dispatchable and Freezed-generated correctly | Unit test | Not present |
| `fvm flutter analyze` passes with zero warnings | Static analysis run | Not executed during review session |
| `make g` completes without errors | Code generation run | Inferred complete (`.freezed.dart` is present and includes `_ScreenLocked`) |

No new automated tests are introduced in Phase 7. The PRD explicitly states "No new tests in this
phase." The generated file's presence confirms `make g` succeeded.

---

## Manual Checks Needed

### MC-1: Static analysis must pass with zero warnings and infos

```
cd example && fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .
```

This is the primary acceptance criterion from the PRD. It must verify:
- Import resolution for `biometric_cipher` and `screen_lock_service.dart` in all modified files.
- `RepositoryFactory` interface implementation by `RepositoryFactoryImpl` is complete.
- `BlocFactory` interface implementation by `BlocFactoryImpl` is complete.
- `LockerBloc` constructor signature matches all call sites (`BlocFactoryImpl.lockerBloc` getter).
- No unused imports (all 4 modified source files must use their new imports).
- No overriding member issues on `ScreenLockService get screenLockService`.
- The `const` keyword on `BlocFactoryImpl` does not trigger any lint warning.

Expected: exits code 0, zero diagnostics.

### MC-2: `make g` completes without errors

```
cd example && make g
```

Verify that `locker_bloc.freezed.dart` is regenerated without errors and includes the
`_ScreenLocked` class. Since the generated file is present in the tree with the correct content,
this is expected to pass.

### MC-3: Scope verification — confirm only 5 files changed vs. plan

```
git diff --name-only HEAD~1
```

Expected changed files: `repository_factory.dart`, `bloc_factory.dart`, `main.dart`,
`locker_event.dart`, `locker_bloc.freezed.dart`. Actual: also includes `locker_bloc.dart`
(Phase 8 scope leakage confirmed from code inspection). The scope constraint from the PRD ("no
changes outside the 4 specified files + generated file") is violated.

### MC-4: `const BlocFactoryImpl` — verify no call-site `const` usage exists

```
grep -r "const BlocFactoryImpl" example/lib example/test
```

Expected: no matches (per Phase 7 research, only `main.dart` constructs it, without `const`).
This confirms that the `const` deviation on the constructor declaration is currently harmless.

### MC-5: `LockerBloc` constructor — verify all callers are updated

Since `LockerBloc` now requires `screenLockService` as a named parameter, all call sites must
be updated. The only call site is `BlocFactoryImpl.lockerBloc` getter, which already passes
`screenLockService: _screenLockService`. Verify no other call sites exist:

```
grep -r "LockerBloc(" example/lib example/test
```

Expected: `bloc_factory.dart` (1 call), any test files that mock `LockerBloc` construction
(need to add `screenLockService` mock argument).

### MC-6: `LockerBloc` test files — ensure they still compile

If any test at `example/test/features/locker/bloc/` constructs `LockerBloc(...)` directly, the
new `required ScreenLockService screenLockService` parameter must be supplied. These test files
are not in Phase 7 scope but must not be broken.

### MC-7: Dart format compliance

```
cd example && fvm dart format --line-length 120 --set-exit-if-changed .
```

Expected: exits code 0. All modified source files should follow the 120-character line length
and trailing comma rules.

---

## Risk Zone

| Risk | Likelihood | Impact | Assessment |
|------|-----------|--------|------------|
| Static analysis fails (MC-1 not run during review) | Low — all imports are valid path deps; implementation is structurally sound | High — blocks acceptance | Must be verified. Expected to pass given correct import resolution and interface satisfaction. |
| `const` on `BlocFactoryImpl` violates PRD constraint | Certain (deviation observed) | Low today — no `const` call site exists | Should be corrected before Phase 8 to avoid surprises if a future caller uses `const`. |
| `locker_bloc.dart` modified (Phase 8 scope leakage) | Certain (deviation observed) | Low — partial implementation is safe; feature is still inert | Phase 8 developer must be briefed that constructor injection is already done to avoid duplicate declarations. |
| Double `_screenLockService.dispose()` (from `LockerBloc.close()` and `RepositoryFactoryImpl.dispose()`) | Certain (both call paths exist) | None — `dispose()` is idempotent | Acceptable. No defensive guard needed. |
| `on<_ScreenLocked>` not registered — `screenLocked` events are silently dropped | Certain (Phase 8 not started) | None for Phase 7 | Expected. `flutter_bloc` silently drops unhandled events. Phase 8 remedies this. |
| `LockerBloc` test files broken by new required `screenLockService` constructor param | Medium — tests may construct `LockerBloc` directly | Medium — test compile failure would surface at analysis or test run | Must be verified via MC-5 and MC-6. |
| `LateInitializationError` vs `StateError` inconsistency in `RepositoryFactoryImpl` | Very Low — `init()` is always called before getter access | Low | Accepted per PRD design decision. |
| `RepositoryFactory` getter inconsistency — `screenLockService` has no `StateError` guard while `timerService` does | Certain (structural difference) | Low | Known and accepted per PRD. `late final` provides equivalent crash on misuse. |

---

## Final Verdict

**RELEASE WITH RESERVATIONS**

Phase 7 delivers the required DI wiring and `LockerEvent.screenLocked()` declaration. The four core
tasks (repository factory wiring, main.dart update, event declaration, code generation) are correctly
implemented. The DI chain is correct: `ScreenLockService` is instantiated once in
`RepositoryFactoryImpl.init()`, exposed via a getter, passed through `BlocFactoryImpl`,
and available in `LockerBloc`. `dispose()` is wired correctly. The Freezed event is generated and
ready for Phase 8 handler registration.

**Reservations:**

1. **MC-1 (static analysis) not run during review.** This is the designated acceptance criterion
   from the PRD. Until `cd example && fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .`
   exits with code 0, the phase cannot be considered fully accepted.

2. **`const` not removed from `BlocFactoryImpl` constructor.** The PRD and plan explicitly state to
   remove `const`. The deviation is harmless today (no `const` call site exists), but it violates
   the stated constraint and could confuse future developers. This should be corrected.

3. **`locker_bloc.dart` modified outside Phase 7 scope.** The constructor injection of
   `ScreenLockService` into `LockerBloc` is a Phase 8 deliverable. It has been partially done here
   (field + constructor param + dispose, but no handler, no callback set, no start/stop wiring).
   Phase 8 must be carefully scoped to add only the remaining parts (callback setup, `on<_ScreenLocked>`
   registration, `startListening()`/`stopListening()` wiring) without duplicating the already-present
   field declarations. The Phase 8 developer and reviewer must be explicitly briefed on this.

4. **`LockerBloc` test files may be broken** by the new required `screenLockService` constructor
   parameter. MC-5 and MC-6 verification is mandatory before merging.

Phase 7 is ready to proceed to Phase 8 once MC-1 (analyzer), MC-5 (LockerBloc call sites), and
MC-6 (LockerBloc test compilation) are confirmed passing, and the `const` deviation is addressed.
