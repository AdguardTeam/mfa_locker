# Research: AW-2160 Phase 8 — Example App Password-Only Biometric Disable

## Resolved Questions

The PRD lists no open questions. The user instructed to proceed with research immediately.

---

## Phase Scope

Phase 8 closes the biometric key-invalidation recovery loop that Phase 7 opened. The sole scope is the example app (`example/lib/`). Five code tasks plus one codegen step:

| # | Task | File |
|---|------|------|
| 8.1 | Add `disableBiometricPasswordOnly` to repository | `example/lib/features/locker/data/repositories/locker_repository.dart` |
| 8.2 | Add `disableBiometricPasswordOnlyRequested` event | `example/lib/features/locker/bloc/locker_event.dart` |
| 8.3 | Run `make g` (codegen) | `example/` |
| 8.4 | Register + implement BLoC handler | `example/lib/features/locker/bloc/locker_bloc.dart` |
| 8.5 | Route Settings toggle to new event | `example/lib/features/settings/views/settings_screen.dart` |
| 8.6 | Clear flag on successful biometric re-enable | `example/lib/features/locker/bloc/locker_bloc.dart` |

No library files under `lib/` or `packages/` are touched.

---

## Related Modules and Services

### Library layer (read-only for this phase)

- `/Users/comrade77/Documents/Performix/Projects/mfa_locker/lib/locker/mfa_locker.dart`
  — Contains `teardownBiometryPasswordOnly` (Phase 5). Confirmed signature:
  ```dart
  Future<void> teardownBiometryPasswordOnly({
    required PasswordCipherFunc passwordCipherFunc,
    required String biometricKeyTag,
  })
  ```
  It calls `_sync` + `_executeWithCleanup`, erases `passwordCipherFunc`, then attempts `_secureProvider.deleteKey` with the suppressed error pattern.

- `/Users/comrade77/Documents/Performix/Projects/mfa_locker/lib/security/security_provider.dart`
  — `SecurityProviderImpl.authenticatePassword({required String password, bool forceNewSalt = false})` returns `PasswordCipherFunc`. This is the factory the repository uses; no `BioCipherFunc` is created for the password-only path.

### Example app layer (all files to be modified)

- **Repository** — `example/lib/features/locker/data/repositories/locker_repository.dart`
  - Abstract `LockerRepository` currently has `disableBiometric({required String password})` as the disable method. The new `disableBiometricPasswordOnly` must be added to both the abstract class and `LockerRepositoryImpl`.
  - `LockerRepositoryImpl` helper `_securityProvider` is a lazy-cached `SecurityProviderImpl` bound to the current `_locker` instance. It is the correct object to call `authenticatePassword` on.
  - `_ensureLockerInstance()` is the guard that all repository methods call first. Task 8.1's implementation follows this exact pattern.
  - `AppConstants.biometricKeyTag` (`'mfa_demo_bio_key'`) is passed as the `biometricKeyTag` argument.

- **BLoC event** — `example/lib/features/locker/bloc/locker_event.dart`
  - Freezed `sealed` class, `part of 'locker_bloc.dart'`. The new event factory follows the same pattern as the existing `disableBiometricRequested`:
    ```dart
    const factory LockerEvent.disableBiometricPasswordOnlyRequested({
      required String password,
    }) = _DisableBiometricPasswordOnlyRequested;
    ```
  - Generated private class name: `_DisableBiometricPasswordOnlyRequested`.

- **BLoC** — `example/lib/features/locker/bloc/locker_bloc.dart`
  - All 25 existing event handlers are registered in the constructor. The new registration must be appended.
  - `_handleVaultOperation` signature confirmed:
    ```dart
    Future<void> _handleVaultOperation({
      required Future<void> Function() operation,
      FutureOr<void> Function(Object error)? onError,
      void Function(Object error)? onDecryptFailed,
      String? operationDescription,
    })
    ```
    Catches `DecryptFailedException` for `onDecryptFailed`, all others for `onError`.
  - `_handleDecryptFailure(emit, action)` — resets `loadState` to `none`, emits the action.
  - `_handleGenericFailure(emit, action)` — identical shape to `_handleDecryptFailure`.
  - `_refreshBiometricState(emit, {bool resetLoadState = false})` — confirmed signature with named `resetLoadState` parameter. Delegates to `_determineBiometricStateAndEmit`. Calling it with `resetLoadState: true` emits `loadState: none` as part of the biometric state update.
  - `_onEnableBiometricRequested` (task 8.6 insertion point): success path is inside `_handleVaultOperation.operation`:
    ```dart
    await _lockerRepository.enableBiometric(password: event.password);
    await _refreshBiometricState(emit, resetLoadState: true);
    action(const LockerAction.showSuccess(message: 'Biometric authentication enabled'));
    if (!isClosed) { add(LockerEvent.biometricOperationStateChanged(...idle...)); }
    ```
    The `emit(state.copyWith(isBiometricKeyInvalidated: false))` goes immediately after `_refreshBiometricState` and before the `action(showSuccess)` call — or after it; either order is acceptable since the flag clear is independent of the success toast, but placing it right after `_refreshBiometricState` and before `action(showSuccess)` keeps it close to the state refresh.
  - `_onDisableBiometricRequested` — the closest template for the new handler. Key difference: it wraps everything in a `try/finally` that sets `biometricOperationState: awaitingResume`. The new handler must NOT do that — it is password-only, no system biometric dialog, no `biometricOperationState` management.
  - `isBiometricKeyInvalidated` field is confirmed in `LockerState` (Phase 7, task 7.1). Default is `false`.

- **Settings screen** — `example/lib/features/settings/views/settings_screen.dart`
  - `_handleBiometricToggle(bool value)` is an instance method on `_SettingsViewState`.
  - Current disable path (lines 149–152):
    ```dart
    } else {
      lockerBloc.add(
        LockerEvent.disableBiometricRequested(password: result!.password!),
      );
    }
    ```
  - `lockerBloc` is obtained via `context.read<LockerBloc>()` on line 143, after the `await showModalBottomSheet` call.
  - `isBiometricKeyInvalidated` is read from `lockerBloc.state` — synchronous property access on the BLoC's current state snapshot. This is safe because the flag only transitions from `true` → `false` on the success of this very operation, and reading it after the password prompt completes is the correct moment.
  - The `if (!mounted || !result.hasValidPassword)` guard (line 139) runs before `lockerBloc` is read, so `lockerBloc.state` is always safe to access when the routing check runs.
  - The routing block must be inserted inside the `else` branch before the existing `disableBiometricRequested` dispatch, causing an early `return` when invalidated:
    ```dart
    } else {
      if (lockerBloc.state.isBiometricKeyInvalidated) {
        lockerBloc.add(
          LockerEvent.disableBiometricPasswordOnlyRequested(password: result!.password!),
        );
        return;
      }
      lockerBloc.add(
        LockerEvent.disableBiometricRequested(password: result!.password!),
      );
    }
    ```

---

## Current Endpoints and Contracts

### `LockerRepository` interface additions (task 8.1)

```dart
/// Disable biometric authentication using password only.
///
/// Use when the biometric key has been permanently invalidated and the
/// normal [disableBiometric] flow cannot succeed.
Future<void> disableBiometricPasswordOnly({required String password});
```

### `LockerEvent` additions (task 8.2)

```dart
const factory LockerEvent.disableBiometricPasswordOnlyRequested({
  required String password,
}) = _DisableBiometricPasswordOnlyRequested;
```

### Downstream library call (confirmed)

`MFALocker.teardownBiometryPasswordOnly(passwordCipherFunc: ..., biometricKeyTag: AppConstants.biometricKeyTag)`
— `AppConstants.biometricKeyTag` is `'mfa_demo_bio_key'`.

---

## Patterns Used

### Repository method pattern (task 8.1)

Every mutating repository method follows:
1. `await _ensureLockerInstance();`
2. Obtain cipher function(s) from `_securityProvider`.
3. Call the corresponding `_locker.*` method.

`disableBiometricPasswordOnly` follows this pattern but obtains only `passwordCipherFunc` (no `authenticateBiometric()` call).

### Password-only BLoC handler pattern (task 8.4)

The closest template is `_onUnlockPasswordSubmitted` (no `biometricOperationState`, `try/finally`, or `awaitingResume`):
```
emit(state.copyWith(loadState: loading))
await _handleVaultOperation(
  operation: ...,
  onDecryptFailed: _handleDecryptFailure(emit, ...),
  onError: _handleGenericFailure(emit, ...),
  operationDescription: ...,
)
```
`_handleDecryptFailure` and `_handleGenericFailure` both reset `loadState` to `none`. Because `_refreshBiometricState(emit, resetLoadState: true)` is called inside `operation`, there is no need for a manual `loadState: none` reset after the `operation` closure.

### State-mutation emit pattern

Inside `operation` closures, emits always guard with `if (!isClosed)`. The new handler must guard the `isBiometricKeyInvalidated: false` emit similarly.

### Freezed event pattern

`locker_event.dart` is a `part of 'locker_bloc.dart'` file. All event factories use `const factory LockerEvent.xxxx(...) = _Xxxx;`. After modifying this file, `make g` must be run before any code that references `_DisableBiometricPasswordOnlyRequested`.

---

## Phase-Specific Limitations and Risks

### 1. `_onEnableBiometricRequested` `finally` block overrides emit

`_onEnableBiometricRequested` has a `finally` block that always emits:
```dart
emit(state.copyWith(
  loadState: LoadState.none,
  biometricOperationState: BiometricOperationState.awaitingResume,
));
```
This runs after the `try` block including the `operation` closure. The `isBiometricKeyInvalidated: false` emit (task 8.6) is placed inside `operation` — the `finally` block's `copyWith` call does not include `isBiometricKeyInvalidated`, so the cleared flag is preserved across the `finally` emission. No conflict. However, `loadState` is already reset by `_refreshBiometricState(emit, resetLoadState: true)` before the `finally` runs — the `finally` will emit `loadState: none` again (idempotent, no harm).

### 2. `_refreshBiometricState` may fail

`_determineBiometricStateAndEmit` catches all errors internally and only resets `loadState` when `resetLoadState: true`. If the biometric state check fails, `loadState` is reset to `none` but the `isBiometricKeyInvalidated: false` emit (which comes after `_refreshBiometricState`) may or may not be reached depending on implementation. Examining the code: `_determineBiometricStateAndEmit` catches its own errors without rethrowing — `_refreshBiometricState` always returns normally. So `isBiometricKeyInvalidated: false` will always be emitted after `_refreshBiometricState` regardless of whether the biometric state check succeeded.

### 3. `lockerBloc.state` capture timing in `_handleBiometricToggle`

The password prompt is `await showModalBottomSheet`, which is async. When the method resumes after the prompt, `lockerBloc.state.isBiometricKeyInvalidated` is read from the then-current state snapshot. In theory, some other event could change the flag between showing the prompt and reading the state. In practice this is impossible: the flag only changes from `true` to `false` on successful completion of this same operation, and the operation has not started yet. Accepted as zero risk.

### 4. Codegen ordering constraint

Task 8.4 (BLoC handler) references `_DisableBiometricPasswordOnlyRequested` which is generated by `make g`. If 8.4 is attempted before 8.3, the file will not compile. The task ordering in phase-8.md (8.1+8.2 parallel → 8.3 → 8.4 → 8.5+8.6 parallel) must be strictly followed.

### 5. No `biometricOperationState` management — risk of accidental copy from `_onDisableBiometricRequested`

`_onDisableBiometricRequested` is the most visually similar handler but wraps everything in `try/finally` with `biometricOperationState: inProgress` and `awaitingResume`. Copying that pattern into the new handler would incorrectly block auto-lock during a pure password operation. The correct template is `_onUnlockPasswordSubmitted` or `_onChangePasswordSubmitted`.

### 6. `disableBiometric` vs `disableBiometricPasswordOnly` naming consistency

The existing repository method is `disableBiometric` (not `disableBiometricRequested` — that is the event). The new method is `disableBiometricPasswordOnly` — this naming matches the event `disableBiometricPasswordOnlyRequested` and the library method `teardownBiometryPasswordOnly`. Consistent.

---

## New Technical Questions Discovered During Research

None. All implementation decisions are fully specified in the PRD and phase-8.md. The codebase state confirms that all Phase 7 prerequisites are in place:
- `isBiometricKeyInvalidated: bool` is in `LockerState` (line 14 of `locker_state.dart`).
- `biometricKeyInvalidated()` is in `LockerAction` (line 31 of `locker_action.dart`).
- `_canToggleBiometric` in Settings screen allows toggle when `isBiometricKeyInvalidated` is `true` (line 125 of `settings_screen.dart`).
- `MFALocker.teardownBiometryPasswordOnly` is implemented (lines 442–460 of `mfa_locker.dart`).
