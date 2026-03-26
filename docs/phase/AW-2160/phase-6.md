# Phase 6: Tests

Status: COMPLETED

**Goal:** Add unit test coverage for all new Dart-layer code paths introduced in Phases 3-5: the `BiometricCipherExceptionCode.fromString` mapping, the `BiometricCipherProviderImpl` exception mapping, `MFALocker.teardownBiometryPasswordOnly` (three cases), and regression tests for existing exception mappings. The only production code change is a `@visibleForTesting` injectable `secureProvider` constructor parameter on `MFALocker`.

---

## Tasks

- [x] **Step 1** — Create `test/mocks/mock_biometric_cipher.dart`

  `MockBiometricCipher extends Mock implements BiometricCipher`

  Imports: `package:biometric_cipher/biometric_cipher.dart`, `package:mocktail/mocktail.dart`

  **Acceptance criteria:**
  - File exists at `test/mocks/mock_biometric_cipher.dart`.
  - `fvm flutter analyze` exits 0 — no unused import, no missing interface member.

- [x] **Step 2** — Create `test/mocks/mock_biometric_cipher_provider.dart`

  `MockBiometricCipherProvider extends Mock implements BiometricCipherProvider`

  Imports: `package:locker/security/biometric_cipher_provider.dart`, `package:mocktail/mocktail.dart`

  **Acceptance criteria:**
  - File exists at `test/mocks/mock_biometric_cipher_provider.dart`.
  - `fvm flutter analyze` exits 0.

- [x] **Step 3** — Modify `lib/locker/mfa_locker.dart`: add injectable `secureProvider`

  - Remove the getter `BiometricCipherProvider get _secureProvider => BiometricCipherProviderImpl.instance;`.
  - Add a `final BiometricCipherProvider _secureProvider;` field (positioned after `_storage`).
  - Add `@visibleForTesting BiometricCipherProvider? secureProvider` as an optional named constructor parameter.
  - Extend the initializer list: `_secureProvider = secureProvider ?? BiometricCipherProviderImpl.instance`.

  **Acceptance criteria:**
  - `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` exits 0.
  - All existing call sites (no `secureProvider` argument) continue to compile and pick up `BiometricCipherProviderImpl.instance` by default.
  - `fvm flutter test` passes all existing tests (no behavior change).

- [x] **Step 4** — Task 6.1: Add `fromString` test to `packages/biometric_cipher/test/biometric_cipher_test.dart`

  Add a new `group('BiometricCipherExceptionCode', ...)` after the existing `group('BiometricCipher tests', ...)` block with one test:

  ```dart
  test('fromString KEY_PERMANENTLY_INVALIDATED returns keyPermanentlyInvalidated', () {
    // Arrange
    const code = 'KEY_PERMANENTLY_INVALIDATED';
    // Act
    final result = BiometricCipherExceptionCode.fromString(code);
    // Assert
    expect(result, BiometricCipherExceptionCode.keyPermanentlyInvalidated);
  });
  ```

  No new file is created; the test is added to the existing file.

  **Acceptance criteria:**
  - `fvm flutter test packages/biometric_cipher/test/biometric_cipher_test.dart` exits 0 with the new test passing.
  - No existing test case in the file is modified or removed.

- [x] **Step 5** — Tasks 6.2 and 6.4: Create `test/security/biometric_cipher_provider_test.dart`

  New file. Uses `BiometricCipherProviderImpl.forTesting(mockCipher)`. Three tests inside `group('BiometricCipherProviderImpl', () { group('_mapExceptionToBiometricException', ...) })`:

  - **6.2** — Stub `mockCipher.decrypt` to throw `BiometricCipherException(code: BiometricCipherExceptionCode.keyPermanentlyInvalidated, message: 'test')`. Assert provider throws `BiometricException` with `type == BiometricExceptionType.keyInvalidated`.
  - **6.4a** — Stub with `authenticationError`. Assert `type == BiometricExceptionType.failure`.
  - **6.4b** — Stub with `authenticationUserCanceled`. Assert `type == BiometricExceptionType.cancel`.

  Each test: Arrange (create mock + provider + stub), Act (call `provider.decrypt(tag: 'tag', data: Uint8List.fromList([1]))`), Assert (expect thrown `BiometricException` with correct `type`).

  **Acceptance criteria:**
  - File exists at `test/security/biometric_cipher_provider_test.dart`.
  - `fvm flutter test test/security/biometric_cipher_provider_test.dart` exits 0 with all three tests passing.
  - `fvm flutter analyze` exits 0.

- [x] **Step 6** — Task 6.3: Add `teardownBiometryPasswordOnly` group to `test/locker/mfa_locker_test.dart`

  Add `import '../mocks/mock_biometric_cipher_provider.dart';` at the top of the file.

  Add a new `group('teardownBiometryPasswordOnly', ...)` inside the top-level `group('MFALocker', ...)` block, positioned after the `wrap management` group. The group has its own `setUp` and `tearDown` that create a `MockBiometricCipherProvider` and a separate `MFALocker` instance with both `storage` and `secureProvider` injected:

  - **6.3a (happy path)** — Stub `storage.readAllMeta` via `_Helpers.stubReadAllMeta`, stub `storage.deleteWrap(originToDelete: Origin.bio, cipherFunc: pwd)` to succeed, stub `secureProvider.deleteKey(tag: 'tag')` to succeed. Call `teardownBiometryPasswordOnly`. Verify `storage.deleteWrap` called once with `originToDelete: Origin.bio` and `cipherFunc: pwd`. Verify `secureProvider.deleteKey(tag: 'tag')` called once. Assert no exception.
  - **6.3b (`deleteKey` throws, suppressed)** — Same stubs except `secureProvider.deleteKey(tag: 'tag')` throws `Exception('key gone')`. Call `teardownBiometryPasswordOnly`. Assert no exception propagates (method completes normally).
  - **6.3c (locked-state ordering)** — Locker starts locked (default after construction). Stub `storage.readAllMeta` and `storage.deleteWrap` to succeed. Stub `secureProvider.deleteKey` to succeed. Call `teardownBiometryPasswordOnly`. Use `verifyInOrder` to assert `storage.readAllMeta` is called before `storage.deleteWrap`.

  **Acceptance criteria:**
  - `fvm flutter test test/locker/mfa_locker_test.dart` exits 0 with all three new tests passing.
  - No existing test case in `mfa_locker_test.dart` is modified or removed.
  - `fvm flutter analyze` exits 0.

- [x] **Step 7** — Verify all tests and analysis pass

  1. Run `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` — must exit 0.
  2. Run `fvm flutter test` (root package) — all tests pass including new ones.
  3. Run `fvm flutter test packages/biometric_cipher/test/biometric_cipher_test.dart` — passes.

  **Acceptance criteria:**
  - Zero analyzer warnings or infos (root package).
  - Zero test failures across the entire test suite.
  - All four new test groups (6.1, 6.2/6.4, 6.3a/b/c) are confirmed green.

---

## Dependencies

- Phase 5 complete: `teardownBiometryPasswordOnly` is implemented in `MFALocker` and declared in `Locker`.
- Phase 4 complete: `BiometricExceptionType.keyInvalidated` exists and is mapped in `BiometricCipherProviderImpl`.
- Phase 3 complete: `BiometricCipherExceptionCode.keyPermanentlyInvalidated` exists and `fromString` maps `'KEY_PERMANENTLY_INVALIDATED'` to it.
- `MockEncryptedStorage` exists at `test/mocks/mock_encrypted_storage.dart`.
- `MockPasswordCipherFunc` exists at `test/mocks/mock_password_cipher_func.dart`.
- `BiometricCipherProviderImpl.forTesting(BiometricCipher)` constructor exists.
- `_Helpers.stubReadAllMeta` exists in `test/locker/mfa_locker_test_helpers.dart`.

## Test

Phase is complete when:

- `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` exits 0.
- `fvm flutter test` exits 0 with zero failures (root package, all test files).
- `fvm flutter test packages/biometric_cipher/test/biometric_cipher_test.dart` exits 0.
- No existing test case was removed or modified.
- No production logic was changed beyond the single `@visibleForTesting secureProvider` constructor parameter.
