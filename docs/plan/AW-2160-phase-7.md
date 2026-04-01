# Plan: AW-2160 Phase 7 -- Example App: Detect and Display Biometric Key Invalidation

Status: PLAN_APPROVED

## Phase Scope

Phase 7 wires the example app (`example/lib/`) to detect `BiometricExceptionType.keyInvalidated` at runtime, display actionable inline messages, hide the broken biometric UI, and show an informational message in Settings. No library-layer changes. Nine tasks across eight files, plus one code-generation step.

**Phase 8 boundary:** The password-only disable flow (`disableBiometricPasswordOnlyRequested` event, `_handleBiometricToggle` routing, clearing the flag on successful `enableBiometric`) is Phase 8. Phase 7 ends at detection and display.

---

## Dependencies

| Dependency | Status |
|------------|--------|
| Phase 1 -- Android native `KEY_PERMANENTLY_INVALIDATED` | Complete |
| Phase 2 -- iOS/macOS native `KEY_PERMANENTLY_INVALIDATED` | Complete |
| Phase 3 -- Dart plugin `BiometricCipherExceptionCode.keyPermanentlyInvalidated` | Complete |
| Phase 4 -- Locker library `BiometricExceptionType.keyInvalidated` | Complete |
| Phase 5 -- `MFALocker.teardownBiometryPasswordOnly` | Complete |
| Phase 6 -- Unit tests for Phases 3--5 | Complete |

All prior phases are complete. Phase 7 has no external blockers.

---

## Components

### Files modified (all under `example/lib/`)

| File | Task(s) | Change summary |
|------|---------|----------------|
| `features/locker/bloc/locker_state.dart` | 7.1 | Add `@Default(false) bool isBiometricKeyInvalidated` field to `LockerState` |
| `features/locker/bloc/locker_action.dart` | 7.2 | Add `LockerAction.biometricKeyInvalidated()` Freezed factory |
| -- (codegen) -- | 7.3 | `cd example && make g` to regenerate `.freezed.dart` files |
| `features/locker/bloc/locker_bloc.dart` | 7.4, 7.9 | Split `keyInvalidated` from `failure` in `_handleBiometricFailure`; clear flag in `_onEraseStorageRequested` |
| `features/locker/views/widgets/locker_bloc_biometric_stream.dart` | 7.5 | Map `biometricKeyInvalidated` to `BiometricFailed(...)` |
| `features/locker/views/auth/locked_screen.dart` | 7.6 | Update `buildWhen`, `showBiometricButton`, and `onBiometricPressed` guard |
| `features/locker/views/widgets/biometric_unlock_button.dart` | 7.7 | Update `buildWhen` and hide condition |
| `features/settings/views/settings_screen.dart` | 7.8 | Update `buildWhen`, `_canToggleBiometric`, `_getBiometricStateDescription`, subtitle error color, `_AutoLockTimeoutTile` biometric check |
| `features/settings/bloc/settings_bloc.dart` | 7.8b | Handle `keyInvalidated` in `_onAutoLockTimeoutSelectedWithBiometric` |

**Zero new files created.** All changes are additive modifications to existing files.

---

## API Contract

No public APIs are added or modified. All changes are internal to the example app's BLoC/state/view layer.

### New Freezed fields and factories

**`LockerState`** -- new field:
```dart
@Default(false) bool isBiometricKeyInvalidated,
```

**`LockerAction`** -- new factory:
```dart
const factory LockerAction.biometricKeyInvalidated() = BiometricKeyInvalidatedAction;
```

These are internal to the example app and consumed only by the example app's BLoC, views, and stream extensions.

---

## Data Flows

### Flow 1: Biometric key invalidation detection (runtime)

```
User taps biometric unlock
  -> LockerBloc dispatches unlock via repository
  -> Repository calls MFALocker biometric operation
  -> Platform throws keyPermanentlyInvalidated (Phases 1-4)
  -> BiometricExceptionType.keyInvalidated reaches _handleBiometricFailure
  -> BLoC emits state.copyWith(isBiometricKeyInvalidated: true)
  -> BLoC emits LockerAction.biometricKeyInvalidated()
  -> BLoC adds biometricOperationStateChanged(idle), returns early
  -> LockerBlocBiometricStream maps action to BiometricFailed('Biometrics have changed...')
  -> Auth bottom sheet shows inline error message
  -> Biometric button hides (locked screen + BiometricUnlockButton rebuild)
```

### Flow 2: Settings displays invalidation state

```
User navigates to Settings (isBiometricKeyInvalidated == true)
  -> Inner BlocBuilder rebuilds (buildWhen includes isBiometricKeyInvalidated)
  -> _getBiometricStateDescription returns invalidation message
  -> Subtitle Text renders in Theme.of(context).colorScheme.error
  -> _canToggleBiometric returns true (toggle enabled for disable flow)
  -> _AutoLockTimeoutTile biometric condition excludes invalidated key
```

### Flow 3: Settings timeout update with invalidated key

```
User triggers auto-lock timeout update
  -> SettingsBloc._onAutoLockTimeoutSelectedWithBiometric catches keyInvalidated
  -> Emits biometricAuthenticationFailed(message: 'Biometrics have changed...')
  -> Returns early (no generic 'Failed to update timeout' message)
```

### Flow 4: Erase clears flag

```
User confirms erase
  -> _onEraseStorageRequested completes
  -> BLoC emits state.copyWith(isBiometricKeyInvalidated: false) in success path
  -> Fresh state, no stale invalidation knowledge
```

---

## Implementation Steps

### Step 1 (Task 7.1): Add `isBiometricKeyInvalidated` to `LockerState`

**File:** `example/lib/features/locker/bloc/locker_state.dart`

Add `@Default(false) bool isBiometricKeyInvalidated,` to the `LockerState` factory constructor. Place it after `biometricOperationState` and before `enableBiometricAfterInit` to group biometric-related fields together.

### Step 2 (Task 7.2): Add `biometricKeyInvalidated()` to `LockerAction`

**File:** `example/lib/features/locker/bloc/locker_action.dart`

Add a new no-parameter factory after `biometricNotAvailable`:

```dart
/// Biometric key permanently invalidated due to enrollment change
const factory LockerAction.biometricKeyInvalidated() = BiometricKeyInvalidatedAction;
```

### Step 3 (Task 7.3): Run code generation

```bash
cd example && make g
```

This regenerates `locker_bloc.freezed.dart` with the new field and factory. Tasks 7.4--7.9 depend on this step completing successfully.

### Step 4 (Task 7.4): Split `keyInvalidated` from `failure` in `_handleBiometricFailure`

**File:** `example/lib/features/locker/bloc/locker_bloc.dart` (lines 1081--1083)

Current state: `keyInvalidated` shares the `failure` case and both call `_determineBiometricStateAndEmit`, then fall through to the generic `biometricAuthenticationFailed` action.

Change: Extract `keyInvalidated` into its own case that:

1. Emits `state.copyWith(isBiometricKeyInvalidated: true)`.
2. Emits `LockerAction.biometricKeyInvalidated()` via `action(...)`.
3. Adds `LockerEvent.biometricOperationStateChanged(biometricOperationState: BiometricOperationState.idle)`.
4. Returns early -- does NOT fall through to `biometricAuthenticationFailed`.

The `failure` case retains its current behavior unchanged: calls `_determineBiometricStateAndEmit` and falls through to the generic action.

### Step 5 (Task 7.5): Map `biometricKeyInvalidated` in stream extension

**File:** `example/lib/features/locker/views/widgets/locker_bloc_biometric_stream.dart`

Add to the `mapOrNull` call:

```dart
biometricKeyInvalidated: (_) =>
    const BiometricFailed('Biometrics have changed. Please use your password.'),
```

Copy is final and approved.

### Step 6 (Task 7.6): Update `LockedScreen`

**File:** `example/lib/features/locker/views/auth/locked_screen.dart`

Three changes:

1. **`buildWhen`** (line 20--21): Append `|| previous.isBiometricKeyInvalidated != current.isBiometricKeyInvalidated`.

2. **`showBiometricButton`** (line 72): Change from `state.biometricState.isEnabled` to `state.biometricState.isEnabled && !state.isBiometricKeyInvalidated`.

3. **`onBiometricPressed` guard** (line 74): Change condition from `state.biometricState.isEnabled` to `state.biometricState.isEnabled && !state.isBiometricKeyInvalidated`.

### Step 7 (Task 7.7): Update `BiometricUnlockButton`

**File:** `example/lib/features/locker/views/widgets/biometric_unlock_button.dart`

Two changes:

1. **`buildWhen`** (line 10--11): Append `|| previous.isBiometricKeyInvalidated != current.isBiometricKeyInvalidated`.

2. **Hide condition** (line 13): Change from `if (!state.biometricState.isEnabled)` to `if (!state.biometricState.isEnabled || state.isBiometricKeyInvalidated)`.

### Step 8 (Task 7.8): Update `SettingsScreen`

**File:** `example/lib/features/settings/views/settings_screen.dart`

Five changes:

1. **Inner `BlocBuilder` `buildWhen`** (line 77): Append `|| previous.isBiometricKeyInvalidated != current.isBiometricKeyInvalidated`.

2. **`_canToggleBiometric`** (line 115--116): Change from `state.biometricState.isAvailable` to `(state.biometricState.isAvailable || state.isBiometricKeyInvalidated)`. The `&& state.loadState != LoadState.loading` condition remains.

3. **`_getBiometricStateDescription` signature and body** (lines 147--156): Add `{required bool isKeyInvalidated}` named parameter. When `isKeyInvalidated` is `true`, return `'Biometrics changed. Disable and re-enable to use new biometrics.'` before the switch. Copy is final.

4. **Subtitle `Text` widget** (lines 83--85): Conditionally apply `style: TextStyle(color: Theme.of(context).colorScheme.error)` when `innerLockerState.isBiometricKeyInvalidated` is `true`. Update the `_getBiometricStateDescription` call site to pass the new parameter.

5. **`_AutoLockTimeoutTile._showTimeoutDialog`** (line 202): Change from `lockerBloc.state.biometricState.isEnabled` to `lockerBloc.state.biometricState.isEnabled && !lockerBloc.state.isBiometricKeyInvalidated`. All downstream uses of `isBiometricEnabled` in `_showTimeoutDialog` then correctly reflect invalidation.

### Step 9 (Task 7.8b): Update `SettingsBloc`

**File:** `example/lib/features/settings/bloc/settings_bloc.dart`

In `_onAutoLockTimeoutSelectedWithBiometric`, extract `keyInvalidated` from the `failure`/`notConfigured`/`keyInvalidated` break group (lines 131--134). Add a separate case:

```dart
case BiometricExceptionType.keyInvalidated:
  action(
    const SettingsAction.biometricAuthenticationFailed(
      message: 'Biometrics have changed. Please use your password.',
    ),
  );
  return;
```

This prevents fall-through to the generic `'Failed to update timeout using biometric.'` messages. The `showError` action is NOT emitted for this case -- the error is surfaced via the auth sheet stream only.

### Step 10 (Task 7.9): Clear flag on erase

**File:** `example/lib/features/locker/bloc/locker_bloc.dart` (lines 888--894)

Add `isBiometricKeyInvalidated: false` to the `state.copyWith(...)` call in the success path of `_onEraseStorageRequested`.

### Step 11: Verify

1. Run `cd example && fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` -- must exit 0.
2. Run `cd example && fvm dart format . --line-length 120` -- must produce no diffs.
3. Confirm existing library tests still pass: `fvm flutter test` from root.

---

## NFR

| Requirement | How satisfied |
|-------------|---------------|
| Example app only -- no library changes | All eight files are under `example/lib/` |
| Flag is in-memory only | `@Default(false)` Freezed field -- no persistence. Resets on cold launch. |
| No regression on generic biometric failures | `failure` case retains its existing behavior; only `keyInvalidated` is extracted |
| Code style compliance | Line length 120, single quotes, trailing commas, `buildWhen` pattern consistent with existing widgets |
| Static analysis passes | `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` must exit 0 |
| Copy is final | Two approved strings used exactly as written |

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| `make g` fails after Freezed model changes in 7.1/7.2 | Low | Medium -- blocks 7.4--7.9 | Run `make g` immediately after steps 1--2 and confirm clean codegen before proceeding |
| `mapOrNull` parameter `biometricKeyInvalidated` unavailable until codegen | Low -- deterministic | Low | Strict task ordering: 7.1 -> 7.2 -> 7.3 -> 7.4+ |
| `_handleBiometricFailure` switch structure differs from research | Very low -- confirmed by reading source | Low -- adjust split accordingly | Source verified at lines 1081--1088 of `locker_bloc.dart` |
| `_canToggleBiometric` with `|| state.isBiometricKeyInvalidated` allows toggle on simulator with no biometric hardware | Low -- dev concern, not production | Low -- the toggle enables; actual disable routing is Phase 8 | Accepted per PRD decision |
| `SettingsBloc` `keyInvalidated` case must `return` without emitting `showError` | Low -- explicit in this plan | Medium -- redundant snackbar if missed | Code review verification |

---

## Open Questions

None.
