# AW-2479: List of initial entries in `init` + optional `EntryId` in `addEntry`/`write`

**Current Phase:** 7

## Progress

| # | Task | Status |
|---|------|--------|
| 1 | Create `EntryInput` model + `duplicateEntry` exception | ✅ Complete |
| 2 | Update `EncryptedStorage` + `EncryptedStorageImpl` | ✅ Complete |
| 3 | Fix existing storage tests | ✅ Complete |
| 4 | Add new storage tests | ✅ Complete |
| 5 | Update `Locker` + `MFALocker` | ✅ Complete |
| 6 | Fix existing locker tests + add new | ✅ Complete |
| 7 | Update example app | ⬜ Pending |
| 8 | Final QA: format, analyze, full test suite | ⬜ Pending |

---

## Tasks

### 1. Create `EntryInput` model + `duplicateEntry` exception

- [ ] Create `lib/storage/models/domain/entry_input.dart` — `EntryInput` class with `EntryId? id`, `EntryMeta meta`, `EntryValue value`, implements `Erasable`
- [ ] Add `duplicateEntry` to `StorageExceptionType` enum in `lib/storage/models/exceptions/storage_exception.dart`
- [ ] Add `factory StorageException.duplicateEntry({required String entryId})`
- [ ] Export `EntryInput` from `lib/locker.dart` barrel file

**Verify:** `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .`

---

### 2. Update `EncryptedStorage` + `EncryptedStorageImpl`

- [ ] `EncryptedStorage.init` — replace `initialEntryMeta`/`initialEntryValue` with `List<EntryInput> initialEntries`
- [ ] `EncryptedStorageImpl.init` — loop over `initialEntries`, use `entry.id?.value ?? _generateEntryId()`, validate no duplicate explicit IDs, allow empty list
- [ ] `EncryptedStorage.addEntry` — add optional `EntryId? id` parameter
- [ ] `EncryptedStorageImpl.addEntry` — use `id ?? EntryId(_generateEntryId())`, duplicate check when `id != null`

**Verify:** `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` (tests will fail until step 3)

---

### 3. Fix existing storage tests

- [ ] Update 5 existing `init` tests — wrap single entry in `[EntryInput(...)]`
- [ ] Update 4 existing `addEntry` tests — no signature change needed (id is optional)

**Verify:** `fvm flutter test test/storage/encrypted_storage_impl_test.dart`

---

### 4. Add new storage tests

- [ ] `init` creates storage with empty entries list
- [ ] `init` creates storage with multiple entries
- [ ] `init` creates storage with explicit entry IDs
- [ ] `init` creates storage mixing explicit and generated IDs
- [ ] `init` throws on duplicate explicit IDs
- [ ] `addEntry` stores entry with explicit id
- [ ] `addEntry` throws on duplicate explicit id

**Verify:** `fvm flutter test test/storage/encrypted_storage_impl_test.dart`

---

### 5. Update `Locker` + `MFALocker`

- [ ] `Locker.init` — replace `initialEntryMeta`/`initialEntryValue` with `List<EntryInput> initialEntries`
- [ ] `MFALocker.init` — `erasables: [passwordCipherFunc, ...initialEntries]`, forward list to `_storage.init`
- [ ] `Locker.write` — add optional `EntryId? id` parameter
- [ ] `MFALocker.write` — forward `id` to `_storage.addEntry(id: id, ...)`

**Verify:** `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .`

---

### 6. Fix existing locker tests + add new

- [x] Update 3 existing `init` tests — wrap single entry in `[EntryInput(...)]`, update mock stubs
- [x] Update 4 existing `write` tests — update mock stubs for optional `id`
- [x] Add test: `write` passes explicit id to `storage.addEntry`

**Verify:** `fvm flutter test test/locker/mfa_locker_test.dart`

---

### 7. Update example app

- [ ] `LockerRepositoryImpl.init` — wrap single entry in `[EntryInput(meta: entryMeta, value: entryValue)]`
- [ ] `addEntry`/`addEntryWithBiometric` — unchanged (don't use explicit IDs)

**Verify:** `cd example && make analyze`

---

### 8. Final QA

- [ ] `fvm dart format . --line-length 120`
- [ ] `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .`
- [ ] `fvm flutter test` — all tests pass
