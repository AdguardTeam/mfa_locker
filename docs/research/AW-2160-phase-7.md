# AW-2160 Phase 7 Research: Example App — Detect and Display Biometric Key Invalidation

## Resolved Questions (from user answers)

**Q1 — enableBiometric flag clearing:** Phase 7 does NOT touch `_onEnableBiometricRequested`. Clearing `isBiometricKeyInvalidated` on successful enable is Phase 8 (task 8.6). Phase 7 only clears the flag on erase (task 7.9).

**Q2 — locked_screen.dart onPressed guard:** Both `showBiometricButton` and the `onPressed` guard inside `_showAuthenticationSheet` must use `state.biometricState.isEnabled && !state.isBiometricKeyInvalidated`. The guard in `onPressed` (currently `state.biometricState.isEnabled`) needs updating alongside the `showBiometricButton` assignment.

**Q3 — biometric_unlock_button.dart buildWhen:** Preserve the existing fields (`biometricState`, `loadState`) and ADD `isBiometricKeyInvalidated` to the comparison. Do not replace existing conditions.

**Q4 — _AutoLockTimeoutTile location:** It stays inline in `settings_screen.dart`. No separate file is created. Edit in place.

---

## Phase Scope

Nine tasks across eight files. All changes are confined to `example/lib/`. No library files under `lib/` or `packages/` are touched.

**Task order constraint:** Tasks 7.1 and 7.2 modify Freezed models (`LockerState`, `LockerAction`). Task 7.3 runs `make g` (codegen). Tasks 7.4–7.9 reference the generated code and must come after 7.3.

### Task mapping

| Task | File | What changes |
|------|------|--------------|
| 7.1 | `locker_state.dart` | Add `@Default(false) bool isBiometricKeyInvalidated` field |
| 7.2 | `locker_action.dart` | Add `LockerAction.biometricKeyInvalidated()` factory |
| 7.3 | — | `cd example && make g` |
| 7.4 | `locker_bloc.dart` | Split `keyInvalidated` from `failure` in `_handleBiometricFailure` |
| 7.5 | `locker_bloc_biometric_stream.dart` | Map `biometricKeyInvalidated` → `BiometricFailed(...)` |
| 7.6 | `locked_screen.dart` | Update `buildWhen` + `showBiometricButton` + `onPressed` guard |
| 7.7 | `biometric_unlock_button.dart` | Update `buildWhen` + hide when `isBiometricKeyInvalidated` |
| 7.8 | `settings_screen.dart` | Update `buildWhen` + `_getBiometricStateDescription` + `_canToggleBiometric` + `_AutoLockTimeoutTile` biometric condition + inline message |
| 7.8b | `settings_bloc.dart` | Handle `keyInvalidated` in `_onAutoLockTimeoutSelectedWithBiometric` |
| 7.9 | `locker_bloc.dart` | Clear flag in `_onEraseStorageRequested` |

---

## Related Modules and Services

### `lib/security/models/exceptions/biometric_exception.dart`
`BiometricExceptionType.keyInvalidated` is available (added in Phase 4). The full enum is: `cancel`, `failure`, `keyInvalidated`, `keyNotFound`, `keyAlreadyExists`, `notAvailable`, `notConfigured`.

### `lib/locker/models/biometric_state.dart`
`BiometricState` is an enum. `isAvailable` returns `true` for `availableButDisabled` or `enabled`. `isEnabled` returns `true` only for `enabled`.

---

## Current State of Each Affected File Section

### 1. `example/lib/features/locker/bloc/locker_state.dart` (Task 7.1)

Current `LockerState` factory has these fields:
```dart
@Default(LockerStatus.initializing) LockerStatus status,
@Default({}) Map<EntryId, String> entries,
@Default(LoadState.none) LoadState loadState,
@Default('') String tempPassword,
@Default(BiometricState.hardwareUnavailable) BiometricState biometricState,
@Default(BiometricOperationState.idle) BiometricOperationState biometricOperationState,
@Default(false) bool enableBiometricAfterInit,
```

**What to add:** `@Default(false) bool isBiometricKeyInvalidated,` as a new field. Placement: after `biometricOperationState`, before `enableBiometricAfterInit` (alphabetical or logical grouping — biometric fields together).

### 2. `example/lib/features/locker/bloc/locker_action.dart` (Task 7.2)

Current factories: `showError`, `showSuccess`, `biometricAuthenticationCancelled`, `biometricAuthenticationSucceeded`, `biometricAuthenticationFailed`, `biometricNotAvailable`, `navigateBack`, `showEntryValue`.

**What to add:** A new no-parameter factory:
```dart
/// Biometric key permanently invalidated due to enrollment change
const factory LockerAction.biometricKeyInvalidated() = BiometricKeyInvalidatedAction;
```

Placement: logically grouped with the other biometric action factories (after `biometricNotAvailable`).

### 3. `example/lib/features/locker/bloc/locker_bloc.dart` (Tasks 7.4 and 7.9)

#### Task 7.4 — `_handleBiometricFailure` (lines 1011–1104)

Current switch structure inside `if (error is BiometricException)`:
```
case BiometricExceptionType.cancel:       → biometricAuthenticationCancelled + idle
case BiometricExceptionType.notAvailable: → biometricNotAvailable + checkBiometricAvailabilityRequested + idle
case BiometricExceptionType.keyNotFound:  → biometricAuthenticationFailed + checkBiometricAvailabilityRequested + idle
case BiometricExceptionType.keyAlreadyExists: → biometricAuthenticationFailed + idle
case BiometricExceptionType.failure:
case BiometricExceptionType.keyInvalidated:   → _determineBiometricStateAndEmit (FALL THROUGH)
case BiometricExceptionType.notConfigured:    → break (fall through to generic)
```

Currently `keyInvalidated` shares the `failure` case and both call `_determineBiometricStateAndEmit`. This is the fall-through that must be broken.

**What to change:** Split `keyInvalidated` from `failure`. The new `keyInvalidated` case must:
1. `emit(state.copyWith(isBiometricKeyInvalidated: true))`
2. `action(const LockerAction.biometricKeyInvalidated())`
3. `add(const LockerEvent.biometricOperationStateChanged(biometricOperationState: BiometricOperationState.idle))`
4. `return` — do NOT fall through to the `action(LockerAction.biometricAuthenticationFailed(...))` at the bottom

The `failure` case retains its current behavior: calls `_determineBiometricStateAndEmit` and falls through to the generic `biometricAuthenticationFailed` action.

#### Task 7.9 — `_onEraseStorageRequested` (lines 874–914)

Current successful emit (lines 888–895):
```dart
emit(
  state.copyWith(
    status: LockerStatus.notInitialized,
    entries: {},
    loadState: LoadState.none,
  ),
);
```

**What to add:** `isBiometricKeyInvalidated: false` to the `copyWith` call in the success path.

### 4. `example/lib/features/locker/views/widgets/locker_bloc_biometric_stream.dart` (Task 7.5)

Current `mapOrNull` call maps: `biometricAuthenticationSucceeded`, `biometricAuthenticationCancelled`, `biometricAuthenticationFailed`, `biometricNotAvailable`.

**What to add:** `biometricKeyInvalidated: (_) => const BiometricFailed('Biometrics have changed. Please use your password.')` — added after Freezed codegen (task 7.3) generates the `biometricKeyInvalidated` parameter on `mapOrNull`.

**Copy is final (approved):** `'Biometrics have changed. Please use your password.'`

### 5. `example/lib/features/locker/views/auth/locked_screen.dart` (Task 7.6)

Current `buildWhen` (lines 20–21):
```dart
buildWhen: (previous, current) =>
    previous.loadState != current.loadState || previous.biometricState != current.biometricState,
```

**What to add to `buildWhen`:** `|| previous.isBiometricKeyInvalidated != current.isBiometricKeyInvalidated`

Current `showBiometricButton` in `_showAuthenticationSheet` (line 72):
```dart
showBiometricButton: state.biometricState.isEnabled,
```

**New condition:** `showBiometricButton: state.biometricState.isEnabled && !state.isBiometricKeyInvalidated,`

Current `onBiometricPressed` guard (line 74):
```dart
onBiometricPressed: state.biometricState.isEnabled
    ? () => bloc.add(const LockerEvent.unlockWithBiometricRequested())
    : null,
```

**New condition:** `onBiometricPressed: state.biometricState.isEnabled && !state.isBiometricKeyInvalidated`

Note: The `ElevatedButton.onPressed` on the main screen body (line 46) uses `state.loadState == LoadState.loading` — this is the "Unlock Storage" / "Unlock with Password" button and does NOT need a biometric guard change.

### 6. `example/lib/features/locker/views/widgets/biometric_unlock_button.dart` (Task 7.7)

Current `buildWhen` (lines 10–11):
```dart
buildWhen: (previous, current) =>
    previous.biometricState != current.biometricState || previous.loadState != current.loadState,
```

**Updated `buildWhen`:** Add `|| previous.isBiometricKeyInvalidated != current.isBiometricKeyInvalidated`

Current hide condition (line 13):
```dart
if (!state.biometricState.isEnabled) {
  return const SizedBox.shrink();
}
```

**Updated condition:** `if (!state.biometricState.isEnabled || state.isBiometricKeyInvalidated)` — returns `SizedBox.shrink()` when either biometric is not enabled OR the key is invalidated.

### 7. `example/lib/features/settings/views/settings_screen.dart` (Task 7.8)

#### Inner `BlocBuilder` for biometric card (line 76–77)

Current `buildWhen`:
```dart
buildWhen: (previous, current) => previous.biometricState != current.biometricState,
```

**Updated:** Add `|| previous.isBiometricKeyInvalidated != current.isBiometricKeyInvalidated`

Note: The inner builder uses `innerLockerState` as variable name.

#### `_canToggleBiometric` (lines 115–116)

Current:
```dart
bool _canToggleBiometric(LockerState state) =>
    state.biometricState.isAvailable && state.loadState != LoadState.loading;
```

**Updated condition:** `(state.biometricState.isAvailable || state.isBiometricKeyInvalidated) && state.loadState != LoadState.loading`

Note: `state.loadState` here refers to the outer `lockerState.loadState`. The `_canToggleBiometric` method receives the `innerLockerState` from the inner `BlocBuilder` — which is also a `LockerState`, so `loadState` is accessible from the same state object.

#### `_getBiometricStateDescription` (lines 147–156)

Current signature: `String _getBiometricStateDescription(BiometricState biometricState)` — takes only `BiometricState`.

**New signature:** Must accept `isBiometricKeyInvalidated` as well. Options:
- Change signature to `String _getBiometricStateDescription(BiometricState biometricState, {required bool isKeyInvalidated})`
- Or pass the full `LockerState` and read both fields.

**When `isKeyInvalidated` is true:** Return `'Biometrics changed. Disable and re-enable to use new biometrics.'` (copy is final).

The PRD specifies rendering this text in `Theme.of(context).colorScheme.error`. The `_getBiometricStateDescription` function returns a `String`, so the error color must be applied at the call site on the `Text` widget, not inside the function.

Current call site (line 83–85):
```dart
subtitle: Text(
  _getBiometricStateDescription(innerLockerState.biometricState),
),
```

**Updated:** The `Text` widget must conditionally apply `style: TextStyle(color: Theme.of(context).colorScheme.error)` when `innerLockerState.isBiometricKeyInvalidated` is `true`.

#### `_AutoLockTimeoutTile._showTimeoutDialog` biometric condition (lines 201–247)

Current check:
```dart
final isBiometricEnabled = lockerBloc.state.biometricState.isEnabled;
```

Used in three places within `_showTimeoutDialog`:
- `lockerBloc.add(LockerEvent.biometricOperationStateChanged(biometricOperationState: BiometricOperationState.inProgress))` guard
- `showBiometricButton: isBiometricEnabled`
- `onBiometricPressed: isBiometricEnabled ? ...`
- `lockerBloc.add(LockerEvent.biometricOperationStateChanged(biometricOperationState: BiometricOperationState.idle))` guard

**Updated condition:** The biometric button in the timeout tile should NOT appear when the key is invalidated. Change the condition to:
```dart
final isBiometricEnabled = lockerBloc.state.biometricState.isEnabled && !lockerBloc.state.isBiometricKeyInvalidated;
```

All three uses of `isBiometricEnabled` in `_showTimeoutDialog` will then correctly reflect invalidation.

Note: `_AutoLockTimeoutTile` is a `StatelessWidget` with `BuildContext context` available from `build`. The `_showTimeoutDialog` is an instance method on `_AutoLockTimeoutTile`, which receives `BuildContext context` as parameter — it reads `context.read<LockerBloc>()` so access to `isBiometricKeyInvalidated` is straightforward.

### 8. `example/lib/features/settings/bloc/settings_bloc.dart` (Task 7.8b)

Current `_onAutoLockTimeoutSelectedWithBiometric` catch block switch (lines 105–136):
```
case BiometricExceptionType.cancel:           → biometricAuthenticationCancelled + return
case BiometricExceptionType.notAvailable:     → biometricNotAvailable + return
case BiometricExceptionType.keyNotFound:      → biometricAuthenticationFailed('key not found') + return
case BiometricExceptionType.keyAlreadyExists: → biometricAuthenticationFailed('already exists') + return
case BiometricExceptionType.failure:
case BiometricExceptionType.notConfigured:
case BiometricExceptionType.keyInvalidated:   → break (fall through to generic 'Failed to update timeout')
```

Currently `keyInvalidated` groups with `failure` and `notConfigured` via `break` — all fall through to:
```dart
action(const SettingsAction.biometricAuthenticationFailed(message: 'Failed to update timeout using biometric.'));
action(const SettingsAction.showError('Failed to update timeout using biometric.'));
```

**What to change:** Add a separate `case BiometricExceptionType.keyInvalidated:` that:
```dart
action(const SettingsAction.biometricAuthenticationFailed(
  message: 'Biometrics have changed. Please use your password.',
));
return;
```

Copy is final (approved): `'Biometrics have changed. Please use your password.'`

This matches the same copy used in `LockerBlocBiometricStream`. The `showError` action is NOT emitted for this case (the message is surfaced via the auth sheet stream, not a snackbar).

---

## Patterns Used

### Freezed field addition pattern (`locker_state.dart`)

All fields use `@Default(value) Type name,` syntax inside the single `const factory LockerState(...)` constructor. The `part` file is `locker_bloc.freezed.dart`. Adding a field to the constructor and running `make g` regenerates `locker_bloc.freezed.dart` automatically. No manual edits to the `.freezed.dart` file.

### Freezed sealed action factory pattern (`locker_action.dart`)

The file is a `part` of `locker_bloc.dart`. Factories are added as `const factory LockerAction.name() = GeneratedClassName;` inside the `@freezed sealed class LockerAction`. After codegen, `mapOrNull` in the extension will have a new optional parameter `biometricKeyInvalidated`.

### `mapOrNull` in stream extensions

Both `locker_bloc_biometric_stream.dart` and `settings_bloc_biometric_stream.dart` use `actions.map((action) => action.mapOrNull(...)).where((r) => r != null).cast<BiometricAuthResult>()`. The `mapOrNull` generated method has an optional named parameter per factory. Adding a new factory adds a new parameter. The extension will not compile until codegen runs (task 7.3 must precede task 7.5).

### `buildWhen` pattern

Existing widgets use `previous.fieldA != current.fieldA || previous.fieldB != current.fieldB`. New fields are appended with `||`. No existing conditions are removed.

### Codegen

`cd example && make g` runs `fvm dart run build_runner build --delete-conflicting-outputs`. This regenerates `locker_bloc.freezed.dart` (and any other `.freezed.dart` files in the example). Must be run from the `example/` directory.

---

## Current `_handleBiometricFailure` Switch — Full Structure

The method is at lines 1011–1104 of `locker_bloc.dart`. Key structural detail for task 7.4:

```dart
case BiometricExceptionType.failure:
case BiometricExceptionType.keyInvalidated:
  await _determineBiometricStateAndEmit(emit);
  // falls through to action(LockerAction.biometricAuthenticationFailed(...)) below
```

After the switch, execution continues to:
```dart
action(LockerAction.biometricAuthenticationFailed(message: fallbackMessage));
add(LockerEvent.biometricOperationStateChanged(biometricOperationState: BiometricOperationState.idle));
```

The `failure` case must keep this fall-through. The `keyInvalidated` case must return early and NOT reach those two lines.

---

## Phase-Specific Limitations and Risks

**Risk 1 — Codegen ordering.** Tasks 7.4 and 7.5 reference `biometricKeyInvalidated` on the generated type. If the implementer edits `locker_bloc.dart` or `locker_bloc_biometric_stream.dart` before running `make g`, the analyzer will report undefined identifiers. The strict order is: 7.1 → 7.2 → `make g` → 7.4 → 7.5 → 7.6 → 7.7 → 7.8 → 7.8b → 7.9.

**Risk 2 — `_getBiometricStateDescription` signature change and call site.** The function currently takes `BiometricState` only. Adding the `isKeyInvalidated` parameter requires updating both the function signature and the call site in the inner `BlocBuilder`. The error color must be applied on the `Text` widget, not inside the `String`-returning function.

**Risk 3 — `loadState` in `_canToggleBiometric`.** The `_canToggleBiometric` method takes `LockerState state` (the `innerLockerState` from the inner `BlocBuilder`). The `state.loadState` accessed there is the same `LockerState.loadState`. This works correctly since both `biometricState` and `loadState` come from the same `LockerState` instance.

**Risk 4 — `SettingsBloc` `keyInvalidated` case must `return`** without emitting a `showError` action. The error is communicated via the auth sheet stream (`biometricAuthenticationFailed` action → `BiometricFailed` result), not via a snackbar. Emitting `showError` would produce a redundant snackbar.

**Risk 5 — `_AutoLockTimeoutTile` isBiometricEnabled variable.** The variable is read once at the start of `_showTimeoutDialog` from `lockerBloc.state`. This is a snapshot. Since the biometric operation state / key invalidation state won't change mid-dialog in this flow, reading it once is sufficient.

**No regression risk on `failure` case.** The `failure` branch's existing behavior (`_determineBiometricStateAndEmit` + `biometricAuthenticationFailed` fallback) is unchanged. Only `keyInvalidated` is extracted.

---

## New Technical Questions

None discovered during research. All ambiguities are resolved by the PRD and user answers.
