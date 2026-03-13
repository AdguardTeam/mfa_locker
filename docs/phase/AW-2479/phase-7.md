# Phase 7: Update example app

**Goal:** Update `LockerRepositoryImpl.init` to use the new `initialEntries: [EntryInput(...)]` signature. The `addEntry`/`addEntryWithBiometric` methods do not use explicit IDs and need no changes.

## Context

Phase 5 changed `Locker.init` to accept `List<EntryInput> initialEntries` instead of `EntryMeta initialEntryMeta, EntryValue initialEntryValue`. The example app's `LockerRepositoryImpl.init` still uses the old signature, causing a compilation error.

**Files to change:**

| File | Action |
|------|--------|
| `example/lib/features/locker/data/repositories/locker_repository.dart` | Add `EntryInput` import, update `_locker.init(...)` call |

## Tasks

- [x] 7.1 Add `import 'package:locker/storage/models/domain/entry_input.dart';` (after `entry_id.dart`, alphabetical)
- [x] 7.2 In `LockerRepositoryImpl.init`, replace the old `_locker.init(...)` call with `initialEntries: [EntryInput(meta: entryMeta, value: entryValue)]`

## Acceptance Criteria

**Test:** `cd example && make analyze` — exits 0 with no warnings or infos.

## Dependencies

- Phase 5 complete (`Locker` + `MFALocker` updated)

## Technical Details

### Current code (lines 179–184)

```dart
await _locker.init(
  passwordCipherFunc: passwordCipherFunc,
  initialEntryMeta: entryMeta,
  initialEntryValue: entryValue,
  lockTimeout: lockTimeout,
);
```

### Updated code

```dart
await _locker.init(
  passwordCipherFunc: passwordCipherFunc,
  initialEntries: [EntryInput(meta: entryMeta, value: entryValue)],
  lockTimeout: lockTimeout,
);
```

### Import to add (after `entry_id.dart`, alphabetical)

```dart
import 'package:locker/storage/models/domain/entry_input.dart';
```

Current import block for reference:
```dart
import 'package:locker/storage/models/domain/entry_id.dart';
// ← insert here
import 'package:locker/storage/models/domain/entry_meta.dart';
import 'package:locker/storage/models/domain/entry_value.dart';
```

## Implementation Notes

- `entryMeta` and `entryValue` locals are already created before the `_locker.init` call — no changes to those lines.
- `addEntry` and `addEntryWithBiometric` call `_locker.write(...)` without an explicit `id` — no changes needed there.
- The `EntryInput` constructor takes named params `meta:` and `value:` (no `id:` needed here since we want an auto-generated UUID for the first entry).
