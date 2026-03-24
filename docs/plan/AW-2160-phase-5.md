# Plan: AW-2160 Phase 5 -- `teardownBiometryPasswordOnly`

Status: PLAN_APPROVED

## Phase Scope

Phase 5 is the final phase of AW-2160. It adds one new public method (`teardownBiometryPasswordOnly`) to the `Locker` abstract interface and its `MFALocker` implementation. The method allows the app layer to remove a stale `Origin.bio` wrap using only password authentication, without triggering a biometric prompt -- necessary when the biometric hardware key has been permanently invalidated (detected via `BiometricExceptionType.keyInvalidated` from Phase 4).

No new files. No storage data model changes. No tests in scope (user decision).

---

## Components

Two files modified:

| File | Change |
|------|--------|
| `lib/locker/locker.dart` | Add `teardownBiometryPasswordOnly` method declaration to the `Locker` abstract interface, positioned immediately after `teardownBiometry` |
| `lib/locker/mfa_locker.dart` | Add `teardownBiometryPasswordOnly` implementation in `MFALocker`, positioned immediately after the existing `teardownBiometry` implementation (line 438) |

No other files are created or modified.

---

## API Contract

### New method on `Locker` interface

```dart
/// Removes the biometric wrap using password authentication only.
///
/// Use this when the biometric hardware key has been permanently invalidated
/// (e.g., after a biometric enrollment change) and [teardownBiometry] cannot
/// be called because the biometric prompt would fail.
///
/// Attempts to delete the hardware key identified by [biometricKeyTag] after
/// removing the wrap; errors during key deletion are suppressed because the
/// key may already be inaccessible or deleted by the OS.
Future<void> teardownBiometryPasswordOnly({
  required PasswordCipherFunc passwordCipherFunc,
  required String biometricKeyTag,
});
```

### Existing methods -- no changes

- `teardownBiometry` -- unchanged, continues to require `BioCipherFunc`
- `disableBiometry` -- unchanged, remains `@visibleForTesting`
- All other `Locker` / `MFALocker` methods -- unchanged

---

## Data Flows

### Internal flow of `teardownBiometryPasswordOnly`

```
teardownBiometryPasswordOnly(passwordCipherFunc, biometricKeyTag)
  |
  |-- Phase A: Storage operation (inside _sync + _executeWithCleanup)
  |     |
  |     |-- _sync(() => _executeWithCleanup(
  |     |       erasables: [passwordCipherFunc],
  |     |       callback: () async {
  |     |           loadAllMetaIfLocked(passwordCipherFunc)
  |     |               -- authenticates with password, unlocks if locked
  |     |           _storage.deleteWrap(originToDelete: Origin.bio, cipherFunc: passwordCipherFunc)
  |     |               -- removes Origin.bio wrap from storage
  |     |               -- returns false (not throws) if wrap absent
  |     |       },
  |     |   ))
  |     |
  |     +-- finally: passwordCipherFunc.erase()
  |
  |-- Phase B: Hardware key deletion (outside _sync, errors suppressed)
        |
        |-- try { _secureProvider.deleteKey(tag: biometricKeyTag) }
        |   catch (_, __) {
        |       logger.logWarning('teardownBiometryPasswordOnly: failed to delete biometric key, suppressing')
        |   }
```

### Key design decisions in the flow

1. **No private helper** -- The storage operations are inlined directly in the `_executeWithCleanup` callback, mirroring `disableBiometry` but with only `passwordCipherFunc` in the erasables list (no `bioCipherFunc`). The research confirmed that a private `_disableBiometryWithPasswordOnly` helper is unnecessary.

2. **`deleteKey` outside `_sync`** -- Matches the pattern of `teardownBiometry`, which calls `disableBiometry` (owns `_sync`) then calls `deleteKey` outside the lock. Hardware key deletion has no shared locker state and should not extend lock duration.

3. **`deleteWrap` returning `false` is non-exceptional** -- When `Origin.bio` wrap is absent, `EncryptedStorageImpl.deleteWrap` internally throws `StorageException.other(...)` which is caught by its own generic `catch` block and returns `false`. The caller does not need to guard against this. Scenario 5 (no bio wrap exists) is handled silently.

4. **Erasables: `[passwordCipherFunc]` only** -- Consistent with other single-cipher methods (`readValue`, `delete`, `updateLockTimeout`). There is no `bioCipherFunc` to erase.

5. **`biometricKeyTag` is a raw `String`** -- The caller provides the tag directly. No `BioCipherFunc` is instantiated. The parameter is the same tag that was used during `setupBiometry`.

6. **Suppression uses `logWarning`** -- Not `logInfo` (which `setupBiometry` uses for pre-existing key deletion). The `logWarning` level reflects that this is a post-teardown cleanup failure, though expected and non-fatal.

---

## NFR

| Requirement | How satisfied |
|-------------|---------------|
| No biometric prompt triggered | `BioCipherFunc` is never instantiated or passed; only `PasswordCipherFunc` is used |
| Memory safety (erasable cleanup) | `passwordCipherFunc` is in the `erasables` list of `_executeWithCleanup`, erased in `finally` |
| Thread safety | Storage operations wrapped in `_sync` (reentrant lock) |
| Backward compatibility | Existing `teardownBiometry`, `disableBiometry`, and all other methods are untouched |
| Code style | Line length 120, single quotes, trailing commas, doc comment style matches adjacent `teardownBiometry` declaration |
| Static analysis | Must pass `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` |
| Tests | Must pass `fvm flutter test` (existing tests, no new tests) |

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| `deleteWrap` behavior when `Origin.bio` wrap is absent | Resolved | N/A | Research confirmed: returns `false` (does not throw). No guard needed. |
| Pattern mismatch between `teardownBiometry` and `disableBiometry` | Resolved | N/A | Research confirmed both follow the same `_sync` + `_executeWithCleanup` structure. Implementation mirrors `disableBiometry` body with single-cipher erasables. |
| `disableBiometry` is `@visibleForTesting` -- new method must not call it directly | Low (code review catches) | Low | Implementation inlines the two storage calls rather than delegating to `disableBiometry`. |
| Caller passes wrong `biometricKeyTag` | Low (app-layer concern) | Low -- key deletion is best-effort and errors are suppressed | Doc comment explicitly states the caller must pass the same tag used during `setupBiometry`. |
| Adding method to `Locker` interface breaks compilation of downstream implementors | Very low -- `Locker` is an abstract interface, not sealed | Medium if hit | `fvm flutter analyze` will surface any compile errors immediately. |

---

## Dependencies

| Dependency | Status |
|------------|--------|
| Phase 4 (`BiometricExceptionType.keyInvalidated`) | Complete -- provides the signal that triggers the app layer to call `teardownBiometryPasswordOnly` |
| `_executeWithCleanup` pattern | Exists in `MFALocker` (line 440) |
| `_sync` (reentrant lock) | Exists in `MFALocker` (line 41) |
| `loadAllMetaIfLocked` | Exists in `MFALocker` (line 271) |
| `_storage.deleteWrap` | Exists in `EncryptedStorage` interface and `EncryptedStorageImpl` |
| `_secureProvider.deleteKey` | Exists in `BiometricCipherProvider` interface |
| `logger.logWarning` | Available via `adguard_logger` (already imported in `mfa_locker.dart`) |
| `Origin.bio` | Exists in `lib/storage/models/data/origin.dart` (already imported in `mfa_locker.dart`) |
| `PasswordCipherFunc` | Already imported in both `locker.dart` and `mfa_locker.dart` |

---

## Implementation Steps

1. **`lib/locker/locker.dart`** -- Add `teardownBiometryPasswordOnly` declaration immediately after `teardownBiometry` (after line 159). Include the doc comment as specified in the API contract section above.

2. **`lib/locker/mfa_locker.dart`** -- Add `teardownBiometryPasswordOnly` implementation immediately after `teardownBiometry` (after line 438). The method body:
   - Wraps storage operations in `_sync(() => _executeWithCleanup(...))` with `erasables: [passwordCipherFunc]`
   - Callback: `loadAllMetaIfLocked(passwordCipherFunc)` then `_storage.deleteWrap(originToDelete: Origin.bio, cipherFunc: passwordCipherFunc)`
   - After `_sync` completes: `try { await _secureProvider.deleteKey(tag: biometricKeyTag) } catch (_, __) { logger.logWarning(...) }`

3. **Verify** -- Run `fvm flutter analyze` and `fvm flutter test` to confirm no regressions.

---

## Open Questions

None. All implementation details are fully specified by the PRD, research, idea, vision, and phase documents, and confirmed by reading the actual source files.
