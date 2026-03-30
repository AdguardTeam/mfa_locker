# Research: AW-2160 Phase 13 — Locker: `BiometricState.keyInvalidated` + Proactive `determineBiometricState`

## Resolved Questions

No open questions were raised by the user. The phase doc and PRD are unambiguous.

---

## Phase Scope

Add proactive key validity detection at the locker library level so that `determineBiometricState()` can return `BiometricState.keyInvalidated` when called at init time — before any user-triggered biometric operation. This eliminates the biometric button flash on the lock screen.

Five files must be modified in `lib/`. No new files. All changes are additive (backwards compatible).

**Phases 1–12 are complete prerequisites.** `BiometricCipher.isKeyValid(tag)` is already wired on Android, iOS/macOS, Windows, and the Dart plugin layer.

---

## Critical Discovery: All Five Target Files Are Already Implemented

**Every task in Phase 13 (13.1–13.5) has already been implemented in the codebase**, even though the tasklist (`docs/tasklist-2160.md`) still marks them as not started. What remains is Phase 14 — the unit tests.

### Task 13.1 — `BiometricState.keyInvalidated` (DONE)

File: `/Users/comrade77/Documents/Performix/Projects/mfa_locker/lib/locker/models/biometric_state.dart`

`keyInvalidated` enum value is present (line 28), along with `isKeyInvalidated` getter (line 38). The value is correctly excluded from both `isAvailable` and `isEnabled`. The implementation exactly matches the spec in the phase doc.

### Task 13.2 — `isKeyValid` abstract method in `BiometricCipherProvider` (DONE)

File: `/Users/comrade77/Documents/Performix/Projects/mfa_locker/lib/security/biometric_cipher_provider.dart`

Abstract method at line 56–57:
```dart
Future<bool> isKeyValid({required String tag});
```

Note: the tasklist references `lib/security/providers/biometric_cipher_provider_impl.dart` as a separate file for Task 13.3, but the project structure has both the abstract class and `BiometricCipherProviderImpl` in the same file (`lib/security/biometric_cipher_provider.dart`). There is no `lib/security/providers/` subdirectory.

### Task 13.3 — `isKeyValid` implementation in `BiometricCipherProviderImpl` (DONE)

Same file, line 118:
```dart
Future<bool> isKeyValid({required String tag}) => _biometricCipher.isKeyValid(tag: tag);
```

### Task 13.4 — `determineBiometricState({String? biometricKeyTag})` in `Locker` interface (DONE)

File: `/Users/comrade77/Documents/Performix/Projects/mfa_locker/lib/locker/locker.dart`

Signature at line 183 with full doc comment describing the optional `biometricKeyTag` semantics.

### Task 13.5 — Key validity check in `MFALocker.determineBiometricState` (DONE)

File: `/Users/comrade77/Documents/Performix/Projects/mfa_locker/lib/locker/mfa_locker.dart`

Lines 293–337. The proactive check runs at lines 329–334:
```dart
if (biometricKeyTag != null) {
  final isValid = await _secureProvider.isKeyValid(tag: biometricKeyTag);
  if (!isValid) {
    return BiometricState.keyInvalidated;
  }
}
```

This exactly matches the spec. No logging was added (per the implementation notes).

---

## Related Modules and Services

### Files changed by this phase

| File | Role |
|------|------|
| `lib/locker/models/biometric_state.dart` | Enum with all biometric states; `keyInvalidated` is now the 9th value |
| `lib/security/biometric_cipher_provider.dart` | Contains both `BiometricCipherProvider` abstract class and `BiometricCipherProviderImpl` in one file |
| `lib/locker/locker.dart` | Abstract `Locker` interface — `determineBiometricState` signature |
| `lib/locker/mfa_locker.dart` | `MFALocker` implementation |

### Upstream dependency (Phase 12 complete)

`packages/biometric_cipher/lib/biometric_cipher.dart` — `isKeyValid(tag:)` method is implemented and tested. The Dart-side platform interface and method channel are wired.

### Test infrastructure available

| Mock/helper | Location |
|-------------|----------|
| `MockBiometricCipherProvider` | `test/mocks/mock_biometric_cipher_provider.dart` |
| `MockBiometricCipher` | `test/mocks/mock_biometric_cipher.dart` |
| `MockEncryptedStorage` | `test/mocks/mock_encrypted_storage.dart` |
| `MockFile` | `test/mocks/mock_file.dart` |

---

## Current Endpoints and Contracts

### `BiometricState` enum (current state)

```
tpmUnsupported, tpmVersionIncompatible, hardwareUnavailable, notEnrolled,
disabledByPolicy, securityUpdateRequired, availableButDisabled, enabled, keyInvalidated
```

Getters: `isAvailable` (only `availableButDisabled | enabled`), `isEnabled` (only `enabled`), `isKeyInvalidated` (only `keyInvalidated`).

### `BiometricCipherProvider` abstract interface (current state)

Methods: `configure`, `getTPMStatus`, `getBiometryStatus`, `generateKey`, `encrypt`, `decrypt`, `deleteKey`, `isKeyValid`.

`isKeyValid({required String tag})` is now the 8th method.

### `Locker` interface `determineBiometricState` signature (current state)

```dart
Future<BiometricState> determineBiometricState({String? biometricKeyTag});
```

Callers without `biometricKeyTag` get the existing behavior. Callers passing `biometricKeyTag` get the proactive check.

### `MFALocker` constructor (test injection points)

```dart
MFALocker({
  required File file,
  @visibleForTesting EncryptedStorage? storage,
  @visibleForTesting BiometricCipherProvider? secureProvider,
})
```

Both `storage` and `secureProvider` are injectable for testing.

---

## Patterns Used

### Test structure in `mfa_locker_test.dart`

The `determineBiometricState` group (lines 1451–1582) uses a dedicated `setUp` that:
1. Creates `MockBiometricCipherProvider` and `MockEncryptedStorage` instances.
2. Constructs `MFALocker` injecting both mocks via `@visibleForTesting` params.
3. Stubs default "happy path" state: `TPMStatus.supported`, `BiometricStatus.supported`, `isBiometricEnabled: true`.

Individual tests then override specific stubs to exercise each branch.

### Test structure for `BiometricCipherProviderImpl.isKeyValid` in `biometric_cipher_provider_test.dart`

The `isKeyValid` group (lines 98–124) follows the same setUp/test pattern with `MockBiometricCipher` injected via `BiometricCipherProviderImpl.forTesting(mockCipher)`.

### `biometric_state_test.dart` pattern

Uses flat `group` nesting with short `test` blocks that each check one getter.

### Arrange / Act / Assert comment style

All tests in these files use `// Arrange`, `// Act`, `// Assert` comments (or combined `// Act & Assert` for `expectLater` patterns).

---

## Phase-Specific Limitations and Risks

1. **The tasklist is stale.** Tasks 13.1–13.5 are marked not started but are already done. The implementer should update the tasklist and move on to Phase 14 (tests) — which is what the acceptance criteria require.

2. **No `lib/security/providers/` subdirectory exists.** The tasklist and phase doc mention `lib/security/providers/biometric_cipher_provider_impl.dart` for Task 13.3, but in reality the implementation is co-located with the abstract class in `lib/security/biometric_cipher_provider.dart`. The tests for it live in `test/security/biometric_cipher_provider_test.dart` — already covering `isKeyValid` delegation (lines 98–124).

3. **Phase 14 tests are partially pre-built.** Checking the existing test files:
   - `test/locker/models/biometric_state_test.dart` — already covers `keyInvalidated` (tasks 14.1 ✅)
   - `test/security/biometric_cipher_provider_test.dart` — already covers `isKeyValid` delegation (task 14.2 ✅)
   - `test/locker/mfa_locker_test.dart` — already covers `determineBiometricState` including `keyInvalidated` return (tasks 14.3 ✅) and no-tag backward compatibility (task 14.4 ✅)

4. **All acceptance criteria are already satisfied by the existing code and tests.** Running `fvm flutter analyze` and `fvm flutter test` is the only remaining verification step before marking Phase 13 and Phase 14 done.

5. **`key_validity_status.dart` is present in `lib/security/models/`.** This file was not referenced by the phase doc. It may be related but is not used by the implementation described in this phase — no risk, just an observation.

---

## New Technical Questions Discovered During Research

1. **Why is the tasklist stale?** Tasks 13.1–13.5 are implemented and tests exist (Phase 14 tests are also present). Were these committed together in the Phase 12 branch? The git log shows recent commits with `isKeyValid` feature names but attributed to Phase 12 work. The tasklist may simply not have been updated when code was committed ahead of schedule.

2. **Should the tasklist be updated now?** Tasks 13.1–13.5 and 14.1–14.4 can all be checked off. Phase 15 is already marked complete. This would mean the ticket AW-2160 is effectively done pending a final `fvm flutter analyze + fvm flutter test` run.
