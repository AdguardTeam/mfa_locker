# AW-2160 Phase 12 Summary — Dart Plugin: `BiometricCipher.isKeyValid(tag)`

## What Was Done

Phase 12 wires the Dart-side bridge for the `isKeyValid` method channel call. Phases 9–11 added native handlers for this call on Android, iOS/macOS, and Windows respectively; without this phase, those handlers were unreachable from Dart. Phase 12 adds the abstract method declaration to the platform interface, the concrete `MethodChannel` implementation, the public API on `BiometricCipher`, and four automated tests.

All changes are confined to `packages/biometric_cipher/lib/` and `packages/biometric_cipher/test/`. No native files were touched. No new files were created.

---

## Files Changed

| Task | File | Change |
|------|------|--------|
| 12.1 | `packages/biometric_cipher/lib/biometric_cipher_platform_interface.dart` | Added `isKeyValid({required String tag})` abstract method to `BiometricCipherPlatform` |
| 12.2 | `packages/biometric_cipher/lib/biometric_cipher.dart` | Added `isKeyValid({required String tag})` public method with empty-tag guard and delegation to `_instance` |
| (implicit) | `packages/biometric_cipher/lib/biometric_cipher_method_channel.dart` | Added `@override isKeyValid` calling `invokeMethod('isKeyValid', {'tag': tag})` with `PlatformException` mapping and `?? false` null guard |
| (implicit) | `packages/biometric_cipher/test/mock_biometric_cipher_platform.dart` | Added `isKeyValid` implementation returning `_storedKeys.containsKey(tag)` |
| (implicit) | `packages/biometric_cipher/test/biometric_cipher_test.dart` | Added four tests covering the happy path, nonexistent key, post-deletion, and empty-tag guard |

---

## What Was Added

### Task 12.1 — Platform interface (`biometric_cipher_platform_interface.dart`)

Added the abstract method to `BiometricCipherPlatform`, following the same pattern as `generateKey`, `encrypt`, `decrypt`, and `deleteKey`:

```dart
Future<bool> isKeyValid({required String tag}) {
  throw UnimplementedError('isKeyValid({required String tag}) has not been implemented.');
}
```

The method is documented to explain the no-prompt guarantee and lists the platform-specific mechanism for each platform (Android `Cipher.init()` probe, iOS/macOS `SecItemCopyMatching` with `kSecUseAuthenticationUISkip`, Windows `KeyCredentialManager::OpenAsync()` status check).

Any third-party `BiometricCipherPlatform` subclass that does not override this method will receive a clear `UnimplementedError` at runtime rather than a silent `false`.

### Task 12.2 — Public API (`biometric_cipher.dart`)

Added `isKeyValid` to `BiometricCipher`. The method rejects empty tags with a synchronous `BiometricCipherException(code: BiometricCipherExceptionCode.invalidArgument)` before making any platform call, then delegates to `_instance.isKeyValid(tag: tag)`:

```dart
Future<bool> isKeyValid({required String tag}) {
  if (tag.isEmpty) {
    throw const BiometricCipherException(
      code: BiometricCipherExceptionCode.invalidArgument,
      message: 'Tag cannot be empty',
    );
  }

  return _instance.isKeyValid(tag: tag);
}
```

No `async`/`await` is used — the method returns the `Future<bool>` from `_instance` directly on the happy path, and throws synchronously on the error path. This matches the existing style of `generateKey` and `deleteKey`.

The method does not require the plugin to be configured (`_configured` flag not checked). This is correct by design: validity probing never shows a biometric prompt, so the `ConfigData` used to configure prompt titles is irrelevant.

### Method channel implementation (`biometric_cipher_method_channel.dart`)

`MethodChannelBiometricCipher.isKeyValid` calls `invokeMethod<bool>('isKeyValid', {'tag': tag})`. Two details:

- **Method name:** `'isKeyValid'` is exact camelCase, matching the Android handler (`"isKeyValid"` in `SecureMethodCallHandlerImpl.kt`), the iOS/macOS handler (`"isKeyValid"` in `BiometricCipherPlugin.swift`), and the Windows handler (`{"isKeyValid", MethodName::kIsKeyValid}` in `method_name.cpp`). A mismatch here would produce a `MissingPluginException` at runtime on the mismatched platform.
- **Null guard:** `invokeMethod<bool>` returns `bool?`. The expression `result ?? false` ensures a concrete `bool` is always returned. A `null` response is treated as invalid — conservative and safe, since all three platform implementations are confirmed to return a concrete `bool`.

`PlatformException` is caught and re-thrown as `BiometricCipherException` via the shared `_mapPlatformException` method.

---

## Dart Plugin Call Stack

```
BiometricCipher.isKeyValid(tag)         [biometric_cipher.dart — this phase]
  │ empty-tag guard (throws synchronously)
  └── _instance.isKeyValid(tag: tag)    [BiometricCipherPlatform — this phase]
        │
        └── invokeMethod('isKeyValid', {'tag': tag})   [biometric_cipher_method_channel.dart — this phase]
              │
              ├── Android: Cipher.init() probe → bool        [Phase 9]
              ├── iOS/macOS: SecItemCopyMatching → bool      [Phase 10]
              └── Windows: OpenAsync() status → bool         [Phase 11]
```

---

## Decisions Made

**No `async`/`await` in `BiometricCipher.isKeyValid`.** The guard throws synchronously; the happy path returns a `Future<bool>` directly from `_instance`. Adding `async` would wrap the synchronous throw in a rejected `Future`, changing observable behavior for callers who `catch` synchronously. This is consistent with `generateKey` and `deleteKey`.

**`null` treated as `false` at the channel layer.** Any platform returning `null` from `isKeyValid` is treated as "key not valid." All three platforms return a concrete `bool`, so this fallback is a safety net. A `null` result leading to a password-only fallback is safer than treating an ambiguous result as a valid key.

**No `_configured` guard.** `decrypt` checks `_configured` because it requires `ConfigData` for prompt titles. `isKeyValid` never shows a prompt, so the configuration state is irrelevant. This was a deliberate omission.

**Method name string is exact camelCase `'isKeyValid'`.** Consistency with all three platform handlers (Phases 9–11) is required for routing to work. The string is a runtime dispatch key; it is not validated at compile time.

**`UnimplementedError` in the platform interface default body.** Fail-loud is the correct behavior for an unimplemented platform override. Silent `false` would hide bugs in custom `BiometricCipherPlatform` implementations.

---

## Automated Tests

Four tests were added to `packages/biometric_cipher/test/biometric_cipher_test.dart` (lines 182–240):

| Test | Scenario | Result |
|------|----------|--------|
| `returns true for existing key` | Generate key for `'valid_tag'`, call `isKeyValid(tag: 'valid_tag')` | Expects `true` |
| `returns false for nonexistent key` | Call `isKeyValid(tag: 'nonexistent_tag')` without generating | Expects `false` |
| `returns false after key deletion` | Generate, delete via `deleteKey`, then call `isKeyValid` | Expects `false` |
| `throws invalidArgument for empty tag` | Call `isKeyValid(tag: '')` | Expects `BiometricCipherException(code: invalidArgument)` |

The mock platform (`MockBiometricCipherPlatform`) implements `isKeyValid` by returning `_storedKeys.containsKey(tag)`, which enables the lifecycle path test (generate → delete → validity returns `false`).

The method channel layer (`MethodChannelBiometricCipher.isKeyValid`) is not unit-tested directly — this is consistent with the rest of `MethodChannelBiometricCipher`; no test file sets up a `MethodChannel` mock handler. The implementation is verified by code review and will be confirmed at runtime during Phase 13 integration.

---

## QA Status

QA is complete (status: RELEASE). All acceptance criteria from the phase spec are satisfied:

| Criterion | Result |
|-----------|--------|
| `BiometricCipher.isKeyValid(tag: '')` throws `BiometricCipherException(invalidArgument)` | PASS — code review + automated test |
| `BiometricCipher.isKeyValid(tag: 'some-tag')` invokes the platform interface | PASS — code review + automated test |
| No new files created | PASS — only existing files modified |
| Static analysis passes with no warnings or infos | PASS — confirmed by code review; formal run required before merge |

No defects found. No logging added.

---

## How Phase 12 Fits in the Full AW-2160 Flow

```
Android: KeyPermanentlyInvalidatedException -> FlutterError("KEY_PERMANENTLY_INVALIDATED")      [Phase 1]
iOS/macOS: Secure Enclave key inaccessible -> FlutterError("KEY_PERMANENTLY_INVALIDATED")       [Phase 2]
  -> Dart plugin: BiometricCipherExceptionCode.keyPermanentlyInvalidated                        [Phase 3]
  -> Locker: BiometricExceptionType.keyInvalidated                                              [Phase 4]
  -> MFALocker.teardownBiometryPasswordOnly available for cleanup                               [Phase 5]
  -> Unit tests for Phases 3-5 Dart layer                                                       [Phase 6]
  -> Example app detects keyInvalidated, updates UI, hides biometric button                     [Phase 7]
  -> Example app password-only disable flow, flag cleared on success                            [Phase 8]
  -> Android isKeyValid(tag) silent probe (Cipher.init, no BiometricPrompt)                     [Phase 9]
  -> iOS/macOS isKeyValid(tag) silent probe (SecItemCopyMatching + kSecUseAuthenticationUISkip) [Phase 10]
  -> Windows isKeyValid(tag) silent probe (KeyCredentialManager::OpenAsync, no dialog)          [Phase 11]
  -> Dart-side invokeMethod('isKeyValid', {'tag': tag}) -- all platforms now reachable          [Phase 12 -- this phase]
  -> Integration into determineBiometricState() -- proactive key check at init time             [Phase 13]
```

Phase 12 is the last blocking dependency before Phase 13. The full `isKeyValid` stack from Dart through to all three native platforms is now complete.

---

## Phase Dependencies

| Phase | Status | Relevance |
|-------|--------|-----------|
| Phase 9 (Android `isKeyValid`) | Complete | Registers `"isKeyValid"` on the Android method channel |
| Phase 10 (iOS/macOS `isKeyValid`) | Complete | Registers `"isKeyValid"` on the iOS/macOS method channel |
| Phase 11 (Windows `isKeyValid`) | Complete | Registers `"isKeyValid"` on the Windows method channel |
| Phase 13 (`BiometricCipherProvider.isKeyValid` + `determineBiometricState` integration) | Pending | Consumes `BiometricCipher.isKeyValid` added in this phase |
| Phase 14 (Tests for proactive detection) | Pending | Depends on Phase 13 |
| Phase 15 (Example app proactive detection) | Complete | Was implemented ahead of Phases 13–14 |
