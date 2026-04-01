# Research: AW-2160 Phase 15 — Example App Proactive Biometric Key Invalidation Detection Integration

## Resolved Questions

No open questions were listed in the PRD. The user confirmed: no additional questions — proceed with research.

---

## Phase Scope

Four targeted changes across four existing files in `example/lib/features/locker/`. No new files. No library or plugin changes.

1. **Task 15.1** — `locker_repository.dart`: pass `biometricKeyTag: AppConstants.biometricKeyTag` to `_locker.determineBiometricState(...)`.
2. **Task 15.2** — `locker_bloc.dart`: when `_determineBiometricStateAndEmit` stores `BiometricState.keyInvalidated`, also set `isBiometricKeyInvalidated: true`.
3. **Task 15.3** — `locked_screen.dart`: add `!state.biometricState.isKeyInvalidated` to the `showBiometricButton` condition.
4. **Task 15.4** — `biometric_unlock_button.dart`: add `state.biometricState.isKeyInvalidated` to the early-return guard.

---

## Current State of the Four Target Files

### Task 15.1 — `locker_repository.dart` (lines 323–327)

**ALREADY DONE.** The implementation already passes the tag:

```dart
@override
Future<BiometricState> determineBiometricState() async {
  await _ensureLockerInstance();
  return _locker.determineBiometricState(biometricKeyTag: AppConstants.biometricKeyTag);
}
```

The abstract interface at line 86 declares `Future<BiometricState> determineBiometricState()` with no parameters — the tag is threaded internally in the implementation. `AppConstants.biometricKeyTag = 'mfa_demo_bio_key'` is confirmed present in `example/lib/core/constants/app_constants.dart`.

### Task 15.2 — `locker_bloc.dart` — `_determineBiometricStateAndEmit` (lines 950–979)

**PARTIALLY DONE — needs review.** The helper emits `biometricState` from `determineBiometricState()`:

```dart
emit(
  state.copyWith(
    biometricState: biometricState,
    loadState: resetLoadState ? LoadState.none : state.loadState,
  ),
);
```

This means `state.biometricState` will be `BiometricState.keyInvalidated` after init if the key is invalidated. However, the `isBiometricKeyInvalidated` flag does NOT exist on `LockerState`. The current `locker_state.dart` (as read) does **not** declare `isBiometricKeyInvalidated` as a state field — the `@freezed` factory only has: `status`, `entries`, `loadState`, `tempPassword`, `biometricState`, `biometricOperationState`, `enableBiometricAfterInit`.

The PRD for Phase 15 says "set `isBiometricKeyInvalidated: true` in state", but the `LockerState` Freezed model has no such field in the current code. The runtime `keyInvalidated` case in `_handleBiometricFailure` (line 1082–1091) only sets `biometricState: BiometricState.keyInvalidated` — it does not set an `isBiometricKeyInvalidated` flag either.

The `_autoDisableBiometricIfInvalidated` helper (lines 986–1010) checks `state.biometricState.isKeyInvalidated` directly (not a separate flag). The `canUseBiometric` getter checks `biometricState.isEnabled`.

**Conclusion for Task 15.2:** The `biometricState` field already carries `keyInvalidated` via `_determineBiometricStateAndEmit`. The `isBiometricKeyInvalidated` flag referenced in the PRD is either: (a) already handled by the `biometricState` field alone (no separate flag needed), or (b) a separate field that was supposed to be added in Phase 7 but is absent from the current `LockerState`. The UI logic described in the PRD (`!state.isBiometricKeyInvalidated`) cannot be implemented without this field being present on `LockerState`.

### Task 15.3 — `locked_screen.dart`

**NOT YET DONE for init-time.** The current `buildWhen` at line 20 already includes `biometricState`:

```dart
buildWhen: (previous, current) =>
    previous.loadState != current.loadState || previous.biometricState != current.biometricState,
```

The screen uses `state.canUseBiometric` (which is `biometricState.isEnabled`) to control the bottom sheet and the button label, but there is no `showBiometricButton` local variable — the condition is evaluated inline via `state.canUseBiometric` (line 64: `final showBiometric = state.canUseBiometric`).

The PRD describes a compound condition:
```dart
showBiometricButton: state.biometricState.isEnabled
    && !state.biometricState.isKeyInvalidated
    && !state.isBiometricKeyInvalidated
```

In the current code `canUseBiometric` only checks `biometricState.isEnabled`, so `isKeyInvalidated` will return `false` for `keyInvalidated` — meaning `showBiometric` would already be `false` when `biometricState == BiometricState.keyInvalidated` (since `isEnabled` is `false` for that value). The `isKeyInvalidated` check is therefore **redundant** in `LockedScreen` given the current `canUseBiometric` logic, unless `showBiometricButton` needs to differentiate `keyInvalidated` from other non-enabled states.

### Task 15.4 — `biometric_unlock_button.dart`

**ALREADY DONE.** The current code at line 13 reads:

```dart
if (!state.biometricState.isEnabled || state.biometricState.isKeyInvalidated) {
  return const SizedBox.shrink();
}
```

This already checks `state.biometricState.isKeyInvalidated`. The `buildWhen` also already includes `biometricState`:

```dart
buildWhen: (previous, current) =>
    previous.biometricState != current.biometricState || previous.loadState != current.loadState,
```

There is no `isBiometricKeyInvalidated` flag check here — but since `isEnabled` is already `false` for `keyInvalidated`, the `isKeyInvalidated` check is a belt-and-suspenders guard.

---

## Related Modules and Services

| File | Role |
|------|------|
| `example/lib/features/locker/data/repositories/locker_repository.dart` | Repository layer; wraps `MFALocker`; `determineBiometricState()` interface + impl |
| `example/lib/features/locker/bloc/locker_bloc.dart` | BLoC; event handlers; `_determineBiometricStateAndEmit`; `_handleBiometricFailure` |
| `example/lib/features/locker/bloc/locker_state.dart` | Freezed `LockerState`; `biometricState` field; `canUseBiometric` getter |
| `example/lib/features/locker/bloc/locker_event.dart` | Events; `biometricKeyInvalidationDetected` for external notifications |
| `example/lib/features/locker/views/auth/locked_screen.dart` | Lock screen; uses `state.canUseBiometric` to show/hide biometric path |
| `example/lib/features/locker/views/widgets/biometric_unlock_button.dart` | Button widget; guards on `isEnabled` and `isKeyInvalidated` |
| `lib/locker/models/biometric_state.dart` | `BiometricState` enum; `isEnabled`, `isKeyInvalidated` getters |
| `example/lib/core/constants/app_constants.dart` | `AppConstants.biometricKeyTag = 'mfa_demo_bio_key'` |

---

## Current Endpoints and Contracts

### `LockerRepository` interface (abstract class)

```dart
Future<BiometricState> determineBiometricState();
```

No parameters — the key tag is encapsulated in `LockerRepositoryImpl`.

### `MFALocker.determineBiometricState`

```dart
Future<BiometricState> determineBiometricState({String? biometricKeyTag});
```

Optional named parameter. Passing `biometricKeyTag` activates the silent key validity probe. Omitting it preserves pre-Phase-13 behavior.

### `BiometricState` enum (Phase 13 complete)

```dart
enum BiometricState {
  tpmUnsupported, tpmVersionIncompatible, hardwareUnavailable,
  notEnrolled, disabledByPolicy, securityUpdateRequired,
  availableButDisabled, enabled, keyInvalidated;

  bool get isAvailable => ...;
  bool get isEnabled => this == enabled;
  bool get isKeyInvalidated => this == keyInvalidated;
}
```

### `LockerState` (current — missing `isBiometricKeyInvalidated`)

```dart
@freezed
abstract class LockerState with _$LockerState {
  const factory LockerState({
    @Default(LockerStatus.initializing) LockerStatus status,
    @Default({}) Map<EntryId, String> entries,
    @Default(LoadState.none) LoadState loadState,
    @Default('') String tempPassword,
    @Default(BiometricState.hardwareUnavailable) BiometricState biometricState,
    @Default(BiometricOperationState.idle) BiometricOperationState biometricOperationState,
    @Default(false) bool enableBiometricAfterInit,
  }) = _LockerState;
  // ...
  bool get canUseBiometric => biometricState.isEnabled;
}
```

There is **no `isBiometricKeyInvalidated` field** in the current `LockerState`. The PRD for Phase 15 refers to this flag (`state.isBiometricKeyInvalidated`) as if it were already present from Phase 7. This is the most critical discrepancy to resolve before implementation.

---

## Patterns Used

### BLoC state emission pattern

All state mutations use `state.copyWith(...)` inside event handlers. Freezed codegen produces `.freezed.dart` which must be re-run after any model change (`make g` in `example/`).

### `_determineBiometricStateAndEmit` pattern

Used by both `_refreshBiometricState` and `_onCheckBiometricAvailabilityRequested` and `_onLockerStateChanged`. It calls `_lockerRepository.determineBiometricState()` and emits `biometricState` into state. The `keyInvalidated` value flows through this path automatically.

### `buildWhen` pattern

Both `LockedScreen` and `BiometricUnlockButton` already subscribe to `biometricState` changes in their `buildWhen`. No changes to `buildWhen` are needed for either widget.

### `_autoDisableBiometricIfInvalidated` pattern

Called after password-based operations (unlock, add entry, view entry, delete entry, change password). It reads `state.biometricState.isKeyInvalidated` directly to decide whether to auto-disable. This pattern is already correct for the init-time detection path because `biometricState` carries `keyInvalidated` after `_determineBiometricStateAndEmit` runs.

---

## Phase-Specific Limitations and Risks

### Risk 1 (HIGH): `isBiometricKeyInvalidated` field is absent from `LockerState`

The PRD for Phase 15 (Tasks 15.2, 15.3) and the phase-15.md document reference `state.isBiometricKeyInvalidated` as an existing flag from Phase 7. However, the current `locker_state.dart` does not declare this field. The runtime `keyInvalidated` handling in `_handleBiometricFailure` (line 1082) only sets `biometricState: BiometricState.keyInvalidated` — no separate boolean flag.

This means either:
- Phase 7 was implemented differently than the PRD described (using `biometricState` alone, without a separate bool flag), and Task 15.2 is a no-op; or
- The `isBiometricKeyInvalidated` field needs to be added to `LockerState` as part of this phase (though the PRD calls it pre-existing).

**Impact on Tasks:**
- Task 15.2: May require adding `isBiometricKeyInvalidated` to `LockerState` + regenerating Freezed code, AND updating `_determineBiometricStateAndEmit` and `_handleBiometricFailure` to set it.
- Task 15.3: The PRD's compound condition `!state.isBiometricKeyInvalidated` cannot be compiled without the field.
- Task 15.4: `BiometricUnlockButton` already compiles (only checks `biometricState` fields).

### Risk 2 (MEDIUM): `locked_screen.dart` uses `canUseBiometric` not a compound condition

The current locked screen does not use a `showBiometricButton` local with a compound expression; it uses `state.canUseBiometric` directly (which is `biometricState.isEnabled`). Since `isEnabled` returns `false` for `keyInvalidated`, the button flash elimination may already work through `biometricState` alone — but only if the `canUseBiometric` check applies to ALL the places where the biometric path is offered (the bottom sheet `showBiometricButton:` parameter at line 73 and the button label at line 50).

The change needed is to ensure the `showBiometric` local at line 64 (`final showBiometric = state.canUseBiometric`) either remains as-is (which already excludes `keyInvalidated`) or is updated with the explicit compound condition per the PRD's spec.

### Risk 3 (LOW): Tasks 15.1 and 15.4 are already implemented

- `locker_repository.dart` already passes `biometricKeyTag: AppConstants.biometricKeyTag` (line 326).
- `biometric_unlock_button.dart` already checks `state.biometricState.isKeyInvalidated` (line 13).

These are complete. Implementer must verify the other two tasks carefully.

### Risk 4 (LOW): Freezed codegen required if `LockerState` changes

Adding `isBiometricKeyInvalidated` to `LockerState` requires running `make g` in `example/` to regenerate `locker_bloc.freezed.dart`. Failing to regenerate will cause compile errors.

---

## New Technical Questions Discovered During Research

1. **Was Phase 7 implemented without the `isBiometricKeyInvalidated` boolean field?**
   The current `LockerState` has no such field — only `biometricState: BiometricState`. The PRD's references to `state.isBiometricKeyInvalidated` cannot compile. Clarify whether: (a) the field should be added in Phase 15, (b) all `isBiometricKeyInvalidated` references in the PRD should be replaced with `state.biometricState.isKeyInvalidated`, or (c) something else.

2. **Does Task 15.3 require any actual code change to `locked_screen.dart`?**
   Since `canUseBiometric` already returns `false` when `biometricState == keyInvalidated` (because `isEnabled` is `false` for that value), the biometric button is already hidden. The only real change would be if the PRD intends to use an explicit compound condition for clarity. Confirm whether this is a substantive logic change or a documentation/clarity change.

3. **Does `_handleBiometricFailure`'s `keyInvalidated` case (line 1082–1091) need to be updated?**
   Currently it only sets `biometricState: BiometricState.keyInvalidated`. If a separate `isBiometricKeyInvalidated` field is added to `LockerState`, this handler should also set `isBiometricKeyInvalidated: true` to keep runtime and init-time paths consistent.
