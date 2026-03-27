# Plan: AW-2160 Phase 6 -- Unit Tests for Biometric Key Invalidation and Password-Only Teardown

Status: PLAN_APPROVED

## Phase Scope

Phase 6 is the final phase of AW-2160. It adds unit test coverage for all new Dart-layer code paths introduced in Phases 3--5:

1. `BiometricCipherExceptionCode.fromString('KEY_PERMANENTLY_INVALIDATED')` mapping (Phase 3).
2. `BiometricCipherProviderImpl._mapExceptionToBiometricException` mapping of `keyPermanentlyInvalidated` to `BiometricExceptionType.keyInvalidated` (Phase 4).
3. `MFALocker.teardownBiometryPasswordOnly` -- happy path, `deleteKey` error suppression, and locked-state ordering (Phase 5).
4. Regression tests confirming `authenticationError` -> `failure` and `authenticationUserCanceled` -> `cancel` mappings remain unchanged.

The only production code change is adding a `@visibleForTesting` injectable `secureProvider` constructor parameter to `MFALocker`, replacing the current getter with a final field.

---

## Components

### Production files modified

| File | Change |
|------|--------|
| `lib/locker/mfa_locker.dart` | Add `@visibleForTesting BiometricCipherProvider? secureProvider` constructor parameter. Replace the `BiometricCipherProvider get _secureProvider => BiometricCipherProviderImpl.instance;` getter (line 43) with a `final BiometricCipherProvider _secureProvider;` field initialized in the constructor initializer list via `_secureProvider = secureProvider ?? BiometricCipherProviderImpl.instance`. |

### New test files created

| File | Purpose |
|------|---------|
| `test/mocks/mock_biometric_cipher.dart` | `MockBiometricCipher extends Mock implements BiometricCipher` -- used by Tasks 6.2/6.4 to inject into `BiometricCipherProviderImpl.forTesting(...)` |
| `test/mocks/mock_biometric_cipher_provider.dart` | `MockBiometricCipherProvider extends Mock implements BiometricCipherProvider` -- used by Task 6.3 to inject into `MFALocker` via the new `secureProvider` parameter |
| `test/security/biometric_cipher_provider_test.dart` | New test file for Tasks 6.2 and 6.4 -- provider-level exception mapping tests |

### Existing test files modified

| File | Change |
|------|--------|
| `packages/biometric_cipher/test/biometric_cipher_test.dart` | Task 6.1: Add one new `test()` inside the existing `group('BiometricCipher tests', ...)` for `fromString('KEY_PERMANENTLY_INVALIDATED')` |
| `test/locker/mfa_locker_test.dart` | Task 6.3: Add new `group('teardownBiometryPasswordOnly', ...)` at top level inside the `group('MFALocker', ...)` block, after `wrap management`. Contains three tests (6.3a, 6.3b, 6.3c). Add `MockBiometricCipherProvider` import. |

---

## API Contract

### MFALocker constructor -- before

```dart
MFALocker({
  required File file,
  @visibleForTesting EncryptedStorage? storage,
}) : _storage = storage ?? EncryptedStorageImpl(file: file);

BiometricCipherProvider get _secureProvider => BiometricCipherProviderImpl.instance;
```

### MFALocker constructor -- after

```dart
final BiometricCipherProvider _secureProvider;

MFALocker({
  required File file,
  @visibleForTesting EncryptedStorage? storage,
  @visibleForTesting BiometricCipherProvider? secureProvider,
}) : _storage = storage ?? EncryptedStorageImpl(file: file),
     _secureProvider = secureProvider ?? BiometricCipherProviderImpl.instance;
```

The getter on line 43 is removed. The field `_secureProvider` is `final` and initialized in the initializer list. All existing call sites pass no `secureProvider` argument and get `BiometricCipherProviderImpl.instance` by default. No behavior change.

### No other API changes

All existing public, `@visibleForTesting`, and internal methods remain unchanged. This is the only production code modification.

---

## Data Flows

No data flow changes. All additions are in test code. The only structural change is the `MFALocker._secureProvider` field initialization path, which is functionally identical to the previous getter.

### Test data flows

**Task 6.1 -- `fromString` test:**
```
BiometricCipherExceptionCode.fromString('KEY_PERMANENTLY_INVALIDATED')
  -> returns BiometricCipherExceptionCode.keyPermanentlyInvalidated
```
Pure enum static method call. No mocks needed.

**Tasks 6.2/6.4 -- Provider exception mapping tests:**
```
MockBiometricCipher.decrypt(tag, data)
  -> throws BiometricCipherException(code: <tested_code>, message: '...')
  -> caught by BiometricCipherProviderImpl.decrypt's on BiometricCipherException catch
  -> _mapExceptionToBiometricException(e) produces BiometricException
  -> Error.throwWithStackTrace rethrows as BiometricException
  -> test asserts BiometricException.type == expected
```

**Task 6.3a -- Happy path:**
```
MFALocker.teardownBiometryPasswordOnly(passwordCipherFunc, biometricKeyTag)
  -> _sync -> _executeWithCleanup
    -> loadAllMetaIfLocked(pwd) -> storage.readAllMeta(cipherFunc: pwd)
    -> storage.deleteWrap(originToDelete: Origin.bio, cipherFunc: pwd)
  -> mockSecureProvider.deleteKey(tag: biometricKeyTag) -> succeeds
  -> no exception
```

**Task 6.3b -- `deleteKey` throws, suppressed:**
```
MFALocker.teardownBiometryPasswordOnly(passwordCipherFunc, biometricKeyTag)
  -> _sync -> _executeWithCleanup (same as 6.3a)
  -> mockSecureProvider.deleteKey(tag: biometricKeyTag) -> throws Exception
  -> catch (_, __) { logger.logWarning(...) }
  -> no exception propagates
```

**Task 6.3c -- Locked state, ordering verified:**
```
MFALocker (locked) -> teardownBiometryPasswordOnly(pwd, tag)
  -> loadAllMetaIfLocked -> storage.readAllMeta (unlocks)
  -> storage.deleteWrap
  -> verifyInOrder confirms readAllMeta before deleteWrap
```

---

## NFR

| Requirement | How satisfied |
|-------------|---------------|
| No production logic changes | Only the `_secureProvider` getter -> field refactor; functionally identical |
| Uses `mocktail` | Consistent with existing test infrastructure; no new mocking libraries |
| Code style compliance | Line length 120, single quotes, trailing commas, `// Arrange / // Act / // Assert` pattern |
| Static analysis passes | `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` must exit 0 |
| All existing tests pass | `fvm flutter test` must have zero failures |
| New tests are additive | No existing test cases removed or modified |

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| `MockBiometricCipher extends Mock implements BiometricCipher` -- `BiometricCipher` is a concrete class with guard logic in `decrypt` | Low -- `Mock` intercepts all method calls at the `Mock` level; the real `BiometricCipher.decrypt` implementation (with `_configured` guard) is never invoked when stubbed via `when(...)` | Low | Verified by research: `mocktail` `Mock` uses `noSuchMethod` override, so stub declarations bypass concrete implementations entirely |
| Adding `secureProvider` constructor param to `MFALocker` may require updating existing call sites | Very low -- it is an optional named parameter with default | None -- existing call sites continue to work | Run `fvm flutter analyze` after the change |
| `BiometricCipherException` requires `message` in constructor | Low -- easy to forget in test stubs | Low -- compile error if omitted | All test stubs will include `message: 'test'` |
| `verifyInOrder` is first use in codebase -- unfamiliar API | Low | Low -- well-documented in `mocktail` | Syntax confirmed in research: `verifyInOrder([() => mock.a(...), () => mock.b(...)])` |
| `biometric_cipher_test.dart` uses `flutter_test` while root tests use `test` | None -- Task 6.1 is added to the existing `biometric_cipher` package test file which already uses `flutter_test` | None | The `fromString` test does not import `test` package; it stays in the file's existing `flutter_test` context |

---

## Dependencies

| Dependency | Status |
|------------|--------|
| Phase 3 -- `BiometricCipherExceptionCode.keyPermanentlyInvalidated` + `fromString` | Complete |
| Phase 4 -- `BiometricExceptionType.keyInvalidated` + `_mapExceptionToBiometricException` mapping | Complete |
| Phase 5 -- `teardownBiometryPasswordOnly` implementation | Complete |
| `MockEncryptedStorage` at `test/mocks/mock_encrypted_storage.dart` | Exists |
| `MockPasswordCipherFunc` at `test/mocks/mock_password_cipher_func.dart` | Exists |
| `BiometricCipherProviderImpl.forTesting(BiometricCipher)` constructor | Exists |
| `_Helpers.stubReadAllMeta` in `test/locker/mfa_locker_test_helpers.dart` | Exists |
| `mocktail` (pinned version supports `verifyInOrder`) | Exists |

---

## Implementation Steps

### Step 1: Create `test/mocks/mock_biometric_cipher.dart`

```dart
class MockBiometricCipher extends Mock implements BiometricCipher {}
```

Import: `package:biometric_cipher/biometric_cipher.dart` and `package:mocktail/mocktail.dart`.

### Step 2: Create `test/mocks/mock_biometric_cipher_provider.dart`

```dart
class MockBiometricCipherProvider extends Mock implements BiometricCipherProvider {}
```

Import: `package:locker/security/biometric_cipher_provider.dart` and `package:mocktail/mocktail.dart`.

### Step 3: Modify `lib/locker/mfa_locker.dart` -- injectable `secureProvider`

- Remove the getter: `BiometricCipherProvider get _secureProvider => BiometricCipherProviderImpl.instance;` (line 43).
- Add `final BiometricCipherProvider _secureProvider;` as a field (after `_storage`, before `_stateController`).
- Add `@visibleForTesting BiometricCipherProvider? secureProvider` to the constructor parameter list.
- Add `_secureProvider = secureProvider ?? BiometricCipherProviderImpl.instance` to the initializer list.

### Step 4: Task 6.1 -- Add `fromString` test to `packages/biometric_cipher/test/biometric_cipher_test.dart`

Add a new top-level `group('BiometricCipherExceptionCode', ...)` after the existing `group('BiometricCipher tests', ...)` block. Inside it, add one test:

```dart
group('BiometricCipherExceptionCode', () {
  test('fromString KEY_PERMANENTLY_INVALIDATED returns keyPermanentlyInvalidated', () {
    // Arrange
    const code = 'KEY_PERMANENTLY_INVALIDATED';

    // Act
    final result = BiometricCipherExceptionCode.fromString(code);

    // Assert
    expect(result, BiometricCipherExceptionCode.keyPermanentlyInvalidated);
  });
});
```

Import: `package:biometric_cipher/data/biometric_cipher_exception_code.dart` (or it may already be available via the existing `package:biometric_cipher/biometric_cipher.dart` re-export).

### Step 5: Tasks 6.2 and 6.4 -- Create `test/security/biometric_cipher_provider_test.dart`

New file with the following structure:

```
group('BiometricCipherProviderImpl', () {
  group('_mapExceptionToBiometricException', () {
    test('maps keyPermanentlyInvalidated to BiometricExceptionType.keyInvalidated')  // 6.2
    test('maps authenticationError to BiometricExceptionType.failure')                // 6.4a
    test('maps authenticationUserCanceled to BiometricExceptionType.cancel')          // 6.4b
  });
});
```

Each test:
1. Creates `MockBiometricCipher`.
2. Constructs `BiometricCipherProviderImpl.forTesting(mockCipher)`.
3. Stubs `mockCipher.decrypt(tag: any(named: 'tag'), data: any(named: 'data'))` to throw a `BiometricCipherException` with the target `code` and `message: 'test'`.
4. Calls `provider.decrypt(tag: 'tag', data: Uint8List.fromList([1]))`.
5. Expects the thrown `BiometricException` to have the expected `type`.

Imports: `package:test/test.dart`, `package:mocktail/mocktail.dart`, `dart:typed_data`, `package:biometric_cipher/biometric_cipher.dart`, `package:locker/security/biometric_cipher_provider.dart`, `package:locker/security/models/exceptions/biometric_exception.dart`, and `../mocks/mock_biometric_cipher.dart`.

### Step 6: Task 6.3 -- Add `teardownBiometryPasswordOnly` tests to `test/locker/mfa_locker_test.dart`

Add a new `group('teardownBiometryPasswordOnly', ...)` inside the `group('MFALocker', ...)` block, positioned after the `wrap management` group.

The group's `setUp` block creates a `MockBiometricCipherProvider` and constructs a separate `MFALocker` instance with both `storage` and `secureProvider` injected:

```dart
group('teardownBiometryPasswordOnly', () {
  late MockBiometricCipherProvider secureProvider;
  late MFALocker lockerWithSecureProvider;

  setUp(() {
    secureProvider = MockBiometricCipherProvider();
    lockerWithSecureProvider = MFALocker(
      file: MockFile(),
      storage: storage,
      secureProvider: secureProvider,
    );
  });

  tearDown(() {
    lockerWithSecureProvider.dispose();
  });

  // 6.3a, 6.3b, 6.3c tests here
});
```

**Test 6.3a -- Happy path:**
- Stub `storage.readAllMeta` via `_Helpers.stubReadAllMeta(storage, pwd)`.
- Stub `storage.deleteWrap(originToDelete: Origin.bio, cipherFunc: pwd)` to return `true`.
- Stub `secureProvider.deleteKey(tag: 'tag')` to complete successfully.
- Call `lockerWithSecureProvider.teardownBiometryPasswordOnly(passwordCipherFunc: pwd, biometricKeyTag: 'tag')`.
- Verify `storage.deleteWrap` called once with `originToDelete: Origin.bio`, `cipherFunc: pwd`.
- Verify `secureProvider.deleteKey(tag: 'tag')` called once.
- No exception.

**Test 6.3b -- `deleteKey` throws, suppressed:**
- Same stubs as 6.3a, except `secureProvider.deleteKey(tag: 'tag')` throws `Exception('key gone')`.
- Call `teardownBiometryPasswordOnly`.
- Assert no exception propagates (the method completes normally).

**Test 6.3c -- Locked state, `verifyInOrder`:**
- Locker starts locked (default after construction).
- Stub `storage.readAllMeta` and `storage.deleteWrap` as in 6.3a.
- Stub `secureProvider.deleteKey` to succeed.
- Call `teardownBiometryPasswordOnly`.
- `verifyInOrder([() => storage.readAllMeta(cipherFunc: pwd), () => storage.deleteWrap(originToDelete: Origin.bio, cipherFunc: pwd)])`.

Add import for `MockBiometricCipherProvider` at the top of `mfa_locker_test.dart`:
```dart
import '../mocks/mock_biometric_cipher_provider.dart';
```

### Step 7: Verify

1. Run `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` -- must exit 0.
2. Run `fvm flutter test` (root) -- must pass all tests including new ones.
3. Run `fvm flutter test packages/biometric_cipher/test/biometric_cipher_test.dart` -- must pass.

---

## Open Questions

None.
