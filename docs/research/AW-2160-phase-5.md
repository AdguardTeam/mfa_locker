# Research: AW-2160 Phase 5 — `teardownBiometryPasswordOnly`

## Resolved Questions

**Q1 — Does `deleteWrap` no-op or throw when `Origin.bio` wrap is absent?**

It throws a `StorageException` (via the generic catch block, which logs and returns `false`).

Looking at `EncryptedStorageImpl.deleteWrap` (lines 227–265 in `encrypted_storage_impl.dart`):

```dart
final updatedWraps = currentWraps.where((w) => w.origin != originToDelete).toList();

if (updatedWraps.length == currentWraps.length) {
  throw StorageException.other('The wrap to delete was not found');
}
```

When the `Origin.bio` wrap is not present, `updatedWraps.length == currentWraps.length`, so a `StorageException.other(...)` is thrown. This throw is caught by the generic `catch (e, st)` block lower in the same method, which logs the error and `return false`. The method therefore **returns `false`** (does not propagate the exception) when the wrap is absent.

Additional guard: if deleting the wrap would leave `updatedWraps.isEmpty`, a second `StorageException.other(...)` is thrown and also returns `false` — but that case is irrelevant here since a password wrap must remain.

**Bottom line for the implementation:** `deleteWrap` returning `false` is a non-exceptional path. The caller (`teardownBiometryPasswordOnly`) does not need to guard against a missing bio wrap — the call simply returns `false`, and then key deletion is still attempted and suppressed. Scenario 5 from the PRD (no bio wrap exists) will result in `deleteWrap` returning `false`, after which `deleteKey` is attempted and errors suppressed; the method returns normally.

**Q2 — Does the idea/vision doc suggest a private `_disableBiometryWithPasswordOnly` helper, or should calls be inlined? What does `disableBiometry` do?**

`idea-2160.md §E` shows a sketch with a private `_disableBiometryWithPasswordOnly` helper, but the PRD and vision both describe the implementation as a simple inline sequence:

```
loadAllMetaIfLocked(passwordCipherFunc)
_storage.deleteWrap(originToDelete: Origin.bio, cipherFunc: passwordCipherFunc)
```

The vision doc (§4) shows no helper:

```
teardownBiometryPasswordOnly(passwordCipherFunc, biometricKeyTag)
  ├── loadAllMetaIfLocked(passwordCipherFunc)
  │   _storage.deleteWrap(originToDelete: Origin.bio, cipherFunc: passwordCipherFunc)
  └── try { _secureProvider.deleteKey(tag: biometricKeyTag) } catch (_) { suppress }
```

`disableBiometry` in `mfa_locker.dart` (lines 301–314) does exactly two things inside `_executeWithCleanup`:

1. `loadAllMetaIfLocked(passwordCipherFunc)` — authenticates with password.
2. `_storage.deleteWrap(originToDelete: Origin.bio, cipherFunc: passwordCipherFunc)` — removes the bio wrap.

**Conclusion:** No private helper is needed. The PRD (constraints) says to follow `teardownBiometry` and `disableBiometry` as the reference. The implementation should inline the two storage calls inside `_executeWithCleanup`, mirroring `disableBiometry` exactly (minus the `bioCipherFunc` erasable), then call `deleteKey` with suppression outside `_executeWithCleanup`.

**Q3 — In `teardownBiometry`, what erasables are passed to `_executeWithCleanup`? What is the exact call shape?**

`teardownBiometry` (lines 426–438) calls `disableBiometry`, which wraps with `_sync` + `_executeWithCleanup`. The erasables in `disableBiometry` are `[bioCipherFunc, passwordCipherFunc]`.

For `teardownBiometryPasswordOnly` there is no `bioCipherFunc`, so erasables will be `[passwordCipherFunc]` only — consistent with other single-cipher methods like `readValue` and `delete`.

**Q4 — Tests:** No tests for this phase; scope is code only (`locker.dart` + `mfa_locker.dart` changes only).

**Q5 — Additional constraints:** None.

---

## Phase Scope

Phase 5 is the final phase of AW-2160. It adds one new public method to the `Locker` interface and its `MFALocker` implementation. No new files, no storage data model changes.

- `lib/locker/locker.dart` — add `teardownBiometryPasswordOnly` signature to the abstract interface.
- `lib/locker/mfa_locker.dart` — add the `teardownBiometryPasswordOnly` implementation.

---

## Related Modules / Services

| File | Role |
|------|------|
| `lib/locker/locker.dart` | Abstract `Locker` interface — gains new method declaration |
| `lib/locker/mfa_locker.dart` | `MFALocker` implementation — gains new method body |
| `lib/storage/encrypted_storage.dart` | `EncryptedStorage` interface — `deleteWrap` signature used |
| `lib/storage/encrypted_storage_impl.dart` | `deleteWrap` implementation — confirms no-op/return-false behavior |
| `lib/security/biometric_cipher_provider.dart` | `BiometricCipherProvider.deleteKey` — called with error suppression |
| `lib/storage/models/data/origin.dart` | `Origin.bio` constant passed to `deleteWrap` |

---

## Current Endpoints and Contracts

### `Locker` interface — `teardownBiometry` (reference method, unchanged)

```dart
Future<void> teardownBiometry({
  required BioCipherFunc bioCipherFunc,
  required PasswordCipherFunc passwordCipherFunc,
});
```

### `MFALocker.teardownBiometry` — exact implementation

```dart
Future<void> teardownBiometry({
  required BioCipherFunc bioCipherFunc,
  required PasswordCipherFunc passwordCipherFunc,
}) async {
  await disableBiometry(
    bioCipherFunc: bioCipherFunc,
    passwordCipherFunc: passwordCipherFunc,
  );
  await _secureProvider.deleteKey(tag: bioCipherFunc.keyTag);
}
```

Note: `teardownBiometry` does NOT use `_sync` at the top level; it delegates to `disableBiometry` which owns `_sync`. Key deletion happens outside the lock.

### `MFALocker.disableBiometry` — exact implementation (primary reference)

```dart
Future<void> disableBiometry({
  required BioCipherFunc bioCipherFunc,
  required PasswordCipherFunc passwordCipherFunc,
}) =>
    _sync(
      () => _executeWithCleanup(
        erasables: [bioCipherFunc, passwordCipherFunc],
        callback: () async {
          await loadAllMetaIfLocked(passwordCipherFunc);
          await _storage.deleteWrap(originToDelete: Origin.bio, cipherFunc: passwordCipherFunc);
        },
      ),
    );
```

### `MFALocker.loadAllMetaIfLocked` — signature

```dart
@visibleForTesting
Future<void> loadAllMetaIfLocked(CipherFunc cipherFunc) async
```

Behavior: if storage is not initialized, throws `StateError`. If already unlocked, returns immediately. If locked, reads all meta from storage using `cipherFunc`, populates `_metaCache`, and transitions to `LockerState.unlocked`.

### `EncryptedStorage.deleteWrap` — interface signature

```dart
Future<bool> deleteWrap({
  required Origin originToDelete,
  required CipherFunc cipherFunc,
});
```

### `EncryptedStorageImpl.deleteWrap` — behavior contract

- Loads storage data and finds all wraps NOT matching `originToDelete`.
- If no wrap was removed (wrap absent): throws `StorageException.other(...)`, caught internally → **returns `false`**.
- If removal would leave zero wraps: throws `StorageException.other(...)`, caught internally → **returns `false`**.
- On success: re-signs and saves the updated data → **returns `true`**.
- `DecryptFailedException` and `BiometricException` are re-thrown (not caught by the generic handler).
- The `cipherFunc` is used only to decrypt the master key for HMAC verification and re-signing after deletion; it is a `PasswordCipherFunc` here, so no biometric prompt is triggered.

### `BiometricCipherProvider.deleteKey` — signature

```dart
Future<void> deleteKey({required String tag});
```

The interface doc comment states: "If the key does not exist, this operation should complete without error." However, per the PRD, errors must still be suppressed because the OS may have deleted the key in a way that causes the underlying plugin to throw. The `setupBiometry` method already demonstrates the suppression pattern:

```dart
try {
  await _secureProvider.deleteKey(tag: bioCipherFunc.keyTag);
} catch (e) {
  // Ignore errors - key might not exist yet
  logger.logInfo('Key might not exist yet: $e');
}
```

For `teardownBiometryPasswordOnly`, the PRD specifies `logger.logWarning(...)` instead of `logInfo`.

### `MFALocker._executeWithCleanup` — signature

```dart
Future<T> _executeWithCleanup<T>({
  required List<Erasable> erasables,
  required Future<T> Function() callback,
  List<Erasable> erasablesOnError = const [],
}) async
```

Behavior: runs `callback()`, erases `erasablesOnError` on exception, always erases `erasables` in `finally`. Logs the error before re-throwing.

---

## Patterns Used

### Pattern 1: `_sync` + `_executeWithCleanup` for storage operations

Every `MFALocker` method that touches storage wraps its body in `_sync(() => _executeWithCleanup(...))`. The `teardownBiometryPasswordOnly` storage phase must follow this pattern. The structure is:

```dart
Future<void> teardownBiometryPasswordOnly({...}) async {
  await _sync(
    () => _executeWithCleanup(
      erasables: [passwordCipherFunc],
      callback: () async {
        await loadAllMetaIfLocked(passwordCipherFunc);
        await _storage.deleteWrap(originToDelete: Origin.bio, cipherFunc: passwordCipherFunc);
      },
    ),
  );
  // Key deletion outside the lock, with suppression:
  try {
    await _secureProvider.deleteKey(tag: biometricKeyTag);
  } catch (_, __) {
    logger.logWarning('teardownBiometryPasswordOnly: failed to delete biometric key, suppressing');
  }
}
```

This mirrors `teardownBiometry`, which calls `disableBiometry` (owns `_sync`) and then calls `deleteKey` outside the lock.

### Pattern 2: Erasables list for single cipher

Methods with a single `CipherFunc` use `erasables: [cipherFunc]`:

```dart
// readValue:
erasables: [cipherFunc],
// delete:
erasables: [cipherFunc],
// updateLockTimeout:
erasables: [cipherFunc],
```

For `teardownBiometryPasswordOnly`: `erasables: [passwordCipherFunc]`.

### Pattern 3: `_sync` return value threading

`_sync` is called as `_sync(() => _executeWithCleanup(...))`, which returns `Future<T>`. For `void` methods, the return type of `_executeWithCleanup<void>` is inferred automatically.

### Pattern 4: `setupBiometry` key deletion suppression

```dart
try {
  await _secureProvider.deleteKey(tag: bioCipherFunc.keyTag);
} catch (e) {
  logger.logInfo('Key might not exist yet: $e');
}
```

For `teardownBiometryPasswordOnly`, use `logWarning` and a message matching the vision doc spec: `'teardownBiometryPasswordOnly: failed to delete biometric key, suppressing'`.

### Pattern 5: `Locker` interface doc comment style

Adjacent methods on the `Locker` interface use a one-line summary followed by a blank line and body paragraphs. The `teardownBiometry` doc is:

```dart
/// Disable biometric authentication (requires password confirmation)
/// This method handles storage update and key deletion.
Future<void> teardownBiometry({...});
```

The new method should follow this style. The PRD specifies the doc comment text (from `idea-2160.md §E`).

---

## Phase-Specific Limitations and Risks

### Risk 1: `teardownBiometryPasswordOnly` not wrapped in `_sync` for key deletion

The `deleteKey` call must happen outside `_sync` (same as `teardownBiometry` calling `deleteKey` after `disableBiometry` releases the lock). Calling `deleteKey` inside `_sync` is unnecessary and would extend lock duration.

Confirmed safe: `teardownBiometry` calls `disableBiometry` (which owns `_sync`) and then immediately calls `deleteKey` outside the lock. No data-race risk because `deleteKey` is a hardware operation with no shared locker state.

### Risk 2: `deleteWrap` returning `false` vs. throwing

As confirmed above, `deleteWrap` catches its internal `StorageException.other(...)` and returns `false` — it does NOT propagate as an exception. The implementation must not add a guard like `if (!await _storage.deleteWrap(...)) throw ...` unless the PRD asks for it (it does not). Scenario 5 (no bio wrap) is handled silently.

### Risk 3: Placement in `mfa_locker.dart`

`teardownBiometryPasswordOnly` is a public `@override` method. It belongs after `teardownBiometry` in the file to keep the public surface grouped. The class member order convention (from CLAUDE.md) is: static → constructor fields → constructor → other private fields → public methods → private methods. Both `teardownBiometry` and `teardownBiometryPasswordOnly` are public `@override` methods.

### Risk 4: `disableBiometry` is `@visibleForTesting`

`disableBiometry` is annotated `@visibleForTesting`. `teardownBiometryPasswordOnly` must NOT call `disableBiometry` directly; it should inline the two storage calls (same body as `disableBiometry` but with only `passwordCipherFunc` in erasables).

### Risk 5: `biometricKeyTag` is a `String`, not a `BioCipherFunc.keyTag`

The caller passes a raw `String` (not a `BioCipherFunc`). This is intentional — no biometric cipher is instantiated. The parameter must be `required String biometricKeyTag` on both the interface and implementation.

### Risk 6: `Locker` interface import

The new method signature on `Locker` uses only `PasswordCipherFunc` (already imported). No new imports are needed in `locker.dart`. The `String` parameter is a core Dart type.

---

## New Technical Questions

None. All implementation details are fully specified in the PRD and derivable from reading the existing code.

---

## Summary of Implementation Shape

### `lib/locker/locker.dart` addition

Insert after `teardownBiometry` declaration:

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

### `lib/locker/mfa_locker.dart` addition

Insert after `teardownBiometry` implementation. The method does NOT use a private helper. The structure (based on `disableBiometry` with no `bioCipherFunc` + key deletion with suppression):

```
@override
Future<void> teardownBiometryPasswordOnly({
  required PasswordCipherFunc passwordCipherFunc,
  required String biometricKeyTag,
}) async {
  await _sync(
    () => _executeWithCleanup(
      erasables: [passwordCipherFunc],
      callback: () async {
        await loadAllMetaIfLocked(passwordCipherFunc);
        await _storage.deleteWrap(originToDelete: Origin.bio, cipherFunc: passwordCipherFunc);
      },
    ),
  );
  try {
    await _secureProvider.deleteKey(tag: biometricKeyTag);
  } catch (_, __) {
    logger.logWarning('teardownBiometryPasswordOnly: failed to delete biometric key, suppressing');
  }
}
```
