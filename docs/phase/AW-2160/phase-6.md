# Phase 6: Tests

**Goal:** Unit tests for new exception mapping and password-only teardown.

## Context

Phases 1–5 added `keyPermanentlyInvalidated` exception propagation through all layers and a new `teardownBiometryPasswordOnly` method. This phase covers the test coverage for:

1. **`BiometricCipherExceptionCode.fromString`** — verifies the new `'KEY_PERMANENTLY_INVALIDATED'` string maps to `keyPermanentlyInvalidated`.
2. **Exception mapping in `BiometricCipherProviderImpl`** — verifies `keyPermanentlyInvalidated` maps to `BiometricExceptionType.keyInvalidated`.
3. **`MFALocker.teardownBiometryPasswordOnly`** — verifies the password-only wrap deletion, `deleteKey` call, and error suppression behavior.
4. **Regression** — existing `authenticationError` → `failure` and `authenticationUserCanceled` → `cancel` mappings are unchanged.

**Motivation:** All prior phases were verified by analyze + existing tests. Phase 6 adds explicit test coverage for the new code paths so regressions are caught automatically.

## Tasks

- [ ] **6.1** Test `BiometricCipherExceptionCode.fromString('KEY_PERMANENTLY_INVALIDATED')` → `keyPermanentlyInvalidated`

- [ ] **6.2** Test `_mapExceptionToBiometricException` maps `keyPermanentlyInvalidated` → `BiometricExceptionType.keyInvalidated`

- [ ] **6.3** Test `teardownBiometryPasswordOnly` removes `Origin.bio` wrap, calls `deleteKey`, succeeds even if `deleteKey` throws

- [ ] **6.4** Verify existing exception types are unchanged (regression): `authenticationError` → `failure`, `authenticationUserCanceled` → `cancel`

## Acceptance Criteria

**Test:** `fvm flutter test` — all green.

## Dependencies

- Phase 5 complete (`teardownBiometryPasswordOnly` implemented)
- Phase 4 complete (`BiometricExceptionType.keyInvalidated` + mapping in provider)
- Phase 3 complete (`BiometricCipherExceptionCode.keyPermanentlyInvalidated` + `fromString`)

## Technical Details

### Test locations

| Test | File |
|------|------|
| 6.1 `BiometricCipherExceptionCode.fromString` | `packages/biometric_cipher/test/` |
| 6.2 exception mapping in provider | `test/security/biometric_cipher_provider_test.dart` (or equivalent) |
| 6.3 `teardownBiometryPasswordOnly` | `test/locker/mfa_locker_test.dart` |
| 6.4 regression mappings | `test/security/biometric_cipher_provider_test.dart` (or equivalent) |

### Task 6.1 — `BiometricCipherExceptionCode.fromString`

```dart
test('fromString KEY_PERMANENTLY_INVALIDATED returns keyPermanentlyInvalidated', () {
  expect(
    BiometricCipherExceptionCode.fromString('KEY_PERMANENTLY_INVALIDATED'),
    BiometricCipherExceptionCode.keyPermanentlyInvalidated,
  );
});
```

### Task 6.2 — provider exception mapping

Use `mocktail` to throw a `BiometricCipherException` with code `keyPermanentlyInvalidated`, verify the result is `BiometricException(BiometricExceptionType.keyInvalidated)`.

### Task 6.3 — `teardownBiometryPasswordOnly`

Three test cases:

1. **Happy path** — mock storage `deleteWrap` succeeds, mock `_secureProvider.deleteKey` succeeds. Verify `deleteWrap` called with `originToDelete: Origin.bio` and the password cipher func.
2. **`deleteKey` throws** — mock `deleteKey` to throw. Verify no exception is propagated from `teardownBiometryPasswordOnly`.
3. **Locked state** — ensure `loadAllMetaIfLocked` is called before `deleteWrap` (password auth drives unlock).

Use `MockEncryptedStorage` (existing `@visibleForTesting` injection pattern in `MFALocker`).

### Task 6.4 — regression mappings

```dart
test('authenticationError maps to failure', () { … });
test('authenticationUserCanceled maps to cancel', () { … });
```

Confirm both continue to produce their existing `BiometricExceptionType` values after the new mapping line was added.

## Implementation Notes

- Use `mocktail` — existing pattern in `test/mocks/`.
- `EncryptedStorage` is injectable via `@visibleForTesting` constructor param — no changes to production code needed.
- `_secureProvider` injection pattern: check how existing tests mock it (likely via `MockBiometricCipherProvider`).
- Keep tests focused; no need to re-test phases 1–2 (native) at the Dart level.
