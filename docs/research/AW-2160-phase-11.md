# Research: AW-2160 Phase 11 — Windows `isKeyValid` Silent Probe

## Resolved Questions

No open questions were identified in the PRD. The phase description, idea doc (section G2b), and vision doc provide complete technical detail.

---

## Phase Scope

Phase 11 adds `IsKeyValidAsync(tag)` to the Windows C++/WinRT plugin layer only. The call chain is:

```
BiometricCipherPlugin::HandleMethodCall ("isKeyValid")
  → IsKeyValidCoroutine(tag, result)
  → BiometricCipherService::IsKeyValidAsync(tag)
  → WindowsHelloRepositoryImpl::IsKeyValidAsync(hTag)
  → CheckWindowsHelloIsStatusAsync() + m_HelloWrapper->OpenAsync(tag)
  → KeyCredentialStatus::Success → true / NotFound → false
```

No Dart-layer changes. No new files. All 8 touches are within `packages/biometric_cipher/windows/`.

---

## Related Modules/Services

### All target files — current state

**1. `windows_hello_repository.h`**
Path: `packages/biometric_cipher/windows/include/biometric_cipher/repositories/windows_hello_repository.h`

Pure abstract `struct` with 4 virtual methods: `GetWindowsHelloStatusAsync()`, `SignAsync()`, `CreateCredentialAsync()`, `DeleteCredentialAsync()`. New `IsKeyValidAsync` goes after `DeleteCredentialAsync` (last method).

**2. `windows_hello_repository_impl.h`**
Path: `packages/biometric_cipher/windows/include/biometric_cipher/repositories/windows_hello_repository_impl.h`

Declares overrides for all 4 interface methods in the `public:` section. Private section contains `CheckWindowsHelloIsStatusAsync()` (already exists — reused as-is in the new implementation). New `IsKeyValidAsync` override declaration goes in `public:` after `DeleteCredentialAsync`.

**3. `windows_hello_repository_impl.cpp`**
Path: `packages/biometric_cipher/windows/windows_hello_repository_impl.cpp`

Implements all 4 methods plus the private `CheckWindowsHelloIsStatusAsync()`. The pattern for a method using both `CheckWindowsHelloIsStatusAsync()` and `OpenAsync()` is already established in `SignAsync()` (lines 54–81). `DeleteCredentialAsync` is the last method before `CheckWindowsHelloIsStatusAsync` in the file. New `IsKeyValidAsync` implementation appended after `DeleteCredentialAsync`.

Key detail from `SignAsync`: after calling `CheckWindowsHelloIsStatusAsync()` and `OpenAsync(tag)`, `SignAsync` calls `CheckKeyCredentialStatus()` which throws on `NotFound`. The new `IsKeyValidAsync` must NOT call `CheckKeyCredentialStatus()` — it checks `status == KeyCredentialStatus::Success` directly and returns a `bool`. This is intentional: `NotFound` means `false`, not an exception.

The `CheckWindowsHelloIsStatusAsync()` private method (lines 129–137) throws `hresult_error(error_biometry_not_supported, ...)` if Windows Hello is unavailable. The `IsKeyValidCoroutine` catch block will surface this to Dart via `result->Error(...)`.

**4. `biometric_cipher_service.h`**
Path: `packages/biometric_cipher/windows/include/biometric_cipher/services/biometric_cipher_service.h`

Declares 6 public methods: `GetTPMStatusAsync`, `GetBiometryStatusAsync`, `GenerateKeyAsync`, `DeleteKeyAsync`, `EncryptAsync`, `DecryptAsync`. New `IsKeyValidAsync(const std::string& tag) const` goes in the `public:` section after `DecryptAsync`.

**5. `biometric_cipher_service.cpp`**
Path: `packages/biometric_cipher/windows/biometric_cipher_service.cpp`

Implements all 6 service methods. The simple delegation pattern used for single-argument methods (e.g., `GenerateKeyAsync`, `DeleteKeyAsync`) applies: convert tag with `StringUtil::ConvertStringToHString(tag)`, then delegate to `m_WindowsHelloRepository->IsKeyValidAsync(hTag)`. New `IsKeyValidAsync` appended after `DecryptAsync`/`CreateAESKeyAsync`.

**6. `method_name.h`**
Path: `packages/biometric_cipher/windows/include/biometric_cipher/enums/method_name.h`

Enum currently has 8 values: `kGetTPMStatus`, `kGetBiometryStatus`, `kGenerateKey`, `kEncrypt`, `kDecrypt`, `kDeleteKey`, `kConfigure`, `kNotImplemented`. New `kIsKeyValid` inserted before `kNotImplemented`.

**7. `method_name.cpp`**
Path: `packages/biometric_cipher/windows/method_name.cpp`

`METHOD_NAME_MAP` currently has 7 string-to-enum entries (plus `"notImplemented"` → `kNotImplemented`). `GetMethodName()` falls back to `kNotImplemented` for unknown strings — it does not use integers. New entry `{"isKeyValid", MethodName::kIsKeyValid}` added to the map.

**8. `biometric_cipher_plugin.h`**
Path: `packages/biometric_cipher/windows/biometric_cipher_plugin.h`

Declares 6 private coroutines: `GetTPMStatus`, `GetBiometryStatus`, `GenerateKeyCoroutine`, `DeleteKeyCoroutine`, `EncryptCoroutine`, `DecryptCoroutine`. New `IsKeyValidCoroutine` declaration goes after `DecryptCoroutine` and before `OutputException`.

Signature to add:
```cpp
winrt::fire_and_forget IsKeyValidCoroutine(
    const std::string& tag,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
```

**9. `biometric_cipher_plugin.cpp`**
Path: `packages/biometric_cipher/windows/biometric_cipher_plugin.cpp`

`HandleMethodCall` switch currently has 7 `case` blocks plus `kNotImplemented`/`default`. New `case MethodName::kIsKeyValid:` inserted between `kConfigure` and `kNotImplemented`. Coroutine implementation appended after `DecryptCoroutine` (before `OutputException`).

**10. `mock_windows_hello_repository.h`**
Path: `packages/biometric_cipher/windows/test/mocks/mock_windows_hello_repository.h`

Currently mocks all 4 interface methods with `MOCK_METHOD`. New mock entry required for `IsKeyValidAsync`.

---

## Current Endpoints and Contracts

### Existing method channel methods (unaffected)

| Method name (Dart) | `MethodName` enum | Coroutine |
|--------------------|-------------------|-----------|
| `getTPMStatus` | `kGetTPMStatus` | `GetTPMStatus` |
| `getBiometryStatus` | `kGetBiometryStatus` | `GetBiometryStatus` |
| `generateKey` | `kGenerateKey` | `GenerateKeyCoroutine` |
| `encrypt` | `kEncrypt` | `EncryptCoroutine` |
| `decrypt` | `kDecrypt` | `DecryptCoroutine` |
| `deleteKey` | `kDeleteKey` | `DeleteKeyCoroutine` |
| `configure` | `kConfigure` | (inline, no coroutine) |

### New method channel method

| Method name (Dart) | `MethodName` enum | Coroutine |
|--------------------|-------------------|-----------|
| `isKeyValid` | `kIsKeyValid` | `IsKeyValidCoroutine` |

Flutter method channel name: `"biometric_cipher"` (unchanged, registered in `RegisterWithRegistrar`).

---

## Patterns Used

### 1. Coroutine pattern (`fire_and_forget` + `hresult_error` catch)

All single-value returning coroutines follow this pattern (example: `DeleteKeyCoroutine`):

```cpp
winrt::fire_and_forget BiometricCipherPlugin::DeleteKeyCoroutine(
    const std::string& tag,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
{
    try {
        co_await m_SecureService->DeleteKeyAsync(tag);
        result->Success(NULL);
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

`IsKeyValidCoroutine` follows the same pattern, with `result->Success(isValid)` where `isValid` is a `bool`. The `StandardMethodCodec` encodes `bool` natively — no conversion needed.

### 2. Tag-only switch case pattern

Cases that parse only a `tag` argument (example: `kGenerateKey`, `kDeleteKey`):

```cpp
case MethodName::kGenerateKey:
{
    auto arguments = m_Argument_parser.Parse(method, methodCall.arguments());
    const std::string tag = arguments[ArgumentName::kTag].stringArgument;
    GenerateKeyCoroutine(tag, std::move(result));
    break;
}
```

`kIsKeyValid` follows this same pattern (tag-only, no data argument).

### 3. Tag-to-hstring conversion in service

```cpp
IAsyncAction BiometricCipherService::GenerateKeyAsync(const std::string& tag) const
{
    auto hTag = StringUtil::ConvertStringToHString(tag);
    co_await m_WindowsHelloRepository->CreateCredentialAsync(hTag);
    co_return;
}
```

`IsKeyValidAsync` in the service uses the same `StringUtil::ConvertStringToHString(tag)` conversion.

### 4. CheckWindowsHelloIsStatusAsync + OpenAsync pattern

`SignAsync` already calls both in sequence:

```cpp
co_await CheckWindowsHelloIsStatusAsync();
auto&& keyCredentialRetrievalResult = co_await m_HelloWrapper->OpenAsync(tag);
```

`IsKeyValidAsync` reuses this pattern but does NOT call `CheckKeyCredentialStatus()` afterwards — instead checks `status == KeyCredentialStatus::Success` to produce a `bool`.

### 5. `MOCK_METHOD` pattern in `MockWindowsHelloRepository`

```cpp
MOCK_METHOD(
    (IAsyncAction),
    DeleteCredentialAsync,
    (const hstring tag),
    (const, override)
);
```

New mock for `IsKeyValidAsync`:
```cpp
MOCK_METHOD(
    (IAsyncOperation<bool>),
    IsKeyValidAsync,
    (const hstring tag),
    (const, override)
);
```

---

## Phase-Specific Limitations and Risks

### Critical finding: `argument_parser.cpp` also requires a change

The PRD's task list (tasks 11.1–11.5) and the phase doc do not mention `argument_parser.cpp`, but this file **must also be updated**.

`ArgumentParser::Parse()` (file: `packages/biometric_cipher/windows/argument_parser.cpp`, lines 31–53) has a `switch (methodName)` with a `default` branch that throws:

```cpp
default:
    throw hresult_error(error_invalid_argument, L"Not implemented method name");
```

Every case that calls `m_Argument_parser.Parse(method, methodCall.arguments())` in `HandleMethodCall` requires a corresponding case in `ArgumentParser::Parse()`. The `kIsKeyValid` handler in task 11.5 calls `Parse()` to extract the `tag` argument, so `argument_parser.cpp` must add:

```cpp
case MethodName::kIsKeyValid:
    result[ArgumentName::kTag] = FetchAndValidateArgument(*argumentMap, ArgumentName::kTag);
    break;
```

This can be merged with the existing `kGenerateKey` / `kDeleteKey` case (both parse only `kTag`) or added as a separate case. The existing grouped approach is:

```cpp
case MethodName::kGenerateKey:
case MethodName::kDeleteKey:
    result[ArgumentName::kTag] = FetchAndValidateArgument(*argumentMap, ArgumentName::kTag);
    break;
```

Adding `case MethodName::kIsKeyValid:` before `kGenerateKey` in this group is the minimal change.

**Without this change, calling `isKeyValid` from Dart will cause an `hresult_error` to be thrown inside `Parse()` before `IsKeyValidCoroutine` is ever called.** The PRD should be treated as implicitly requiring this fix.

### `CheckKeyCredentialStatus` must NOT be called in `IsKeyValidAsync`

The existing `SignAsync` calls `CheckKeyCredentialStatus(keyCredentialRetrievalResult.Status())` which throws `hresult_error(error_key_not_found, ...)` for `KeyCredentialStatus::NotFound`. `IsKeyValidAsync` must bypass this helper and evaluate `status == KeyCredentialStatus::Success` directly. `NotFound` must return `false`, not throw.

### `const` qualifier on `IsKeyValidAsync`

All 4 existing interface methods in `WindowsHelloRepository` are `const`. The new method must also be `const`. The impl header and cpp must use `const override`. This is consistent with all other methods in the interface.

### Method name string `"isKeyValid"` — case sensitivity

The existing entries in `METHOD_NAME_MAP` use camelCase matching the Dart method names exactly: `"getTPMStatus"`, `"getBiometryStatus"`, `"generateKey"`, `"encrypt"`, `"decrypt"`, `"deleteKey"`, `"configure"`. The new entry must be `"isKeyValid"` (lowercase `i`, camelCase `K`), matching the Android and iOS/macOS handler names confirmed in Phases 9 and 10.

### `kIsKeyValid` enum position

Adding `kIsKeyValid` before `kNotImplemented` at the end of the enum is safe. The switch in `HandleMethodCall` dispatches by enum label, not by integer value. `kNotImplemented` is the fallback/default, and its position shifting by one integer does not affect runtime behavior.

### No logging to add

The phase explicitly prohibits adding logging. `OutputException` is called only in the error path of the coroutine, consistent with all other coroutines.

### `result->Success(isValid)` — bool encoding

`StandardMethodCodec` on Windows encodes `bool` as a native Flutter `bool` type. No string conversion is needed. This differs from coroutines that return `int` (`GetTPMStatus`, `GetBiometryStatus`) or `std::string` (`EncryptCoroutine`, `DecryptCoroutine`).

---

## New Technical Questions

**One undocumented required change discovered:**

`argument_parser.cpp` must be updated to add `kIsKeyValid` to the `Parse()` switch. This file is not listed in the PRD or phase doc's file list. The implementation agent should treat this as task **11.5a** (prerequisite to the `IsKeyValidCoroutine` handler working correctly).

No other questions. All other architectural decisions are clear from the existing code patterns.
