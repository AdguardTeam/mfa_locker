# Phase 4: Add new storage tests

**Goal:** Add 7 new tests to `test/storage/encrypted_storage_impl_test.dart` covering the new behaviours introduced in Phase 2: multi-entry `init`, explicit entry IDs, and duplicate-ID detection in both `init` and `addEntry`.

## Context

Phase 2 added:
- `EncryptedStorage.init` now accepts `List<EntryInput> initialEntries` (may be empty; may contain explicit `EntryId`s; duplicate explicit IDs throw `StorageException.duplicateEntry`)
- `EncryptedStorage.addEntry` now accepts an optional `EntryId? id`; when provided, a duplicate check is performed

Phase 3 migrated the existing tests. This phase adds the tests that verify the new behaviours end-to-end.

**File to change:**

| File | Action |
|------|--------|
| `test/storage/encrypted_storage_impl_test.dart` | Add 7 new tests inside existing `init` and `addEntry` groups |

## Tasks

- [x] 4.1 `init` creates storage with empty entries list
- [x] 4.2 `init` creates storage with multiple entries
- [x] 4.3 `init` creates storage with explicit entry IDs
- [x] 4.4 `init` creates storage mixing explicit and generated IDs
- [x] 4.5 `init` throws on duplicate explicit IDs
- [x] 4.6 `addEntry` stores entry with explicit id
- [x] 4.7 `addEntry` throws on duplicate explicit id

## Acceptance Criteria

**Test:** `fvm flutter test test/storage/encrypted_storage_impl_test.dart` — all tests pass, zero failures.

## Dependencies

- Phase 1 complete ✅ (`EntryInput` and `duplicateEntry` exist)
- Phase 2 complete ✅ (implementation supports all new behaviours)
- Phase 3 complete ✅ (existing tests green; `EntryInput` import already in test file)

## Technical Details

### Helpers available

From `EncryptedStorageTestHelpers` (imported as `_Helpers`):

```dart
_Helpers.createMockPasswordCipherFunc()     // MockPasswordCipherFunc with default stubs
_Helpers.createMockPasswordCipherFunc(masterKeyBytes: ...)  // cipher that decrypts to given key
_Helpers.createEntryMeta([bytes])           // EntryMeta
_Helpers.createEntryValue([bytes])          // EntryValue
_Helpers.readStorageData(storageFile)       // StorageData from file
```

`EntryInput` is already imported (added in task 3.1).

### Test patterns

#### 4.1 — empty entries list

```dart
test('creates storage with empty entries list', () async {
  final cipherFunc = _Helpers.createMockPasswordCipherFunc();

  await storage.init(
    passwordCipherFunc: cipherFunc,
    initialEntries: [],
    lockTimeout: _Helpers.lockTimeout,
  );

  final data = await _Helpers.readStorageData(storageFile);
  expect(data.entries, isEmpty);
  expect(data.masterKey.wraps, isNotEmpty);
});
```

#### 4.2 — multiple entries

```dart
test('creates storage with multiple entries', () async {
  final cipherFunc = _Helpers.createMockPasswordCipherFunc();
  final entries = [
    EntryInput(meta: _Helpers.createEntryMeta([1]), value: _Helpers.createEntryValue([1])),
    EntryInput(meta: _Helpers.createEntryMeta([2]), value: _Helpers.createEntryValue([2])),
    EntryInput(meta: _Helpers.createEntryMeta([3]), value: _Helpers.createEntryValue([3])),
  ];

  await storage.init(
    passwordCipherFunc: cipherFunc,
    initialEntries: entries,
    lockTimeout: _Helpers.lockTimeout,
  );

  final data = await _Helpers.readStorageData(storageFile);
  expect(data.entries, hasLength(3));
});
```

#### 4.3 — explicit entry IDs

```dart
test('creates storage with explicit entry IDs', () async {
  final cipherFunc = _Helpers.createMockPasswordCipherFunc();
  const id1 = 'explicit-id-1';
  const id2 = 'explicit-id-2';
  final entries = [
    EntryInput(id: EntryId(id1), meta: _Helpers.createEntryMeta(), value: _Helpers.createEntryValue()),
    EntryInput(id: EntryId(id2), meta: _Helpers.createEntryMeta(), value: _Helpers.createEntryValue()),
  ];

  await storage.init(
    passwordCipherFunc: cipherFunc,
    initialEntries: entries,
    lockTimeout: _Helpers.lockTimeout,
  );

  final data = await _Helpers.readStorageData(storageFile);
  final ids = data.entries.map((e) => e.id.value).toList();
  expect(ids, containsAll([id1, id2]));
});
```

#### 4.4 — mixing explicit and generated IDs

```dart
test('creates storage mixing explicit and generated IDs', () async {
  final cipherFunc = _Helpers.createMockPasswordCipherFunc();
  const explicitId = 'my-explicit-id';
  final entries = [
    EntryInput(id: EntryId(explicitId), meta: _Helpers.createEntryMeta(), value: _Helpers.createEntryValue()),
    EntryInput(meta: _Helpers.createEntryMeta(), value: _Helpers.createEntryValue()),
  ];

  await storage.init(
    passwordCipherFunc: cipherFunc,
    initialEntries: entries,
    lockTimeout: _Helpers.lockTimeout,
  );

  final data = await _Helpers.readStorageData(storageFile);
  expect(data.entries, hasLength(2));
  expect(data.entries.map((e) => e.id.value), contains(explicitId));
});
```

#### 4.5 — duplicate explicit IDs throw

```dart
test('throws on duplicate explicit IDs', () async {
  final cipherFunc = _Helpers.createMockPasswordCipherFunc();
  const duplicateId = 'duplicate-id';
  final entries = [
    EntryInput(id: EntryId(duplicateId), meta: _Helpers.createEntryMeta(), value: _Helpers.createEntryValue()),
    EntryInput(id: EntryId(duplicateId), meta: _Helpers.createEntryMeta(), value: _Helpers.createEntryValue()),
  ];

  await expectLater(
    () => storage.init(
      passwordCipherFunc: cipherFunc,
      initialEntries: entries,
      lockTimeout: _Helpers.lockTimeout,
    ),
    throwsA(isA<StorageException>()),
  );
  expect(await storageFile.exists(), isFalse);
});
```

> **Note:** This test also exercises the Phase 2 code-review fix (Task 1): the duplicate-ID exception is thrown by `_validateNoDuplicateExplicitIds` **before** entering the `try` block. If the fix has been applied (validation moved inside `try`), the file will not be created. If the fix has NOT been applied, the test still passes (the exception propagates), but the `initialEntries` erasure guarantee may be violated. The `storageFile.exists()` assertion confirms no partial write occurred.

#### 4.6 — addEntry with explicit id

```dart
test('stores entry with explicit id', () async {
  final masterKey = await CryptographyUtils.generateAESKey();
  final cipherFunc = _Helpers.createMockPasswordCipherFunc(masterKeyBytes: masterKey.bytes);
  final wrapPwd = KeyWrap(origin: Origin.pwd, encryptedKey: masterKey.bytes);
  final signedData = await _Helpers.createStorageData(wraps: [wrapPwd], masterKey: masterKey);
  await _Helpers.writeStorageData(storageFile, signedData);

  const explicitId = 'my-entry-id';

  final returnedId = await storage.addEntry(
    entryMeta: _Helpers.createEntryMeta(),
    entryValue: _Helpers.createEntryValue(),
    cipherFunc: cipherFunc,
    id: EntryId(explicitId),
  );

  expect(returnedId.value, equals(explicitId));
  final updated = await _Helpers.readStorageData(storageFile);
  expect(updated.entries.map((e) => e.id.value), contains(explicitId));
});
```

#### 4.7 — addEntry throws on duplicate explicit id

```dart
test('throws on duplicate explicit id', () async {
  final masterKey = await CryptographyUtils.generateAESKey();
  final cipherFunc = _Helpers.createMockPasswordCipherFunc(masterKeyBytes: masterKey.bytes);
  final wrapPwd = KeyWrap(origin: Origin.pwd, encryptedKey: masterKey.bytes);
  const existingId = 'existing-id';
  final existingEntry = await _Helpers.createEncryptedEntry(masterKey: masterKey, id: existingId);
  final signedData = await _Helpers.createStorageData(
    wraps: [wrapPwd],
    entries: [existingEntry],
    masterKey: masterKey,
  );
  await _Helpers.writeStorageData(storageFile, signedData);

  await _Helpers.expectFileUnchanged(
    storageFile,
    () => expectLater(
      storage.addEntry(
        entryMeta: _Helpers.createEntryMeta(),
        entryValue: _Helpers.createEntryValue(),
        cipherFunc: cipherFunc,
        id: EntryId(existingId),
      ),
      throwsA(isA<StorageException>()),
    ),
  );
});
```

## Implementation Notes

- Add the 5 new `init` tests inside the existing `group('init', ...)` block, after the current 5 tests.
- Add the 2 new `addEntry` tests inside the existing `group('addEntry', ...)` block, after the current 4 tests.
- Do not reorder or modify any existing test.
- `EntryId` is already imported; `EntryInput` was added in Phase 3 (task 3.1).
- `KeyWrap`, `Origin`, and `CryptographyUtils` are already imported.

## Open Prerequisites

The Phase 2 code-review fixes (tracked in `phase-2.md`) remain open. Test 4.5 indirectly exercises the erasure path but does not assert it. These fixes should be resolved before the overall feature merges.

## Code Review Fixes

- [ ] **Task 1: Assert specific `StorageExceptionType.duplicateEntry` in duplicate-detection tests**
  - In `test/storage/encrypted_storage_impl_test.dart`, tests 4.5 (line 341, `throws on duplicate explicit IDs`) and 4.7 (line 814, `throws on duplicate explicit id`) only assert `throwsA(isA<StorageException>())`. This is too broad -- any `StorageException` type (e.g., `alreadyInitialized`, `invalidStorage`, `other`) would satisfy the assertion. Since these tests exist specifically to verify duplicate-ID detection, they should assert the precise exception type.
  - Change the matcher in both tests from `throwsA(isA<StorageException>())` to `throwsA(isA<StorageException>().having((e) => e.type, 'type', StorageExceptionType.duplicateEntry))`.
  - Acceptance criteria:
    - Test 4.5 (`throws on duplicate explicit IDs`) asserts `StorageExceptionType.duplicateEntry`
    - Test 4.7 (`throws on duplicate explicit id`) asserts `StorageExceptionType.duplicateEntry`
    - All tests still pass: `fvm flutter test test/storage/encrypted_storage_impl_test.dart`
