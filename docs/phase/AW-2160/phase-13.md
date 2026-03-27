# Phase 13: Tests for Proactive Detection

**Goal:** Unit tests for `isKeyValid` delegation, `BiometricState.keyInvalidated`, and proactive `determineBiometricState`.

## Context

### What Phase 12 Added

Phase 12 wired the proactive key validity check into `MFALocker.determineBiometricState`. The new code path is:

```
determineBiometricState(biometricKeyTag: tag)
  → isEnabledInSettings = true
  → _secureProvider.isKeyValid(tag: tag) → false
  → return BiometricState.keyInvalidated
```

Phase 13 verifies this entire path with unit tests:
1. The `BiometricState.keyInvalidated` enum value and its getters behave correctly.
2. `BiometricCipherProviderImpl.isKeyValid` correctly delegates to `BiometricCipher.isKeyValid`.
3. `MFALocker.determineBiometricState(biometricKeyTag:)` returns `keyInvalidated` when the key is invalid.
4. `MFALocker.determineBiometricState()` without a tag retains existing behavior (no key check, returns `enabled`).

### Existing Test Infrastructure

- `test/mocks/mock_biometric_cipher.dart` — `MockBiometricCipher`
- `test/mocks/mock_biometric_cipher_provider.dart` — `MockBiometricCipherProvider`
- `test/mocks/mock_encrypted_storage.dart` — `MockEncryptedStorage`
- `test/security/biometric_cipher_provider_test.dart` — existing `BiometricCipherProviderImpl` tests (add 13.2 here)
- `test/locker/mfa_locker_test.dart` — existing `MFALocker` tests (add 13.3 and 13.4 here)

### Test Files by Task

| Task | File |
|------|------|
| 13.1 | `test/locker/models/biometric_state_test.dart` (new file) |
| 13.2 | `test/security/biometric_cipher_provider_test.dart` (extend existing) |
| 13.3 | `test/locker/mfa_locker_test.dart` (extend existing) |
| 13.4 | `test/locker/mfa_locker_test.dart` (extend existing, same group as 13.3) |

## Tasks

- [x] **13.1** Test `BiometricState.keyInvalidated` enum value and `isKeyInvalidated` getter
  - `BiometricState.keyInvalidated.isKeyInvalidated` → `true`
  - `BiometricState.enabled.isKeyInvalidated` → `false`
  - `BiometricState.keyInvalidated.isEnabled` → `false`
  - `BiometricState.keyInvalidated.isAvailable` → `false`

- [x] **13.2** Test `isKeyValid` delegation in `BiometricCipherProviderImpl`
  - Mock `BiometricCipher.isKeyValid` → verify delegation and return value pass-through

- [x] **13.3** Test `determineBiometricState(biometricKeyTag:)` returns `keyInvalidated` when key is invalid
  - Mock `isKeyValid` → `false`, biometrics enabled in settings
  - Expect `BiometricState.keyInvalidated`

- [x] **13.4** Test `determineBiometricState()` without `biometricKeyTag` retains existing behavior
  - Biometrics enabled, no tag passed → expect `BiometricState.enabled` (no key validity check)

## Acceptance Criteria

**Test:** `fvm flutter test` — all green.

- `BiometricState.keyInvalidated.isKeyInvalidated` → `true`
- `BiometricState.enabled.isKeyInvalidated` → `false`
- `BiometricState.keyInvalidated.isEnabled` → `false`
- `BiometricState.keyInvalidated.isAvailable` → `false`
- `BiometricCipherProviderImpl.isKeyValid(tag:)` delegates to `_biometricCipher.isKeyValid(tag: tag)` and passes the return value through unchanged.
- `determineBiometricState(biometricKeyTag: 'tag')` returns `BiometricState.keyInvalidated` when `isKeyValid` returns `false` and biometrics are enabled in settings.
- `determineBiometricState()` with no tag returns `BiometricState.enabled` when biometrics are available and enabled (no `isKeyValid` call made).

## Dependencies

- Phase 12 complete (`BiometricState.keyInvalidated`, `BiometricCipherProvider.isKeyValid`, key validity check in `determineBiometricState`)

## Technical Details

### Task 13.1 — `BiometricState` enum tests

New file: `test/locker/models/biometric_state_test.dart`

```dart
import 'package:locker/locker/models/biometric_state.dart';
import 'package:test/test.dart';

void main() {
  group('BiometricState', () {
    group('keyInvalidated', () {
      test('isKeyInvalidated is true', () {
        expect(BiometricState.keyInvalidated.isKeyInvalidated, isTrue);
      });

      test('isEnabled is false', () {
        expect(BiometricState.keyInvalidated.isEnabled, isFalse);
      });

      test('isAvailable is false', () {
        expect(BiometricState.keyInvalidated.isAvailable, isFalse);
      });
    });

    group('other values', () {
      test('enabled.isKeyInvalidated is false', () {
        expect(BiometricState.enabled.isKeyInvalidated, isFalse);
      });

      test('availableButDisabled.isKeyInvalidated is false', () {
        expect(BiometricState.availableButDisabled.isKeyInvalidated, isFalse);
      });
    });
  });
}
```

### Task 13.2 — `isKeyValid` delegation in `BiometricCipherProviderImpl`

Add a new group to `test/security/biometric_cipher_provider_test.dart`, inside the top-level `'BiometricCipherProviderImpl'` group:

```dart
group('isKeyValid', () {
  late MockBiometricCipher mockCipher;
  late BiometricCipherProviderImpl provider;

  setUp(() {
    mockCipher = MockBiometricCipher();
    provider = BiometricCipherProviderImpl.forTesting(mockCipher);
  });

  test('returns true when cipher returns true', () async {
    when(() => mockCipher.isKeyValid(tag: any(named: 'tag')))
        .thenAnswer((_) async => true);

    final result = await provider.isKeyValid(tag: 'my-key');

    expect(result, isTrue);
    verify(() => mockCipher.isKeyValid(tag: 'my-key')).called(1);
  });

  test('returns false when cipher returns false', () async {
    when(() => mockCipher.isKeyValid(tag: any(named: 'tag')))
        .thenAnswer((_) async => false);

    final result = await provider.isKeyValid(tag: 'my-key');

    expect(result, isFalse);
    verify(() => mockCipher.isKeyValid(tag: 'my-key')).called(1);
  });
});
```

### Task 13.3 + 13.4 — `MFALocker.determineBiometricState` tests

Add a new `'determineBiometricState'` group in `test/locker/mfa_locker_test.dart`, inside the top-level `'MFALocker'` group. Follows the same local-locker pattern used in the `'teardownBiometryPasswordOnly'` group.

```dart
group('determineBiometricState', () {
  const biometricKeyTag = 'test-bio-key-tag';

  late MockBiometricCipherProvider secureProvider;
  late MockEncryptedStorage dsStorage;
  late MFALocker dsLocker;

  setUp(() {
    secureProvider = MockBiometricCipherProvider();
    dsStorage = MockEncryptedStorage();

    dsLocker = MFALocker(
      file: MockFile(),
      storage: dsStorage,
      secureProvider: secureProvider,
    );

    when(() => dsStorage.isInitialized).thenAnswer((_) async => true);
    when(() => dsStorage.lockTimeout)
        .thenAnswer((_) async => _Helpers.lockTimeout.inMilliseconds);

    when(() => secureProvider.getTPMStatus())
        .thenAnswer((_) async => TPMStatus.supported);
    when(() => secureProvider.getBiometryStatus())
        .thenAnswer((_) async => BiometricStatus.supported);
    when(() => dsStorage.isBiometricEnabled).thenAnswer((_) async => true);
  });

  tearDown(() async {
    dsLocker.dispose();
  });

  test('returns keyInvalidated when isKeyValid returns false', () async {
    when(() => secureProvider.isKeyValid(tag: biometricKeyTag))
        .thenAnswer((_) async => false);

    final result = await dsLocker.determineBiometricState(
      biometricKeyTag: biometricKeyTag,
    );

    expect(result, BiometricState.keyInvalidated);
    verify(() => secureProvider.isKeyValid(tag: biometricKeyTag)).called(1);
  });

  test('returns enabled when isKeyValid returns true', () async {
    when(() => secureProvider.isKeyValid(tag: biometricKeyTag))
        .thenAnswer((_) async => true);

    final result = await dsLocker.determineBiometricState(
      biometricKeyTag: biometricKeyTag,
    );

    expect(result, BiometricState.enabled);
  });

  test('returns enabled without key check when biometricKeyTag is null', () async {
    final result = await dsLocker.determineBiometricState();

    expect(result, BiometricState.enabled);
    verifyNever(() => secureProvider.isKeyValid(tag: any(named: 'tag')));
  });
});
```

**Required imports to add** to `mfa_locker_test.dart`:

```dart
import 'package:biometric_cipher/data/biometric_status.dart';
import 'package:biometric_cipher/data/tpm_status.dart';
import 'package:locker/locker/models/biometric_state.dart';
```

## Implementation Notes

- For 13.1, create the directory `test/locker/models/` if it doesn't exist.
- For 13.3/13.4, `dsLocker` uses a local `MFALocker` with an injected `secureProvider` — the same isolation pattern as the `teardownBiometryPasswordOnly` tests. Do not reuse the outer `locker` and `storage` variables.
- `verifyNever` confirms no key validity check occurs when no tag is passed (backwards compatibility guarantee).
- `BiometricStatus.supported` and `TPMStatus.supported` are the happy-path values that let `determineBiometricState` proceed to the `isEnabledInSettings` and key validity checks.
