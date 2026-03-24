# Research: AW-2160 Phase 6 — Unit Tests for Biometric Key Invalidation and Password-Only Teardown

## Resolved Questions

**Q1 — MockBiometricCipherProvider placement:**
Add to `test/mocks/` as a reusable file (e.g., `test/mocks/mock_biometric_cipher_provider.dart`), consistent with `MockEncryptedStorage`, `MockBioCipherFunc`, etc.

**Q2 — MFALocker constructor param for secureProvider:**
Add the `@visibleForTesting` `secureProvider` parameter to the existing `MFALocker` constructor (the single constructor that already has the `storage` `@visibleForTesting` param), not in a separate `forTesting` named constructor. The constructor signature currently is:
```dart
MFALocker({
  required File file,
  @visibleForTesting EncryptedStorage? storage,
})
```
The new `secureProvider` param will be added alongside `storage` in the same constructor.

**Q3 — verifyInOrder style:**
`verifyInOrder` is not currently used in any existing test file. The PRD mandates it for Task 6.3c (ordered verification that `readAllMeta` precedes `deleteWrap`). The syntax from the `mocktail` library is:
```dart
verifyInOrder([
  () => storage.readAllMeta(cipherFunc: pwd),
  () => storage.deleteWrap(originToDelete: Origin.bio, cipherFunc: pwd),
]);
```

**Q4 — Private method testing surface:**
For Tasks 6.2 and 6.4, testing `_mapExceptionToBiometricException` indirectly via `provider.decrypt(tag: ..., data: ...)` configured to throw a `BiometricCipherException`. The natural integration point is `decrypt` because both `encrypt` and `decrypt` contain the `on BiometricCipherException catch (e, stackTrace) { Error.throwWithStackTrace(_mapExceptionToBiometricException(e), stackTrace); }` block.

---

## Phase Scope

Phase 6 is purely additive — tests only, plus one minimal production change:

1. **Task 6.1** — Add `fromString('KEY_PERMANENTLY_INVALIDATED')` test to `packages/biometric_cipher/test/biometric_cipher_test.dart` (existing file).
2. **Task 6.2** — Create `test/security/biometric_cipher_provider_test.dart` (new file). Test that `BiometricCipherProviderImpl` maps `keyPermanentlyInvalidated` → `BiometricExceptionType.keyInvalidated`.
3. **Task 6.3** — Add three `teardownBiometryPasswordOnly` tests to `test/locker/mfa_locker_test.dart` (existing file): happy path (6.3a), suppressed `deleteKey` error (6.3b), `verifyInOrder` call ordering (6.3c).
4. **Task 6.4** — Add regression tests for `authenticationError` → `failure` and `authenticationUserCanceled` → `cancel` to the new provider test file.
5. **Production change** — Add `@visibleForTesting BiometricCipherProvider? secureProvider` parameter to `MFALocker` constructor. The getter `BiometricCipherProvider get _secureProvider` must be replaced to use the injected value when present.

---

## Related Modules/Services

### Production files touched

| File | Role |
|------|------|
| `lib/locker/mfa_locker.dart` | Only change: add `@visibleForTesting` `secureProvider` constructor param and wire it into `_secureProvider` |
| `lib/security/biometric_cipher_provider.dart` | `BiometricCipherProviderImpl` — has `forTesting(BiometricCipher)` constructor and `_mapExceptionToBiometricException` switch; `decrypt` is the integration point for mapping tests |
| `packages/biometric_cipher/lib/data/biometric_cipher_exception_code.dart` | `BiometricCipherExceptionCode.fromString` — line 99 maps `'KEY_PERMANENTLY_INVALIDATED'` → `keyPermanentlyInvalidated` |
| `lib/security/models/exceptions/biometric_exception.dart` | `BiometricException` and `BiometricExceptionType` (including `keyInvalidated`) — used in assert expressions |

### Test infrastructure files

| File | Role |
|------|------|
| `test/mocks/mock_encrypted_storage.dart` | `MockEncryptedStorage extends Mock implements EncryptedStorage` — already used in locker tests |
| `test/mocks/mock_bio_cipher_func.dart` | `MockBioCipherFunc` — pattern for new mock file |
| `test/mocks/mock_password_cipher_func.dart` | `MockPasswordCipherFunc` — same pattern |
| `test/locker/mfa_locker_test.dart` | Main locker test file — Tasks 6.3a/b/c added here |
| `test/locker/mfa_locker_test_helpers.dart` | `part of` the locker test — contains `_Helpers` helpers including `stubReadAllMeta`, `verifyErasedAll` |
| `packages/biometric_cipher/test/biometric_cipher_test.dart` | Task 6.1 added here — uses `flutter_test` (not plain `test`) |
| `packages/biometric_cipher/test/mock_biometric_cipher_platform.dart` | Full mock platform, not needed for new tests |

### New files to create

| File | Purpose |
|------|---------|
| `test/mocks/mock_biometric_cipher_provider.dart` | `MockBiometricCipherProvider extends Mock implements BiometricCipherProvider` |
| `test/security/biometric_cipher_provider_test.dart` | Tasks 6.2 and 6.4 — provider exception mapping tests |

---

## Current Endpoints and Contracts

### `MFALocker` constructor (current)

```dart
MFALocker({
  required File file,
  @visibleForTesting EncryptedStorage? storage,
}) : _storage = storage ?? EncryptedStorageImpl(file: file);
```

`_secureProvider` is currently a getter (no backing field):
```dart
BiometricCipherProvider get _secureProvider => BiometricCipherProviderImpl.instance;
```

After the Phase 6 change, a nullable backing field `_secureProvider` (or an equivalent pattern) is needed so that injected providers take precedence over `BiometricCipherProviderImpl.instance`.

### `teardownBiometryPasswordOnly` (Phase 5 implementation, complete)

```dart
Future<void> teardownBiometryPasswordOnly({
  required PasswordCipherFunc passwordCipherFunc,
  required String biometricKeyTag,
}) async {
  await _sync(
    () => _executeWithCleanup(
      erasables: [passwordCipherFunc],
      callback: () async {
        await loadAllMetaIfLocked(passwordCipherFunc);
        await _storage.deleteWrap(originToDelete: Origin.bio, cipherFunc: passwordCipherFunc);
      },
    ),
  );
  try {
    await _secureProvider.deleteKey(tag: biometricKeyTag);
  } catch (_, __) {
    logger.logWarning('teardownBiometryPasswordOnly: failed to delete biometric key, suppressing');
  }
}
```

Key contract points:
- `loadAllMetaIfLocked` is called first (inside `_sync`+`_executeWithCleanup`).
- `_storage.deleteWrap` is called second (still inside `_sync`).
- `_secureProvider.deleteKey` is called **outside** `_sync` and **after** the `_sync` block completes.
- Any exception from `deleteKey` is caught and suppressed (only logged as warning).

### `BiometricCipherProviderImpl` — `forTesting` constructor

```dart
@visibleForTesting
BiometricCipherProviderImpl.forTesting(this._biometricCipher);
```

Accepts a `BiometricCipher` instance. The test creates a `MockBiometricCipher` (which mocks `BiometricCipher`, not `BiometricCipherPlatform`), configures `decrypt` to throw `BiometricCipherException`, and verifies the thrown `BiometricException` type.

### `BiometricCipherException` constructor

```dart
const BiometricCipherException({
  required BiometricCipherExceptionCode code,
  required String message,
  Object? details,
});
```

Requires both `code` and `message`. When constructing throw-stubs in tests, a non-empty `message` must be provided.

### `EncryptedStorage.deleteWrap` signature

```dart
Future<bool> deleteWrap({
  required Origin originToDelete,
  required CipherFunc cipherFunc,
});
```

Returns `bool`. In existing stub patterns (`disableBiometry` tests), it is stubbed with `.thenAnswer((_) async => true)`.

---

## Patterns Used

### Mock class pattern (from `test/mocks/`)

All three existing mock files follow the identical minimal pattern:
```dart
class MockXxx extends Mock implements Xxx {}
```
`MockBiometricCipherProvider` follows the same pattern, implementing `BiometricCipherProvider`.

### Test file header / imports for `test/security/biometric_cipher_provider_test.dart`

The new provider test file sits under the root `locker` package (not inside `biometric_cipher`). It needs:
- `package:test/test.dart` (not `flutter_test`, since no widgets are involved and the root package uses plain `test`)
- `package:mocktail/mocktail.dart`
- `package:biometric_cipher/biometric_cipher.dart` (exports `BiometricCipherException` and `BiometricCipherExceptionCode`)
- `package:locker/security/biometric_cipher_provider.dart`
- `package:locker/security/models/exceptions/biometric_exception.dart`
- Relative import of `../mocks/mock_biometric_cipher_provider.dart` (but the mock wraps `BiometricCipherProvider`, not `BiometricCipher`)

Wait — important distinction: `BiometricCipherProviderImpl.forTesting` takes a `BiometricCipher`, so the test must mock `BiometricCipher`, not `BiometricCipherProvider`. `BiometricCipher` is a concrete class. A `MockBiometricCipher` must be created. Looking at how `BiometricCipherProviderImpl.forTesting` is designed:

```dart
BiometricCipherProviderImpl.forTesting(this._biometricCipher);
// _biometricCipher is typed as BiometricCipher (a concrete class)
```

`BiometricCipher` is a concrete class but `mocktail` can mock concrete classes. The `decrypt` call chain is:
`provider.decrypt(tag, data)` → `_biometricCipher.decrypt(tag: ..., data: ...)` → `BiometricCipherException` thrown → caught → `_mapExceptionToBiometricException` → `BiometricException` rethrown.

For the mock to work, `MockBiometricCipher extends Mock implements BiometricCipher` is needed. This lives in the `test/mocks/` directory as `mock_biometric_cipher.dart`.

The existing mocks in `test/mocks/` are: `MockEncryptedStorage`, `MockBioCipherFunc`, `MockPasswordCipherFunc`, `MockFile` — all implement interfaces or abstract classes. `BiometricCipher` is a concrete class, but `Mock` can still mock it. Alternatively, a `MockBiometricCipherProvider` that mocks `BiometricCipherProvider` directly could be used instead of going through `forTesting`, but the PRD constraint says to use `BiometricCipherProviderImpl.forTesting(mockBiometricCipher)`.

### `stubReadAllMeta` helper (from `test/locker/mfa_locker_test_helpers.dart`)

```dart
static Map<EntryId, EntryMeta> stubReadAllMeta(
  MockEncryptedStorage storage,
  CipherFunc cipher, {
  String id = 'a',
  List<int> metaBytes = const [1],
}) {
  when(() => storage.readAllMeta(cipherFunc: cipher)).thenAnswer((_) async => result);
  return result;
}
```

For Tasks 6.3a/b/c, this helper will be called with the `PasswordCipherFunc`. The `deleteWrap` stub must be set up separately:
```dart
when(
  () => storage.deleteWrap(originToDelete: Origin.bio, cipherFunc: pwd),
).thenAnswer((_) async => true);
```

### `verifyInOrder` (mocktail API)

`verifyInOrder` is available in `mocktail` 1.0.3 (the pinned version). Syntax:
```dart
verifyInOrder([
  () => mock.methodA(namedArg: value),
  () => mock.methodB(namedArg: value),
]);
```
This is the first use of `verifyInOrder` in the codebase.

### `// Arrange / // Act / // Assert` pattern

All existing tests use this three-section comment pattern consistently. New tests must follow it.

### `setUpAll` / `registerFallbackValue`

`mfa_locker_test.dart` has a `setUpAll` block registering fallback values. No new fallback values are expected for the `teardownBiometryPasswordOnly` tests because `Origin` and `PasswordCipherFunc` are already used in existing tests. If `BiometricCipherProvider` is used in `setUpAll`, the `MockBiometricCipherProvider` must be added there, but since `_secureProvider.deleteKey` is the only method called and it takes a `String tag` (no custom types), no new `registerFallbackValue` call is needed.

### `biometric_cipher_test.dart` imports (Task 6.1)

The existing file uses `flutter_test` (not plain `test`). The new `fromString` test is a pure Dart test (no widgets), but it must be added inside the existing file which already imports `flutter_test`. The import for `BiometricCipherExceptionCode.fromString` is available via `package:biometric_cipher/data/biometric_cipher_exception_code.dart` or through the existing `package:biometric_cipher/biometric_cipher.dart` re-export.

---

## Phase-Specific Limitations and Risks

### Risk 1 — `BiometricCipher` is a concrete class

`BiometricCipherProviderImpl.forTesting` takes `BiometricCipher`, which is a concrete class. `mocktail` can mock concrete classes, but the mock must be declared as `class MockBiometricCipher extends Mock implements BiometricCipher`. However, `BiometricCipher`'s `decrypt` method is not `abstract` — it contains guard logic (`if (_configured == false) throw ...`) before calling `_instance.decrypt(...)`. If the mock does not override that logic, a stub `when(() => mockCipher.decrypt(...)).thenThrow(...)` on the `MockBiometricCipher` will throw before `BiometricCipherProviderImpl` can catch it.

Concretely: `BiometricCipherProviderImpl.decrypt` calls `_biometricCipher.decrypt(tag: tag, data: base64Data)`, and `BiometricCipher.decrypt` first checks `_configured`. On the `MockBiometricCipher`, `_configured` defaults to `false` for a fresh instance, so the `configureError` guard fires before `_instance.decrypt` is reached — and `MockBiometricCipher` bypasses that because `Mock` overrides all methods at the `Mock` level, not at the `BiometricCipher` level. Since `MockBiometricCipher extends Mock implements BiometricCipher`, the `decrypt` call goes to `mocktail`'s stubbing, not to `BiometricCipher`'s implementation. The configured guard in `BiometricCipher.decrypt` is NOT invoked. The stub `when(() => mockCipher.decrypt(tag: any(named: 'tag'), data: any(named: 'data'))).thenThrow(BiometricCipherException(...))` will work correctly.

### Risk 2 — `teardownBiometryPasswordOnly` calls `_secureProvider.deleteKey` outside `_sync`

The suppression test (6.3b) verifies that no exception propagates. Because `deleteKey` is called outside the `_sync` block (after `await _sync(...)`), the injected `MockBiometricCipherProvider` is accessed through the production `_secureProvider` getter. Once the production code is changed to accept the injected provider, the mock's `deleteKey` stub takes effect. This is only testable after the minimal production change is in place.

### Risk 3 — `MFALocker._secureProvider` is currently a getter, not a field

```dart
BiometricCipherProvider get _secureProvider => BiometricCipherProviderImpl.instance;
```

To inject a test provider, this getter must be changed to read from a nullable field that falls back to `BiometricCipherProviderImpl.instance`. The most idiomatic change is:

```dart
// field:
final BiometricCipherProvider _secureProvider;

// constructor addition:
MFALocker({
  required File file,
  @visibleForTesting EncryptedStorage? storage,
  @visibleForTesting BiometricCipherProvider? secureProvider,
}) : _storage = storage ?? EncryptedStorageImpl(file: file),
     _secureProvider = secureProvider ?? BiometricCipherProviderImpl.instance;
```

This removes the getter and replaces it with a final field. Existing call sites pass no `secureProvider` argument and get `BiometricCipherProviderImpl.instance` by default. The existing test `setUp` constructs `MFALocker(file: MockFile(), storage: storage)` — no change needed there.

### Risk 4 — `verifyInOrder` requires that calls actually occurred in order

For Task 6.3c, the locker starts locked (default state after construction). `storage.readAllMeta` is called inside `_sync` via `loadAllMetaIfLocked`, and `storage.deleteWrap` is called next, still inside `_sync`. `verifyInOrder` will pass if both mocks were invoked and `readAllMeta` was recorded before `deleteWrap` in mocktail's invocation log. Since `teardownBiometryPasswordOnly` internally runs them sequentially, this should be reliable.

### Risk 5 — `biometric_cipher_test.dart` uses `flutter_test` while root package tests use plain `test`

The Task 6.1 addition goes into `packages/biometric_cipher/test/biometric_cipher_test.dart`, which already uses `flutter_test`. That's fine — it just means the test runner for that file is `fvm flutter test packages/biometric_cipher/test/biometric_cipher_test.dart`. The new test added there must not use any plain `test` import — it must stay consistent with the file's existing `import 'package:flutter_test/flutter_test.dart'`.

### Risk 6 — `BiometricCipherException` requires `message`

When constructing `BiometricCipherException` in test stubs, the `message` field is `required`. This is easy to forget. Any test that constructs `BiometricCipherException(code: ...)` without `message` will fail to compile.

---

## New Technical Questions Discovered During Research

**TQ1 — Mock for `BiometricCipher` vs `BiometricCipherProvider`?**
`BiometricCipherProviderImpl.forTesting` accepts `BiometricCipher` (concrete class), so a `MockBiometricCipher` is needed for Tasks 6.2 and 6.4 — not `MockBiometricCipherProvider`. A `MockBiometricCipherProvider` is separately needed for Task 6.3b (injected into `MFALocker`). Confirm: are both `mock_biometric_cipher.dart` and `mock_biometric_cipher_provider.dart` to be added to `test/mocks/`, or should `MockBiometricCipher` live inside the new provider test file only?

**TQ2 — `deleteKey` stub return value for the happy path (6.3a)?**
In 6.3a, `_secureProvider.deleteKey` is called (the real `BiometricCipherProviderImpl.instance`) unless a `secureProvider` is injected. For the happy-path test (6.3a), should `secureProvider` also be injected with a mock that stubs `deleteKey` to succeed, or should the test rely on the real provider? Given the real provider would attempt TPM access in a unit test context and likely fail, it seems safest to always inject `MockBiometricCipherProvider` for all three 6.3 sub-tests.

**TQ3 — Group name for teardownBiometryPasswordOnly tests?**
The existing `mfa_locker_test.dart` groups are: `getters`, `init`, `loadAllMeta`, `loadAllMetaIfLocked`, `lock`, `write`, `readValue`, `delete`, `update`, `wrap management`, `eraseStorage`, `race-condition safety`. Should the new tests go under `wrap management` (since it's a wrap removal operation), or under a new top-level group named `teardownBiometryPasswordOnly`?

**TQ4 — `registerFallbackValue` for `MockBiometricCipherProvider` in `setUpAll`?**
The `teardownBiometryPasswordOnly` tests inject `MockBiometricCipherProvider` into `MFALocker`. The `deleteKey({required String tag})` call only uses `String` — no custom type fallback needed. No `registerFallbackValue` addition is expected, but confirm whether any `any(named: ...)` matchers will be used that might require it.
