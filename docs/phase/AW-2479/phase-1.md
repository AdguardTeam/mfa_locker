# Phase 1: Create `EntryInput` model + `duplicateEntry` exception

**Goal:** Add the two foundational building blocks needed by subsequent phases — the `EntryInput` domain type and the `duplicateEntry` storage exception.

## Context

AW-2479 extends the library so callers can pass multiple initial entries to `init` and optionally supply a fixed `EntryId` when calling `addEntry`/`write`. Both changes require a new domain type that bundles `(EntryId?, EntryMeta, EntryValue)` and a new typed exception for duplicate-ID detection.

This phase is purely additive — no existing code is modified.

## Tasks

- [x] 1.1 Create `lib/storage/models/domain/entry_input.dart` — `EntryInput` class with `EntryId? id`, `EntryMeta meta`, `EntryValue value`, implements `Erasable`
- [x] 1.2 Add `duplicateEntry` to `StorageExceptionType` enum in `lib/storage/models/exceptions/storage_exception.dart`
- [x] 1.3 Add `factory StorageException.duplicateEntry({required String entryId})`
- [x] 1.4 Export `EntryInput` from `lib/locker.dart` barrel file — SKIPPED: project does not use barrel files; `EntryInput` is importable via direct path `package:locker/storage/models/domain/entry_input.dart`, consistent with all other types

## Technical Details

### `EntryInput` class

```dart
// lib/storage/models/domain/entry_input.dart
class EntryInput implements Erasable {
  final EntryId? id;
  final EntryMeta meta;
  final EntryValue value;

  const EntryInput({this.id, required this.meta, required this.value});

  @override
  bool get isErased => meta.isErased && value.isErased;

  @override
  void erase() {
    meta.erase();
    value.erase();
  }
}
```

- `id` is optional — when `null`, the storage layer auto-generates a UUID v4.
- Implements `Erasable` so it integrates with `_executeWithCleanup` when spread into the `erasables` list in `MFALocker.init`.

### `duplicateEntry` exception

```dart
// In StorageExceptionType enum
duplicateEntry,

// Factory in StorageException
factory StorageException.duplicateEntry({required String entryId}) => StorageException(
  type: StorageExceptionType.duplicateEntry,
  message: 'Entry with id $entryId already exists',
);
```

Used by `addEntry` when an explicit `EntryId` is provided and an entry with that ID already exists in storage.

## Acceptance Criteria

**Test:** `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` passes with no warnings or errors.

## Dependencies

- None — this is the first phase and is purely additive.

## Implementation Notes

- One type per file: `EntryInput` goes in `entry_input.dart` (file name matches type name).
- `id` field is NOT erased in `erase()` because `EntryId` wraps a plain `String` — no sensitive data to zero out.
