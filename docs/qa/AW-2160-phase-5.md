# QA Plan: AW-2160 Phase 5 — `teardownBiometryPasswordOnly` Method

Status: REVIEWED
Date: 2026-03-17

---

## Phase Scope

Phase 5 is the final phase of AW-2160. It delivers one new public method — `teardownBiometryPasswordOnly` — to both the `Locker` abstract interface and the `MFALocker` implementation. The method allows the app layer to remove a stale `Origin.bio` wrap using password authentication alone, without triggering a biometric prompt. This is the necessary cleanup path after the app detects `BiometricExceptionType.keyInvalidated` (Phase 4).

**Exactly two production files changed:**
- `lib/locker/locker.dart` — new method declaration added immediately after `teardownBiometry` (lines 161–173).
- `lib/locker/mfa_locker.dart` — new method implementation added immediately after `teardownBiometry` (lines 440–459).

**No new files. No storage data model changes. No new unit tests (user decision).**

---

## Implementation Status (observed)

All source files were read directly from the repository.

**`lib/locker/locker.dart`** — verified:
- `teardownBiometryPasswordOnly` is declared at lines 170–173 with the exact signature specified in the plan: `Future<void> teardownBiometryPasswordOnly({required PasswordCipherFunc passwordCipherFunc, required String biometricKeyTag})`.
- The doc comment at lines 161–169 matches the agreed text verbatim: describes use case (permanently invalidated key), explains `biometricKeyTag` usage, and states errors are suppressed.
- Positioned immediately after `teardownBiometry` (lines 156–159). Correct placement.
- All other method declarations are unchanged.

**`lib/locker/mfa_locker.dart`** — verified:
- `teardownBiometryPasswordOnly` is implemented at lines 440–459.
- Storage phase is wrapped in `await _sync(() => _executeWithCleanup(...))` with `erasables: [passwordCipherFunc]`. Matches the single-cipher pattern used by `disableBiometry`, `readValue`, and `updateLockTimeout`.
- Callback: calls `loadAllMetaIfLocked(passwordCipherFunc)` then `_storage.deleteWrap(originToDelete: Origin.bio, cipherFunc: passwordCipherFunc)`. Correct — mirrors `disableBiometry` body with only `passwordCipherFunc`.
- Hardware key deletion is outside `_sync`, in a trailing `try/catch` block:
  ```dart
  try {
    await _secureProvider.deleteKey(tag: biometricKeyTag);
  } catch (_, __) {
    logger.logWarning('teardownBiometryPasswordOnly: failed to delete biometric key, suppressing');
  }
  ```
  This matches the specified log message exactly and places key deletion outside the lock (matching `teardownBiometry`'s pattern).
- `bioCipherFunc` is never referenced in this method. No biometric prompt is possible.
- `teardownBiometry` at lines 426–438 is unchanged.
- `disableBiometry` at lines 301–314 is unchanged.
- `_executeWithCleanup` at lines 461–480 is unchanged.

**`deleteWrap` behavior when `Origin.bio` is absent** — verified by reading `encrypted_storage_impl.dart` lines 227–265:
- When `Origin.bio` wrap does not exist, `updatedWraps.length == currentWraps.length` is `true`, and `StorageException.other('The wrap to delete was not found')` is thrown.
- That `StorageException` is caught by the generic `catch (e, st)` block (lines 258–261) and returns `false`. It is not rethrown.
- Conclusion: calling `teardownBiometryPasswordOnly` when no `Origin.bio` wrap exists returns normally from `_storage.deleteWrap` (returns `false`), and the caller proceeds to the hardware key deletion step without error propagation. This is the correct silent-success behavior for Scenario 5.

---

## Positive Scenarios

### PS-1: Successful password-only teardown after key invalidation (locker locked)

**Setup:** `MFALocker` with mock `EncryptedStorage`. Locker is in locked state. `_storage.isInitialized` returns `true`. `_storage.readAllMeta` (called via `loadAllMetaIfLocked`) returns an empty map. `_storage.deleteWrap` returns `true`.

**Steps:**
1. App has detected `BiometricExceptionType.keyInvalidated`.
2. App calls `locker.teardownBiometryPasswordOnly(passwordCipherFunc: pc, biometricKeyTag: 'myBioTag')`.
3. `loadAllMetaIfLocked(pc)` authenticates, transitions locker to `unlocked`.
4. `_storage.deleteWrap(originToDelete: Origin.bio, cipherFunc: pc)` is called and returns `true`.
5. `_secureProvider.deleteKey(tag: 'myBioTag')` succeeds.
6. `passwordCipherFunc.erase()` is called in `finally`.

**Expected:**
- Method returns normally (no exception).
- Locker state is `unlocked` after completion.
- `_storage.deleteWrap` was called with `originToDelete: Origin.bio` and the password cipher.
- `passwordCipherFunc.erase()` was called exactly once.
- No `BioCipherFunc` was instantiated or involved.

**How to verify:** Dart unit test using `MockEncryptedStorage` (infrastructure already exists in `test/mocks/`). Not written for this phase.

---

### PS-2: Successful password-only teardown when locker already unlocked

**Setup:** Same as PS-1 but locker is already in `unlocked` state.

**Steps:**
1. `loadAllMetaIfLocked` short-circuits (locker already unlocked, returns immediately).
2. `_storage.deleteWrap` is called.
3. `_secureProvider.deleteKey` is called.

**Expected:**
- Method returns normally.
- `_storage.readAllMeta` is NOT called (locker was already unlocked).
- `_storage.deleteWrap` was called once with `originToDelete: Origin.bio`.

**How to verify:** Dart unit test. Not written for this phase.

---

### PS-3: Hardware key already deleted by OS — suppressed error, method returns normally

**Setup:** `_storage.deleteWrap` returns `true` (wrap removed). `_secureProvider.deleteKey` throws any `Exception`.

**Steps:**
1. `_storage.deleteWrap` succeeds.
2. `_secureProvider.deleteKey` throws.
3. `catch (_, __)` catches the error and calls `logger.logWarning(...)`.

**Expected:**
- Method returns normally without rethrowing.
- A warning is logged with the exact message: `'teardownBiometryPasswordOnly: failed to delete biometric key, suppressing'`.
- `passwordCipherFunc.erase()` was still called (the `finally` block executed before the key deletion step).

**How to verify:** Dart unit test. Not written for this phase.

---

### PS-4: Biometric wrap absent — silent success (Scenario 5)

**Setup:** `_storage.deleteWrap` returns `false` (internally `StorageException.other` was thrown and caught, resulting in `false` return). `_secureProvider.deleteKey` succeeds.

**Expected:**
- `_storage.deleteWrap` call completes without throwing from the caller's perspective (returns `false`).
- `teardownBiometryPasswordOnly` proceeds to call `_secureProvider.deleteKey`.
- Method returns normally.
- No exception propagates.

**How to verify:** Dart unit test with `deleteWrap` mocked to return `false`. Not written for this phase.

---

### PS-5: After teardown, `setupBiometry` can be called to re-enable biometrics

**Setup:** Following a successful `teardownBiometryPasswordOnly`, `isBiometricEnabled` returns `false`. The app then calls `setupBiometry` with a new key tag.

**Expected:**
- `setupBiometry` succeeds because the stale bio wrap is gone.
- `isBiometricEnabled` returns `true` after `setupBiometry`.

**How to verify:** Integration-level test or manual verification on a device. Not automated for this phase.

---

### PS-6: Method signature compiles and is accessible on `Locker` interface

**Verification:** `teardownBiometryPasswordOnly` is declared on the abstract interface `Locker`. Any variable of type `Locker` exposes the method. Confirmed by reading `locker.dart` lines 161–173.

---

### PS-7: Existing `teardownBiometry` behavior is completely unchanged

**Verification:** `teardownBiometry` at lines 426–438 of `mfa_locker.dart` is identical to the pre-Phase-5 implementation. It still calls `disableBiometry(bioCipherFunc: bioCipherFunc, passwordCipherFunc: passwordCipherFunc)` followed by `_secureProvider.deleteKey(tag: bioCipherFunc.keyTag)`. No parameters were made optional. No internal logic was touched.

**How to verify:** `fvm flutter test` — all existing tests that exercise `teardownBiometry` pass without modification. No existing tests for `teardownBiometry` were found in `test/locker/mfa_locker_test.dart` (confirming no existing test is broken). Code inspection.

---

## Negative and Edge Cases

### NC-1: Wrong password — authentication exception propagates unchanged

**Setup:** `loadAllMetaIfLocked` calls `_storage.readAllMeta`, which throws a `DecryptFailedException` because the password is wrong.

**Expected:**
- `DecryptFailedException` propagates out of `teardownBiometryPasswordOnly`.
- `_storage.deleteWrap` is NOT called.
- `_secureProvider.deleteKey` is NOT called.
- `passwordCipherFunc.erase()` IS called (it is in the `erasables` list, which is erased in `finally` regardless of success or failure).

**How to verify:** Dart unit test with `_storage.readAllMeta` mocked to throw. Not written for this phase.

---

### NC-2: Storage not initialized — `StateError` propagates

**Setup:** `_storage.isInitialized` returns `false`. `loadAllMetaIfLocked` throws `StateError('Storage is not initialized')`.

**Expected:**
- `StateError` propagates out of `teardownBiometryPasswordOnly`.
- `deleteWrap` and `deleteKey` are not called.
- `passwordCipherFunc.erase()` is called.

**How to verify:** Dart unit test with `isInitialized` mocked to return `false`. Not written for this phase.

---

### NC-3: `deleteWrap` throws an unexpected non-suppressed exception

**Setup:** `_storage.deleteWrap` throws `BiometricException` or `DecryptFailedException` (the two re-thrown cases in `EncryptedStorageImpl.deleteWrap`). However, these should not occur in the password-only path — a `PasswordCipherFunc` will not produce a `BiometricException`, and a `DecryptFailedException` implies wrong-password which would already have been caught at `loadAllMetaIfLocked`. This edge case is a safety check.

**Expected:**
- If `deleteWrap` throws, `_executeWithCleanup` catches and rethrows after logging.
- `passwordCipherFunc.erase()` is called (in `finally`).
- `_secureProvider.deleteKey` is NOT called (the `await _sync(...)` block threw, so execution never reaches the trailing `try/catch`).

**How to verify:** Code inspection of `_executeWithCleanup` (lines 461–480) and the sequential structure of `teardownBiometryPasswordOnly`.

---

### NC-4: `_secureProvider.deleteKey` throws — does not propagate

**Setup:** `_storage.deleteWrap` succeeds. `_secureProvider.deleteKey` throws any exception (e.g., key not found, platform error).

**Expected:**
- Exception is swallowed by `catch (_, __)`.
- `logger.logWarning` is called.
- Method returns normally.
- The caller receives no exception despite the hardware key deletion failure.

**How to verify:** Dart unit test with `deleteKey` mocked to throw. Not written for this phase.

---

### NC-5: `biometricKeyTag` is an empty string

**Setup:** Caller passes `biometricKeyTag: ''`.

**Expected:**
- No validation on `biometricKeyTag` is performed by `teardownBiometryPasswordOnly` itself. It passes the empty string to `_secureProvider.deleteKey`.
- The provider's behavior with an empty tag is platform-defined. Any error thrown by `deleteKey` is suppressed.
- `_storage.deleteWrap` still runs normally; the wrap is still removed.

**How to verify:** Code inspection — no guard is present in the implementation, consistent with the spec. The caller is responsible for the correct tag per the doc comment.

---

### NC-6: Method called multiple times — idempotent on storage

**Setup:** `teardownBiometryPasswordOnly` is called twice with the same password cipher func (but a fresh instance each time, since the first call erases it).

**First call:** Removes `Origin.bio` wrap, returns `true` from `deleteWrap`.
**Second call:** `deleteWrap` returns `false` (wrap already gone — `StorageException.other` is caught internally). `deleteKey` may throw (key already gone) and is suppressed.

**Expected:** Both calls return normally. No exception on the second call.

**How to verify:** Dart unit test. Not written for this phase.

---

### NC-7: `teardownBiometryPasswordOnly` does not interfere with `_sync` reentrance

**Setup:** `_sync` is a reentrant lock. `teardownBiometryPasswordOnly` calls `await _sync(...)`. No other operation is running concurrently in this test.

**Expected:** `_sync` completes normally with no deadlock. Consistent with every other `MFALocker` method that uses `_sync`.

**How to verify:** Code inspection — the `_executeWithCleanup` callback does not call any method that re-enters `_sync` from `MFALocker` (it calls `loadAllMetaIfLocked` which is `@visibleForTesting` and does not use `_sync`, and `_storage.deleteWrap` which uses `EncryptedStorageImpl`'s own `_sync`, a separate instance). No deadlock risk.

---

### NC-8: Calling `teardownBiometryPasswordOnly` does not invalidate the metadata cache

**Setup:** Locker is unlocked with entries in `_metaCache`. `teardownBiometryPasswordOnly` is called.

**Expected:** After the call, `_metaCache` still contains the same entries. The method only removes the `Origin.bio` wrap from the storage `masterKey` structure — it does not call `_cleanupState()` or transition the locker state. The locker remains `unlocked`.

**How to verify:** Code inspection — `teardownBiometryPasswordOnly` does not call `_cleanupState()` or `_stateController.add(LockerState.locked)`. Confirmed by reading lines 440–459.

---

### NC-9: `bioCipherFunc` is never instantiated in the password-only path

**Verification:** `teardownBiometryPasswordOnly` has no parameter of type `BioCipherFunc`. The implementation body references only `passwordCipherFunc` and `biometricKeyTag`. `BioCipherFunc` import is already present in `mfa_locker.dart` (for `setupBiometry`, `teardownBiometry`, etc.) but is not used in this method. No biometric prompt can be triggered from this code path. Confirmed by reading lines 440–459.

---

### NC-10: `passwordCipherFunc.erase()` is called even when `deleteWrap` throws

**Verification:** `passwordCipherFunc` is in the `erasables` list of `_executeWithCleanup`. The `finally` block (lines 475–478) always calls `erase()` regardless of whether the `callback` throws or returns normally. This is the standard `_executeWithCleanup` contract shared by all `MFALocker` methods. Confirmed by code inspection.

---

## Automated Tests Coverage

### Existing tests — non-regression

`test/locker/mfa_locker_test.dart` contains the full `MFALocker` test suite using `MockEncryptedStorage`. No test in that file references `teardownBiometry` or `teardownBiometryPasswordOnly`. Adding the new method to the interface and implementation introduces no changes to any existing test.

The following test files are confirmed unaffected by Phase 5:
- `test/locker/mfa_locker_test.dart`
- `test/storage/encrypted_storage_impl_test.dart`
- `test/storage/hmac_storage_mixin_test.dart`
- `test/utils/cryptography_utils_test.dart`
- `test/utils/erasable_byte_array_test.dart`

### Missing automated tests — not written for this phase

Per the user decision in `docs/plan/AW-2160-phase-5.md`, no new unit tests were written for Phase 5. The following scenarios are left without automated coverage:

| Scenario | Test description |
|---|---|
| PS-1 | `teardownBiometryPasswordOnly` calls `deleteWrap(originToDelete: Origin.bio)` with password cipher |
| PS-3 | `deleteKey` throws → method returns normally + `logWarning` called |
| NC-1 | Wrong password → `DecryptFailedException` propagates, `deleteWrap` not called |
| NC-2 | Storage not initialized → `StateError` propagates |
| NC-4 | `deleteKey` throws → suppressed |
| PS-4 | `deleteWrap` returns `false` → no exception, key deletion attempted |

The `MockEncryptedStorage` infrastructure and `MockPasswordCipherFunc` mock already exist in `test/mocks/` and would support these tests if added in a future phase.

---

## Manual Checks Needed

### MC-1: Static analysis — root package

**Command:**
```
fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .
```
Run from the repository root.

**Pass criterion:** Exits with code 0.

This validates:
- `teardownBiometryPasswordOnly` declaration on `Locker` is syntactically correct and type-checks.
- `MFALocker` satisfies the `Locker` interface (all abstract methods implemented).
- `passwordCipherFunc` parameter type `PasswordCipherFunc` resolves correctly (already imported in both files).
- `String biometricKeyTag` parameter is correct type.
- `Origin.bio` reference compiles (already imported in `mfa_locker.dart` at line 19).
- `logger.logWarning(...)` call compiles (already imported via `adguard_logger`).
- Line length 120, single quotes, trailing comma constraints are met.
- No new `@visibleForTesting` usage or meta import issues.

**Status:** CONFIRMED — `No issues found!` (ran in 2.9s). Exit code 0.

---

### MC-2: All existing tests pass

**Command:**
```
fvm flutter test
```
Run from the repository root.

**Pass criterion:** All tests exit green. No regressions from Phase 5 changes.

**Status:** CONFIRMED — All 140 tests passed. Exit code 0.

---

### MC-3: End-to-end manual test on Android — teardown after key invalidation

**Prerequisite:** Phase 1 complete (native emits `KEY_PERMANENTLY_INVALIDATED`). Phase 3 complete (Dart plugin maps code). Phase 4 complete (`keyInvalidated` enum value in locker layer). App must call `teardownBiometryPasswordOnly` on detecting `keyInvalidated`.

**Procedure:**
1. Install the app with a biometric wrap established (biometry set up).
2. In Android device settings, add or remove a fingerprint to invalidate the KeyStore key.
3. Open the app and trigger a biometric operation. Observe `BiometricExceptionType.keyInvalidated` (Phase 4).
4. App layer calls `teardownBiometryPasswordOnly(passwordCipherFunc: <correct password>, biometricKeyTag: <tag used at setup>)`.
5. Confirm: `isBiometricEnabled` returns `false` after the call.
6. Confirm: No crash, no biometric prompt shown.
7. Optionally, call `setupBiometry` with a fresh key tag and confirm biometrics work again.

**Pass criterion:** Biometric wrap removed, no prompt, no exception, locker intact.

**Status:** Not executed. Recommended before full AW-2160 release.

---

### MC-4: End-to-end manual test on iOS or macOS — teardown after key invalidation

**Procedure:** Same as MC-3, substituting Face ID / Touch ID enrollment change on the Apple device.

**Pass criterion:** Same as MC-3.

**Status:** Not executed. Recommended before full AW-2160 release.

---

### MC-5: Regression — `teardownBiometry` with valid bio key still works

**Procedure:**
1. On any device with biometrics enrolled and a valid (non-invalidated) bio wrap.
2. Call the existing `teardownBiometry(bioCipherFunc: bc, passwordCipherFunc: pc)`.
3. Confirm: biometric prompt appears (or is satisfied by the mock / stored credential).
4. Confirm: `isBiometricEnabled` returns `false` after the call.

**Pass criterion:** `teardownBiometry` behavior is identical to pre-Phase-5. No regression.

**Status:** Not executed. Should be verified on device alongside MC-3/MC-4.

---

### MC-6: Regression — `setupBiometry` and other `MFALocker` methods unaffected

**Procedure:** Run the example app through its main flow: init, write, read, change password, setup biometry, teardown biometry.

**Pass criterion:** All operations succeed as before Phase 5.

**Status:** Not executed. Part of standard regression testing for the AW-2160 release.

---

## Risk Zone

| Risk | Severity | Status |
|---|---|---|
| No automated unit tests for `teardownBiometryPasswordOnly` | High | Open. User decision. The implementation is correct by code inspection and follows established patterns exactly, but the method has zero automated test coverage. Any future regression (e.g., accidental removal of the `Origin.bio` parameter, wrong `originToDelete`) will not be caught automatically. |
| `fvm flutter analyze` not executed in this QA pass | Medium | RESOLVED — `No issues found!` Exit code 0. |
| `fvm flutter test` not executed in this QA pass | Medium | RESOLVED — 140 tests passed. Exit code 0. |
| `deleteWrap` called twice on the same locker (`Origin.bio` wrap already gone on second call) swallows a `StorageException` internally and returns `false` — no error visible to caller | Low | Confirmed correct behavior by reading `EncryptedStorageImpl.deleteWrap` source. The `false` return value from `deleteWrap` is not checked by `teardownBiometryPasswordOnly`, consistent with how `disableBiometry` uses it. This is intentional silent-success. No risk. |
| `_secureProvider.deleteKey` is called outside `_sync` — concurrent calls possible | Low | `deleteKey` operates on the hardware key store, not on in-memory locker state. This matches the existing pattern in `teardownBiometry`. Platform key stores are internally thread-safe. Errors are suppressed. No risk identified. |
| Caller passes wrong `biometricKeyTag` — wrong key deleted or silently missed | Low | App-layer concern, explicitly documented in the method's doc comment. Errors from `deleteKey` are suppressed, so the wrong tag results in a silent no-op on key deletion. The storage wrap is still correctly removed regardless of the tag value. |
| End-to-end device tests not performed for Phase 5 in isolation | Low | The storage-layer logic is identical to `disableBiometry` (already used by `teardownBiometry`). The only new code is the single `try/catch` around `deleteKey` with suppression. The risk of an unanticipated behavior is low but should be confirmed on device before full AW-2160 close. |
| Carry-over: no unit tests for `_mapExceptionToBiometricException` (Phase 4 gap) | Low | Deferred to a future phase. Not a Phase 5 concern, but the full AW-2160 test coverage gap remains open. |

---

## Final Verdict

**Release.**

The Phase 5 implementation is structurally complete and correct for its defined scope:

- `teardownBiometryPasswordOnly` is declared on `Locker` with the exact specified signature and doc comment.
- The `MFALocker` implementation correctly uses `_sync` + `_executeWithCleanup` with `erasables: [passwordCipherFunc]`, following the established pattern from `disableBiometry`.
- `loadAllMetaIfLocked(passwordCipherFunc)` is called before `deleteWrap`, ensuring the locker authenticates with password before touching the wrap.
- `_storage.deleteWrap(originToDelete: Origin.bio, cipherFunc: passwordCipherFunc)` correctly targets only the bio wrap.
- Hardware key deletion is outside `_sync`, errors are suppressed, and the warning log uses the exact agreed message.
- `BioCipherFunc` is never instantiated or referenced in this code path — no biometric prompt is possible.
- `teardownBiometry`, `disableBiometry`, and all other methods are confirmed unchanged by source inspection.
- The absent-wrap edge case (Scenario 5) is handled silently and correctly due to `EncryptedStorageImpl.deleteWrap`'s internal exception swallowing.

The remaining open items (not blocking):

1. **No automated unit tests exist for `teardownBiometryPasswordOnly`.** User decision. The mock infrastructure already exists; tests can be added in a future phase.

2. **No end-to-end device test has been performed.** Recommended before the full AW-2160 ticket is closed, but the storage-layer logic is identical to the already-proven `disableBiometry` path.

Primary acceptance criteria confirmed:
- `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` → No issues found. ✅
- `fvm flutter test` → 140 tests passed. ✅
