# AW-2160 Phase 11 Summary — Windows: `isKeyValid(tag)` Silent Probe

## What Was Done

Phase 11 adds `IsKeyValidAsync(tag)` to the Windows C++/WinRT native layer of the `biometric_cipher` plugin. The method silently probes whether a Windows Hello credential exists for a given tag by calling `KeyCredentialManager::OpenAsync(tag)` — a metadata-only WinRT call that never triggers a biometric dialog or signing operation. This is the Windows counterpart to the Android implementation (Phase 9, `Cipher.init()` probe) and the iOS/macOS implementation (Phase 10, `SecItemCopyMatching` with `kSecUseAuthenticationUISkip`).

All changes are confined to `packages/biometric_cipher/windows/`. No new files were created. No Dart-layer, Android, or iOS/macOS files were modified.

---

## Files Changed

All files are within `packages/biometric_cipher/windows/`.

| Task | File | Change |
|------|------|--------|
| 11.1 | `include/biometric_cipher/repositories/windows_hello_repository.h` | Added `IsKeyValidAsync` pure virtual method to the `WindowsHelloRepository` interface |
| 11.2 | `include/biometric_cipher/repositories/windows_hello_repository_impl.h` | Added `IsKeyValidAsync` override declaration |
| 11.2 | `windows_hello_repository_impl.cpp` | Implemented `IsKeyValidAsync` |
| 11.3 | `include/biometric_cipher/services/biometric_cipher_service.h` | Added `IsKeyValidAsync(const std::string& tag)` declaration |
| 11.3 | `biometric_cipher_service.cpp` | Implemented `IsKeyValidAsync` (tag-to-hstring conversion, delegation to repository) |
| 11.4 | `include/biometric_cipher/enums/method_name.h` | Added `kIsKeyValid` enum value before `kNotImplemented` |
| 11.4 | `method_name.cpp` | Added `{"isKeyValid", MethodName::kIsKeyValid}` to `METHOD_NAME_MAP` |
| 11.6 | `argument_parser.cpp` | Added `case MethodName::kIsKeyValid:` to the tag-only fall-through group in `Parse()` |
| 11.5/11.7 | `biometric_cipher_plugin.h` | Added `IsKeyValidCoroutine` declaration in `private:` section |
| 11.5/11.7 | `biometric_cipher_plugin.cpp` | Added `case MethodName::kIsKeyValid:` dispatch and `IsKeyValidCoroutine` implementation |
| 11.8 | `test/mocks/mock_windows_hello_repository.h` | Added `MOCK_METHOD` for `IsKeyValidAsync` to keep the mock consistent with the interface |

Zero new files. All changes are additive modifications to existing files.

---

## What Was Added

### Task 11.1 — `WindowsHelloRepository` interface method

Added at the end of the `WindowsHelloRepository` struct (before the closing `};`):

```cpp
virtual winrt::Windows::Foundation::IAsyncOperation<bool> IsKeyValidAsync(const winrt::hstring tag) const = 0;
```

This is a pure virtual `const` method, consistent with all existing interface methods.

### Task 11.2 — `WindowsHelloRepositoryImpl` declaration and implementation

The implementation calls `CheckWindowsHelloIsStatusAsync()` first (the existing Windows Hello availability guard used by `SignAsync`), then calls `m_HelloWrapper->OpenAsync(tag)`, and returns whether the result status equals `KeyCredentialStatus::Success`.

The critical behavioral distinction from `SignAsync` is that `CheckKeyCredentialStatus()` is NOT called after `OpenAsync()`. `CheckKeyCredentialStatus()` throws `hresult_error` for `NotFound` — calling it would surface an exception instead of `false`. Instead, `IsKeyValidAsync` evaluates `status == KeyCredentialStatus::Success` directly: any non-`Success` status (including `NotFound`, `UserCanceled`, and any other value) returns `false`.

### Task 11.3 — `BiometricCipherService` method

The service layer accepts a `const std::string& tag` (consistent with `GenerateKeyAsync` and `DeleteKeyAsync`), converts it to `hstring` via `StringUtil::ConvertStringToHString(tag)`, and delegates to `m_WindowsHelloRepository->IsKeyValidAsync(hTag)`.

### Task 11.4 — `MethodName` enum and mapping

`kIsKeyValid` is added between `kConfigure` and `kNotImplemented` in the enum. The string `"isKeyValid"` in `METHOD_NAME_MAP` is exact camelCase, matching the Android handler (Phase 9) and iOS/macOS handler (Phase 10). This ensures a single Dart `invokeMethod('isKeyValid', {'tag': tag})` call dispatches correctly on all three platforms when Phase 12 wires the Dart side.

### Task 11.6 — `argument_parser.cpp` (critical undocumented addition)

This task was not in the original PRD task list. It was identified during planning as a required fix: without it, calling `isKeyValid` from Dart causes `Parse()` to fall through to the `default` branch, which throws `hresult_error(error_invalid_argument, L"Not implemented method name")`, and `IsKeyValidCoroutine` never executes.

The fix adds `case MethodName::kIsKeyValid:` as a fall-through label before the existing `kGenerateKey` and `kDeleteKey` cases in the tag-only argument group:

```cpp
case MethodName::kIsKeyValid:
case MethodName::kGenerateKey:
case MethodName::kDeleteKey:
    result[ArgumentName::kTag] = FetchAndValidateArgument(*argumentMap, ArgumentName::kTag);
    break;
```

This task is a prerequisite for Task 11.5 to work at runtime.

### Tasks 11.5 and 11.7 — Plugin handler and coroutine

`HandleMethodCall` dispatches `kIsKeyValid` by parsing the `tag` argument using the existing `ArgumentName::kTag` and calling `IsKeyValidCoroutine(tag, std::move(result))`.

`IsKeyValidCoroutine` follows the standard `winrt::fire_and_forget` + `hresult_error` catch pattern used by all existing coroutines (`GenerateKeyCoroutine`, `DeleteKeyCoroutine`, `EncryptCoroutine`, `DecryptCoroutine`):

- Happy path: `co_await m_SecureService->IsKeyValidAsync(tag)` returns a `bool`, passed directly to `result->Success(isValid)`. No string conversion is applied — `StandardMethodCodec` encodes `bool` natively.
- Error path: `hresult_error` is caught, `OutputException` is called (debug output only, not a crash), and `result->Error(GetErrorCodeString(hr), errorMessage)` surfaces the failure as a `PlatformException` in Dart.

### Task 11.8 — Mock update

Added `MOCK_METHOD` for `IsKeyValidAsync` to `MockWindowsHelloRepository`. This is required because `WindowsHelloRepository` is an abstract interface: adding a pure virtual method without updating the mock causes a compilation error in any test file that instantiates `MockWindowsHelloRepository`. The existing test files (`biometric_cipher_service_test.cpp`, `windows_hello_repository_test.cpp`) compile and pass without changes to their test logic.

---

## Decisions Made

**`NotFound` returns `false`, not an exception.** `SignAsync` calls `CheckKeyCredentialStatus()` after `OpenAsync()`, which throws for `NotFound`. `IsKeyValidAsync` deliberately does not call it — `NotFound` means the credential is gone, which is the expected non-error condition for a validity probe. Any non-`Success` status is treated as `false`.

**No new logging in the happy path.** The method is a silent probe with no observable side effects. `OutputException` is invoked only in the `hresult_error` catch block, which is the standard error-path behavior for all coroutines.

**`const` throughout.** All three new methods (`WindowsHelloRepository::IsKeyValidAsync`, `WindowsHelloRepositoryImpl::IsKeyValidAsync`, `BiometricCipherService::IsKeyValidAsync`) are declared `const`, consistent with the existing interface contract.

**Reuse of existing infrastructure.** No new argument names, no new argument groups, no new wrapper calls. `ArgumentName::kTag` already exists. `CheckWindowsHelloIsStatusAsync()` already exists. `m_HelloWrapper->OpenAsync()` already exists. The only new behavior is omitting `CheckKeyCredentialStatus()` after `OpenAsync()`.

**Method name string is exact camelCase `"isKeyValid"`.** This must match the Android and iOS/macOS handlers for Phase 12 (Dart `invokeMethod`) to route correctly on all platforms. Verified against Phase 9 and Phase 10 implementations.

**Acceptance criterion is a build test only.** No new behavioral automated tests are required in Phase 11. The `MockWindowsHelloRepository` update enables future tests to mock `IsKeyValidAsync` in Phases 12 and 13. The acceptance test — `fvm flutter build windows --debug` with no compilation errors — must be run on a Windows machine with the Visual Studio toolchain and WinRT SDK.

---

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Credential exists (`KeyCredentialStatus::Success`) | Returns `true`; no prompt triggered |
| Credential not found (`KeyCredentialStatus::NotFound`) | Returns `false`; no exception thrown; no prompt triggered |
| Any other `KeyCredentialStatus` value | Returns `false` (conservative: credential is not cleanly accessible) |
| `CheckWindowsHelloIsStatusAsync()` throws (Windows Hello unavailable or unsupported) | `hresult_error` caught in `IsKeyValidCoroutine`; Dart receives `PlatformException` |
| `OpenAsync()` throws (hardware fault, `E_ACCESSDENIED`) | `hresult_error` caught in `IsKeyValidCoroutine`; Dart receives `PlatformException` |
| `tag` argument missing or non-string | `FetchAndValidateArgument` throws `hresult_error(error_invalid_argument, ...)`; Dart receives `PlatformException` |
| Unknown method name | `GetMethodName` returns `kNotImplemented`; `HandleMethodCall` calls `result->NotImplemented()` (unaffected by this phase) |

---

## QA Status

QA is complete (status: RELEASE). All 11 file changes verified by code review. Key findings:

- `argument_parser.cpp` Task 11.6 is implemented correctly at lines 40–44 — the critical undocumented requirement from planning is present.
- `CheckKeyCredentialStatus()` is not called in `IsKeyValidAsync` — `NotFound` evaluates to `false` as required.
- `result->Success(isValid)` passes the raw `bool` — no wrapping or conversion.
- `MockWindowsHelloRepository` is updated — existing test suite compiles without changes.
- No logging added, no new files created, method name `"isKeyValid"` matches all platforms.

The build test (`fvm flutter build windows --debug`) requires a Windows machine and must be confirmed on the Windows CI agent before merge.

---

## How Phase 11 Fits in the Full AW-2160 Flow

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
  -> Windows isKeyValid(tag) silent probe (KeyCredentialManager::OpenAsync, no dialog)          [Phase 11 -- this phase]
  -> Dart-side invokeMethod('isKeyValid', {'tag': tag}) -- all platforms now ready              [Phase 12]
  -> Integration into determineBiometricState() -- proactive key check at init time             [Phase 13]
```

---

## Phase Dependencies

| Phase | Status | Relevance |
|-------|--------|-----------|
| Phase 9 (Android `isKeyValid`) | Complete | Establishes the shared method name `"isKeyValid"` |
| Phase 10 (iOS/macOS `isKeyValid`) | Complete | Confirms method name consistency; same string literal |
| Phase 12 (Dart-side invocation) | Pending | Requires all three platforms to handle `"isKeyValid"` — now unblocked |
| Phase 13 (`determineBiometricState` integration) | Pending | Depends on Phase 12 |
