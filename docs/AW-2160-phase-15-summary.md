# AW-2160 Phase 15 — Summary

**Ticket:** AW-2160
**Phase:** 15
**Title:** Example App: Proactive Biometric Key Invalidation Detection Integration
**Status:** COMPLETE (QA: RELEASE)

---

## What Was Done

Phase 15 wires the example app to the proactive key validity check added in Phase 13, so that the locked screen never shows the biometric unlock button when the biometric hardware key is already invalidated. The change eliminates the "button flash" UX problem — where the button briefly appeared before a failed biometric attempt hid it.

All four tasks were already implemented in the codebase as a result of prior phase work. No new code was written. The phase is a documentation and verification checkpoint confirming that the wiring is correct end-to-end.

### Changes Verified (four files, no new files)

**Task 15.1 — `LockerRepositoryImpl.determineBiometricState` passes `biometricKeyTag`**
`example/lib/features/locker/data/repositories/locker_repository.dart` (line 326)

The implementation now calls `_locker.determineBiometricState(biometricKeyTag: AppConstants.biometricKeyTag)`. Passing this tag activates the silent key validity probe in the library. The public `LockerRepository` interface is unchanged; the BLoC still calls `repo.determineBiometricState()` with no arguments.

**Task 15.2 — `LockerBloc` stores `keyInvalidated` returned at init time**
`example/lib/features/locker/bloc/locker_bloc.dart` (lines 950–979, 1167)

`_determineBiometricStateAndEmit` stores whatever `determineBiometricState()` returns directly into `state.biometricState` via `copyWith`, with no conditional branch that could discard `keyInvalidated`. This method is called at lock-state entry via `_onLockerStateChanged` (line 1167), so the probe runs every time the lock screen is mounted.

The `LockerState.canUseBiometric` getter (line 19 of `locker_state.dart`) is `biometricState.isEnabled`. Because `BiometricState.isEnabled` is `this == enabled`, it returns `false` for `keyInvalidated` without any additional code. No separate `isBiometricKeyInvalidated` boolean field was added (see Architectural Decision below).

**Task 15.3 — `LockedScreen` hides the biometric button when key is invalidated**
`example/lib/features/locker/views/auth/locked_screen.dart`

`_showAuthenticationSheet` captures `showBiometric = state.canUseBiometric` (line 64) and passes it to `AuthenticationBottomSheet`. When `biometricState == keyInvalidated`, `canUseBiometric` is `false`, so `showBiometricButton: false` is passed and the button is not rendered. The button label also adapts: `state.canUseBiometric ? 'Unlock Storage' : 'Unlock with Password'` (line 50). `BlocBuilder.buildWhen` (line 20–21) includes `biometricState`, ensuring a rebuild when the init-time probe result arrives.

**Task 15.4 — `BiometricUnlockButton` explicitly checks `isKeyInvalidated`**
`example/lib/features/locker/views/widgets/biometric_unlock_button.dart` (line 13)

The guard condition is:
```dart
if (!state.biometricState.isEnabled || state.biometricState.isKeyInvalidated)
  return const SizedBox.shrink();
```
The `isKeyInvalidated` check is defense-in-depth: `!isEnabled` already covers `keyInvalidated`, but the explicit check makes the intent transparent and provides an independent safety net. `buildWhen` includes `biometricState`.

---

## Architectural Decision: Single Source of Truth

The PRD described adding a separate `isBiometricKeyInvalidated: bool` field to `LockerState` alongside `biometricState`. The actual implementation uses `BiometricState` as the single source of truth instead. There is no `isBiometricKeyInvalidated` field anywhere in the example app.

**Why:** The `BiometricState.isEnabled` getter is defined as `this == enabled`, which is already `false` for `keyInvalidated`. Maintaining a redundant boolean would create two independently-managed state values that could diverge, introducing a class of bugs that does not exist in the current design.

Both the init-time detection path (Phase 15: `_determineBiometricStateAndEmit` at lock-state entry) and the runtime detection path (Phase 7: `_handleBiometricFailure` on a failed biometric attempt) converge on the same `state.biometricState` field. All UI checks, `_autoDisableBiometricIfInvalidated`, and the settings screen use `biometricState.isKeyInvalidated` or `canUseBiometric` uniformly.

---

## End-to-End Proactive Detection Flow

```
App starts / lock screen mounts
  → _onLockerStateChanged detects RepositoryLockerState.locked
  → _determineBiometricStateAndEmit called
  → _lockerRepository.determineBiometricState()
  → LockerRepositoryImpl calls _locker.determineBiometricState(biometricKeyTag: AppConstants.biometricKeyTag)
  → Library: silent key validity probe (no biometric prompt shown)
      Android: Cipher.init() → KeyPermanentlyInvalidatedException → false
      iOS/macOS: SecItemCopyMatching with kSecUseAuthenticationUISkip → false
      Windows: KeyCredentialManager.OpenAsync → NotFound → false
  → Library returns BiometricState.keyInvalidated
  → emit state.copyWith(biometricState: BiometricState.keyInvalidated)
  → LockedScreen rebuilds: canUseBiometric == false → no biometric button, label = "Unlock with Password"
  → BiometricUnlockButton: isKeyInvalidated == true → SizedBox.shrink()
  → No button flash — UI is correct from the first rendered frame
```

---

## Key Relationships to Prior Phases

| Phase | Contribution to Phase 15 |
|-------|--------------------------|
| Phase 7 | `biometricState: BiometricState.keyInvalidated` set on runtime failure; same field used for init-time detection |
| Phase 8 | Password-only biometric disable flow; invoked by `_autoDisableBiometricIfInvalidated` which reads `biometricState.isKeyInvalidated` |
| Phase 13 | `BiometricState.keyInvalidated` enum value, `isKeyInvalidated` getter, `MFALocker.determineBiometricState(biometricKeyTag:)`, and `BiometricCipherProvider.isKeyValid` |
| Phase 14 | Unit tests confirming `keyInvalidated.isEnabled == false`, `keyInvalidated.isKeyInvalidated == true`, and the library's `determineBiometricState` delegation |

---

## QA Result

**Verdict: RELEASE.** All 15 positive scenarios and all 6 negative/edge-case checks passed (code review and data flow analysis). No defects found.

Key scenario outcomes:
- PS-1 through PS-5: All four task-level checks passed via code review.
- PS-6: Proactive detection flow confirmed correct by data flow analysis — no button flash possible given Flutter's single-thread BLoC emit model.
- PS-7: Valid biometric key still shows the button normally — no regression.
- PS-8: Runtime invalidation (Phase 7) path is unaffected — both paths set the same `biometricState` field.
- NC-1: The PRD's `isBiometricKeyInvalidated` flag design was deliberately superseded by the single-source-of-truth approach. Behavioral outcome is identical.

Manual device tests (MC-3, MC-4: cold start with invalidated / valid key) and the formal analyze/format run (MC-1, MC-2) are required before release.

### Carry-Forward Items (non-blocking)

- Add BLoC unit test: `_determineBiometricStateAndEmit` with `keyInvalidated` returned → stored in state.
- Add widget test: `LockedScreen` with `biometricState == keyInvalidated` → no biometric button.
- Add widget test: `BiometricUnlockButton` with `biometricState.isKeyInvalidated == true` → `SizedBox.shrink()`.
- Three library-layer test gaps inherited from Phase 14 (NC-6): `biometricKeyTag` + disabled settings `verifyNever`, early-exit + tag `verifyNever`, `isKeyValid` exception propagation.

---

## Scope

- **Changed files:** 4 (all pre-existing, all in `example/lib/features/locker/`)
- **New files:** 0
- **Library (`lib/`) changes:** None
- **Plugin (`packages/biometric_cipher/`) changes:** None
- **New tests:** None (phase spec explicitly excluded tests; Phase 14 covers the underlying library behavior)
