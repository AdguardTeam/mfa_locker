# AW-2160-5: Locker: `teardownBiometryPasswordOnly` Method

Status: PRD_READY

## Context / Idea

This is Phase 5 of AW-2160, the final phase. AW-2160 as a whole adds biometric key invalidation detection and a password-only teardown path across the full stack.

**Phases 1–4 status (all complete):**
- Phase 1: Android native emits `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")` when `KeyPermanentlyInvalidatedException` is caught.
- Phase 2: iOS/macOS native emits `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")` when the Secure Enclave key is inaccessible after biometric enrollment change.
- Phase 3: The Dart plugin maps `'KEY_PERMANENTLY_INVALIDATED'` → `BiometricCipherExceptionCode.keyPermanentlyInvalidated`.
- Phase 4: The locker library maps `BiometricCipherExceptionCode.keyPermanentlyInvalidated` → `BiometricExceptionType.keyInvalidated`.

**The problem this phase solves:** When a biometric key is permanently invalidated, `teardownBiometry` cannot be called — it requires a `BioCipherFunc` that would trigger the hardware prompt, which will fail because the key is already gone. The actual storage operation (`deleteWrap`) only needs `passwordCipherFunc`; the `bioCipherFunc` in the existing flow is present only as an erasable. The app layer has no path to cleanly remove the stale `Origin.bio` wrap after detecting `BiometricExceptionType.keyInvalidated` (Phase 4).

**Design decision (already made in idea-2160.md §E and vision-2160.md §4):** New dedicated method `teardownBiometryPasswordOnly` rather than making `bioCipherFunc` optional in the existing `teardownBiometry`. Explicit intent, no risk of breaking existing callers.

**Scope:** Two files modified — `lib/locker/locker.dart` (new method signature on the abstract interface) and `lib/locker/mfa_locker.dart` (new method implementation). No new files. No storage data model changes.

---

## Goals

1. Add `teardownBiometryPasswordOnly` to the `Locker` abstract interface in `lib/locker/locker.dart` with the agreed signature and doc comment.
2. Implement `teardownBiometryPasswordOnly` in `MFALocker` (`lib/locker/mfa_locker.dart`), following the existing `_executeWithCleanup` + `_sync` patterns used by `teardownBiometry` and `disableBiometry`.
3. The implementation must authenticate with password only (`loadAllMetaIfLocked(passwordCipherFunc)`) and delete the `Origin.bio` wrap (`_storage.deleteWrap(originToDelete: Origin.bio, cipherFunc: passwordCipherFunc)`) without triggering any biometric prompt.
4. After the wrap is deleted, attempt to delete the hardware key via `_secureProvider.deleteKey(tag: biometricKeyTag)`. Suppress all errors with a single warning log; the key may already be deleted by the OS.
5. Maintain full backward compatibility: existing `teardownBiometry` and all other `MFALocker` methods are not changed.

---

## User Stories

**US-1 — App layer can remove stale biometric wrap after key invalidation**
As the app layer consuming `MFALocker`, I need a method that removes the `Origin.bio` wrap using only my password, so that after detecting `BiometricExceptionType.keyInvalidated` I can clean up the stale wrap without triggering a failing biometric prompt.

**US-2 — Re-enable biometrics after cleanup**
As an app user, after removing the invalidated biometric wrap, I need the locker to be in a clean state (no `Origin.bio` wrap) so that I can set up biometrics again with a fresh hardware key if I choose to.

**US-3 — Normal teardown with a valid key is unaffected**
As any existing caller of `teardownBiometry`, I need that method to continue working exactly as before, so that my flow is not broken by the addition of the new method.

**US-4 — Password authentication errors propagate correctly**
As the app layer, if I provide an incorrect password to `teardownBiometryPasswordOnly`, I need the method to throw the appropriate auth exception (same as any other password-authenticated operation), so that I can prompt the user to re-enter their password.

---

## Main Scenarios

### Scenario 1: Successful password-only teardown after key invalidation

1. App has detected `BiometricExceptionType.keyInvalidated` from Phase 4 mapping.
2. App calls `teardownBiometryPasswordOnly(passwordCipherFunc: pc, biometricKeyTag: tag)`.
3. `loadAllMetaIfLocked(passwordCipherFunc)` authenticates with password, unlocking the locker if locked.
4. `_storage.deleteWrap(originToDelete: Origin.bio, cipherFunc: passwordCipherFunc)` removes the `Origin.bio` wrap from storage.
5. `_secureProvider.deleteKey(tag: tag)` succeeds (key still exists or was already deleted by OS without error).
6. Method returns normally.
7. App can call `setupBiometry` to re-enable biometrics with a fresh key.

### Scenario 2: Hardware key already deleted by OS — suppressed error

1. Same as Scenario 1, steps 1–4.
2. `_secureProvider.deleteKey(tag: tag)` throws because the OS already removed the key.
3. The error is caught and suppressed. A warning is logged: `'teardownBiometryPasswordOnly: failed to delete biometric key, suppressing'`.
4. Method returns normally — the wrap has already been removed from storage (step 4 succeeded).

### Scenario 3: Wrong password — authentication fails

1. App calls `teardownBiometryPasswordOnly(passwordCipherFunc: wrongPc, biometricKeyTag: tag)`.
2. `loadAllMetaIfLocked(passwordCipherFunc)` fails with an auth exception (wrong password).
3. Exception propagates out of `teardownBiometryPasswordOnly` unchanged.
4. `Origin.bio` wrap is untouched; no key deletion is attempted.

### Scenario 4: Normal `teardownBiometry` with a valid bio key — unchanged behavior

1. App calls existing `teardownBiometry(bioCipherFunc: bc, passwordCipherFunc: pc)`.
2. Flow is identical to what existed before Phase 5.
3. No regression.

### Scenario 5: `teardownBiometryPasswordOnly` called when no biometric wrap exists

1. App calls `teardownBiometryPasswordOnly` but `Origin.bio` wrap does not exist in storage.
2. `_storage.deleteWrap` behaves according to existing `deleteWrap` contract (succeeds silently or throws — follow the actual `deleteWrap` implementation behavior, confirmed by reading the code before implementing).
3. Hardware key deletion is attempted and errors suppressed.

---

## Success / Metrics

| Criterion | How to verify |
|-----------|--------------|
| `teardownBiometryPasswordOnly` is declared on `Locker` interface with the correct signature | Code review / compile check |
| `MFALocker.teardownBiometryPasswordOnly` removes `Origin.bio` wrap using password auth with no biometric prompt | Unit test: mock `_storage.deleteWrap` called with `originToDelete: Origin.bio`; mock `_secureProvider` not invoked for any cipher init |
| Key deletion errors are suppressed and a warning is logged | Unit test: `_secureProvider.deleteKey` throws; method returns normally; warning log captured |
| Wrong password causes auth exception to propagate | Unit test: `loadAllMetaIfLocked` mock throws; exception propagates from `teardownBiometryPasswordOnly` |
| Existing `teardownBiometry` behavior is unchanged | Existing tests pass without modification |
| Root library analysis passes | `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` exits 0 |
| All tests pass | `fvm flutter test` exits 0 |

---

## Constraints and Assumptions

- **Two files only:** `lib/locker/locker.dart` and `lib/locker/mfa_locker.dart`.
- **No new files:** 0 new files created.
- **No storage data model changes:** JSON structure (`salt`, `lockTimeout`, `masterKey`, `entries`, `hmacKey`, `hmacSignature`) stays identical.
- **No biometric prompt:** `BioCipherFunc` is not instantiated or passed to any method in this flow.
- **Follow existing patterns:** The implementation must use `_sync` (reentrant lock) and `_executeWithCleanup` exactly as `teardownBiometry` and `disableBiometry` do. Read both methods before implementing.
- **`biometricKeyTag` parameter:** The caller is responsible for providing the correct key tag (the same tag used when `setupBiometry` was called). The locker does not store or look up the tag.
- **Log level:** One warning log on suppressed key deletion error using the existing `logger.logWarning` call in `MFALocker`.
- **Dart code style:** Line length 120, single quotes, trailing commas on multi-line constructs, doc comment consistent with adjacent methods on `Locker` interface.
- **Erasables cleanup:** `passwordCipherFunc` must be erased in the `finally` block of `_executeWithCleanup`, consistent with how other methods handle cipher func arguments.
- **Phase 4 is confirmed complete.** `BiometricExceptionType.keyInvalidated` exists. This phase does not depend on Phase 4 at compile time but is the API consumer of the `keyInvalidated` signal at the app layer.

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| `deleteWrap` with a non-existent `Origin.bio` behaves differently than expected (e.g., throws instead of no-ops) | Low — behavior is deterministic; read the source before implementing | Medium — may require a guard or different call order | Confirm `deleteWrap` contract by reading `EncryptedStorage` and its implementation before coding |
| `_executeWithCleanup` or `_sync` patterns differ between `teardownBiometry` and `disableBiometry` | Low — both follow the same pattern | Low — minor style inconsistency | Read both methods before implementing; follow `teardownBiometry` as primary reference |
| Adding `teardownBiometryPasswordOnly` to the `Locker` interface breaks exhaustive switch/match on `Locker` (unlikely — `Locker` is not an enum) | Very low — `Locker` is an abstract interface, not a sealed class | Low | `fvm flutter analyze` surfaces any compile errors |
| The `biometricKeyTag` that the app passes at teardown time differs from the tag used at setup time, causing key deletion to silently fail or delete the wrong key | Low — app-layer concern, not locker's responsibility; errors are suppressed | Low — key deletion is best-effort | Document clearly in the method's doc comment that the caller must pass the same tag used during `setupBiometry` |
| Locker is already locked and password is correct, but `loadAllMetaIfLocked` has an edge case when called from this new method | Very low — same code path as other password-authenticated operations | Low | Unit test covers the locked-then-unlocked flow |

---

## Open Questions

None. The scope is fully defined by the phase-5.md description, the design decisions recorded in idea-2160.md §E and vision-2160.md §4, and the existing patterns in `Locker` and `MFALocker`. All implementation details (signature, internal flow, logging, error suppression) are specified. Remaining decisions (exact placement of `deleteWrap` no-op behavior, exact `_executeWithCleanup` call shape) are directly derivable from reading the existing source files before editing.
