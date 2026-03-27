# Phase 11: Windows — `isKeyValid(tag)` Silent Probe

**Goal:** Add a platform method to probe key validity on Windows without showing a Windows Hello prompt. `KeyCredentialManager::OpenAsync(tag)` queries credential metadata — `KeyCredentialStatus::NotFound` means the key is gone, `Success` means it exists and is usable. No signing operation is performed, so no biometric prompt is triggered.

## Context

### Feature Motivation

Phases 1–8 implement **reactive** detection: `keyInvalidated` is discovered only when the user triggers a biometric operation. This causes the lock screen to briefly show the biometric button before hiding it.

Iterations 9–14 add **proactive** detection: `determineBiometricState()` checks key validity at init time without triggering any biometric prompt. The lock screen can immediately hide the biometric button when the key is invalidated — no button flash.

This iteration is the Windows half of the platform method (Android was Phase 9, iOS/macOS was Phase 10).

### Why Windows Can Do This Silently

On Windows, `KeyCredentialManager::OpenAsync(tag)` returns a `KeyCredentialRetrievalResult` whose `Status()` property indicates whether the credential exists and is accessible. This call **does not** request a signing operation, so no Windows Hello biometric prompt is triggered — it only queries credential metadata.

- `KeyCredentialStatus::NotFound` → credential does not exist or has been removed → `false`
- `KeyCredentialStatus::Success` → credential exists and is usable → `true`

Unlike Android (where `Cipher.init()` throws `KeyPermanentlyInvalidatedException` for invalidated keys) and iOS/macOS (where the OS deletes the Secure Enclave key on biometric enrollment change), Windows Hello credentials are tied to the user account, not biometric enrollment. However, credentials can be deleted externally (e.g., via `certutil`, device reset, or TPM clear). `isKeyValid` on Windows checks whether the credential still exists and is openable.

### Windows Method Channel Path (New)

```
WindowsHelloRepositoryImpl::IsKeyValidAsync(tag)
  → calls CheckWindowsHelloIsStatusAsync() + m_HelloWrapper->OpenAsync(tag)
  → BiometricCipherService::IsKeyValidAsync(tag)   [new: delegate]
  → MethodName::kIsKeyValid handler                [new: channel handler]
  → Flutter method channel → Dart
```

### How isKeyValid Differs from decrypt/encrypt

The existing `encrypt`/`decrypt` paths involve `WindowsHelloRepositoryImpl` requesting a signing or encryption operation via `Windows.Security.Credentials.KeyCredential::RequestSignAsync` or equivalent, which triggers a Windows Hello prompt. The new `isKeyValid` path:
- Only calls `KeyCredentialManager::OpenAsync(tag)` — a metadata query
- Never triggers any authentication prompt or UI
- Returns a `bool` result via coroutine

### Project Structure — Files Changed

```
packages/biometric_cipher/windows/
├── include/biometric_cipher/repositories/
│   ├── windows_hello_repository.h         # + IsKeyValidAsync interface method
│   └── windows_hello_repository_impl.h    # + IsKeyValidAsync declaration
├── include/biometric_cipher/services/
│   └── biometric_cipher_service.h         # + IsKeyValidAsync method
├── include/biometric_cipher/enums/
│   └── method_name.h                      # + kIsKeyValid enum value
├── windows_hello_repository_impl.cpp      # + IsKeyValidAsync implementation
├── biometric_cipher_service.cpp           # + IsKeyValidAsync implementation
├── method_name.cpp                        # + "isKeyValid" → kIsKeyValid mapping
├── biometric_cipher_plugin.h              # + IsKeyValidCoroutine declaration
└── biometric_cipher_plugin.cpp            # + kIsKeyValid case + IsKeyValidCoroutine
```

No new files. All changes are additions to existing files.

## Tasks

- [ ] **11.1** Add `IsKeyValidAsync` to `WindowsHelloRepository` interface
  - File: `packages/biometric_cipher/windows/include/biometric_cipher/repositories/windows_hello_repository.h`
  - Add `virtual IAsyncOperation<bool> IsKeyValidAsync(const winrt::hstring tag) const = 0;`

- [ ] **11.2** Implement `IsKeyValidAsync` in `WindowsHelloRepositoryImpl`
  - File: `packages/biometric_cipher/windows/include/biometric_cipher/repositories/windows_hello_repository_impl.h` (declaration)
  - File: `packages/biometric_cipher/windows/windows_hello_repository_impl.cpp` (implementation)
  - Call `CheckWindowsHelloIsStatusAsync()` → `m_HelloWrapper->OpenAsync(tag)` → return `status == KeyCredentialStatus::Success`

- [ ] **11.3** Add `IsKeyValidAsync` to `BiometricCipherService`
  - File: `packages/biometric_cipher/windows/include/biometric_cipher/services/biometric_cipher_service.h` (declaration)
  - File: `packages/biometric_cipher/windows/biometric_cipher_service.cpp` (implementation)
  - Delegate: convert tag to `hstring`, call `m_WindowsHelloRepository->IsKeyValidAsync(hTag)`

- [ ] **11.4** Add `kIsKeyValid` to `MethodName` enum and mapping
  - File: `packages/biometric_cipher/windows/include/biometric_cipher/enums/method_name.h`
  - Add `kIsKeyValid` before `kNotImplemented`
  - File: `packages/biometric_cipher/windows/method_name.cpp`
  - Add `{"isKeyValid", MethodName::kIsKeyValid}` to `METHOD_NAME_MAP`

- [ ] **11.5** Add `isKeyValid` method channel handler to `BiometricCipherPlugin`
  - File: `packages/biometric_cipher/windows/biometric_cipher_plugin.h` (declaration)
  - File: `packages/biometric_cipher/windows/biometric_cipher_plugin.cpp` (implementation)
  - Add `case MethodName::kIsKeyValid:` to `HandleMethodCall` switch
  - Parse `tag` argument, call `IsKeyValidCoroutine(tag, std::move(result))`
  - `IsKeyValidCoroutine`: call `m_SecureService->IsKeyValidAsync(tag)` → `result->Success(bool)`

## Acceptance Criteria

**Test:** Build Windows (`fvm flutter build windows --debug`) — build succeeds with no compilation errors.

- `isKeyValid` is callable from the Flutter method channel with a `tag` string argument
- Returns `false` for a missing/deleted credential without showing any Windows Hello prompt
- Returns `true` for a valid credential without showing any Windows Hello prompt
- Method name `"isKeyValid"` matches Android and iOS/macOS channel handler names

## Dependencies

- Phase 10 complete (iOS/macOS `isKeyValid` done — same method name must match)
- Method name `"isKeyValid"` must be identical to the Android (Phase 9) and iOS/macOS (Phase 10) handler names — all are called from the same Dart-side channel invocation in Phase 12

## Technical Details

### Task 11.1 — Interface method in `WindowsHelloRepository`

```cpp
virtual winrt::Windows::Foundation::IAsyncOperation<bool> IsKeyValidAsync(const winrt::hstring tag) const = 0;
```

Add alongside existing virtual methods (`OpenAsync`, `DeleteAsync`, etc.).

### Task 11.2 — Implementation in `WindowsHelloRepositoryImpl`

Header declaration:
```cpp
winrt::Windows::Foundation::IAsyncOperation<bool> IsKeyValidAsync(const winrt::hstring tag) const override;
```

Implementation:
```cpp
IAsyncOperation<bool> WindowsHelloRepositoryImpl::IsKeyValidAsync(const winrt::hstring tag) const
{
    co_await CheckWindowsHelloIsStatusAsync();

    auto&& keyCredentialRetrievalResult = co_await m_HelloWrapper->OpenAsync(tag);
    auto status = keyCredentialRetrievalResult.Status();

    co_return status == KeyCredentialStatus::Success;
}
```

`OpenAsync` only queries the credential store — it does not trigger a biometric prompt. `KeyCredentialStatus::NotFound` → key is gone → `false`. `KeyCredentialStatus::Success` → key exists and is usable → `true`.

### Task 11.3 — `BiometricCipherService`

Header declaration:
```cpp
winrt::Windows::Foundation::IAsyncOperation<bool> IsKeyValidAsync(const std::string& tag) const;
```

Implementation:
```cpp
IAsyncOperation<bool> BiometricCipherService::IsKeyValidAsync(const std::string& tag) const
{
    auto hTag = StringUtil::ConvertStringToHString(tag);
    co_return co_await m_WindowsHelloRepository->IsKeyValidAsync(hTag);
}
```

### Task 11.4 — `MethodName` enum and mapping

Enum (`method_name.h`):
```cpp
enum class MethodName {
    kGetTPMStatus,
    kGetBiometryStatus,
    kGenerateKey,
    kEncrypt,
    kDecrypt,
    kDeleteKey,
    kConfigure,
    kIsKeyValid,       // new
    kNotImplemented,
};
```

Mapping (`method_name.cpp`):
```cpp
{"isKeyValid", MethodName::kIsKeyValid},
```

### Task 11.5 — Channel handler in `BiometricCipherPlugin`

Plugin header declaration:
```cpp
winrt::fire_and_forget IsKeyValidCoroutine(
    const std::string& tag,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
```

Switch case in `HandleMethodCall` (`biometric_cipher_plugin.cpp`):
```cpp
case MethodName::kIsKeyValid:
{
    auto arguments = m_Argument_parser.Parse(method, methodCall.arguments());
    const std::string tag = arguments[ArgumentName::kTag].stringArgument;

    IsKeyValidCoroutine(tag, std::move(result));
    break;
}
```

Coroutine implementation:
```cpp
winrt::fire_and_forget BiometricCipherPlugin::IsKeyValidCoroutine(
    const std::string& tag,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
{
    try {
        auto isValid = co_await m_SecureService->IsKeyValidAsync(tag);

        result->Success(isValid);
    }
    catch (const hresult_error& e) {
        auto hr = e.code();
        auto message = e.message();
        auto errorMessage = StringUtil::ConvertHStringToString(message);
        OutputException(hr, errorMessage);

        result->Error(GetErrorCodeString(hr), errorMessage);
    }
}
```

## Implementation Notes

- Tasks 11.1 → 11.2 → 11.3 → 11.4 → 11.5 must be done in order (each depends on the previous).
- Do not add logging — the operation is a silent probe with no side effects.
- The method name `"isKeyValid"` must be identical to the Android (Phase 9) and iOS/macOS (Phase 10) handler names — all are called from the same Dart-side channel invocation in Phase 12.
- `ArgumentName::kTag` should already exist (used by existing handlers like `encrypt`, `decrypt`, `deleteKey`) — no new argument name needed.
