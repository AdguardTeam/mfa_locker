# Phase 5: Locker: `teardownBiometryPasswordOnly` method

**Goal:** Allow removing the `Origin.bio` wrap using password auth only, for when the biometric key is already invalidated.

## Context

When a biometric key is permanently invalidated (after a biometric enrollment change), `teardownBiometry` cannot be called because it requires a `bioCipherFunc` that would trigger the hardware prompt — which will fail. The actual storage operation (`deleteWrap`) uses only `passwordCipherFunc`; `bioCipherFunc` in the existing flow is only there for the erasables list. This phase adds a dedicated password-only teardown path.

**Motivation:** The app layer detects `BiometricExceptionType.keyInvalidated` (Phase 4) and needs a way to cleanly remove the stale `Origin.bio` wrap from storage without triggering a biometric prompt. After removing the wrap, any best-effort cleanup of the hardware key is attempted with errors suppressed (the key may already be deleted by the OS).

**Design decision:** New dedicated method rather than making `bioCipherFunc` optional in existing `teardownBiometry`. Explicit intent, no risk of breaking existing callers.

## Tasks

- [x] **5.1** Add `teardownBiometryPasswordOnly` to `Locker` abstract interface
  - File: `lib/locker/locker.dart`
  - Signature: `Future<void> teardownBiometryPasswordOnly({required PasswordCipherFunc passwordCipherFunc, required String biometricKeyTag})`

- [x] **5.2** Implement `teardownBiometryPasswordOnly` in `MFALocker`
  - File: `lib/locker/mfa_locker.dart`
  - Password-only `disableBiometry` logic: `loadAllMetaIfLocked(passwordCipherFunc)` → `_storage.deleteWrap(originToDelete: Origin.bio, cipherFunc: passwordCipherFunc)`
  - Wrap in `_sync` + `_executeWithCleanup` (follow existing patterns)
  - After wrap deletion: `try { _secureProvider.deleteKey(tag: biometricKeyTag) } catch (_) { /* suppress */ }`
  - Log warning on suppressed key deletion error

## Acceptance Criteria

**Test:** `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` + `fvm flutter test`

- `teardownBiometryPasswordOnly` removes the `Origin.bio` wrap using password auth alone, without triggering a biometric prompt.
- Generic auth failures and normal `teardownBiometry` with a valid bio key continue to work as before.

## Dependencies

- Phase 4 complete (provides `BiometricExceptionType.keyInvalidated` — consumed by the app layer that calls this new method)

## Technical Details

### Method signature (from idea-2160.md §E)

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

### Internal flow (from vision-2160.md §4)

```
teardownBiometryPasswordOnly(passwordCipherFunc, biometricKeyTag)
  │
  ├── Password-only disableBiometry logic:
  │     loadAllMetaIfLocked(passwordCipherFunc)
  │     _storage.deleteWrap(originToDelete: Origin.bio, cipherFunc: passwordCipherFunc)
  │
  └── try { _secureProvider.deleteKey(tag: biometricKeyTag) } catch (_) { suppress }
```

### Logging (from vision-2160.md §7)

One log point only — when hardware key deletion is suppressed:

```dart
logger.logWarning('teardownBiometryPasswordOnly: failed to delete biometric key, suppressing');
```

### Workflow context (from vision-2160.md §6)

```
App detects keyInvalidated (from Phase 4)
  → App calls teardownBiometryPasswordOnly(passwordCipherFunc, biometricKeyTag)
    → Authenticate with password (loadAllMetaIfLocked)
    → Delete Origin.bio wrap from storage (deleteWrap)
    → Try to delete hardware key (deleteKey) — errors suppressed
  → Biometric wrap is cleanly removed
  → App can re-enable biometrics with fresh key if desired
```

## Implementation Notes

- Follow the existing `_executeWithCleanup` + `_sync` patterns used by `teardownBiometry` and `disableBiometry`.
- The `bioCipherFunc` is **not** needed — only `passwordCipherFunc` is used for the `deleteWrap` call.
- Key deletion suppression is intentional: the key may already be deleted by the OS after a biometric enrollment change.
- No changes to the storage data model — JSON structure stays identical.
