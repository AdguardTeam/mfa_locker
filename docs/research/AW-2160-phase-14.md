# Research: AW-2160 Phase 14 — Tests for Proactive Detection

## Resolved Questions

No open questions were raised for this phase. The user confirmed to proceed directly with research.

---

## Phase Scope

Phase 14 adds unit test coverage for the three additions made in Phase 13:

| Symbol | Source file | Test file |
|--------|-------------|-----------|
| `BiometricState.keyInvalidated` + `isKeyInvalidated` getter | `lib/locker/models/biometric_state.dart` | `test/locker/models/biometric_state_test.dart` |
| `BiometricCipherProviderImpl.isKeyValid` | `lib/security/biometric_cipher_provider.dart` | `test/security/biometric_cipher_provider_test.dart` |
| `MFALocker.determineBiometricState({String? biometricKeyTag})` | `lib/locker/mfa_locker.dart` | `test/locker/mfa_locker_test.dart` |

**Status at research time:** The tasklist (`docs/tasklist-2160.md`) marks all four subtasks (14.1–14.4) as done, and all test cases are already present in the three files. Phase 14 is complete. The active ticket (`docs/.active_ticket`) is `AW-2160-14`, consistent with this phase.

---

## Related Modules / Services

### Source under test

**`lib/locker/models/biometric_state.dart`**
Full enum with nine values. The two additions from Phase 13:
- `keyInvalidated` — ninth value, after `enabled`
- `bool get isKeyInvalidated => this == keyInvalidated`

Existing getters also tested:
- `bool get isAvailable => this == availableButDisabled || this == enabled` — `keyInvalidated` returns `false` here
- `bool get isEnabled => this == enabled` — `keyInvalidated` returns `false` here

**`lib/security/biometric_cipher_provider.dart`**
Contains both the abstract interface and the `BiometricCipherProviderImpl` class in one file.
- Abstract method: `Future<bool> isKeyValid({required String tag})`
- Implementation (line 118): `Future<bool> isKeyValid({required String tag}) => _biometricCipher.isKeyValid(tag: tag);` — a one-line delegation with no transformation.
- `@visibleForTesting` constructor: `BiometricCipherProviderImpl.forTesting(this._biometricCipher)` — used in tests.

**`lib/locker/mfa_locker.dart`**
`determineBiometricState({String? biometricKeyTag})` logic (lines 293–337):
1. Check `getTPMStatus()` → early returns for `unsupported` / `tpmVersionUnsupported`
2. Check `getBiometryStatus()` → early returns for hardware/enrollment/policy states
3. Check `isBiometricEnabled` in storage → return `availableButDisabled` if false
4. If `biometricKeyTag != null`: call `_secureProvider.isKeyValid(tag: biometricKeyTag)` → return `keyInvalidated` if false
5. Return `BiometricState.enabled`

`MFALocker` accepts an optional `@visibleForTesting BiometricCipherProvider? secureProvider` constructor parameter, enabling mock injection in tests.

---

## Current Endpoints and Contracts

No HTTP endpoints. The relevant Dart API contracts:

```dart
// BiometricState enum (lib/locker/models/biometric_state.dart)
enum BiometricState {
  tpmUnsupported, tpmVersionIncompatible, hardwareUnavailable,
  notEnrolled, disabledByPolicy, securityUpdateRequired,
  availableButDisabled, enabled, keyInvalidated;

  bool get isAvailable => this == availableButDisabled || this == enabled;
  bool get isEnabled   => this == enabled;
  bool get isKeyInvalidated => this == keyInvalidated;
}

// BiometricCipherProvider (lib/security/biometric_cipher_provider.dart)
abstract class BiometricCipherProvider {
  Future<bool> isKeyValid({required String tag});
  // ... other methods
}

// MFALocker constructor (lib/locker/mfa_locker.dart)
MFALocker({
  required File file,
  @visibleForTesting EncryptedStorage? storage,
  @visibleForTesting BiometricCipherProvider? secureProvider,
});

// Locker interface (determineBiometricState)
Future<BiometricState> determineBiometricState({String? biometricKeyTag});
```

---

## Patterns Used

### Test file structure

All three test files follow the same pattern used throughout the project:

- `mocktail` for all mocking (`Mock` base class, `when().thenAnswer()`, `verify()`, `verifyNever()`)
- `group` / `test` from `package:test/test.dart`
- `setUp` for mock initialization and stub baseline
- Arrange / Act / Assert (AAA) layout (no inline comments — tests are concise)
- `registerFallbackValue` called in `setUpAll` only for types used as `any(named:)` arguments

### Mock declarations

All mocks live in `test/mocks/` as simple one-liner classes:

```
test/mocks/
├── mock_biometric_cipher.dart          # MockBiometricCipher extends Mock implements BiometricCipher
├── mock_biometric_cipher_provider.dart # MockBiometricCipherProvider extends Mock implements BiometricCipherProvider
├── mock_encrypted_storage.dart
├── mock_bio_cipher_func.dart
├── mock_password_cipher_func.dart
└── mock_file.dart
```

`MockBiometricCipher` and `MockBiometricCipherProvider` are both bare `extends Mock implements X` — no stub pre-registration is needed beyond individual `when()` calls in tests.

### `determineBiometricState` group setUp baseline

The existing `determineBiometricState` group in `mfa_locker_test.dart` creates a dedicated `dsLocker` + `dsStorage` + `secureProvider` triple in its own `setUp`. The baseline stubs are:
```dart
when(() => secureProvider.getTPMStatus()).thenAnswer((_) async => TPMStatus.supported);
when(() => secureProvider.getBiometryStatus()).thenAnswer((_) async => BiometricStatus.supported);
when(() => dsStorage.isBiometricEnabled).thenAnswer((_) async => true);
```
Tests 14.3 and 14.4 add per-test stubs on top of this baseline (no baseline modification needed).

### `biometric_cipher_provider_test.dart` group structure

Uses `BiometricCipherProviderImpl.forTesting(mockCipher)` to inject `MockBiometricCipher`. The `isKeyValid` group sits alongside the existing `_mapExceptionToBiometricException` group — separate `setUp` per group, both creating their own `mockCipher` and `provider` instances.

---

## Existing Test Coverage — What Phase 14 Added

### Task 14.1 — `biometric_state_test.dart`

Two groups already present:
- `keyInvalidated` group: `isKeyInvalidated is true`, `isEnabled is false`, `isAvailable is false`
- `other values` group: `enabled.isKeyInvalidated is false`, `availableButDisabled.isKeyInvalidated is false`

The phase-14 doc required `keyInvalidated.isKeyInvalidated → true`, `enabled.isKeyInvalidated → false`, `keyInvalidated.isEnabled → false`, `keyInvalidated.isAvailable → false` — all four assertions are covered.

### Task 14.2 — `biometric_cipher_provider_test.dart`

`isKeyValid` group (lines 98–124) with two tests:
- `returns true when cipher returns true` — stubs `isKeyValid → true`, calls `provider.isKeyValid(tag: 'my-key')`, asserts result + verifies delegation with exact tag
- `returns false when cipher returns false` — same pattern for `false`

Both tests use `verify(() => mockCipher.isKeyValid(tag: 'my-key')).called(1)` to confirm the delegation.

### Tasks 14.3 & 14.4 — `mfa_locker_test.dart`

Inside the `determineBiometricState` group (lines 1451–1582), three tests are directly related to Phase 14:
- Line 1480: `returns keyInvalidated when isKeyValid returns false` — stubs `isKeyValid → false`, passes `biometricKeyTag`, expects `keyInvalidated`, verifies call
- Line 1491: `returns enabled when isKeyValid returns true` — stubs `isKeyValid → true`, same tag, expects `enabled`
- Line 1501: `returns enabled without key check when biometricKeyTag is null` — no tag passed, expects `enabled`, uses `verifyNever` on `isKeyValid`
- Line 1574: `returns availableButDisabled...` already uses `verifyNever(() => secureProvider.isKeyValid(tag: any(named: 'tag')))` — regression guard confirming key check is skipped before the enabled gate

The `const biometricKeyTag = 'test-bio-key-tag'` is defined at the top of the group and reused by all tag-using tests.

---

## Phase-Specific Limitations and Risks

1. **All tests already written and marked done.** The research confirms Phase 14 implementation is complete. No code changes are needed. If the task is to verify or review, the research document serves as the audit trail.

2. **`MockBiometricCipherProvider` has no `isKeyValid` stub registered in `setUpAll`.** Because `mocktail` requires no fallback registration for named-parameter matchers when the method is stubbed with `any(named: 'tag')`, this is fine. However, if a future test calls `isKeyValid` without a `when()` stub, it will throw a `MissingStubError` at runtime — this is the expected mocktail behavior and not a risk for the current tests.

3. **`returns enabled when isKeyValid returns true` (line 1491) does not call `verify`.** The test asserts `result == enabled` but does not explicitly verify `isKeyValid` was called once. This is intentional (the important behavior is the return value), but it means the test would pass even if the key validity check were removed from the implementation. The companion test at line 1480 does call `verify`, so the delegation is confirmed there.

4. **`biometric_state_test.dart` only imports `package:test/test.dart`.** No mocks or async needed — enum getter tests are synchronous. Clean isolation.

5. **No `tearDown` in `biometric_cipher_provider_test.dart`.** Unlike `mfa_locker_test.dart` which calls `dsLocker.dispose()` in `tearDown`, the provider test has no disposable resources, so the absence of `tearDown` is correct.

---

## New Technical Questions

None discovered during research. The implementation is complete and consistent with the phase spec. The three test files map precisely to the three layers described in the phase doc.
