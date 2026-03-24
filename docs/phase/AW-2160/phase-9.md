# Phase 9: Android — `isKeyValid(tag)` Silent Probe

**Goal:** Add a platform method to probe biometric key validity without showing a `BiometricPrompt`. `Cipher.init(ENCRYPT_MODE, key)` throws `KeyPermanentlyInvalidatedException` synchronously for invalidated keys — no user interaction.

## Context

### Feature Motivation

Phases 1–8 implement **reactive** detection: `keyInvalidated` is discovered only when the user triggers a biometric operation (e.g. tapping the unlock button). This causes the lock screen to briefly show the biometric button before hiding it.

Iterations 9–14 add **proactive** detection: `determineBiometricState()` checks key validity at init time without triggering any biometric prompt. The lock screen can immediately hide the biometric button when the key is invalidated — no button flash.

This iteration is the Android half of that platform method.

### Why Android Can Do This Silently

On Android, `Cipher.init()` with the secret key throws `KeyPermanentlyInvalidatedException` **synchronously** before the `BiometricPrompt` is shown. This means:
- No UI prompt, no user interaction
- The probe is a pure Kotlin call to `Cipher.init(Cipher.ENCRYPT_MODE, key)`
- A valid key succeeds silently; an invalidated key throws immediately

### Android Error Propagation (Existing)

```
KeyPermanentlyInvalidatedException (thrown by Cipher.init)
  → SecureRepositoryImpl            (new: isKeyValid)
  → SecureServiceImpl               (new: delegate)
  → SecureMethodCallHandlerImpl     (new: "isKeyValid" channel handler)
  → Flutter method channel → Dart
```

### How isKeyValid Differs from Decrypt

The existing `decrypt` path loads the cipher with `DECRYPT_MODE` and uses it inside a `BiometricPrompt` callback. The new `isKeyValid` path:
- Uses `ENCRYPT_MODE` (any mode works for the probe — `Cipher.init` fails before any data is processed)
- Never creates or shows a `BiometricPrompt`
- Returns a `Boolean` result immediately

### Project Structure — Files Changed

```
packages/biometric_cipher/android/src/main/kotlin/…/
├── SecureRepositoryImpl.kt         # + isKeyValid(keyAlias): Boolean
├── SecureServiceImpl.kt            # + isKeyValid(tag): Boolean (delegate)
└── handlers/
    └── SecureMethodCallHandlerImpl.kt  # + "isKeyValid" channel handler
```

No new files. All changes are additions to existing files.

## Tasks

- [ ] **9.1** Add `isKeyValid(keyAlias)` to `SecureRepositoryImpl`
  - File: `packages/biometric_cipher/android/src/main/kotlin/…/SecureRepositoryImpl.kt`
  - Load `AndroidKeyStore`, get key by alias (return `false` if null)
  - `Cipher.getInstance(TRANSFORMATION)` → `cipher.init(Cipher.ENCRYPT_MODE, key)` → return `true`
  - Catch `KeyPermanentlyInvalidatedException` → return `false`

- [ ] **9.2** Add `isKeyValid(tag)` delegation to `SecureServiceImpl`
  - File: `packages/biometric_cipher/android/src/main/kotlin/…/SecureServiceImpl.kt`
  - Delegate: `fun isKeyValid(tag: String): Boolean = secureRepository.isKeyValid(tag)`

- [ ] **9.3** Add `"isKeyValid"` method channel handler to `SecureMethodCallHandlerImpl`
  - File: `packages/biometric_cipher/android/src/main/kotlin/…/handlers/SecureMethodCallHandlerImpl.kt`
  - Parse `tag` argument (error if missing)
  - Call `secureService.isKeyValid(tag)` → `result.success(Boolean)`

## Acceptance Criteria

**Test:** Build Android (`fvm flutter build apk --debug`) — build succeeds with no compilation errors.

- `isKeyValid` is callable from the Flutter method channel with a `tag` string argument
- Returns `false` for a permanently invalidated key without showing a `BiometricPrompt`
- Returns `true` for a valid key without showing a `BiometricPrompt`
- Missing `tag` argument returns a channel error (not a crash)

## Dependencies

- Phase 8 complete (app-level password-only disable flow is done)
- `TRANSFORMATION` constant already exists in `SecureRepositoryImpl` — reuse it
- `KeyPermanentlyInvalidatedException` import: `android.security.keystore.KeyPermanentlyInvalidatedException`
- `ErrorType.INVALID_ARGUMENT` already exists for the missing-tag error

## Technical Details

### Task 9.1 — `SecureRepositoryImpl.isKeyValid`

```kotlin
import android.security.keystore.KeyPermanentlyInvalidatedException

fun isKeyValid(keyAlias: String): Boolean {
    val keyStore = KeyStore.getInstance("AndroidKeyStore")
    keyStore.load(null)

    val key = keyStore.getKey(keyAlias, null) ?: return false

    return try {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key)
        true
    } catch (e: KeyPermanentlyInvalidatedException) {
        false
    }
}
```

Key points:
- `keyStore.getKey(keyAlias, null)` returns `null` if the alias doesn't exist → return `false` (key never created)
- `Cipher.init(ENCRYPT_MODE, ...)` fails synchronously for invalidated keys — no prompt, no async
- Only `KeyPermanentlyInvalidatedException` is caught — all other exceptions propagate normally

### Task 9.2 — `SecureServiceImpl.isKeyValid`

```kotlin
fun isKeyValid(tag: String): Boolean = secureRepository.isKeyValid(tag)
```

Simple delegation, same pattern as existing `deleteKey`, `createKey`, etc.

### Task 9.3 — Channel handler in `SecureMethodCallHandlerImpl`

```kotlin
"isKeyValid" -> {
    val tag = call.argument<String>("tag")
        ?: return result.error(ErrorType.INVALID_ARGUMENT.name, "Tag is required", null)
    result.success(secureService.isKeyValid(tag))
}
```

Add this `when` branch alongside the existing `"encrypt"`, `"decrypt"`, `"deleteKey"`, etc. branches.

The method name `"isKeyValid"` must match the Dart-side channel call in Iteration 11.

## Implementation Notes

- Tasks 9.1 → 9.2 → 9.3 must be done in order (each depends on the previous).
- The `TRANSFORMATION` constant used in `Cipher.getInstance(TRANSFORMATION)` is already defined in `SecureRepositoryImpl` for the encrypt/decrypt path — use it directly, no change needed.
- Do not add logging — the operation is a silent probe with no side effects.
- Do not wrap `keyStore.load(null)` in a try/catch — let unexpected keystore errors propagate; the goal is only to suppress `KeyPermanentlyInvalidatedException`.
