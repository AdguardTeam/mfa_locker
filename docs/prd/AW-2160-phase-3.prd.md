# AW-2160-3: Dart Plugin — Map `KEY_PERMANENTLY_INVALIDATED` to `BiometricCipherExceptionCode`

Status: PRD_READY

## Context / Idea

This is Phase 3 of AW-2160, which as a whole adds biometric key invalidation detection and a password-only teardown path across the full stack (Android, iOS/macOS native, Dart plugin, and locker library).

**Phase dependency:** Phase 1 (Android) and Phase 2 (iOS/macOS) are both complete. Both platforms now emit `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")` over the method channel when a biometric key has been permanently invalidated.

**The problem:** The Dart plugin layer currently has no entry for `KEY_PERMANENTLY_INVALIDATED` in `BiometricCipherExceptionCode.fromString()`. When the string `'KEY_PERMANENTLY_INVALIDATED'` arrives from either platform, it falls through to the `_ => unknown` branch and is returned as `BiometricCipherExceptionCode.unknown`. The locker layer (Phases 4–5) cannot distinguish permanent key invalidation from any other unrecognised error, blocking the correct recovery flow.

**Current state of the target file:**

```
packages/biometric_cipher/lib/data/biometric_cipher_exception_code.dart
```

The enum currently has 13 values (`invalidArgument` … `configureError` … `unknown`). The `fromString` switch has no branch for `'KEY_PERMANENTLY_INVALIDATED'`. The `unknown` value is the last entry in the enum and serves as the `_` fallback in `fromString`.

**Error propagation chain (this phase closes the Dart plugin gap):**

```
FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")   ← from Android (Phase 1) or iOS/macOS (Phase 2)
  → BiometricCipherExceptionCode.fromString('KEY_PERMANENTLY_INVALIDATED')
  → BiometricCipherExceptionCode.keyPermanentlyInvalidated   (new — this phase)
  → consumed by locker layer (Phase 4)
```

**Scope:** One file, two additive lines. No logic changes, no new files.

---

## Goals

1. Add `keyPermanentlyInvalidated` as a named enum value to `BiometricCipherExceptionCode`, positioned before `unknown`.
2. Map the channel string `'KEY_PERMANENTLY_INVALIDATED'` to the new enum value in `fromString`, so the code is no longer swallowed by the `unknown` fallthrough.
3. Keep `unknown` as the last enum value and the `_` fallback — no reordering of existing values.
4. Maintain full backward compatibility: all existing `fromString` mappings must continue to produce exactly the same results.

---

## User Stories

**US-1 — Plugin consumer receives a typed `keyPermanentlyInvalidated` code**
As the locker library (Phase 4 consumer) calling the `biometric_cipher` plugin, I need `BiometricCipherException.code` to equal `BiometricCipherExceptionCode.keyPermanentlyInvalidated` (not `unknown`) when the platform emits `"KEY_PERMANENTLY_INVALIDATED"`, so that I can map it to `BiometricExceptionType.keyInvalidated` and trigger the correct recovery flow.

**US-2 — Existing error codes are unaffected**
As any existing caller of `BiometricCipherExceptionCode.fromString`, I need all currently mapped codes (`authenticationError`, `decryptionError`, `keyNotFound`, etc.) to continue producing exactly the same enum values, so that no existing error-handling path is broken.

**US-3 — `unknown` remains the fallback**
As a plugin consumer, I need unrecognised platform error codes to continue producing `BiometricCipherExceptionCode.unknown`, so that unexpected future codes are handled gracefully.

---

## Main Scenarios

### Scenario 1: Android key permanently invalidated — code mapped correctly

1. Android detects `KeyPermanentlyInvalidatedException` and emits `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")` (Phase 1).
2. The Dart plugin's method channel handler creates a `BiometricCipherException` using `BiometricCipherExceptionCode.fromString('KEY_PERMANENTLY_INVALIDATED')`.
3. After this phase: `fromString` returns `BiometricCipherExceptionCode.keyPermanentlyInvalidated`.
4. Before this phase: `fromString` would return `BiometricCipherExceptionCode.unknown`.

### Scenario 2: iOS/macOS Secure Enclave key permanently invalidated — code mapped correctly

1. iOS/macOS detects biometric invalidation and emits `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")` (Phase 2).
2. Same mapping path as Scenario 1 — `fromString` returns `keyPermanentlyInvalidated`.

### Scenario 3: Unrecognised error code — fallback unchanged

1. Platform emits an error code not present in `fromString` (e.g., a future code `"SOME_NEW_ERROR"`).
2. The `_ => unknown` branch still applies; `fromString` returns `BiometricCipherExceptionCode.unknown`.
3. No regression in fallback behaviour.

### Scenario 4: All existing error codes — no regression

1. Any existing platform error string (`'AUTHENTICATION_ERROR'`, `'DECRYPTION_ERROR'`, `'KEY_NOT_FOUND'`, etc.) is passed to `fromString`.
2. The result is identical to the result before this phase — no existing mapping is changed or displaced.

---

## Success / Metrics

| Criterion | How to verify |
|-----------|--------------|
| `BiometricCipherExceptionCode.fromString('KEY_PERMANENTLY_INVALIDATED')` returns `keyPermanentlyInvalidated` | Dart unit test or `dart test` assertion |
| `BiometricCipherExceptionCode.fromString('KEY_PERMANENTLY_INVALIDATED')` does **not** return `unknown` | Same unit test — negative assertion |
| `unknown` remains the last enum value | Code review / enum ordering check |
| All existing `fromString` mappings produce the same result as before | Existing tests continue to pass without modification |
| Package analysis passes | `cd packages/biometric_cipher && fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` exits 0 |

---

## Constraints and Assumptions

- **One file only:** `packages/biometric_cipher/lib/data/biometric_cipher_exception_code.dart`. No other files are modified in this phase.
- **Two lines of change:** one new enum value (`keyPermanentlyInvalidated` before `unknown`) and one new switch case (`'KEY_PERMANENTLY_INVALIDATED' => keyPermanentlyInvalidated`).
- **Placement rule:** `keyPermanentlyInvalidated` must appear **before** `unknown` in the enum body. The `unknown` value must remain last as it is the `_` catch-all in `fromString`.
- **No serialization impact:** `BiometricCipherExceptionCode` is never written to disk. Adding a new enum value is safe with no migration required.
- **No protocol/interface changes:** `BiometricCipherExceptionCode` is a plain Dart enum with a static factory. No interfaces are affected.
- **Style match:** The new enum value gets a doc comment consistent with adjacent values. The new switch case is placed near the end of the switch, before the final `_ => unknown` line, consistent with existing ordering.
- **`unknown` fallback string aliases:** The current code maps `'UNKNOWN_ERROR' || 'UNKNOWN_EXCEPTION' || 'CONVERTING_STRING_ERROR' || _` to `unknown`. The `_ => unknown` pattern must be preserved exactly.
- Phases 1 and 2 are complete. This phase does not depend on any in-progress native work.

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Enum value added in wrong position (after `unknown`) causes `unknown` to no longer be the last value | Low — straightforward edit | Medium — could affect exhaustive switch consumers | Verify placement in code review; `fromString` switch itself is unordered so placement there is flexible |
| Existing exhaustive `switch` on `BiometricCipherExceptionCode` in consuming code breaks at compile time after adding new value | Low — Dart enums with exhaustive switch will warn/error at compile time, which surfaces the issue immediately | Low — easy to fix | `fvm flutter analyze` catches this before merge |
| `'KEY_PERMANENTLY_INVALIDATED'` string mismatch with what Android/iOS actually emit | Very low — Phase 1 and Phase 2 are complete and both emit exactly this string | High if it occurs | Confirmed by reading Phase 1 and Phase 2 implementation (both use `KEY_PERMANENTLY_INVALIDATED` verbatim) |

---

## Open Questions

None. The scope is fully defined by Phase 3 description, the current state of `biometric_cipher_exception_code.dart`, and the completed Phase 1 and Phase 2 implementations. All design decisions (placement, naming, style) are directly derivable from existing code patterns.
