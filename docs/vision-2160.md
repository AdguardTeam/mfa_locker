# Vision: Biometric Key Invalidation Handling (AW-2160)

## Summary

Detect when a biometric key has been permanently invalidated (vs. a generic auth failure) by exposing a dedicated `keyInvalidated` exception type through all layers. Provide a password-only teardown path to clean up stale biometric wraps when the hardware key is already gone.

Companion to: `docs/idea-2160.md`

---

## 1. Technologies

No new technologies or dependencies. All changes use the existing stack:

- **Kotlin** — Android native (`ErrorType`, `SecureMethodCallHandlerImpl`)
- **Swift** — iOS/macOS native (`KeychainService`, `SecureEnclaveManager`, plugin error types)
- **Dart** — Flutter plugin enums + locker library mappings

Platform APIs used are already available:
- Android: `KeyPermanentlyInvalidatedException` (Android SDK)
- iOS/macOS: `errSecAuthFailed`, `SecItemCopyMatching` with `kSecUseAuthenticationUISkip` (Security framework)

---

## 2. Development Principles

1. **KISS** — Minimal changes to existing code. Add new enum values and one catch branch per platform. No refactoring of surrounding code.
2. **Follow existing patterns** — Each layer already has an error enum + mapping. We add one value to each enum and one mapping line. Same pattern, no new abstractions.
3. **Error propagation chain** — Errors flow bottom-up through existing layers without shortcuts:
   - Android: `KeyPermanentlyInvalidatedException` → `ErrorType` → Flutter channel
   - iOS/macOS: `KeychainServiceError` → `SecureEnclaveManagerError` → `SecureEnclavePluginError` → Flutter channel
   - Dart: `BiometricCipherExceptionCode` → `BiometricExceptionType`
4. **Fail-safe for teardown** — Password-only teardown suppresses key deletion errors because the key may already be gone. Goal is cleanup, not correctness guarantees on an already-invalidated key.
5. **No behavior changes to existing flows** — Generic auth failures (wrong fingerprint, lockout, cancel) continue producing existing error types unchanged.

---

## 3. Project Structure

No new files or directories. All changes go into existing files:

```
packages/biometric_cipher/
├── android/src/main/kotlin/…/
│   ├── ErrorType.kt                              # + KEY_PERMANENTLY_INVALIDATED value
│   └── SecureMethodCallHandlerImpl.kt            # + catch branch
├── darwin/Classes/
│   ├── KeychainServiceError.swift                # + .keyPermanentlyInvalidated case
│   ├── KeychainService.swift                     # rewrite decryptData() + add keyExists()
│   ├── SecureEnclaveManagerError.swift           # + .keyPermanentlyInvalidated case
│   ├── SecureEnclaveManager.swift                # rewrite decrypt()
│   ├── SecureEnclavePluginError.swift            # + .keyPermanentlyInvalidated case
│   └── BiometricCipherPlugin.swift               # + catch → FlutterError mapping
└── lib/data/
    └── biometric_cipher_exception_code.dart      # + keyPermanentlyInvalidated + mapping

lib/
├── security/
│   ├── models/exceptions/
│   │   └── biometric_exception.dart              # + keyInvalidated value
│   └── providers/
│       └── biometric_cipher_provider_impl.dart   # + mapping line
└── locker/
    ├── locker.dart                               # + teardownBiometryPasswordOnly signature
    └── mfa_locker.dart                           # + teardownBiometryPasswordOnly implementation

example/lib/
├── features/
│   ├── locker/
│   │   ├── data/repositories/
│   │   │   └── locker_repository.dart            # + disableBiometricPasswordOnly method
│   │   ├── bloc/
│   │   │   ├── locker_state.dart                 # + isBiometricKeyInvalidated flag
│   │   │   ├── locker_event.dart                 # + disableBiometricPasswordOnlyRequested event
│   │   │   ├── locker_action.dart                # + biometricKeyInvalidated action
│   │   │   └── locker_bloc.dart                  # separate keyInvalidated handling, new handler, clear flag
│   │   └── views/
│   │       ├── auth/
│   │       │   └── locked_screen.dart            # hide biometric when key invalidated
│   │       └── widgets/
│   │           ├── biometric_unlock_button.dart   # hide when key invalidated
│   │           └── locker_bloc_biometric_stream.dart # map biometricKeyInvalidated → BiometricFailed
│   └── settings/
│       ├── bloc/
│       │   └── settings_bloc.dart                # keyInvalidated case in timeout-with-biometric handler
│       └── views/
│           └── settings_screen.dart              # invalidation description, toggle routing, timeout tile
```

**Total: 22 existing files modified, 0 new files** (12 library + 10 example app).

---

## 4. Architecture

Architecture stays unchanged. The change adds one new error code to the existing error propagation chain + one new method on `MFALocker`.

### Error propagation (new path, same architecture)

```
┌─────────────────────────────────────────────────────────────┐
│ Platform Native                                             │
│                                                             │
│ Android: KeyPermanentlyInvalidatedException                 │
│          → ErrorType.KEY_PERMANENTLY_INVALIDATED            │
│          → FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")│
│                                                             │
│ iOS/macOS: keyExists() == false / errSecAuthFailed          │
│          → KeychainServiceError.keyPermanentlyInvalidated   │
│          → SecureEnclaveManagerError.keyPermanentlyInvalidated│
│          → FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")│
└──────────────────────────┬──────────────────────────────────┘
                           │ Flutter method channel
┌──────────────────────────▼──────────────────────────────────┐
│ biometric_cipher (Dart plugin)                              │
│ BiometricCipherExceptionCode.keyPermanentlyInvalidated      │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│ locker (Dart library)                                       │
│ BiometricCipherProviderImpl maps →                          │
│ BiometricExceptionType.keyInvalidated                       │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│ App layer (consumer)                                        │
│ Catches keyInvalidated → calls teardownBiometryPasswordOnly │
└─────────────────────────────────────────────────────────────┘
```

### Password-only teardown (new method)

```
teardownBiometryPasswordOnly(passwordCipherFunc, biometricKeyTag)
  │
  ├── Password-only disableBiometry logic:
  │     loadAllMetaIfLocked(passwordCipherFunc)
  │     _storage.deleteWrap(originToDelete: Origin.bio, cipherFunc: passwordCipherFunc)
  │
  └── try { _secureProvider.deleteKey(tag: biometricKeyTag) } catch (_) { suppress }
```

**Decision:** New dedicated method (`teardownBiometryPasswordOnly`) rather than making `bioCipherFunc` optional in existing `teardownBiometry`. Explicit intent, no risk of breaking existing callers.

### App-level flow (example app)

```
┌─────────────────────────────────────────────────────────────┐
│ UI Layer                                                     │
│                                                              │
│ LockedScreen / BiometricUnlockButton                         │
│   └── Hide biometric button when isBiometricKeyInvalidated   │
│                                                              │
│ AuthenticationBottomSheet (via biometric stream)              │
│   └── Show "Biometrics have changed" inline message          │
│                                                              │
│ SettingsScreen                                               │
│   └── Show invalidation description in error color           │
│   └── Route toggle-off to password-only event                │
└──────────────────────────┬───────────────────────────────────┘
                           │
┌──────────────────────────▼───────────────────────────────────┐
│ BLoC Layer (LockerBloc)                                      │
│                                                              │
│ _handleBiometricFailure:                                     │
│   keyInvalidated → set flag, emit biometricKeyInvalidated    │
│                    action, reset to idle, return early        │
│                                                              │
│ _onDisableBiometricPasswordOnlyRequested:                    │
│   password-only → repo.disableBiometricPasswordOnly          │
│                 → clear flag, refresh biometric state         │
│                                                              │
│ Clear flag on: enable success, erase                         │
└──────────────────────────┬───────────────────────────────────┘
                           │
┌──────────────────────────▼───────────────────────────────────┐
│ Repository Layer (LockerRepositoryImpl)                       │
│                                                              │
│ disableBiometricPasswordOnly(password):                      │
│   authenticatePassword → locker.teardownBiometryPasswordOnly │
└──────────────────────────┬───────────────────────────────────┘
                           │
┌──────────────────────────▼───────────────────────────────────┐
│ Library Layer (MFALocker)                                    │
│                                                              │
│ teardownBiometryPasswordOnly(passwordCipherFunc, keyTag):    │
│   deleteWrap(Origin.bio) + try deleteKey (suppress errors)   │
└─────────────────────────────────────────────────────────────┘
```

---

## 5. Data Model

No changes to the storage data model. JSON structure (`salt`, `lockTimeout`, `masterKey`, `entries`, `hmacKey`, `hmacSignature`) stays identical.

New enum values added to existing enums (all in-memory only, none serialized):

| Layer | Enum | New Value |
|-------|------|-----------|
| Android native | `ErrorType` | `KEY_PERMANENTLY_INVALIDATED` |
| iOS/macOS native | `KeychainServiceError` | `.keyPermanentlyInvalidated` |
| iOS/macOS native | `SecureEnclaveManagerError` | `.keyPermanentlyInvalidated` |
| iOS/macOS native | `SecureEnclavePluginError` | `.keyPermanentlyInvalidated` |
| Dart plugin | `BiometricCipherExceptionCode` | `keyPermanentlyInvalidated` |
| Dart locker | `BiometricExceptionType` | `keyInvalidated` |

---

## 6. Workflows

### Workflow 1: Biometric key invalidation detection

```
User triggers decrypt with biometrics
  → Platform attempts cipher init / key access
  → Key is permanently invalidated
  → Platform throws keyPermanentlyInvalidated
  → Dart plugin maps to BiometricCipherExceptionCode.keyPermanentlyInvalidated
  → Locker provider maps to BiometricExceptionType.keyInvalidated
  → App layer receives keyInvalidated (distinct from failure/cancel)
```

No retry, no fallback at the locker level — the app decides what to do.

### Workflow 2: Password-only biometric teardown

```
App detects keyInvalidated
  → App calls teardownBiometryPasswordOnly(passwordCipherFunc, biometricKeyTag)
    → Authenticate with password (loadAllMetaIfLocked)
    → Delete Origin.bio wrap from storage (deleteWrap)
    → Try to delete hardware key (deleteKey) — errors suppressed
  → Biometric wrap is cleanly removed
  → App can re-enable biometrics with fresh key if desired
```

### Workflow 3: Example app biometric invalidation recovery

```
User changes biometrics in device settings (e.g., enrolls new fingerprint)
  → User opens app → vault is locked
  → User taps "Unlock Storage" → auth bottom sheet opens with biometric button
  → Biometric prompt triggers → platform throws keyPermanentlyInvalidated
  → BLoC sets isBiometricKeyInvalidated = true
  → BLoC emits biometricKeyInvalidated action
  → Biometric stream maps to BiometricFailed("Biometrics have changed. Please use your password.")
  → Auth bottom sheet shows inline error message
  → Biometric button hides (sheet + locked screen)
  → User enters password → vault unlocks normally
  → User navigates to Settings
  → Biometric tile shows "Biometrics changed. Disable and re-enable to use new biometrics." in error color
  → User toggles biometric OFF → password prompt appears
  → User enters password → LockerBloc dispatches disableBiometricPasswordOnlyRequested
  → Repository calls teardownBiometryPasswordOnly (no biometric prompt)
  → Origin.bio wrap removed, flag cleared
  → User toggles biometric ON → password + biometric prompts
  → Fresh key created, biometric re-enabled with new enrollment
```

### Unchanged workflows (must not break)

- Wrong fingerprint → `BiometricExceptionType.failure`
- User cancels prompt → `BiometricExceptionType.cancel`
- Device lockout → `BiometricExceptionType.failure`
- Normal `teardownBiometry` with valid bio key → works as before

---

## 7. Logging

No new logging infrastructure. Use existing `logger` in `MFALocker`.

Only one log point needed:

- **`teardownBiometryPasswordOnly`** — log when hardware key deletion is suppressed:
  ```
  logger.logWarning('teardownBiometryPasswordOnly: failed to delete biometric key, suppressing')
  ```

Native layer: no additional logging. The error code `KEY_PERMANENTLY_INVALIDATED` flowing through the channel is self-documenting. Platform-level logging already captures exception stack traces by default.

No logging for enum mappings — pure transformations with no side effects worth logging.

---

## Acceptance Criteria

1. `BiometricCipherExceptionCode.keyPermanentlyInvalidated` is thrown when the Android key is permanently invalidated.
2. `BiometricCipherExceptionCode.keyPermanentlyInvalidated` is thrown when the iOS/macOS Secure Enclave key is inaccessible due to biometric enrollment change.
3. `BiometricExceptionType.keyInvalidated` is surfaced from the locker layer when the underlying cipher code is `keyPermanentlyInvalidated`.
4. `MFALocker.teardownBiometryPasswordOnly` removes the `Origin.bio` wrap using password auth alone, without triggering a biometric prompt.
5. Generic auth failures (wrong fingerprint, lockout, cancel) continue producing `failure` / `cancel` — not reclassified as `keyInvalidated`.
