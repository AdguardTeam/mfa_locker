# Plan: AW-2160 Phase 15 -- Example App: Proactive Biometric Key Invalidation Detection Integration

Status: PLAN_APPROVED

## Phase Scope

Phase 15 wires the example app to use the proactive `determineBiometricState(biometricKeyTag:)` capability from Phase 13 so that the locked screen hides the biometric button from the first frame when the biometric key is invalidated -- eliminating the "button flash" UX problem.

**Scope:** Pure example app wiring across four files in `example/lib/features/locker/`. No library or plugin code changes. No new files.

**Conclusion: All four tasks are already implemented in the codebase. No code changes are required for this phase.**

---

## Resolved Open Questions

### 1. Should `isBiometricKeyInvalidated` be added as a separate field?

**Decision: No.** Use `biometricState.isKeyInvalidated` directly. The codebase already uses `biometricState` as the single source of truth for key invalidation state. Phase 7 was implemented without a separate `isBiometricKeyInvalidated` boolean field, and the entire example app (settings, biometric unlock button, auto-disable, runtime detection) already works correctly using `biometricState.isKeyInvalidated` directly. Adding a redundant boolean would introduce state duplication and risk divergence.

### 2. Should explicit `!state.biometricState.isKeyInvalidated` checks be added to LockedScreen/BiometricUnlockButton?

**Decision: Skip.** Phase 15 is effectively already complete. The proactive detection flow works end-to-end with no code changes needed:

- `LockedScreen` uses `state.canUseBiometric` (which is `biometricState.isEnabled`, returning `false` for `keyInvalidated`) -- the button is already hidden.
- `BiometricUnlockButton` already checks `state.biometricState.isKeyInvalidated` explicitly.
- Adding a redundant `!state.biometricState.isKeyInvalidated` check to `LockedScreen` would be defense-in-depth against a scenario that cannot occur (since `isEnabled` already returns `false` for `keyInvalidated`).

---

## Dependencies

| Dependency | Status |
|------------|--------|
| Phase 7 -- Example app runtime key invalidation detection | Complete (implemented using `biometricState: BiometricState.keyInvalidated` directly) |
| Phase 8 -- Password-only biometric disable recovery flow | Complete |
| Phase 13 -- `BiometricState.keyInvalidated`, `BiometricCipherProvider.isKeyValid`, `MFALocker.determineBiometricState(biometricKeyTag:)` | Complete |
| Phase 14 -- Unit tests for Phase 13 | Complete |

---

## Components

### Files analyzed (all under `example/lib/features/locker/`)

| File | Task | Status | Evidence |
|------|------|--------|----------|
| `data/repositories/locker_repository.dart` | 15.1 | COMPLETE | Line 326: `_locker.determineBiometricState(biometricKeyTag: AppConstants.biometricKeyTag)` |
| `bloc/locker_bloc.dart` | 15.2 | COMPLETE | `_determineBiometricStateAndEmit` (lines 950-979) stores `BiometricState.keyInvalidated` into `state.biometricState` when returned by `determineBiometricState()`. Called at lock-state entry (line 1167). |
| `bloc/locker_state.dart` | 15.2 | COMPLETE | `canUseBiometric` (line 19) returns `biometricState.isEnabled`, which is `false` for `keyInvalidated`. No separate `isBiometricKeyInvalidated` field needed. |
| `views/auth/locked_screen.dart` | 15.3 | COMPLETE | Line 64 uses `state.canUseBiometric` which returns `false` when `biometricState == keyInvalidated`. `buildWhen` (line 21) includes `biometricState`, ensuring rebuild on state change. |
| `views/widgets/biometric_unlock_button.dart` | 15.4 | COMPLETE | Line 13: `!state.biometricState.isEnabled \|\| state.biometricState.isKeyInvalidated` hides the button. `buildWhen` (line 11) includes `biometricState`. |

---

## Architectural Decision: Single Source of Truth via `biometricState`

The codebase uses the `BiometricState` enum as the single source of truth for biometric key invalidation, rather than maintaining a separate `isBiometricKeyInvalidated` boolean flag as originally planned in Phase 7. This approach:

- **Eliminates state duplication.** One authoritative source (`biometricState`) instead of two potentially-divergent sources.
- **Simplifies state management.** No risk of `isBiometricKeyInvalidated == true` while `biometricState != keyInvalidated` or vice versa.
- **Is already consistently used.** All UI checks, `_autoDisableBiometricIfInvalidated`, runtime detection in `_handleBiometricFailure`, and init-time detection in `_determineBiometricStateAndEmit` all use `biometricState.isKeyInvalidated` or `canUseBiometric` (which delegates to `biometricState.isEnabled`).

---

## Data Flows (all verified as working)

### Flow 1: Proactive key invalidation detection at init

```
App starts / lock screen mounts
  -> _onLockerStateChanged detects RepositoryLockerState.locked (line 1154)
  -> Calls _determineBiometricStateAndEmit (line 1167)
  -> _determineBiometricStateAndEmit calls _lockerRepository.determineBiometricState()
  -> LockerRepositoryImpl calls _locker.determineBiometricState(biometricKeyTag: AppConstants.biometricKeyTag)
  -> Library performs silent key validity probe (no biometric prompt)
  -> Key invalid -> library returns BiometricState.keyInvalidated
  -> _determineBiometricStateAndEmit emits state.copyWith(biometricState: BiometricState.keyInvalidated)
  -> LockedScreen rebuilds (buildWhen includes biometricState)
  -> state.canUseBiometric == false (isEnabled returns false for keyInvalidated)
  -> showBiometric == false -> biometric button NOT shown
  -> BiometricUnlockButton also checks isKeyInvalidated -> SizedBox.shrink()
  -> No button flash -- UI correct from first frame
```

### Flow 2: Runtime invalidation (Phase 7 path, unchanged)

```
User taps biometric unlock
  -> Platform throws keyPermanentlyInvalidated
  -> _handleBiometricFailure keyInvalidated case (line 1082)
  -> emit state.copyWith(biometricState: BiometricState.keyInvalidated)
  -> action(LockerAction.biometricKeyInvalidated())
  -> Biometric button hides via same canUseBiometric / isKeyInvalidated checks
```

### Flow 3: Valid key at init (no regression)

```
App starts / lock screen mounts
  -> determineBiometricState returns BiometricState.enabled
  -> state.canUseBiometric == true, isKeyInvalidated == false
  -> Biometric button shows normally
```

---

## Implementation Steps

**No implementation steps required.** All four tasks are already complete in the codebase:

- **15.1:** Repository already passes `biometricKeyTag: AppConstants.biometricKeyTag`.
- **15.2:** `_determineBiometricStateAndEmit` already stores `keyInvalidated` in `state.biometricState`.
- **15.3:** `LockedScreen` uses `canUseBiometric` which already returns `false` for `keyInvalidated`.
- **15.4:** `BiometricUnlockButton` already checks `state.biometricState.isKeyInvalidated`.

The only remaining step is verification:

### Verification

```bash
cd example && fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .
cd example && fvm dart format . --line-length 120
```

Both must pass with zero errors, warnings, or formatting changes.

---

## NFR

| Requirement | How satisfied |
|-------------|---------------|
| Example app only -- no library changes | All relevant code is in `example/lib/`. No changes to `lib/` or `packages/`. |
| No button flash on init | `biometricState.isKeyInvalidated` is set from `determineBiometricState` before first frame via `_determineBiometricStateAndEmit` |
| No regression on valid biometric keys | `determineBiometricState` returns `enabled` for valid keys; `canUseBiometric == true`; biometric button shows normally |
| No regression on runtime detection | `_handleBiometricFailure` `keyInvalidated` case unchanged; sets same `biometricState` |
| Code style compliance | No code changes needed; existing code already compliant |
| Static analysis passes | To be verified as final step |

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| `canUseBiometric` getter changes in future to not account for `keyInvalidated` | Very low -- getter is `biometricState.isEnabled` which is `this == enabled` | Medium -- would re-introduce button flash | `BiometricUnlockButton` has explicit `isKeyInvalidated` check as safety net |
| `buildWhen` in `LockedScreen` does not fire for init-time state | Very low -- `BlocBuilder` always builds with current state on first build; `buildWhen` includes `biometricState` | Low -- standard BLoC behavior handles this | Verified: `buildWhen` on line 21 includes `previous.biometricState != current.biometricState` |
| Phase considered "not done" despite all goals being satisfied by existing code | Low -- depends on process expectations | Low -- documentation here provides evidence | This plan documents the complete evidence chain for each task |
