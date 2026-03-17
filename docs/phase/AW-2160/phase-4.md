# Phase 4: Locker — `keyInvalidated` exception type

**Goal:** Map the plugin `keyPermanentlyInvalidated` exception code to a locker-level `BiometricExceptionType.keyInvalidated`, so the app layer receives a distinct, actionable error.

## Context

**Feature motivation:** Phases 1–3 wired all native layers and the Dart plugin to surface `BiometricCipherExceptionCode.keyPermanentlyInvalidated`. Phase 4 closes the final gap in the locker layer: without a dedicated `keyInvalidated` type in `BiometricExceptionType`, the locker currently treats permanently-invalidated keys the same as any generic decryption failure. The app layer cannot distinguish them and cannot offer the user a targeted recovery path (password-only teardown in Phase 5).

**Technical approach:** Pure additive change — one new enum value in `BiometricExceptionType` and one new mapping line in `_mapExceptionToBiometricException`. No logic changes, no new files. Follows the exact same pattern used for `failure`, `cancel`, etc.

**Error propagation chain (locker layer):**
```
BiometricCipherExceptionCode.keyPermanentlyInvalidated   <- from biometric_cipher plugin (Phase 3)
  -> _mapExceptionToBiometricException (BiometricCipherProvider)
  -> BiometricExceptionType.keyInvalidated
  -> BiometricException(BiometricExceptionType.keyInvalidated)
  -> App layer (consumer — handles in Phase 5 via teardownBiometryPasswordOnly)
```

**Files affected:**
```
lib/security/models/exceptions/biometric_exception.dart
  # + keyInvalidated enum value

lib/security/biometric_cipher_provider.dart
  # + BiometricCipherExceptionCode.keyPermanentlyInvalidated => const BiometricException(BiometricExceptionType.keyInvalidated)
  # Note: idea doc references providers/biometric_cipher_provider_impl.dart — read actual file path before editing
```

## Tasks

- [x] **4.1** Add `keyInvalidated` to `BiometricExceptionType`
  - File: `lib/security/models/exceptions/biometric_exception.dart`
  - Add enum value (e.g., after `cancel`, before any `unknown`/fallback value)
  - Meaning: hardware key permanently invalidated by biometric enrollment change

- [x] **4.2** Map `keyPermanentlyInvalidated` -> `keyInvalidated` in provider
  - File: `lib/security/biometric_cipher_provider.dart` (verify actual path with ast-index)
  - In `_mapExceptionToBiometricException`: add `BiometricCipherExceptionCode.keyPermanentlyInvalidated => const BiometricException(BiometricExceptionType.keyInvalidated)`

## Acceptance Criteria

**Verify:** `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` + `fvm flutter test`

- `BiometricExceptionType.keyInvalidated` exists and is distinct from `failure` and `cancel`.
- When `BiometricCipherException` with code `keyPermanentlyInvalidated` is passed to `_mapExceptionToBiometricException`, it returns a `BiometricException` with type `keyInvalidated`.
- Generic auth failures (`authenticationError`, `authenticationUserCanceled`) still map to `failure`/`cancel` unchanged — no regressions.

## Dependencies

- Phase 1 complete
- Phase 2 complete
- Phase 3 complete

## Technical Details

### Data model

`BiometricExceptionType` is an in-memory enum — not serialized to disk. Adding `keyInvalidated` has no storage impact.

| Layer | Enum | New Value |
|-------|------|-----------|
| Dart plugin | `BiometricCipherExceptionCode` | `keyPermanentlyInvalidated` (Phase 3) |
| Dart locker | `BiometricExceptionType` | `keyInvalidated` <- this phase |

### Target mapping in `_mapExceptionToBiometricException`

```dart
BiometricException _mapExceptionToBiometricException(BiometricCipherException e) {
  return switch (e.code) {
    BiometricCipherExceptionCode.authenticationError => const BiometricException(BiometricExceptionType.failure),
    BiometricCipherExceptionCode.authenticationUserCanceled => const BiometricException(BiometricExceptionType.cancel),
    // ... existing mappings unchanged ...
    BiometricCipherExceptionCode.keyPermanentlyInvalidated =>
        const BiometricException(BiometricExceptionType.keyInvalidated),  // new
    _ => const BiometricException(BiometricExceptionType.failure),
  };
}
```

> **Note:** The exact mapping style (switch expression vs. if-else) and existing case names may differ. Read the actual file with ast-index before editing to match the existing style.

### Unchanged workflows

- Wrong fingerprint -> `BiometricExceptionType.failure` (must not change)
- User cancels prompt -> `BiometricExceptionType.cancel` (must not change)
- Device lockout -> `BiometricExceptionType.failure` (must not change)

## Implementation Notes

- Read actual file paths via ast-index before editing: `/Applications/ast-index search "BiometricExceptionType"` and `/Applications/ast-index search "_mapExceptionToBiometricException"`.
- The idea doc references `providers/biometric_cipher_provider_impl.dart` while the tasklist references `lib/security/biometric_cipher_provider.dart` — confirm the actual file before editing.
- Two lines of change total across two files. KISS.
- No logging needed for enum mappings — pure transformations.

## Code Review Fixes

- [x] **Task 1: Fix `@visibleForTesting` constructor to accept injectable `BiometricCipher`**
  - The `BiometricCipherProviderImpl.forTesting()` constructor currently takes no parameters. The `_biometricCipher` field is still initialized inline as `BiometricCipher()`, making mock injection impossible.
  - Change `_biometricCipher` from an inline-initialized field to a constructor-initialized field.
  - Update `BiometricCipherProviderImpl._()` to use `: _biometricCipher = BiometricCipher()`.
  - Update `BiometricCipherProviderImpl.forTesting(this._biometricCipher)` to accept a `BiometricCipher` parameter.
  - Acceptance criteria:
    - `BiometricCipherProviderImpl.forTesting(mockBiometricCipher)` compiles and uses the provided instance
    - The existing `instance` singleton still uses `BiometricCipher()` via the private constructor
    - `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` passes

- [ ] **Task 2: Create unit tests for `_mapExceptionToBiometricException` mapping** _(deferred to Iteration 6)_
  - Create `test/mocks/mock_biometric_cipher.dart` with `class MockBiometricCipher extends Mock implements BiometricCipher {}`
  - Create `test/security/biometric_cipher_provider_test.dart` with the following tests:
    - `decrypt()` with mock throwing `BiometricCipherException(code: keyPermanentlyInvalidated)` produces `BiometricException` with `type == BiometricExceptionType.keyInvalidated`
    - Negative assertion: same input does NOT produce `BiometricExceptionType.failure`
    - `authenticationUserCanceled` still produces `BiometricExceptionType.cancel`
    - `authenticationError` still produces `BiometricExceptionType.failure`
  - Acceptance criteria:
    - `test/security/biometric_cipher_provider_test.dart` exists and contains all four test cases
    - `test/mocks/mock_biometric_cipher.dart` exists
    - `fvm flutter test` passes with all new tests green

- [x] **Task 3: Add doc comment to `keyInvalidated` enum value**
  - Add `/// Hardware-backed biometric key permanently invalidated due to a biometric enrollment change.` above `keyInvalidated` in `lib/security/models/exceptions/biometric_exception.dart`
  - Acceptance criteria:
    - `keyInvalidated` has a `///` doc comment explaining its meaning
    - `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` passes

- [x] **Task 4: Example app BLoC changes** — kept (grouped with `failure` temporarily; Phase 5 will replace with proper recovery UX)
  - Remove the `keyInvalidated` case additions from `example/lib/features/locker/bloc/locker_bloc.dart` and `example/lib/features/settings/bloc/settings_bloc.dart`
  - These changes cross phase boundaries and belong in Phase 5, where the targeted recovery UX (teardownBiometryPasswordOnly) will be implemented
  - The root library's `flutter analyze` does not scan `example/`, so this will not cause analysis failures
  - Acceptance criteria:
    - `locker_bloc.dart` and `settings_bloc.dart` do not reference `BiometricExceptionType.keyInvalidated`
    - `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` still passes from root
