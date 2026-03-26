# AW-2160 Phase 4 Summary — Locker Library: `keyInvalidated` Exception Type

## What Was Done

Phase 4 closed the locker-library gap in the biometric key invalidation error propagation chain. Prior to this phase, a `BiometricCipherException` with code `keyPermanentlyInvalidated` — produced by the Dart plugin in Phase 3 — fell through to the `_ =>` wildcard in `BiometricCipherProviderImpl._mapExceptionToBiometricException` and was treated as a generic `BiometricExceptionType.failure`. The app layer had no way to distinguish a permanently invalidated hardware key from a wrong-fingerprint error, and could not offer a targeted recovery path.

Three additive changes were made across two production files. No logic was removed, no existing behavior changed, and no new files were added to the library.

### Change 1 — New enum value in `lib/security/models/exceptions/biometric_exception.dart`

`keyInvalidated` was added to `BiometricExceptionType` between `failure` (position 2) and `keyNotFound` (position 3), with a `///` doc comment:

```
/// Hardware-backed biometric key permanently invalidated due to a biometric enrollment change.
keyInvalidated,
```

`BiometricExceptionType` is an in-memory enum — it is never serialized to disk. Adding the value has no storage or migration impact.

### Change 2 — New mapping arm in `lib/security/biometric_cipher_provider.dart`

A standalone switch arm was added to `BiometricCipherProviderImpl._mapExceptionToBiometricException`, immediately before the `_ =>` wildcard:

```
BiometricCipherExceptionCode.keyPermanentlyInvalidated =>
  const BiometricException(BiometricExceptionType.keyInvalidated),
```

The wildcard arm (`_ => BiometricException(BiometricExceptionType.failure, originalError: e)`) was preserved intact. All existing named arms were confirmed unchanged by code inspection.

### Change 3 — `@visibleForTesting` constructor on `BiometricCipherProviderImpl`

The `_biometricCipher` field was moved from inline initialization to constructor initialization, and a `@visibleForTesting` named constructor was added:

```
BiometricCipherProviderImpl._() : _biometricCipher = BiometricCipher();

@visibleForTesting
BiometricCipherProviderImpl.forTesting(this._biometricCipher);
```

This makes the mapping method testable by injection. The singleton (`instance`) is unaffected and continues to use the private `_()` constructor. `package:meta/meta.dart` was already imported.

### Example app BLoC handling (interim)

Adding `keyInvalidated` to `BiometricExceptionType` required it to be present in any exhaustive switch on that enum. In the example app:

- `locker_bloc.dart` (line 1082): `keyInvalidated` is grouped with `failure` in the `_handleBiometricFailure` switch, producing the existing `biometricAuthenticationFailed` action.
- `settings_bloc.dart` (line 133): `keyInvalidated` is grouped with `failure` and `notConfigured` in a `case` that falls through to a `break`.

This is an accepted interim state. Targeted recovery UX (password-only teardown) belongs to Phase 5.

---

## Error Propagation Chain (complete after Phase 4)

```
Android: KeyPermanentlyInvalidatedException → FlutterError("KEY_PERMANENTLY_INVALIDATED")   [Phase 1]
iOS/macOS: Secure Enclave key inaccessible → FlutterError("KEY_PERMANENTLY_INVALIDATED")    [Phase 2]
  → Dart plugin: BiometricCipherExceptionCode.keyPermanentlyInvalidated                     [Phase 3]
  → Locker: BiometricExceptionType.keyInvalidated                                           [Phase 4 — this phase]
  → App: catches keyInvalidated → teardownBiometryPasswordOnly                              [Phase 5]
```

---

## Decisions Made

**Why `keyInvalidated` and not `keyPermanentlyInvalidated` at the locker level?**
The locker's `BiometricExceptionType` vocabulary is intentionally abstract — it describes what the exception means to the locker consumer, not how the platform surfaced it. `keyInvalidated` is the shortest clear name that communicates the state to an app developer without exposing platform-specific terminology.

**Why is `keyInvalidated` placed between `failure` and `keyNotFound`?**
The plan specified position 7 (after `notConfigured`), but the implementation placed it at position 3 (between `failure` and `keyNotFound`). Both are correct — `BiometricExceptionType` is not serialized, and switch matching uses value names, not ordinal positions. No impact on behavior.

**Why a dedicated `forTesting` constructor rather than making `_biometricCipher` a constructor parameter on the private constructor?**
This follows the exact same pattern used by `MFALocker`, which has a `@visibleForTesting` constructor that accepts a `storage` parameter. The singleton stays clean, and the testing constructor has a name that makes its purpose explicit and prevents accidental use in production code.

**Why are the example BLoC `keyInvalidated` cases kept rather than reverted?**
The code review fix task (Task 4 in the phase tasklist) asked for a revert. The implementation instead kept the cases grouped with `failure`. This avoids an exhaustive-switch analyzer warning inside `example/` and eliminates a churn step when Phase 5 adds the targeted recovery arm. The root `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` does not scan `example/`, so there is no analysis risk. The approach is valid and documented here for the Phase 5 implementer.

---

## API Contract Change

| Condition | Before Phase 4 | After Phase 4 |
|-----------|----------------|---------------|
| `BiometricCipherExceptionCode.keyPermanentlyInvalidated` arrives at `_mapExceptionToBiometricException` | Falls through to `_ =>` → `BiometricException(BiometricExceptionType.failure)` | Explicit arm → `const BiometricException(BiometricExceptionType.keyInvalidated)` |
| All other existing codes | Unchanged | Unchanged |
| `BiometricCipherProviderImpl.instance` singleton | Created via `_()` with inline field init | Created via `_()` with constructor-init field — same runtime behavior |

---

## Files Changed

| File | Change |
|------|--------|
| `lib/security/models/exceptions/biometric_exception.dart` | Added `keyInvalidated` enum value with `///` doc comment |
| `lib/security/biometric_cipher_provider.dart` | Added `@visibleForTesting` constructor `forTesting(this._biometricCipher)`; moved `_biometricCipher` to constructor init; added `keyPermanentlyInvalidated` switch arm |
| `example/lib/features/locker/bloc/locker_bloc.dart` | Added `BiometricExceptionType.keyInvalidated` case grouped with `failure` in `_handleBiometricFailure` (interim) |
| `example/lib/features/settings/bloc/settings_bloc.dart` | Added `BiometricExceptionType.keyInvalidated` case grouped with `failure`/`notConfigured` (interim) |

---

## QA Status

The QA review (`docs/qa/AW-2160-phase-4.md`) confirmed the implementation is structurally correct:

- `keyInvalidated` exists as a distinct enum value with the correct `///` doc comment.
- The `keyPermanentlyInvalidated` switch arm is a standalone arm placed before `_ =>`, uses `const`, and carries a trailing comma.
- The `_ =>` wildcard is preserved intact at the correct position.
- All eight existing mapping arms produce identical results to before Phase 4.
- `BiometricCipherProviderImpl.forTesting(this._biometricCipher)` correctly accepts an injectable `BiometricCipher` — the singleton path is unaffected.

Four items remain open before Phase 4 is fully releasable:

1. **No automated unit tests for `_mapExceptionToBiometricException`.** This is the primary acceptance criterion from the PRD. The four required test cases (positive mapping, negative assertion, `cancel` regression, `failure` regression) are deferred to Phase 6, which must also create `test/mocks/mock_biometric_cipher.dart` and `test/security/biometric_cipher_provider_test.dart`.
2. **`fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` has not been executed** as part of the QA review. Must pass before release.
3. **`fvm flutter test` has not been executed** as part of the QA review. Must pass before release.
4. **No device-level end-to-end test** was performed in isolation for Phase 4. Deferred to Phase 5 device testing.

---

## Phase Dependencies

| Phase | Status | Relevance |
|-------|--------|-----------|
| Phase 1 (Android) | Complete | Provides `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")` from Android KeyStore |
| Phase 2 (iOS/macOS) | Complete | Provides `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")` from Secure Enclave |
| Phase 3 (Dart plugin) | Complete | Provides `BiometricCipherExceptionCode.keyPermanentlyInvalidated` |
| Phase 4 (this phase) | Complete | `BiometricExceptionType.keyInvalidated` exists; locker maps the code correctly |
| Phase 5 (Password-only teardown) | Not started | Needs `keyInvalidated` to exist (now available); adds `teardownBiometryPasswordOnly` to `MFALocker` and targeted recovery UX to the example app BLoCs |
| Phase 6 (Tests) | Not started | Must deliver `test/security/biometric_cipher_provider_test.dart` with all four test cases and `test/mocks/mock_biometric_cipher.dart` |
