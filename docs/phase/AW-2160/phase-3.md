# Phase 3: Dart plugin — `keyPermanentlyInvalidated` code

**Goal:** Map the native `KEY_PERMANENTLY_INVALIDATED` channel code to a Dart enum value so the locker layer can distinguish it from generic failures.

## Context

**Feature motivation:** Phases 1 and 2 wired Android and iOS/macOS to emit `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")` over the method channel. Phase 3 closes the final gap in the plugin layer: the Dart side currently falls through to `unknown` for this code. Without this change, Iterations 4–5 cannot map the error at the locker level.

**Technical approach:** Pure additive change — one new enum value and one new case in the `fromString` switch. No logic changes, no new files. Follows the exact same pattern used for `AUTHENTICATION_ERROR`, `AUTHENTICATION_USER_CANCELED`, etc.

**Error propagation chain (Dart plugin layer):**
```
FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")   ← from iOS/macOS or Android
  → BiometricCipherExceptionCode.fromString('KEY_PERMANENTLY_INVALIDATED')
  → BiometricCipherExceptionCode.keyPermanentlyInvalidated
  → (consumed by locker layer in Iteration 4)
```

**File affected:**
```
packages/biometric_cipher/lib/data/biometric_cipher_exception_code.dart
  # + keyPermanentlyInvalidated enum value (before `unknown`)
  # + 'KEY_PERMANENTLY_INVALIDATED' => keyPermanentlyInvalidated in fromString
```

## Tasks

- [ ] **3.1** Add `keyPermanentlyInvalidated` to `BiometricCipherExceptionCode`
  - File: `packages/biometric_cipher/lib/data/biometric_cipher_exception_code.dart`
  - Add enum value before `unknown`
  - Add `'KEY_PERMANENTLY_INVALIDATED' => keyPermanentlyInvalidated` to `fromString` switch

## Acceptance Criteria

**Verify:** `cd packages/biometric_cipher && fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .`

`BiometricCipherExceptionCode.fromString('KEY_PERMANENTLY_INVALIDATED')` returns `keyPermanentlyInvalidated` (not `unknown`).

## Dependencies

- Phase 1 complete ✅
- Phase 2 complete ✅

## Technical Details

### Target state of `biometric_cipher_exception_code.dart`

```dart
enum BiometricCipherExceptionCode {
  authenticationError,
  authenticationUserCanceled,
  // ... existing values ...
  keyPermanentlyInvalidated,  // new — hardware key permanently invalidated by biometric change

  unknown;

  static BiometricCipherExceptionCode fromString(String value) => switch (value) {
    'AUTHENTICATION_ERROR' => authenticationError,
    'AUTHENTICATION_USER_CANCELED' => authenticationUserCanceled,
    // ... existing mappings unchanged ...
    'KEY_PERMANENTLY_INVALIDATED' => keyPermanentlyInvalidated,  // new
    _ => unknown,
  };
}
```

### Placement rule

Add `keyPermanentlyInvalidated` **before** `unknown` in the enum declaration. The `unknown` value must remain the last entry as it is the `_` fallback in `fromString`.

## Implementation Notes

- One file, two lines of change — enum value + switch case. KISS.
- Do not change `unknown` or any existing mappings.
- The actual enum values and exact switch keys in the file may differ from the idea doc's example (which lists `decryptionError`). Read the file before editing to match the existing style.
- No serialization impact — `BiometricCipherExceptionCode` is never stored to disk.
