# Plan: AW-2160 Phase 3 -- Dart Plugin: Map `KEY_PERMANENTLY_INVALIDATED` to `BiometricCipherExceptionCode`

Status: PLAN_APPROVED

## Phase Scope

Phase 3 closes the Dart plugin gap in the error propagation chain. Phases 1 (Android) and 2 (iOS/macOS) already emit `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")` over the method channel when a biometric key is permanently invalidated. The Dart plugin currently has no mapping for this string -- it falls through to `BiometricCipherExceptionCode.unknown`. This phase adds the mapping so downstream consumers (Phase 4) can distinguish permanent key invalidation from generic errors.

**Scope is exactly one file, two additive lines:**
1. A new enum value `keyPermanentlyInvalidated` in the `BiometricCipherExceptionCode` enum.
2. A new case `'KEY_PERMANENTLY_INVALIDATED' => keyPermanentlyInvalidated` in the `fromString` switch.

No new files. No logic changes. No behavioral changes to existing mappings.

---

## Components

### Affected

| Component | File | Change |
|-----------|------|--------|
| `BiometricCipherExceptionCode` enum | `packages/biometric_cipher/lib/data/biometric_cipher_exception_code.dart` | Add `keyPermanentlyInvalidated` enum value before `unknown`; add `'KEY_PERMANENTLY_INVALIDATED'` case to `fromString` switch |

### Unaffected (verified safe)

| Component | File | Why unaffected |
|-----------|------|---------------|
| `BiometricCipherMethodChannel._mapPlatformException()` | `packages/biometric_cipher/lib/biometric_cipher_method_channel.dart` | Calls `fromString()` -- automatically picks up the new mapping, no code change needed |
| `BiometricCipherProviderImpl._mapExceptionToBiometricException()` | `lib/security/biometric_cipher_provider.dart` | Uses `_ =>` wildcard fallback; new enum value falls through to `failure` -- correct for Phase 3; Phase 4 adds the explicit arm |
| `BiometricCipher` | `packages/biometric_cipher/lib/biometric_cipher.dart` | Constructs exceptions with named literals, not via exhaustive switch |
| Test mocks | `packages/biometric_cipher/test/` | No exhaustive switch on the enum |

---

## API Contract

### Modified API

**`BiometricCipherExceptionCode` enum** (additive only):

```dart
enum BiometricCipherExceptionCode {
  // ... existing 13 values unchanged ...
  configureError,

  /// The biometric key has been permanently invalidated.
  keyPermanentlyInvalidated,  // NEW -- position 14

  /// An unknown or unclassified error occurred.
  unknown;                     // remains position 15 (was 14), still last

  static BiometricCipherExceptionCode fromString(String code) => switch (code) {
    // ... all existing cases unchanged ...

    'KEY_PERMANENTLY_INVALIDATED' => keyPermanentlyInvalidated,  // NEW

    'UNKNOWN_ERROR' || 'UNKNOWN_EXCEPTION' || 'CONVERTING_STRING_ERROR' || _ => unknown,  // unchanged
  };
}
```

### No new APIs

No new classes, methods, or files. This is a pure enum extension.

---

## Data Flows

### Before Phase 3

```
Platform: FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")
  -> Dart: BiometricCipherExceptionCode.fromString('KEY_PERMANENTLY_INVALIDATED')
  -> Result: BiometricCipherExceptionCode.unknown  (incorrect -- lost information)
```

### After Phase 3

```
Platform: FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")
  -> Dart: BiometricCipherExceptionCode.fromString('KEY_PERMANENTLY_INVALIDATED')
  -> Result: BiometricCipherExceptionCode.keyPermanentlyInvalidated  (correct -- preserves intent)
```

### Downstream propagation (Phase 3 does NOT change this; documented for context)

```
BiometricCipherExceptionCode.keyPermanentlyInvalidated
  -> BiometricCipherProviderImpl._mapExceptionToBiometricException()
  -> Falls through _ => BiometricException(BiometricExceptionType.failure, originalError: e)
  (Phase 4 will add an explicit arm mapping to BiometricExceptionType.keyInvalidated)
```

---

## NFR

| Requirement | Target |
|-------------|--------|
| Backward compatibility | All existing `fromString` mappings produce identical results |
| `unknown` fallback | `unknown` remains the last enum value and the `_` catch-all |
| Static analysis | `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` passes for both `packages/biometric_cipher/` and root |
| No serialization impact | `BiometricCipherExceptionCode` is never stored to disk -- no migration needed |
| Code style | Doc comment matches adjacent values (single sentence, period at end); lowerCamelCase naming; 120-char line length |

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Enum value placed after `unknown` instead of before | Low | Medium -- `unknown` would no longer be the last value, potentially confusing exhaustive switch consumers | Code review check; verify enum declaration order |
| String mismatch between `'KEY_PERMANENTLY_INVALIDATED'` in Dart and what platforms emit | None -- Phase 1 and Phase 2 are complete and both confirmed to emit this exact string | High if it occurred | Verified by reading Phase 1 (Android `ErrorType.KEY_PERMANENTLY_INVALIDATED.name`) and Phase 2 (iOS/macOS hardcoded `"KEY_PERMANENTLY_INVALIDATED"`) implementations |
| Exhaustive `switch` consumers break at compile time | Low -- the one known consumer (`_mapExceptionToBiometricException`) uses `_ =>` wildcard | Low -- compile error surfaces immediately if it happens | Run `fvm flutter analyze` on both `packages/biometric_cipher/` and root to catch any issues |
| New value reaches `_mapExceptionToBiometricException` and is silently mapped to `failure` instead of a dedicated type | Certain for Phase 3 | Acceptable -- Phase 4 adds the explicit `keyInvalidated` mapping | This is by design. Phase 3 is plugin-only; Phase 4 closes the locker-layer gap |

---

## Dependencies

### On previous phases

| Phase | Status | What it provides |
|-------|--------|-----------------|
| Phase 1 (Android) | Complete | `ErrorType.KEY_PERMANENTLY_INVALIDATED` + catch branch in `SecureMethodCallHandlerImpl` -- emits `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")` |
| Phase 2 (iOS/macOS) | Complete | `keyPermanentlyInvalidated` cases in `KeychainServiceError`, `SecureEnclaveManagerError`, plugin error types -- emits `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")` |

### For downstream phases

| Phase | What it needs from Phase 3 |
|-------|---------------------------|
| Phase 4 (Locker layer) | `BiometricCipherExceptionCode.keyPermanentlyInvalidated` exists so it can be mapped to `BiometricExceptionType.keyInvalidated` |

### External dependencies

None. No new packages, no new platform APIs, no build configuration changes.

---

## Implementation Steps

1. **Edit enum body** in `packages/biometric_cipher/lib/data/biometric_cipher_exception_code.dart`:
   - Add doc comment `/// The biometric key has been permanently invalidated.` and value `keyPermanentlyInvalidated,` immediately before `unknown`.

2. **Edit `fromString` switch** in the same file:
   - Add case `'KEY_PERMANENTLY_INVALIDATED' => keyPermanentlyInvalidated,` immediately before the final `'UNKNOWN_ERROR' || ... || _ => unknown,` line.

3. **Verify**: Run static analysis on the biometric_cipher package and the root package to confirm no compile errors or warnings.

---

## Open Questions

None. The scope is fully defined by the PRD, research document, phase task list, and the current state of the target file. All design decisions (naming, placement, style, string key) are directly derivable from existing code patterns.
