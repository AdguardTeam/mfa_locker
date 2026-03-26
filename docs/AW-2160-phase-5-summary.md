# AW-2160 Phase 5 Summary — Locker Library: `teardownBiometryPasswordOnly` Method

## What Was Done

Phase 5 is the final phase of AW-2160. It delivers the password-only biometric teardown path that the earlier phases made necessary.

The problem: after Phases 1–4, the app layer can detect `BiometricExceptionType.keyInvalidated` and knows the hardware key is gone. But it has no clean way to remove the stale `Origin.bio` wrap from storage. The existing `teardownBiometry` method requires a `BioCipherFunc`, which triggers a hardware prompt — that prompt will fail because the key is already invalidated. Phase 5 closes this gap.

Two production files were modified. No new files were created. No storage data model changes were made. No new tests were added (user decision).

---

## Files Changed

| File | Change |
|------|--------|
| `lib/locker/locker.dart` | New method declaration `teardownBiometryPasswordOnly` added to the `Locker` abstract interface, positioned immediately after `teardownBiometry` at lines 161–173 |
| `lib/locker/mfa_locker.dart` | New method implementation `teardownBiometryPasswordOnly` added to `MFALocker`, positioned immediately after `teardownBiometry` at lines 440–459 |

---

## What Was Added

### New method on `Locker` interface (`lib/locker/locker.dart`)

`teardownBiometryPasswordOnly` is declared with the signature:

```
Future<void> teardownBiometryPasswordOnly({
  required PasswordCipherFunc passwordCipherFunc,
  required String biometricKeyTag,
})
```

The doc comment explains the intended use case (permanently invalidated key), describes `biometricKeyTag` (caller-supplied, same tag used during `setupBiometry`), and states that key deletion errors are suppressed. The declaration is placed immediately after `teardownBiometry`, keeping biometric teardown methods together.

### New method implementation in `MFALocker` (`lib/locker/mfa_locker.dart`)

The implementation has two sequential phases:

**Phase A — Storage operation (inside the lock):**
Wrapped in `await _sync(() => _executeWithCleanup(...))` with `erasables: [passwordCipherFunc]`, following the same single-cipher pattern used by `disableBiometry`, `readValue`, and `updateLockTimeout`. The callback:
1. Calls `loadAllMetaIfLocked(passwordCipherFunc)` — authenticates with password and transitions the locker to unlocked if it was locked.
2. Calls `_storage.deleteWrap(originToDelete: Origin.bio, cipherFunc: passwordCipherFunc)` — removes the `Origin.bio` wrap from the storage master key list.

`BioCipherFunc` is never instantiated or passed anywhere in this method. No biometric prompt is possible.

**Phase B — Hardware key deletion (outside the lock):**

```dart
try {
  await _secureProvider.deleteKey(tag: biometricKeyTag);
} catch (_, __) {
  logger.logWarning('teardownBiometryPasswordOnly: failed to delete biometric key, suppressing');
}
```

Key deletion runs outside `_sync`, consistent with how `teardownBiometry` handles it. Errors are suppressed because the OS may have already deleted the key when the biometric enrollment changed.

---

## Decisions Made

**New dedicated method rather than an optional parameter on `teardownBiometry`.**
Making `bioCipherFunc` nullable in the existing method would have required touching `teardownBiometry`, `disableBiometry`, and all tests that exercise those methods. The dedicated method has explicit intent and zero risk of breaking existing callers. This decision was made in `docs/idea-2160.md` §E and confirmed in `docs/vision-2160.md` §4.

**No private `_disableBiometryWithPasswordOnly` helper.**
The storage operations are inlined directly in the `_executeWithCleanup` callback. `disableBiometry` is `@visibleForTesting` and must not be called from a production method. Inlining the two calls (`loadAllMetaIfLocked` + `deleteWrap`) mirrors the `disableBiometry` body without delegation, keeping the implementation simple and avoiding a `@visibleForTesting` call from non-test code.

**`deleteKey` outside `_sync`.**
Matches the pattern in `teardownBiometry`. Hardware key deletion operates on platform key storage, not on in-memory locker state, so extending the lock duration is unnecessary. Errors are suppressed at that point regardless.

**`deleteWrap` returning `false` is non-exceptional.**
When no `Origin.bio` wrap exists, `EncryptedStorageImpl.deleteWrap` internally throws `StorageException.other('The wrap to delete was not found')`, catches it in its own generic `catch` block, and returns `false`. The return value is not checked by `teardownBiometryPasswordOnly`, so calling the method when no bio wrap exists is a silent success. This was confirmed by reading `EncryptedStorageImpl.deleteWrap` (lines 227–265) before implementing.

**`logWarning` for suppressed key deletion, not `logInfo`.**
`setupBiometry` uses `logInfo` when it silently deletes a pre-existing key before generating a new one. The warning level here reflects that key deletion is happening as cleanup after an error condition (invalidated key), making it worth surfacing above normal informational logging even though the error is intentionally suppressed.

**`passwordCipherFunc` erased in `finally`.**
`passwordCipherFunc` is in the `erasables` list of `_executeWithCleanup`. The `finally` block zeroes its bytes regardless of whether the callback succeeds or throws. This is the standard `MFALocker` memory-safety contract, consistent with all other methods that handle a `PasswordCipherFunc`.

---

## How the Method Fits in the Full AW-2160 Flow

```
Android: KeyPermanentlyInvalidatedException → FlutterError("KEY_PERMANENTLY_INVALIDATED")   [Phase 1]
iOS/macOS: Secure Enclave key inaccessible → FlutterError("KEY_PERMANENTLY_INVALIDATED")    [Phase 2]
  → Dart plugin: BiometricCipherExceptionCode.keyPermanentlyInvalidated                     [Phase 3]
  → Locker: BiometricExceptionType.keyInvalidated                                           [Phase 4]
  → App detects keyInvalidated
  → App calls teardownBiometryPasswordOnly(passwordCipherFunc, biometricKeyTag)             [Phase 5 — this phase]
      → Authenticate with password (loadAllMetaIfLocked)
      → Delete Origin.bio wrap (deleteWrap)
      → Try to delete hardware key — errors suppressed (deleteKey)
  → Biometric wrap is cleanly removed
  → App can re-enable biometrics with a fresh key if desired
```

---

## Backward Compatibility

`teardownBiometry`, `disableBiometry`, and all other `MFALocker` and `Locker` methods are unchanged. Adding `teardownBiometryPasswordOnly` to the `Locker` abstract interface does not break existing implementors because `Locker` is not a sealed class — the only production implementation is `MFALocker`, which now provides the method.

---

## QA Status

The QA review (`docs/qa/AW-2160-phase-5.md`) confirmed the implementation is structurally correct by code inspection:

- Method is declared on `Locker` with the exact agreed signature and doc comment.
- `MFALocker` implementation uses `_sync` + `_executeWithCleanup` with `erasables: [passwordCipherFunc]`.
- `loadAllMetaIfLocked` is called before `deleteWrap`.
- `deleteKey` is outside `_sync`, errors are suppressed, log message matches specification exactly.
- `BioCipherFunc` is never referenced in the method body.
- `teardownBiometry` and `disableBiometry` are confirmed unchanged.
- Absent-wrap edge case (Scenario 5) is handled silently via `EncryptedStorageImpl`'s internal exception swallowing.

Three items remain open before AW-2160 is considered fully released:

1. **No automated unit tests for `teardownBiometryPasswordOnly`.** The `MockEncryptedStorage` and `MockPasswordCipherFunc` infrastructure already exists in `test/mocks/` and would support these tests with minimal effort. Writing them is recommended before the full AW-2160 close.
2. **`fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` must be confirmed green** before release.
3. **`fvm flutter test` must be confirmed green** (confirms no existing tests are broken by the interface addition).
4. **End-to-end device tests** (Android: enroll a new fingerprint, confirm `teardownBiometryPasswordOnly` removes the wrap; iOS/macOS: change Face ID / Touch ID enrollment) have not been performed and are recommended before full ticket close.

---

## Phase Dependencies

| Phase | Status | Relevance |
|-------|--------|-----------|
| Phase 1 (Android native) | Complete | Emits `"KEY_PERMANENTLY_INVALIDATED"` from Android KeyStore |
| Phase 2 (iOS/macOS native) | Complete | Emits `"KEY_PERMANENTLY_INVALIDATED"` from Secure Enclave |
| Phase 3 (Dart plugin) | Complete | `BiometricCipherExceptionCode.keyPermanentlyInvalidated` |
| Phase 4 (Locker library) | Complete | `BiometricExceptionType.keyInvalidated`; mapping in `BiometricCipherProviderImpl` |
| Phase 5 (this phase) | Complete | `teardownBiometryPasswordOnly` on `Locker` and `MFALocker` |
