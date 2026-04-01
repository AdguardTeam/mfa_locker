# AW-2160 Phase 3 Summary — Dart Plugin: `keyPermanentlyInvalidated` Code

## What Was Done

Phase 3 closed the Dart plugin gap in the biometric key invalidation error propagation chain. A single file was changed with two additive lines — no logic changes, no new files.

**File changed:** `packages/biometric_cipher/lib/data/biometric_cipher_exception_code.dart`

1. Added `keyPermanentlyInvalidated` as a new enum value in `BiometricCipherExceptionCode`, positioned immediately before `unknown` (which remains the last value and the `_` fallback).
2. Added the switch case `'KEY_PERMANENTLY_INVALIDATED' => keyPermanentlyInvalidated` to `fromString`, placed before the final `'UNKNOWN_ERROR' || 'UNKNOWN_EXCEPTION' || 'CONVERTING_STRING_ERROR' || _ => unknown` fallthrough.

## Why It Was Needed

Phases 1 (Android) and 2 (iOS/macOS) established that both platforms emit `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")` over the Flutter method channel when a biometric key is permanently invalidated. Before Phase 3, the Dart plugin had no mapping for this string — it fell through to `BiometricCipherExceptionCode.unknown`. This meant the locker library (Phase 4 consumer) could not distinguish permanent key invalidation from any generic unrecognised error, blocking the correct recovery flow.

## Error Propagation Chain (after Phase 3)

```
Platform (Android or iOS/macOS)
  → FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")
  → BiometricCipherMethodChannel._mapPlatformException()
      calls BiometricCipherExceptionCode.fromString('KEY_PERMANENTLY_INVALIDATED')
  → BiometricCipherExceptionCode.keyPermanentlyInvalidated   (was: unknown)
  → consumed by locker layer (Phase 4)
```

The method channel call site (`BiometricCipherMethodChannel._mapPlatformException`) required no changes — it already calls `fromString` and automatically picks up the new mapping.

## What Is Not Changed

- All 13 previously existing `fromString` mappings produce identical results (full backward compatibility).
- `unknown` remains the last enum value and the `_` catch-all in `fromString`.
- The downstream consumer `BiometricCipherProviderImpl._mapExceptionToBiometricException` uses a `_ =>` wildcard as its final arm. In Phase 3, `keyPermanentlyInvalidated` falls through to `BiometricExceptionType.failure` there. This is correct and intentional — Phase 4 adds the explicit `keyInvalidated` arm.
- No serialization impact: `BiometricCipherExceptionCode` is never written to disk.

## Key Decision

New named enum value rather than reusing `unknown`. This preserves the information from the platform layer so Phase 4 can map it to a dedicated `BiometricExceptionType.keyInvalidated` and trigger the correct recovery path (password-only biometric teardown).

## QA Notes

The QA review confirmed the implementation is functionally correct. Two items were flagged:

1. **No Dart unit test for `fromString('KEY_PERMANENTLY_INVALIDATED')`** — the PRD named a direct unit test as the primary verification method. The test gap is tracked under Iteration 6 (task 6.1). Phase 4 depends on this mapping as a contract, so the test should be added before Phase 6.
2. **`fvm flutter analyze` not executed during the QA pass** — must be confirmed green before release (PRD acceptance criterion).

## Phase Dependencies

| Phase | Status | Relevance |
|-------|--------|-----------|
| Phase 1 (Android) | Complete | Provides `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")` from Android KeyStore |
| Phase 2 (iOS/macOS) | Complete | Provides `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")` from Secure Enclave |
| Phase 3 (this phase) | Complete | `BiometricCipherExceptionCode.keyPermanentlyInvalidated` is now a typed constant |
| Phase 4 (Locker layer) | Not started | Maps `keyPermanentlyInvalidated` → `BiometricExceptionType.keyInvalidated` |
| Phase 5 (Password-only teardown) | Not started | `MFALocker.teardownBiometryPasswordOnly` implementation |
| Phase 6 (Tests) | Not started | Unit tests including task 6.1 for this phase |
