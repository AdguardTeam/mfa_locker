# Plan: AW-2160 Phase 8 — Example App Password-Only Biometric Disable

Status: PLAN_APPROVED

## Phase Scope

Phase 8 closes the biometric key-invalidation recovery loop opened by Phase 7. When a user's biometric key has been permanently invalidated (detected in Phase 7), the existing `disableBiometricRequested` event triggers a biometric prompt that will always fail. Phase 8 introduces a password-only disable path so the user can remove the invalidated biometric wrap without a biometric prompt, then re-enable biometrics with fresh enrollment.

All changes are scoped to the example app (`example/lib/`). No library files under `lib/` or `packages/` are modified.

Six tasks:
1. Repository method addition (interface + implementation)
2. Freezed event addition
3. Code generation (`make g`)
4. BLoC handler registration and implementation
5. Settings screen toggle routing
6. Clear invalidation flag on successful biometric re-enable

## Components

### 1. Repository Layer

**File:** `example/lib/features/locker/data/repositories/locker_repository.dart`

- Add `disableBiometricPasswordOnly({required String password})` to the `LockerRepository` abstract class.
- Implement in `LockerRepositoryImpl` following the established repository pattern:
  1. `await _ensureLockerInstance()`
  2. `_securityProvider.authenticatePassword(password: password)` to obtain `PasswordCipherFunc`
  3. `_locker.teardownBiometryPasswordOnly(passwordCipherFunc: ..., biometricKeyTag: AppConstants.biometricKeyTag)`
- No `BioCipherFunc` is created. This is the key difference from `disableBiometric`.

### 2. BLoC Event

**File:** `example/lib/features/locker/bloc/locker_event.dart`

- Add Freezed factory: `const factory LockerEvent.disableBiometricPasswordOnlyRequested({required String password}) = _DisableBiometricPasswordOnlyRequested;`
- Follows the same pattern as the existing `disableBiometricRequested` event.

### 3. BLoC Handler

**File:** `example/lib/features/locker/bloc/locker_bloc.dart`

- Register `on<_DisableBiometricPasswordOnlyRequested>(_onDisableBiometricPasswordOnlyRequested)` in the constructor, appended after the existing 25 handlers (before `_timerService.onLockCallback`).
- Handler `_onDisableBiometricPasswordOnlyRequested` follows the password-only pattern (like `_onUnlockPasswordSubmitted`), NOT the biometric operation pattern (like `_onDisableBiometricRequested`):
  - Emit `loadState: LoadState.loading`
  - Call `_handleVaultOperation` with `operation`, `onDecryptFailed`, `onError`, `operationDescription`
  - Inside `operation`: call repo, `_refreshBiometricState(emit, resetLoadState: true)`, clear `isBiometricKeyInvalidated`, emit success action
  - No `biometricOperationState` management (no `inProgress`/`awaitingResume`), no `try/finally` block wrapping the whole handler
  - `onDecryptFailed` maps to `'Incorrect password: $error'`
  - `onError` maps to `'Failed to disable biometric: $error'`

### 4. BLoC Enable Handler Modification

**File:** `example/lib/features/locker/bloc/locker_bloc.dart`

- In `_onEnableBiometricRequested`, inside the `_handleVaultOperation.operation` closure, after `_refreshBiometricState(emit, resetLoadState: true)` and before `action(showSuccess)`:
  - Add `emit(state.copyWith(isBiometricKeyInvalidated: false))`
- This is an idempotent safety measure. After a password-only disable the flag is already `false`, but this guarantees cleanup in edge cases.

### 5. Settings Screen

**File:** `example/lib/features/settings/views/settings_screen.dart`

- In `_handleBiometricToggle`, inside the `else` branch (disable path, `value == false`), add a routing check before the existing `disableBiometricRequested` dispatch:
  - If `lockerBloc.state.isBiometricKeyInvalidated` is `true`, dispatch `disableBiometricPasswordOnlyRequested` and `return` early.
  - Otherwise, fall through to the existing `disableBiometricRequested` dispatch (no change).
- No new UI elements, dialogs, or screens are introduced. The existing password prompt is reused.

## API Contract

### New Repository Method

```dart
// LockerRepository (abstract)
Future<void> disableBiometricPasswordOnly({required String password});

// LockerRepositoryImpl
@override
Future<void> disableBiometricPasswordOnly({required String password}) async {
  await _ensureLockerInstance();
  final passwordCipherFunc = await _securityProvider.authenticatePassword(password: password);
  await _locker.teardownBiometryPasswordOnly(
    passwordCipherFunc: passwordCipherFunc,
    biometricKeyTag: AppConstants.biometricKeyTag,
  );
}
```

### New BLoC Event

```dart
const factory LockerEvent.disableBiometricPasswordOnlyRequested({
  required String password,
}) = _DisableBiometricPasswordOnlyRequested;
```

### Modified BLoC Handlers

**New handler** `_onDisableBiometricPasswordOnlyRequested`:
- Input: `_DisableBiometricPasswordOnlyRequested event`, `Emitter<LockerState> emit`
- Emits: `loadState: loading` -> (on success) `isBiometricKeyInvalidated: false` + `showSuccess` action; (on decrypt fail) `loadState: none` + `showError`; (on error) `loadState: none` + `showError`

**Modified handler** `_onEnableBiometricRequested`:
- Adds `emit(state.copyWith(isBiometricKeyInvalidated: false))` after `_refreshBiometricState` in the success path.

## Data Flows

### Password-Only Disable Flow

```
User toggles biometric OFF (isBiometricKeyInvalidated == true)
  -> SettingsScreen._handleBiometricToggle(false)
  -> Password prompt (existing modal bottom sheet)
  -> lockerBloc.state.isBiometricKeyInvalidated == true
  -> dispatch LockerEvent.disableBiometricPasswordOnlyRequested(password)
  -> LockerBloc._onDisableBiometricPasswordOnlyRequested
     -> emit loadState: loading
     -> _handleVaultOperation:
        -> repo.disableBiometricPasswordOnly(password)
           -> _securityProvider.authenticatePassword -> PasswordCipherFunc
           -> _locker.teardownBiometryPasswordOnly(passwordCipherFunc, keyTag)
              -> Removes Origin.bio wrap, attempts key deletion (suppressed errors)
        -> _refreshBiometricState(emit, resetLoadState: true)
           -> determineBiometricState -> emit biometricState + loadState: none
        -> emit isBiometricKeyInvalidated: false
        -> action showSuccess
  -> Settings screen rebuilds: error description gone, toggle OFF, normal state
```

### Re-Enable Flow (After Password-Only Disable)

```
User toggles biometric ON
  -> Normal enableBiometricRequested flow
  -> On success:
     -> _refreshBiometricState(emit, resetLoadState: true)
     -> emit isBiometricKeyInvalidated: false  [NEW - Phase 8 safety clear]
     -> action showSuccess
```

### Error Flows

**Wrong password:**
```
_handleVaultOperation catches DecryptFailedException
  -> onDecryptFailed -> _handleDecryptFailure(emit, showError('Incorrect password: $error'))
  -> loadState: none, error action emitted
  -> isBiometricKeyInvalidated remains true, user can retry
```

**Generic failure:**
```
_handleVaultOperation catches generic error
  -> onError -> _handleGenericFailure(emit, showError('Failed to disable biometric: $error'))
  -> loadState: none, error action emitted
  -> isBiometricKeyInvalidated remains true, user can retry
```

## NFR

- **No regression on normal disable flow:** When `isBiometricKeyInvalidated == false`, the existing `disableBiometricRequested` path is used unchanged.
- **No new biometric prompts:** The password-only path must never trigger a biometric system dialog. No `BioCipherFunc` is created, no `biometricOperationState` management.
- **Idempotent flag clear:** Clearing `isBiometricKeyInvalidated` on enable is safe even if the flag is already `false`.
- **Lint/format compliance:** `cd example && fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` exits 0; `fvm dart format . --line-length 120` produces no diffs.

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Copy-paste from `_onDisableBiometricRequested` accidentally includes `biometricOperationState` management | Medium | High -- would block auto-lock during password-only operation | Use `_onUnlockPasswordSubmitted` as the template, not `_onDisableBiometricRequested`. Verify no `biometricOperationState`, no `try/finally` wrapping the full handler. |
| `_refreshBiometricState` internally fails, preventing `isBiometricKeyInvalidated: false` emit | Low | Medium -- flag stays true despite successful disable | Confirmed that `_determineBiometricStateAndEmit` catches errors without rethrowing, so `_refreshBiometricState` always returns normally. The flag clear emit will always execute. |
| `_onEnableBiometricRequested` `finally` block overrides `isBiometricKeyInvalidated` emit | Low | Medium -- flag could revert to true | Confirmed: the `finally` block's `copyWith` does not include `isBiometricKeyInvalidated`, so the cleared flag is preserved. |
| Codegen (`make g`) fails | Low | Medium -- blocks task 8.4 | Run `make g` immediately after task 8.2 changes; confirm success before proceeding. |

## Dependencies

### On Previous Phases

- **Phase 5 (complete):** `MFALocker.teardownBiometryPasswordOnly` is the library method called by the new repository method.
- **Phase 7 (complete):** `isBiometricKeyInvalidated: bool` field in `LockerState` (task 7.1), `biometricKeyInvalidated()` action in `LockerAction` (task 7.2), `_canToggleBiometric` allowing toggle when invalidated (task 7.7), `_handleBiometricFailure` setting the flag on `keyInvalidated` (task 7.3), and erase clearing the flag (task 7.9).

### On External Systems

- None. All library-level support (`teardownBiometryPasswordOnly`, `BiometricExceptionType.keyInvalidated`) is already in place from Phases 1-6.

### Task Ordering

```
8.1 (repository) ──┐
                    ├── 8.3 (make g) ── 8.4 (BLoC handler) ──┬── 8.5 (Settings routing)
8.2 (event)     ───┘                                         └── 8.6 (enable flag clear)
```

- 8.1 and 8.2 are independent of each other and can be done in parallel.
- 8.3 must follow both 8.1 and 8.2 (Freezed codegen needs the event change; repository must compile).
- 8.4 must follow 8.3 (references generated `_DisableBiometricPasswordOnlyRequested`).
- 8.5 and 8.6 are independent of each other and can follow 8.4.

## Open Questions

None.
