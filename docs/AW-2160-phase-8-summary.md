# AW-2160 Phase 8 Summary — Example App: Password-Only Biometric Disable

## What Was Done

Phase 8 closes the biometric key-invalidation recovery loop that Phase 7 opened. Phase 7 wired the detection and display of a permanently invalidated biometric key, but toggling biometrics OFF in Settings still dispatched `disableBiometricRequested` — a path that creates a `BioCipherFunc` and triggers a biometric system dialog that will always fail on an invalidated key. Phase 8 fixes that: when the `isBiometricKeyInvalidated` flag is `true`, the toggle-off flow now routes to a new `disableBiometricPasswordOnlyRequested` event, the repository calls `MFALocker.teardownBiometryPasswordOnly` with password-only authentication, and on success the `isBiometricKeyInvalidated` flag is cleared. A safety clear is also added to the successful biometric re-enable path.

All changes are scoped to the example app (`example/lib/`). No library files under `lib/` or `packages/` were modified.

---

## Files Changed

All files are under `example/lib/`.

| File | Task | Change |
|------|------|--------|
| `features/locker/data/repositories/locker_repository.dart` | 8.1 | Added `disableBiometricPasswordOnly({required String password})` to `LockerRepository` interface and `LockerRepositoryImpl` |
| `features/locker/bloc/locker_event.dart` | 8.2 | Added `LockerEvent.disableBiometricPasswordOnlyRequested({required String password})` Freezed factory |
| (codegen) | 8.3 | `make g` regenerated `.freezed.dart` files for the updated event class |
| `features/locker/bloc/locker_bloc.dart` | 8.4 | Registered and implemented `_onDisableBiometricPasswordOnlyRequested` handler |
| `features/locker/bloc/locker_bloc.dart` | 8.6 | Added `emit(state.copyWith(isBiometricKeyInvalidated: false))` in `_onEnableBiometricRequested` success path |
| `features/settings/views/settings_screen.dart` | 8.5 | Added routing check in `_handleBiometricToggle` to dispatch `disableBiometricPasswordOnlyRequested` when `isBiometricKeyInvalidated` is `true` |

Zero new files were created. All changes are additive modifications to existing files.

---

## What Was Added

### Task 8.1 — `disableBiometricPasswordOnly` repository method

Added to the `LockerRepository` abstract interface and implemented in `LockerRepositoryImpl`. The method:
1. Calls `_ensureLockerInstance()`.
2. Calls `_securityProvider.authenticatePassword(password: password)` to obtain a `PasswordCipherFunc`.
3. Calls `_locker.teardownBiometryPasswordOnly(passwordCipherFunc: ..., biometricKeyTag: AppConstants.biometricKeyTag)`.

No `BioCipherFunc` is created. No `_securityProvider.authenticateBiometric()` is called. No system biometric dialog fires. This is the critical correctness property of Phase 8.

### Task 8.2 — `disableBiometricPasswordOnlyRequested` Freezed event

A new `const factory LockerEvent.disableBiometricPasswordOnlyRequested({required String password})` Freezed factory, placed after `disableBiometricRequested` in `locker_event.dart`. The generated private class `_DisableBiometricPasswordOnlyRequested` is the type used in the BLoC handler registration and implementation.

### Task 8.3 — Code generation

`make g` was run after tasks 8.1 and 8.2. This regenerated the `.freezed.dart` files so that `_DisableBiometricPasswordOnlyRequested` is available as a concrete class for the BLoC to reference in task 8.4.

### Task 8.4 — `_onDisableBiometricPasswordOnlyRequested` BLoC handler

Registered in the constructor as `on<_DisableBiometricPasswordOnlyRequested>(_onDisableBiometricPasswordOnlyRequested)`, positioned after the existing `_onDisableBiometricRequested` registration.

The handler follows the **password-only pattern** (same as `_onUnlockPasswordSubmitted`), not the biometric operation pattern. Key behavioral properties:

- Emits `state.copyWith(loadState: LoadState.loading)` immediately — the loading overlay appears on the Settings screen.
- Calls `_handleVaultOperation` with no `try/finally` wrapper and **no `biometricOperationState` management**. This is intentional: the password-only path must not block the auto-lock timer.
- Inside `operation`: calls `repo.disableBiometricPasswordOnly`, then `_refreshBiometricState(emit, resetLoadState: true)` (which sets `loadState` back to `none`), then guards `!isClosed` before emitting `state.copyWith(isBiometricKeyInvalidated: false)`, then emits `LockerAction.showSuccess(message: 'Biometric authentication disabled')`.
- `onDecryptFailed` maps to `'Incorrect password: $error'` — a specific message distinguishable from a generic failure.
- `onError` maps to `'Failed to disable biometric: $error'` for unexpected errors.
- `operationDescription` is `'disable biometric (password-only)'`.

Contrast with `_onDisableBiometricRequested`, which sets `biometricOperationState: inProgress` and uses a `try/finally` to ensure the state resets after the biometric dialog. The password-only handler deliberately omits all of that.

### Task 8.5 — Settings toggle routing

In `SettingsScreen._handleBiometricToggle`, inside the `else` branch (disable path, `value == false`), a new routing check was added before the existing `disableBiometricRequested` dispatch:

```dart
if (lockerBloc.state.isBiometricKeyInvalidated) {
  lockerBloc.add(
    LockerEvent.disableBiometricPasswordOnlyRequested(password: result!.password!),
  );
  return;
}
```

When the flag is `true`, the new event is dispatched and the method returns early. When the flag is `false`, execution falls through to the original `disableBiometricRequested` dispatch unchanged. The normal disable flow is not affected (no regression).

The state is read synchronously from `lockerBloc.state` after the async password prompt has completed. This is safe because `isBiometricKeyInvalidated` can only transition `true → false` by completing the very operation being set up — no concurrent path can clear it while the password bottom sheet is open.

### Task 8.6 — Clear `isBiometricKeyInvalidated` on successful biometric re-enable

In `_onEnableBiometricRequested`, inside the `_handleVaultOperation.operation` closure, after `await _refreshBiometricState(emit, resetLoadState: true)` and guarded by `if (!isClosed)`:

```dart
emit(state.copyWith(isBiometricKeyInvalidated: false));
```

This is an idempotent safety measure. After a successful password-only disable (task 8.4), the flag is already `false` when the re-enable runs. The emit ensures the flag is cleared even if unusual session state somehow left it `true`. The `finally` block of `_onEnableBiometricRequested` only sets `loadState` and `biometricOperationState` — it does not touch `isBiometricKeyInvalidated` — so the cleared value is preserved.

---

## Decisions Made

**Password-only pattern, not biometric operation pattern.** The new handler was modelled after `_onUnlockPasswordSubmitted`, not `_onDisableBiometricRequested`. The biometric operation pattern (`biometricOperationState: inProgress` in a `try/finally`) exists to block the auto-lock timer while a system biometric dialog is open. A password-only operation has no system dialog, so there is nothing to block for. Using the biometric pattern would prevent the auto-lock timer from running during the password-only disable — an incorrect side effect.

**`_refreshBiometricState(emit, resetLoadState: true)` resets `loadState` to `none`.** The handler does not manually reset `loadState` after the operation closure. The `resetLoadState: true` flag in `_refreshBiometricState` handles this as part of the state refresh. This matches the pattern used throughout the BLoC for password-only operations.

**Routing check reads state after the async password prompt.** The flag `isBiometricKeyInvalidated` is read from `lockerBloc.state` after `await showModalBottomSheet` returns. There is a theoretical question of whether the flag could change during the modal. In practice, the flag can only transition `true → false` by a successful completion of this same operation, which cannot happen while the bottom sheet is open. The timing is safe.

**`isBiometricKeyInvalidated: false` emit in the re-enable handler is idempotent.** After password-only disable clears the flag (task 8.4), a successful re-enable will always find the flag already `false`. The emit still runs unconditionally (guarded only by `!isClosed`) as a defensive property.

**Phase 7 reservation resolved.** Phase 7 QA (NC-2) noted that the Settings toggle dispatched `disableBiometricRequested` unconditionally for the `value == false` path, even when `isBiometricKeyInvalidated` was `true`. Phase 8 task 8.5 resolves this completely.

---

## `isBiometricKeyInvalidated` Flag Lifecycle (complete picture)

| Event | Effect | Phase |
|-------|--------|-------|
| Biometric operation returns `BiometricExceptionType.keyInvalidated` | Flag set to `true` | Phase 7, `_handleBiometricFailure` |
| Storage erase (`_onEraseStorageRequested`) succeeds | Flag cleared to `false` | Phase 7, task 7.9 |
| Password-only disable (`_onDisableBiometricPasswordOnlyRequested`) succeeds | Flag cleared to `false` | Phase 8, task 8.4 |
| Biometric re-enable (`_onEnableBiometricRequested`) succeeds | Flag cleared to `false` (idempotent) | Phase 8, task 8.6 |

The flag is in-memory only. It is not persisted. It resets to `false` on every cold launch.

---

## Recovery Workflow (User-Visible)

```
User changes biometrics in device settings (e.g., new fingerprint enrolled)
  -> Phase 7: biometric prompt returns keyPermanentlyInvalidated
  -> isBiometricKeyInvalidated = true
  -> Auth sheet shows inline "Biometrics have changed. Please use your password."
  -> User enters password, vault unlocks
  -> User navigates to Settings
  -> Biometric tile shows "Biometrics changed. Disable and re-enable to use new biometrics." in error color
  -> Toggle is ON and enabled
  -> User toggles biometric OFF -> password prompt appears
  -> User enters password
  -> isBiometricKeyInvalidated is true -> disableBiometricPasswordOnlyRequested dispatched
  -> teardownBiometryPasswordOnly runs (no biometric prompt)
  -> Origin.bio wrap removed from storage, key deletion attempted (errors suppressed)
  -> isBiometricKeyInvalidated = false
  -> Settings returns to normal state (toggle OFF, no error color)
  -> User toggles biometric ON -> password + biometric prompts
  -> Fresh biometric key created, biometric re-enabled with new enrollment
```

---

## Error Handling

| Error | Handler | User sees |
|-------|---------|-----------|
| Wrong password | `onDecryptFailed` → `_handleDecryptFailure` | `'Incorrect password: ...'` snackbar; `isBiometricKeyInvalidated` remains `true`; user can retry |
| Generic I/O or storage failure | `onError` → `_handleGenericFailure` | `'Failed to disable biometric: ...'` snackbar; `isBiometricKeyInvalidated` remains `true`; user can retry |
| BLoC closed during operation | `!isClosed` guard on flag-clear emit | Flag clear is silently skipped; no crash |

---

## Open Issues Carried Forward

**No end-to-end device test has been executed for Phase 8 (or any prior phase of AW-2160).** The full pipeline from the native `keyPermanentlyInvalidated` signal, through all Dart layers, to the password-only disable in the example app has never been exercised on a real device or simulator. Device-level testing (MC-4 and MC-5 in the QA plan) is mandatory before the complete AW-2160 feature reaches production.

**No automated tests for example app code.** All Phase 8 changes are verified by code review and static analysis only. The example app has no test suite in this repository.

**Full AW-2160 end-to-end smoke test not yet performed.** Phase 8 is the last implementation phase. Before communicating the feature as production-ready, a single continuous test run covering Phases 1–8 (native exception → Dart mapping → library → example app detection → password-only disable → re-enable) must be executed on a device.

---

## How Phase 8 Fits in the Full AW-2160 Flow

```
Android: KeyPermanentlyInvalidatedException → FlutterError("KEY_PERMANENTLY_INVALIDATED")   [Phase 1]
iOS/macOS: Secure Enclave key inaccessible → FlutterError("KEY_PERMANENTLY_INVALIDATED")    [Phase 2]
  -> Dart plugin: BiometricCipherExceptionCode.keyPermanentlyInvalidated                    [Phase 3]
  -> Locker: BiometricExceptionType.keyInvalidated                                          [Phase 4]
  -> MFALocker.teardownBiometryPasswordOnly available for cleanup                           [Phase 5]
  -> Unit tests for Phases 3-5 Dart layer                                                   [Phase 6]
  -> Example app detects keyInvalidated:                                                    [Phase 7]
      -> isBiometricKeyInvalidated flag set; auth sheet inline error; biometric button hidden
      -> Settings tile shows error description; toggle remains enabled
  -> Example app password-only disable flow:                                                [Phase 8]
      -> disableBiometricPasswordOnlyRequested event + LockerRepository method
      -> _onDisableBiometricPasswordOnlyRequested handler (no biometric prompt)
      -> isBiometricKeyInvalidated cleared on success
      -> idempotent flag clear on successful re-enable
```

---

## Phase Dependencies

| Phase | Status | Relevance |
|-------|--------|-----------|
| Phase 1 (Android native) | Complete | Emits `"KEY_PERMANENTLY_INVALIDATED"` from Android KeyStore |
| Phase 2 (iOS/macOS native) | Complete | Emits `"KEY_PERMANENTLY_INVALIDATED"` from Secure Enclave |
| Phase 3 (Dart plugin) | Complete | `BiometricCipherExceptionCode.keyPermanentlyInvalidated` |
| Phase 4 (Locker library) | Complete | `BiometricExceptionType.keyInvalidated`; provider mapping |
| Phase 5 (Locker library) | Complete | `teardownBiometryPasswordOnly` on `Locker` and `MFALocker` |
| Phase 6 (Unit tests) | Complete | Unit tests for Dart-layer additions from Phases 3–5 |
| Phase 7 (Example app detection) | Complete | `isBiometricKeyInvalidated` flag, UI feedback, Settings toggle enabled |
| Phase 8 (this phase) | Complete | Password-only disable flow; flag cleared on success and on re-enable |
