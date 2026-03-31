# AW-2160-4: Locker Layer — Map `keyPermanentlyInvalidated` to `BiometricExceptionType.keyInvalidated`

Status: PRD_READY

## Context / Idea

This is Phase 4 of AW-2160, which as a whole adds biometric key invalidation detection and a password-only teardown path across the full stack (Android, iOS/macOS native, Dart plugin, and locker library).

**Phase dependency:** Phases 1–3 are all complete:
- Phase 1: Android emits `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")` when `KeyPermanentlyInvalidatedException` is caught.
- Phase 2: iOS/macOS emits `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")` when the Secure Enclave key is inaccessible.
- Phase 3: The Dart plugin maps `'KEY_PERMANENTLY_INVALIDATED'` → `BiometricCipherExceptionCode.keyPermanentlyInvalidated`.

**The problem:** The locker library currently has no entry for `keyPermanentlyInvalidated` in `_mapExceptionToBiometricException`. When a `BiometricCipherException` with code `keyPermanentlyInvalidated` arrives from the plugin, it falls through to the default `_` branch and is treated as a generic `BiometricExceptionType.failure`. The app layer cannot distinguish permanent key invalidation from a wrong-fingerprint error, and therefore cannot offer the user a targeted recovery path (password-only teardown, implemented in Phase 5).

**Current state of the target files:**

```
lib/security/models/exceptions/biometric_exception.dart   — BiometricExceptionType enum
lib/security/biometric_cipher_provider.dart               — _mapExceptionToBiometricException (verify actual path)
```

**Error propagation chain (this phase closes the locker layer gap):**

```
BiometricCipherException(code: keyPermanentlyInvalidated)   ← from biometric_cipher plugin (Phase 3)
  → _mapExceptionToBiometricException (BiometricCipherProvider)
  → BiometricExceptionType.keyInvalidated                   (new — this phase)
  → BiometricException(BiometricExceptionType.keyInvalidated)
  → App layer (consumer — handles in Phase 5 via teardownBiometryPasswordOnly)
```

**Scope:** Two files, two additive lines. No logic changes, no new files. Pure additive change following the same pattern used for `failure`, `cancel`, and other existing `BiometricExceptionType` values.

---

## Goals

1. Add `keyInvalidated` as a named enum value to `BiometricExceptionType` in `lib/security/models/exceptions/biometric_exception.dart`, with a doc comment describing its meaning (hardware key permanently invalidated by biometric enrollment change).
2. Add a mapping entry in `_mapExceptionToBiometricException` so that `BiometricCipherExceptionCode.keyPermanentlyInvalidated` maps to `const BiometricException(BiometricExceptionType.keyInvalidated)`.
3. Keep the default `_` fallback intact — unrecognised codes continue to produce `BiometricExceptionType.failure`.
4. Maintain full backward compatibility: all existing mappings (`authenticationError` → `failure`/`cancel`, etc.) must produce exactly the same results as before.

---

## User Stories

**US-1 — App layer receives a typed `keyInvalidated` exception**
As the app layer consuming `MFALocker`, I need `BiometricException.type` to equal `BiometricExceptionType.keyInvalidated` (not `failure`) when the biometric hardware key has been permanently invalidated, so that I can present a targeted recovery UX (Phase 5) rather than a generic error message.

**US-2 — Existing error mappings are unaffected**
As any existing caller that handles `BiometricException.type`, I need `failure` and `cancel` to continue being produced for wrong-fingerprint, lockout, and user-cancel scenarios, so that no existing error-handling path is broken.

**US-3 — Default fallback preserved**
As a locker consumer, I need unrecognised `BiometricCipherExceptionCode` values to continue producing `BiometricExceptionType.failure`, so that future unknown codes are handled gracefully without crashing.

---

## Main Scenarios

### Scenario 1: Android key permanently invalidated — locker emits `keyInvalidated`

1. Android detects `KeyPermanentlyInvalidatedException` and emits `"KEY_PERMANENTLY_INVALIDATED"` (Phase 1).
2. The Dart plugin maps it to `BiometricCipherExceptionCode.keyPermanentlyInvalidated` (Phase 3).
3. The locker's `_mapExceptionToBiometricException` receives `BiometricCipherException(code: keyPermanentlyInvalidated)`.
4. After this phase: returns `BiometricException(BiometricExceptionType.keyInvalidated)`.
5. Before this phase: falls through to `_ => BiometricException(BiometricExceptionType.failure)`.

### Scenario 2: iOS/macOS Secure Enclave key permanently invalidated — locker emits `keyInvalidated`

1. iOS/macOS detects biometric invalidation and emits `"KEY_PERMANENTLY_INVALIDATED"` (Phase 2).
2. Same Dart plugin mapping (Phase 3) and same locker mapping path as Scenario 1.
3. App layer receives `BiometricException(BiometricExceptionType.keyInvalidated)`.

### Scenario 3: Wrong fingerprint — `failure` unchanged

1. User presents wrong fingerprint; platform emits `authenticationError`.
2. `_mapExceptionToBiometricException` maps to `BiometricExceptionType.failure` as before.
3. No regression.

### Scenario 4: User cancels biometric prompt — `cancel` unchanged

1. User cancels the biometric prompt; platform emits `authenticationUserCanceled`.
2. `_mapExceptionToBiometricException` maps to `BiometricExceptionType.cancel` as before.
3. No regression.

### Scenario 5: Device lockout — `failure` unchanged

1. Device is locked out after too many attempts.
2. `_mapExceptionToBiometricException` maps to `BiometricExceptionType.failure` as before.
3. No regression.

---

## Success / Metrics

| Criterion | How to verify |
|-----------|--------------|
| `BiometricExceptionType.keyInvalidated` exists as a distinct enum value | Code review / compile check |
| `_mapExceptionToBiometricException` with code `keyPermanentlyInvalidated` returns `BiometricException(BiometricExceptionType.keyInvalidated)` | Dart unit test |
| `_mapExceptionToBiometricException` with code `keyPermanentlyInvalidated` does **not** return `BiometricException(BiometricExceptionType.failure)` | Same unit test — negative assertion |
| All existing mappings (`authenticationError`, `authenticationUserCanceled`, etc.) produce the same result as before | Existing tests pass without modification |
| Root library analysis passes | `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` exits 0 |
| All tests pass | `fvm flutter test` exits 0 |

---

## Constraints and Assumptions

- **Two files only:** `lib/security/models/exceptions/biometric_exception.dart` and the file containing `_mapExceptionToBiometricException` (confirm actual path with ast-index before editing — the idea doc references `providers/biometric_cipher_provider_impl.dart` while the task list references `lib/security/biometric_cipher_provider.dart`).
- **Two lines of change total:** one new enum value in `BiometricExceptionType` and one new case in the mapping switch/if-else.
- **Enum placement:** `keyInvalidated` should be placed logically near other auth-failure-related values (e.g., after `cancel`), following the existing ordering convention. Exact position is determined by reading the actual file.
- **No serialization impact:** `BiometricExceptionType` is an in-memory enum never written to disk. Adding a value requires no migration.
- **No interface changes:** Adding `keyInvalidated` to a Dart enum used in a `switch` expression may require updating exhaustive switch consumers — `fvm flutter analyze` will surface any such breakage immediately.
- **Style match:** New enum value gets a doc comment consistent with adjacent values. New switch case uses the same pattern (`const BiometricException(BiometricExceptionType.keyInvalidated)`) as adjacent cases. Read the actual file before editing to confirm switch style (expression vs. statement).
- **Default fallback preserved:** The `_ => const BiometricException(BiometricExceptionType.failure)` fallback must remain intact.
- Phases 1, 2, and 3 are confirmed complete.

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Adding `keyInvalidated` to `BiometricExceptionType` breaks an exhaustive `switch` on that enum elsewhere in the codebase | Low-Medium — Dart exhaustive switches on enums will fail to compile or produce analyzer warnings | Medium — must be fixed before merge | `fvm flutter analyze` surfaces this immediately; fix any exhaustive switch by adding the new case |
| Actual file path for `_mapExceptionToBiometricException` differs from both the idea doc and task list references | Low — two plausible paths cited; one is correct | Low — easy to confirm with ast-index | Run `/Applications/ast-index search "_mapExceptionToBiometricException"` before editing |
| Mapping style (switch expression vs. if-else) differs from what the PRD assumes | Low | Low — purely cosmetic; follow actual file style | Read the actual file before editing |
| `BiometricCipherExceptionCode.keyPermanentlyInvalidated` enum value name mismatch (e.g., camelCase vs. snake_case) | Very low — Phase 3 is complete and the value name is confirmed | High if it occurs | Confirm by reading `biometric_cipher_exception_code.dart` before editing |

---

## Open Questions

None. The scope is fully defined by the Phase 4 description, the error propagation chain established by Phases 1–3, and the existing patterns in `BiometricExceptionType` and `_mapExceptionToBiometricException`. All design decisions (placement, naming, mapping style) are directly derivable from the existing code, which should be read via ast-index before editing.
