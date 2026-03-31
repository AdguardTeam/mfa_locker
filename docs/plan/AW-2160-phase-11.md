# Plan: AW-2160 Phase 11 -- Windows `isKeyValid(tag)` Silent Probe

Status: PLAN_APPROVED

## Phase Scope

This phase adds `IsKeyValidAsync(tag)` to the Windows C++/WinRT native plugin layer. The method silently probes whether a Windows Hello credential exists and is usable for a given tag, without triggering any biometric prompt. It uses `KeyCredentialManager::OpenAsync(tag)` which only queries credential metadata -- no signing operation is performed.

Scope is strictly limited to `packages/biometric_cipher/windows/`. No Dart-layer changes, no Android or iOS/macOS changes, no new files. All modifications are additions to existing files.

---

## Components

All affected files are within `packages/biometric_cipher/windows/`:

| # | File | Change |
|---|------|--------|
| 1 | `include/.../repositories/windows_hello_repository.h` | Add `IsKeyValidAsync` pure virtual method |
| 2 | `include/.../repositories/windows_hello_repository_impl.h` | Add `IsKeyValidAsync` override declaration |
| 3 | `windows_hello_repository_impl.cpp` | Implement `IsKeyValidAsync` |
| 4 | `include/.../services/biometric_cipher_service.h` | Add `IsKeyValidAsync` method declaration |
| 5 | `biometric_cipher_service.cpp` | Implement `IsKeyValidAsync` (delegate to repository) |
| 6 | `include/.../enums/method_name.h` | Add `kIsKeyValid` enum value before `kNotImplemented` |
| 7 | `method_name.cpp` | Add `{"isKeyValid", MethodName::kIsKeyValid}` to `METHOD_NAME_MAP` |
| 8 | `argument_parser.cpp` | Add `case MethodName::kIsKeyValid:` to `Parse()` switch (tag-only group) |
| 9 | `biometric_cipher_plugin.h` | Add `IsKeyValidCoroutine` declaration |
| 10 | `biometric_cipher_plugin.cpp` | Add `kIsKeyValid` switch case + `IsKeyValidCoroutine` implementation |
| 11 | `test/mocks/mock_windows_hello_repository.h` | Add `MOCK_METHOD` for `IsKeyValidAsync` |

---

## API Contract

### New method channel method

| Attribute | Value |
|-----------|-------|
| Channel name | `biometric_cipher` (existing, unchanged) |
| Method name | `"isKeyValid"` |
| Arguments | `{"tag": "<string>"}` |
| Return type | `bool` (`true` if credential exists and is usable, `false` otherwise) |
| Error | `PlatformException` via `result->Error(...)` for WinRT `hresult_error` exceptions |

The method name `"isKeyValid"` is identical to the Android (Phase 9) and iOS/macOS (Phase 10) handlers, enabling a single Dart-side `invokeMethod('isKeyValid', {'tag': tag})` call in Phase 12.

### New C++ signatures

**Repository interface** (`WindowsHelloRepository`):
```cpp
virtual winrt::Windows::Foundation::IAsyncOperation<bool> IsKeyValidAsync(const winrt::hstring tag) const = 0;
```

**Repository implementation** (`WindowsHelloRepositoryImpl`):
```cpp
winrt::Windows::Foundation::IAsyncOperation<bool> IsKeyValidAsync(const winrt::hstring tag) const override;
```

**Service** (`BiometricCipherService`):
```cpp
winrt::Windows::Foundation::IAsyncOperation<bool> IsKeyValidAsync(const std::string& tag) const;
```

**Plugin coroutine** (`BiometricCipherPlugin`):
```cpp
winrt::fire_and_forget IsKeyValidCoroutine(
    const std::string& tag,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
```

---

## Data Flows

### Happy path -- credential exists

```
Dart invokeMethod("isKeyValid", {"tag": "biometric"})
  -> HandleMethodCall resolves "isKeyValid" -> MethodName::kIsKeyValid
  -> ArgumentParser::Parse() extracts tag (kTag group)
  -> IsKeyValidCoroutine("biometric", result)
  -> m_SecureService->IsKeyValidAsync("biometric")
     -> StringUtil::ConvertStringToHString("biometric") -> hTag
     -> m_WindowsHelloRepository->IsKeyValidAsync(hTag)
        -> co_await CheckWindowsHelloIsStatusAsync()    [Windows Hello available]
        -> co_await m_HelloWrapper->OpenAsync(hTag)     [returns KeyCredentialStatus::Success]
        -> co_return status == KeyCredentialStatus::Success  [true]
  -> result->Success(true)
  -> Dart receives true
```

### Credential missing

Same flow, but `OpenAsync(hTag)` returns `KeyCredentialStatus::NotFound`. The expression `status == KeyCredentialStatus::Success` evaluates to `false`. `result->Success(false)` is returned. No exception is thrown -- `NotFound` is an expected, non-error condition for this probe.

### WinRT exception (hardware fault, access denied, Windows Hello unavailable)

`CheckWindowsHelloIsStatusAsync()` or `OpenAsync()` throws `hresult_error`. The `IsKeyValidCoroutine` catch block calls `OutputException(hr, errorMessage)` then `result->Error(GetErrorCodeString(hr), errorMessage)`. Dart receives a `PlatformException`.

### Key difference from `SignAsync`

`SignAsync` calls `CheckKeyCredentialStatus()` after `OpenAsync`, which throws `hresult_error` for `NotFound`. `IsKeyValidAsync` must NOT call `CheckKeyCredentialStatus()` -- it evaluates `status == KeyCredentialStatus::Success` directly. `NotFound` means `false`, not an exception.

---

## Task List

Tasks must be completed in strict order (each depends on the previous).

### Task 11.1 -- Add `IsKeyValidAsync` to `WindowsHelloRepository` interface

**File:** `packages/biometric_cipher/windows/include/biometric_cipher/repositories/windows_hello_repository.h`

Add after `DeleteCredentialAsync` (line 21), before the closing `};` (line 22):

```cpp
virtual winrt::Windows::Foundation::IAsyncOperation<bool> IsKeyValidAsync(const winrt::hstring tag) const = 0;
```

All existing methods are `const` pure virtual -- the new method follows the same pattern.

### Task 11.2 -- Implement `IsKeyValidAsync` in `WindowsHelloRepositoryImpl`

**File (declaration):** `packages/biometric_cipher/windows/include/biometric_cipher/repositories/windows_hello_repository_impl.h`

Add in the `public:` section after `DeleteCredentialAsync` (line 29), before `private:` (line 30):

```cpp
winrt::Windows::Foundation::IAsyncOperation<bool> IsKeyValidAsync(const winrt::hstring tag) const override;
```

**File (implementation):** `packages/biometric_cipher/windows/windows_hello_repository_impl.cpp`

Add after `DeleteCredentialAsync` (ends at line 127) and before `CheckWindowsHelloIsStatusAsync` (line 129):

```cpp
IAsyncOperation<bool> WindowsHelloRepositoryImpl::IsKeyValidAsync(const winrt::hstring tag) const
{
    co_await CheckWindowsHelloIsStatusAsync();

    auto&& keyCredentialRetrievalResult = co_await m_HelloWrapper->OpenAsync(tag);
    auto status = keyCredentialRetrievalResult.Status();

    co_return status == KeyCredentialStatus::Success;
}
```

Key design decision: does NOT call `CheckKeyCredentialStatus()`. `NotFound` returns `false` rather than throwing.

### Task 11.3 -- Add `IsKeyValidAsync` to `BiometricCipherService`

**File (declaration):** `packages/biometric_cipher/windows/include/biometric_cipher/services/biometric_cipher_service.h`

Add in the `public:` section after `DecryptAsync` (line 40), before `private:` (line 42):

```cpp
winrt::Windows::Foundation::IAsyncOperation<bool> IsKeyValidAsync(const std::string& tag) const;
```

**File (implementation):** `packages/biometric_cipher/windows/biometric_cipher_service.cpp`

Add after `CreateAESKeyAsync` (ends at line 127), before closing namespace brace (line 128):

```cpp
IAsyncOperation<bool> BiometricCipherService::IsKeyValidAsync(const std::string& tag) const
{
    auto hTag = StringUtil::ConvertStringToHString(tag);
    co_return co_await m_WindowsHelloRepository->IsKeyValidAsync(hTag);
}
```

Follows the same tag-to-hstring delegation pattern as `GenerateKeyAsync` and `DeleteKeyAsync`.

### Task 11.4 -- Add `kIsKeyValid` to `MethodName` enum and mapping

**File (enum):** `packages/biometric_cipher/windows/include/biometric_cipher/enums/method_name.h`

Add `kIsKeyValid` between `kConfigure,` (line 14) and `kNotImplemented,` (line 15):

```cpp
kIsKeyValid,
```

**File (mapping):** `packages/biometric_cipher/windows/method_name.cpp`

Add to `METHOD_NAME_MAP` between `"configure"` (line 16) and `"notImplemented"` (line 17):

```cpp
{"isKeyValid", MethodName::kIsKeyValid},
```

The string `"isKeyValid"` must be exact camelCase, matching Android (Phase 9) and iOS/macOS (Phase 10).

### Task 11.5 -- Add `kIsKeyValid` case to plugin `HandleMethodCall`

**File:** `packages/biometric_cipher/windows/biometric_cipher_plugin.cpp`

Add new case after `kConfigure` (ends at line 144) and before `kNotImplemented` (line 146):

```cpp
case MethodName::kIsKeyValid:
{
    auto arguments = m_Argument_parser.Parse(method, methodCall.arguments());
    const std::string tag = arguments[ArgumentName::kTag].stringArgument;

    IsKeyValidCoroutine(tag, std::move(result));
    break;
}
```

Follows the same tag-only pattern as `kGenerateKey` and `kDeleteKey`.

### Task 11.6 -- Add `kIsKeyValid` case to `ArgumentParser::Parse()`

**File:** `packages/biometric_cipher/windows/argument_parser.cpp`

Add `case MethodName::kIsKeyValid:` to the existing tag-only group (lines 40-43). Change:

```cpp
case MethodName::kGenerateKey:
case MethodName::kDeleteKey:
```

to:

```cpp
case MethodName::kIsKeyValid:
case MethodName::kGenerateKey:
case MethodName::kDeleteKey:
```

**This is a critical undocumented requirement discovered during research.** Without this change, calling `isKeyValid` from Dart will cause `Parse()` to fall through to the `default` branch, which throws `hresult_error(error_invalid_argument, L"Not implemented method name")`. The `IsKeyValidCoroutine` would never execute.

This task is a prerequisite for Task 11.5 to work correctly at runtime -- `Parse()` is called within the `kIsKeyValid` switch case, before the coroutine is launched.

### Task 11.7 -- Implement `IsKeyValidCoroutine` in plugin

**File (declaration):** `packages/biometric_cipher/windows/biometric_cipher_plugin.h`

Add in the `private:` section after `DecryptCoroutine` (ends at line 61) and before `OutputException` (line 63):

```cpp
winrt::fire_and_forget IsKeyValidCoroutine(
    const std::string& tag,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
```

**File (implementation):** `packages/biometric_cipher/windows/biometric_cipher_plugin.cpp`

Add after `DecryptCoroutine` (ends at line 265) and before `OutputException` (line 267):

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

Follows the exact `fire_and_forget` + `hresult_error` catch pattern used by all existing coroutines. `result->Success(isValid)` passes a `bool` directly -- `StandardMethodCodec` encodes `bool` natively.

### Task 11.8 -- Update `MockWindowsHelloRepository`

**File:** `packages/biometric_cipher/windows/test/mocks/mock_windows_hello_repository.h`

Add after the `DeleteCredentialAsync` mock (after line 46):

```cpp
MOCK_METHOD(
    (IAsyncOperation<bool>),
    IsKeyValidAsync,
    (const hstring tag),
    (const, override)
);
```

Required because `WindowsHelloRepository` is an abstract interface. Adding a pure virtual method without updating the mock will cause a compilation error in any test that instantiates `MockWindowsHelloRepository`.

---

## NFR

| Requirement | How addressed |
|-------------|---------------|
| No biometric prompt | `OpenAsync(tag)` queries credential metadata only -- no signing operation, no UI |
| No logging | No logging statements added; `OutputException` is called only in the error path (consistent with all coroutines) |
| No new files | All changes are additions to 11 existing files |
| Method name consistency | `"isKeyValid"` string matches Android (Phase 9) and iOS/macOS (Phase 10) exactly |
| Build verification | `fvm flutter build windows --debug` must compile with no errors |
| `const` correctness | All new methods are `const`, consistent with existing interface contract |
| Backward compatibility | Existing method channel methods are unaffected; enum dispatch is by label, not integer |

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| `argument_parser.cpp` update omitted | Medium (not in original PRD task list) | High -- runtime crash when `isKeyValid` is called from Dart | Explicitly included as Task 11.6 in this plan |
| Method name `"isKeyValid"` typo vs. Android/iOS handler | Low | High -- Phase 12 Dart channel call would miss the Windows handler | Cross-check string literal against Phase 9 and Phase 10 before merging |
| `MockWindowsHelloRepository` update forgotten | Medium (easy to overlook) | High -- CI build failure; test suite will not compile | Explicitly included as Task 11.8 |
| `KeyCredentialStatus` values other than `Success`/`NotFound` treated as `false` | Low | Low -- returning `false` is the conservative correct behavior for any non-`Success` status | Document in code comment; no mitigation needed |
| `CheckWindowsHelloIsStatusAsync()` throws when Windows Hello is unavailable | Low | Medium -- surfaces as `PlatformException` rather than clean `false` | The `hresult_error` catch in `IsKeyValidCoroutine` handles this correctly |
| `kIsKeyValid` enum position shifts `kNotImplemented` integer value | Very low | None -- switch dispatches by enum label; no serialization of enum integers | Confirmed safe by code review |

---

## Dependencies

### On previous phases

- **Phase 9 (complete):** Android native `isKeyValid` -- establishes the shared method name `"isKeyValid"`.
- **Phase 10 (complete):** iOS/macOS native `isKeyValid` -- confirms method name consistency across all platforms.

### On existing infrastructure (already present)

- `ArgumentName::kTag` -- already exists, used by `encrypt`, `decrypt`, `deleteKey`, `generateKey`.
- `CheckWindowsHelloIsStatusAsync()` -- private method in `WindowsHelloRepositoryImpl`, reused as-is.
- `m_HelloWrapper->OpenAsync(tag)` -- already used in `SignAsync`; reused for metadata-only query.
- `fire_and_forget` + `hresult_error` coroutine pattern -- all 6 existing coroutines use this.
- `StringUtil::ConvertStringToHString(tag)` -- standard string conversion used by all service methods.

### Downstream consumers

- **Phase 12:** Dart-side method channel call (`invokeMethod('isKeyValid', {'tag': tag})`) -- depends on this phase completing so all three platforms handle the method.
- **Phase 13:** Integration into `determineBiometricState()` -- uses the Dart-side `isKeyValid` from Phase 12.

---

## Open Questions

None. All architectural decisions are established by existing code patterns and confirmed by Phases 9 and 10. The critical undocumented requirement (`argument_parser.cpp` update) has been identified and is included as Task 11.6.
