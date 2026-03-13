# Phase 6: Fix existing locker tests + add new

**Goal:** Update `test/locker/mfa_locker_test.dart` to compile and pass after the Phase 5 signature changes: replace old `initialEntryMeta`/`initialEntryValue` call sites in `init` tests with `initialEntries: [EntryInput(...)]`, update `write` test stubs to include the new optional `id` parameter, and add one new test verifying that an explicit `EntryId` is forwarded to `storage.addEntry`.

## Context

Phase 5 changed two signatures:
- `Locker.init` / `MFALocker.init`: replaced `EntryMeta initialEntryMeta, EntryValue initialEntryValue` with `List<EntryInput> initialEntries`
- `Locker.write` / `MFALocker.write`: added optional `EntryId? id`; the impl always passes `id: id` to `_storage.addEntry`

The test file currently uses the old `init` signature -> **compilation failure**. The `write` test stubs don't specify `id` -> stubs may not match the updated call site. Both must be fixed.

**Files to change:**

| File | Action |
|------|--------|
| `test/locker/mfa_locker_test.dart` | Update 3 `init` tests, update 4 `write` tests, add 1 new `write` test |

## Tasks

- [x] 6.1 Add `import 'package:locker/storage/models/domain/entry_input.dart';` to the test file (alphabetical among `domain/` imports)
- [x] 6.2 Update `init` test "loads meta, unlocks locker" -- replace old params with `initialEntries`
- [x] 6.3 Update `init` test "throws when storage already initialized" -- replace old params with `initialEntries`
- [x] 6.4 Update `init` test "rethrows on storage error" -- replace old params with `initialEntries`
- [x] 6.5 Update 4 `write` tests -- add `id: null` (or `id: any(named: 'id')` for `any` matchers) to `storage.addEntry` stubs
- [x] 6.6 Add new test "passes explicit id to storage.addEntry" in the `write` group

## Acceptance Criteria

**Test:** `fvm flutter test test/locker/mfa_locker_test.dart` -- all tests pass.

## Dependencies

- Phase 5 complete (`Locker` + `MFALocker` updated)

## Technical Details

### 6.1: Import

Add after the existing `entry_meta.dart` import line (alphabetical):

```dart
import 'package:locker/storage/models/domain/entry_input.dart';
```

### 6.2-6.4: `init` test changes

The three tests in `group('init', ...)` currently call:

```dart
// OLD -- compilation error
locker.init(
  passwordCipherFunc: pwd,
  initialEntryMeta: meta,
  initialEntryValue: value,
  lockTimeout: _Helpers.lockTimeout,
);
```

Change to:

```dart
// NEW
final entry = EntryInput(meta: meta, value: value);
// ...
locker.init(
  passwordCipherFunc: pwd,
  initialEntries: [entry],
  lockTimeout: _Helpers.lockTimeout,
);
```

Update every `when` stub and `verify` / `verifyNever` call that references `storage.init` similarly:

```dart
// OLD stub
when(
  () => storage.init(
    passwordCipherFunc: pwd,
    initialEntryMeta: meta,
    initialEntryValue: value,
    lockTimeout: _Helpers.lockTimeout.inMilliseconds,
  ),
).thenAnswer(...);

// NEW stub
when(
  () => storage.init(
    passwordCipherFunc: pwd,
    initialEntries: [entry],
    lockTimeout: _Helpers.lockTimeout.inMilliseconds,
  ),
).thenAnswer(...);
```

For `verifyNever` in the "throws when storage already initialized" test:

```dart
// OLD
verifyNever(
  () => storage.init(
    passwordCipherFunc: any(named: 'passwordCipherFunc'),
    initialEntryMeta: any(named: 'initialEntryMeta'),
    initialEntryValue: any(named: 'initialEntryValue'),
    lockTimeout: any(named: 'lockTimeout'),
  ),
);

// NEW
verifyNever(
  () => storage.init(
    passwordCipherFunc: any(named: 'passwordCipherFunc'),
    initialEntries: any(named: 'initialEntries'),
    lockTimeout: any(named: 'lockTimeout'),
  ),
);
```

**Erasable verification:** `_Helpers.verifyErasedAll([pwd, meta, value])` remains valid -- `EntryInput.erase()` erases `meta` and `value` transitively. Alternatively, replace with `_Helpers.verifyErasedAll([pwd, entry])` since `entry.isErased` delegates to both.

### 6.5: `write` test stub updates

`MFALocker.write` now calls `_storage.addEntry(..., id: id)`. When `write` is called without an explicit `id`, it passes `id: null`. Update every existing `when` / `verify` / `verifyNever` stub for `storage.addEntry` to include `id: null` (for exact-value stubs) or `id: any(named: 'id')` (for `any`-matcher stubs):

```dart
// Exact-value stubs -- add id: null
when(
  () => storage.addEntry(
    entryMeta: metaToAdd,
    entryValue: valueToAdd,
    cipherFunc: cipher,
    id: null,             // <- add
  ),
).thenAnswer((_) async => expectedId);

verify(
  () => storage.addEntry(
    entryMeta: metaToAdd,
    entryValue: valueToAdd,
    cipherFunc: cipher,
    id: null,             // <- add
  ),
).called(1);

// any-matcher stubs (verifyNever) -- add id: any(named: 'id')
verifyNever(
  () => storage.addEntry(
    entryMeta: any(named: 'entryMeta'),
    entryValue: any(named: 'entryValue'),
    cipherFunc: any(named: 'cipherFunc'),
    id: any(named: 'id'),  // <- add
  ),
);
```

Also update the race-condition test "two concurrent write calls are serialized" (lines 1154-1186) which also stubs `storage.addEntry` without `id`.

### 6.6: New test -- "passes explicit id to storage.addEntry"

Add inside `group('write', ...)`, after the last existing write test:

```dart
test('passes explicit id to storage.addEntry', () async {
  // Arrange
  final cipher = _Helpers.createMockPasswordCipherFunc();
  final meta = _StorageHelpers.createEntryMeta([1, 2]);
  final value = _StorageHelpers.createEntryValue();
  final explicitId = EntryId('my-custom-id');

  _Helpers.stubReadAllMeta(storage, cipher);
  await locker.loadAllMeta(cipher);

  when(
    () => storage.addEntry(
      entryMeta: meta,
      entryValue: value,
      cipherFunc: cipher,
      id: explicitId,
    ),
  ).thenAnswer((_) async => explicitId);

  // Act
  final result = await locker.write(
    entryMeta: meta,
    entryValue: value,
    cipherFunc: cipher,
    id: explicitId,
  );

  // Assert
  verify(
    () => storage.addEntry(
      entryMeta: meta,
      entryValue: value,
      cipherFunc: cipher,
      id: explicitId,
    ),
  ).called(1);

  expect(result, equals(explicitId));
  expect(locker.allMeta[explicitId], same(meta));

  _Helpers.verifyErasedAll([cipher, value]);
});
```

## Implementation Notes

- The `entry_input.dart` import must be added -- `EntryInput` is not yet imported in the test file.
- `meta` and `value` local variables in the `init` tests stay; they are still needed to build `EntryInput` and to verify erasure.
- `registerFallbackValue` in `setUpAll` does not need a fallback for `EntryInput` because mocktail only needs fallbacks for types used with `any()` matchers, and no `init` test uses `any(named: 'initialEntries')`.
- Do not touch tests outside `init` and `write` groups (other groups compile and pass as-is).

## Code Review Fixes

- [ ] **Task 1: Add explicit `id: null` to `when`/`verify` stubs in 3 write tests**
  - The phase plan (task 6.5) requires adding `id: null` to every exact-value `when`/`verify` for `storage.addEntry`. Three tests are missing it:
    - "updates cache and call the storage.addEntry" (lines 342-364): add `id: null` to both `when(...)` and `verify(...)` calls
    - "replaces existing meta and erases previous one when id matches" (lines 384-398): add `id: null` to `when(...)`
    - "rethrows on storage error" (lines 413-419): add `id: null` to `when(...)`
  - Also add `id: null` to the two `verify(...)` calls in the race-condition test "two concurrent write calls are serialized" (lines 1228-1231)
  - Acceptance criteria:
    - Every `when(() => storage.addEntry(...))` and `verify(() => storage.addEntry(...))` in the `write` and `race-condition` groups includes `id: null` (for exact-value stubs) or `id: any(named: 'id')` (for any-matcher stubs)
    - `fvm flutter test test/locker/mfa_locker_test.dart` -- all tests pass
