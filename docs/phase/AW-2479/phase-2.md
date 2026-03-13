# Phase 2: Update `EncryptedStorage` + `EncryptedStorageImpl`

**Goal:** Replace the single-entry `init` signature with `List<EntryInput> initialEntries` and add an optional `EntryId? id` parameter to `addEntry` on both the abstract interface and its implementation.

## Context

AW-2479 extends the library so callers can pass multiple initial entries to `init` and optionally supply a fixed `EntryId` when calling `addEntry`. Phase 1 introduced the `EntryInput` type and `duplicateEntry` exception. This phase wires them into the storage layer.

**Files to change:**

| File | Action |
|------|--------|
| `lib/storage/encrypted_storage.dart` | Update `init` and `addEntry` signatures |
| `lib/storage/encrypted_storage_impl.dart` | Implement loop in `init`, optional id + duplicate check in `addEntry` |

## Tasks

- [x] 2.1 `EncryptedStorage.init` — replace `initialEntryMeta`/`initialEntryValue` with `List<EntryInput> initialEntries`
- [x] 2.2 `EncryptedStorageImpl.init` — loop over `initialEntries`, use `entry.id?.value ?? _generateEntryId()`, validate no duplicate explicit IDs, allow empty list
- [x] 2.3 `EncryptedStorage.addEntry` — add optional `EntryId? id` parameter
- [x] 2.4 `EncryptedStorageImpl.addEntry` — use `id ?? EntryId(_generateEntryId())`, duplicate check when `id != null`

## Acceptance Criteria

**Test:** `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` passes (tests will fail until phase 3 fixes them — that is expected).

## Dependencies

- Phase 1 complete ✅ (`EntryInput` and `duplicateEntry` exist)

## Technical Details

### `EncryptedStorageImpl.init`

- Loop over `initialEntries`; for each entry use `entry.id?.value ?? _generateEntryId()` as the storage key.
- Validate no duplicate explicit IDs **within the list** before writing any entry. Throw `StorageException.duplicateEntry` if a clash is found.
- An empty list is explicitly allowed — creates storage with master key, salt, HMAC, and an empty entries array.
- Spread pattern for erasables: `[passwordCipherFunc, ...initialEntries]` handles cleanup via `_executeWithCleanup`.

### `EncryptedStorageImpl.addEntry`

- Accept optional `EntryId? id` parameter (positional or named, consistent with existing style).
- Use `id?.value ?? _generateEntryId()` instead of always generating.
- Duplicate check runs **only when `id != null`** — UUID v4 collisions without an explicit ID are astronomically improbable and not worth the overhead.
- When an explicit ID is provided and already exists, throw `StorageException.duplicateEntry(entryId: id.value)`.

### Signature changes

| Layer | Method | Old params | New params |
|-------|--------|-----------|------------|
| `EncryptedStorage` | `init` | `EntryMeta initialEntryMeta, EntryValue initialEntryValue` | `List<EntryInput> initialEntries` |
| `EncryptedStorage` | `addEntry` | (no id param) | `EntryId? id` added |

## Implementation Notes

- Existing tests will break after this phase (they pass the old single-entry signature). That is expected — phase 3 fixes them.
- `EncryptedStorage` is an abstract class; update its abstract method signatures first, then update `EncryptedStorageImpl` to implement them.
- Keep the `@visibleForTesting` constructor for injection — no changes needed there.

## Code Review Fixes

- [ ] **Task 1: Guarantee `initialEntries` erasure on early validation failure in `EncryptedStorageImpl.init`**
  - In `lib/storage/encrypted_storage_impl.dart`, the `_validateNoDuplicateExplicitIds(initialEntries)` call (line 123) and `CryptographyUtils.generateAESKey()` (line 125) are placed before the `try`/`finally` block that erases `initialEntries`. If either throws, the sensitive `EntryInput` data is not erased.
  - Move the validation and key generation inside the `try` block, or wrap the entry erasure in an outer `finally` to ensure cleanup on all exit paths.
  - Acceptance criteria:
    - If `_validateNoDuplicateExplicitIds` throws, all `initialEntries` are still erased before the exception propagates.
    - If `CryptographyUtils.generateAESKey()` throws, all `initialEntries` are still erased before the exception propagates.

- [ ] **Task 2: Align `init` erasure pattern with established `EncryptedStorageImpl` conventions**
  - In `lib/storage/encrypted_storage_impl.dart`, the `init` method erases caller-provided `initialEntries` in its `finally` block (lines 171-173), but `addEntry` does NOT erase caller-provided `entryMeta`/`entryValue`. This breaks the established pattern where `EncryptedStorageImpl` methods do not take ownership of caller-provided erasable data (that is `MFALocker._executeWithCleanup`'s responsibility).
  - Either: (a) remove `initialEntries` erasure from `EncryptedStorageImpl.init` to match the `addEntry` pattern and let the caller handle cleanup, or (b) add a code comment explaining why `init` is intentionally different.
  - Acceptance criteria:
    - The erasure responsibility for `initialEntries` is consistent with the erasure pattern used by `addEntry` for `entryMeta`/`entryValue`, OR the deviation is documented with a comment explaining the rationale.
