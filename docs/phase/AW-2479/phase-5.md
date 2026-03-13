# Phase 5: Update `Locker` + `MFALocker`

**Goal:** Mirror the storage-layer signature changes at the locker layer: replace `initialEntryMeta`/`initialEntryValue` in `Locker.init`/`MFALocker.init` with `List<EntryInput> initialEntries`, and add an optional `EntryId? id` parameter to `Locker.write`/`MFALocker.write`.

## Context

Phase 2 updated `EncryptedStorage.init` and `EncryptedStorage.addEntry`. `MFALocker` still calls the old storage signatures, so `fvm flutter analyze` currently fails. This phase fixes the locker layer to compile and forward the new parameters.

**Files to change:**

| File | Action |
|------|--------|
| `lib/locker/locker.dart` | Update `init` and `write` signatures; add `EntryInput` import |
| `lib/locker/mfa_locker.dart` | Update `init` and `write` implementations; add `EntryInput` import |

## Tasks

- [x] 5.1 Add `import 'package:locker/storage/models/domain/entry_input.dart';` to `lib/locker/locker.dart`
- [x] 5.2 `Locker.init` — replace `EntryMeta initialEntryMeta, EntryValue initialEntryValue` with `List<EntryInput> initialEntries`; update doc comment
- [x] 5.3 `Locker.write` — add optional named `EntryId? id` parameter; update doc comment
- [x] 5.4 Add `import 'package:locker/storage/models/domain/entry_input.dart';` to `lib/locker/mfa_locker.dart`
- [x] 5.5 `MFALocker.init` — update signature, change `erasables` list, forward `initialEntries` to `_storage.init`
- [x] 5.6 `MFALocker.write` — add `EntryId? id` parameter; forward to `_storage.addEntry(id: id, ...)`

## Acceptance Criteria

**Test:** `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` passes. (Locker tests will break until Phase 6 fixes them — that is expected.)

## Dependencies

- Phase 1 complete ✅ (`EntryInput` exists)
- Phase 2 complete ✅ (`EncryptedStorage` interface already updated)

## Technical Details

### 5.1–5.2: `lib/locker/locker.dart` — `init` signature

Add import (alphabetical among `package:locker/storage/models/domain/` imports):

```dart
import 'package:locker/storage/models/domain/entry_input.dart';
```

Change signature (remove old params, remove `entry_meta` and `entry_value` imports **only if** no other method on the interface still references them — they are still needed for `write`, `update`, etc., so keep those imports):

```dart
// Before
Future<void> init({
  required PasswordCipherFunc passwordCipherFunc,
  required EntryMeta initialEntryMeta,
  required EntryValue initialEntryValue,
  required Duration lockTimeout,
});

// After
Future<void> init({
  required PasswordCipherFunc passwordCipherFunc,
  required List<EntryInput> initialEntries,
  required Duration lockTimeout,
});
```

Update the doc comment: remove the phrase "creates the first entry" and replace with "stores the provided initial entries (may be empty)".

### 5.3: `lib/locker/locker.dart` — `write` signature

```dart
// Before
Future<EntryId> write({
  required EntryMeta entryMeta,
  required EntryValue entryValue,
  required CipherFunc cipherFunc,
});

// After
Future<EntryId> write({
  required EntryMeta entryMeta,
  required EntryValue entryValue,
  required CipherFunc cipherFunc,
  EntryId? id,
});
```

Add to doc comment: `/// [id] - Optional fixed entry ID. When provided, a duplicate check is performed. Throws [StorageException] if [id] already exists.`

### 5.4–5.5: `lib/locker/mfa_locker.dart` — `MFALocker.init`

Add import:
```dart
import 'package:locker/storage/models/domain/entry_input.dart';
```

```dart
// Before
@override
Future<void> init({
  required PasswordCipherFunc passwordCipherFunc,
  required EntryMeta initialEntryMeta,
  required EntryValue initialEntryValue,
  required Duration lockTimeout,
}) =>
    _sync(
      () => _executeWithCleanup(
        erasables: [passwordCipherFunc, initialEntryMeta, initialEntryValue],
        callback: () async {
          if (await isStorageInitialized) {
            throw StateError('Storage is already initialized');
          }

          await _storage.init(
            passwordCipherFunc: passwordCipherFunc,
            initialEntryMeta: initialEntryMeta,
            initialEntryValue: initialEntryValue,
            lockTimeout: lockTimeout.inMilliseconds,
          );

          await loadAllMetaIfLocked(passwordCipherFunc);
        },
      ),
    );

// After
@override
Future<void> init({
  required PasswordCipherFunc passwordCipherFunc,
  required List<EntryInput> initialEntries,
  required Duration lockTimeout,
}) =>
    _sync(
      () => _executeWithCleanup(
        erasables: [passwordCipherFunc, ...initialEntries],
        callback: () async {
          if (await isStorageInitialized) {
            throw StateError('Storage is already initialized');
          }

          await _storage.init(
            passwordCipherFunc: passwordCipherFunc,
            initialEntries: initialEntries,
            lockTimeout: lockTimeout.inMilliseconds,
          );

          await loadAllMetaIfLocked(passwordCipherFunc);
        },
      ),
    );
```

### 5.6: `lib/locker/mfa_locker.dart` — `MFALocker.write`

```dart
// Before
@override
Future<EntryId> write({
  required EntryMeta entryMeta,
  required EntryValue entryValue,
  required CipherFunc cipherFunc,
}) =>
    _sync(
      () => _executeWithCleanup<EntryId>(
        // dispose entryMeta only on error because it is cached
        erasables: [cipherFunc, entryValue],
        erasablesOnError: [entryMeta],
        callback: () async {
          await loadAllMetaIfLocked(cipherFunc);

          final id = await _storage.addEntry(
            entryMeta: entryMeta,
            entryValue: entryValue,
            cipherFunc: cipherFunc,
          );

          _metaCache[id]?.erase();
          _metaCache[id] = entryMeta;

          return id;
        },
      ),
    );

// After
@override
Future<EntryId> write({
  required EntryMeta entryMeta,
  required EntryValue entryValue,
  required CipherFunc cipherFunc,
  EntryId? id,
}) =>
    _sync(
      () => _executeWithCleanup<EntryId>(
        // dispose entryMeta only on error because it is cached
        erasables: [cipherFunc, entryValue],
        erasablesOnError: [entryMeta],
        callback: () async {
          await loadAllMetaIfLocked(cipherFunc);

          final entryId = await _storage.addEntry(
            entryMeta: entryMeta,
            entryValue: entryValue,
            cipherFunc: cipherFunc,
            id: id,
          );

          _metaCache[entryId]?.erase();
          _metaCache[entryId] = entryMeta;

          return entryId;
        },
      ),
    );
```

Note the local variable rename from `id` to `entryId` to avoid shadowing the `id` parameter.

## Implementation Notes

- `entry_meta.dart` and `entry_value.dart` imports in both files stay — they are used by `write`, `update`, `readValue`, and others.
- The `entry_input.dart` import goes in alphabetical order among the `domain/` imports.
- Tests will break after this phase (they still use the old `initialEntryMeta`/`initialEntryValue` call sites). That is expected — Phase 6 fixes them.
- Do not change any test files in this phase.
