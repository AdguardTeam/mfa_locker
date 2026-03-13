# Phase 3: Fix existing storage tests

**Goal:** Update the 5 existing `init` tests in `encrypted_storage_impl_test.dart` to use the new `List<EntryInput> initialEntries` API, and confirm the 4 existing `addEntry` tests still pass without changes (since `EntryId? id` is an optional parameter).

## Context

Phase 2 changed `EncryptedStorage.init` to accept `List<EntryInput> initialEntries` instead of `EntryMeta initialEntryMeta, EntryValue initialEntryValue`. The existing `init` tests pass the old signature and must be migrated. The `addEntry` signature gained an optional `EntryId? id` parameter — backward-compatible, so those tests need no edits but must still be confirmed green.

**Files to change:**

| File | Action |
|------|--------|
| `test/storage/encrypted_storage_impl_test.dart` | Update `init` group (5 tests); verify `addEntry` group (4 tests) |

**File under test:** `lib/storage/encrypted_storage_impl.dart`

### Phase 2 Code Review Fixes (prerequisite)

Phase 2's `phase-2.md` lists two open code-review items that affect correctness. These should be resolved **before** or **alongside** this phase, since the tests may expose the issues:

1. **Guarantee `initialEntries` erasure on early validation failure** — if `_validateNoDuplicateExplicitIds` or `CryptographyUtils.generateAESKey()` throw, `initialEntries` must still be erased. Move validation inside the `try` block.
2. **Align erasure pattern with `addEntry`** — either remove `initialEntries` erasure from `EncryptedStorageImpl.init`'s `finally` block (matching `addEntry`) or add a comment explaining the intentional difference.

## Tasks

- [x] 3.1 Add `import 'package:locker/storage/models/domain/entry_input.dart';` to `encrypted_storage_impl_test.dart`
- [x] 3.2 Update test `'creates storage file on init'` — replace `initialEntryMeta`/`initialEntryValue` with `initialEntries: [EntryInput(meta: entryMeta, value: entryValue)]`
- [x] 3.3 Update test `'throws when already initialized'` — same migration
- [x] 3.4 Update test `'does not create file when encrypt fails'` — same migration
- [x] 3.5 Update test `'throws when lockTimeout is zero'` — same migration
- [x] 3.6 Update test `'throws when lockTimeout is negative'` — same migration
- [x] 3.7 Verify the 4 `addEntry` tests pass without any edits

## Acceptance Criteria

**Test:** `fvm flutter test test/storage/encrypted_storage_impl_test.dart` — all tests pass, zero failures.

## Dependencies

- Phase 1 complete ✅ (`EntryInput` and `duplicateEntry` exist)
- Phase 2 complete ✅ (`EncryptedStorage.init` / `addEntry` signatures updated)
- Phase 2 code-review fixes addressed (see above)

## Technical Details

### Current test pattern (broken after Phase 2)

```dart
await storage.init(
  passwordCipherFunc: cipherFunc,
  initialEntryMeta: entryMeta,   // ← old param, no longer exists
  initialEntryValue: entryValue, // ← old param, no longer exists
  lockTimeout: _Helpers.lockTimeout,
);
```

### Updated test pattern

```dart
await storage.init(
  passwordCipherFunc: cipherFunc,
  initialEntries: [EntryInput(meta: entryMeta, value: entryValue)],
  lockTimeout: _Helpers.lockTimeout,
);
```

### Helper usage

`_Helpers.createEntryMeta()` and `_Helpers.createEntryValue()` are unchanged — construct `EntryInput` inline using them:

```dart
final entryMeta = _Helpers.createEntryMeta();
final entryValue = _Helpers.createEntryValue();
// ...
initialEntries: [EntryInput(meta: entryMeta, value: entryValue)],
```

### `addEntry` — no test changes needed

The updated abstract signature is:

```dart
Future<EntryId> addEntry({
  required EntryMeta entryMeta,
  required EntryValue entryValue,
  required CipherFunc cipherFunc,
  EntryId? id,   // ← new optional param; existing tests omit it → still valid
});
```

The 4 existing `addEntry` tests do not pass `id`, so they remain valid as-is. Just run them to confirm they pass.

## Implementation Notes

- Only `test/storage/encrypted_storage_impl_test.dart` needs edits in this phase.
- Do not add new tests here — that is Phase 4.
- Do not change any `lib/` source files — that is Phase 2's scope (and its code-review fixes).
