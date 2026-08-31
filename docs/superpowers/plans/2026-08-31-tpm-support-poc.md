# TPM Support POC Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add TPM version exposure and TPM key enumeration to the `biometric_cipher` Windows plugin, plus universal `encryptString`/`decryptString` Dart APIs, demonstrable from the plugin's example app.

**Architecture:** Extend the existing three-layer plugin structure (C++ repository → service → method channel → Dart API) with two new read-only TPM operations (`getTPMVersion`, `listKeys`) implemented natively via NCrypt, and two universal Dart orchestration functions (`encryptString`, `decryptString`) that chain existing primitives (`getTPMStatus` → `isKeyValid` → `generateKey` → `encrypt`/`decrypt`). The example app gets UI buttons to exercise everything.

**Tech Stack:** C++20 / WinRT / NCrypt (Platform Crypto Provider), Flutter method channel, Dart. Spec: `docs/superpowers/specs/2026-08-31-tpm-support-poc-design.md`

## Global Constraints

- POC scope: must work on Windows when exercised from `packages/biometric_cipher/example`; other platforms are out of scope (new methods may throw missing-plugin errors there)
- Do NOT modify the root `locker` library or the `example/` demo app (`mfa_demo`)
- All commands run with `fvm` (falls back to system `flutter` if `fvm` is unavailable)
- C++: C++20, `/W4 /WX` (warnings are errors), mimic the tab indentation and PascalCase method naming of surrounding files
- Dart: line length 120, single quotes, trailing commas on multi-line constructs, `///` doc comments on all public APIs, no `!` null assertions — null-check instead
- Analysis gate: `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` from `packages/biometric_cipher` must produce zero findings after every task
- Commit messages: plain imperative, no prefix (matches repo style, e.g. "Enable debug logging for biometric cipher plugin")
- One deviation from the spec: the service method for key listing is named `ListKeys()` (synchronous, returns `std::vector<TpmKeyInfo>`) instead of `ListKeysAsync()` because WinRT `IAsyncOperation<T>` cannot carry arbitrary C++ structs. `GetTPMVersionAsync()` stays async (`IAsyncOperation<int>`, matching `GetTPMStatusAsync`)

---

### Task 1: Native — TPM key enumeration in the repository layer

**Files:**
- Modify: `packages/biometric_cipher/windows/include/biometric_cipher/wrappers/ncrypt_wrapper.h`
- Modify: `packages/biometric_cipher/windows/include/biometric_cipher/wrappers/ncrypt_wrapper_impl.h`
- Modify: `packages/biometric_cipher/windows/include/biometric_cipher/repositories/windows_tpm_repository.h`
- Modify: `packages/biometric_cipher/windows/include/biometric_cipher/repositories/windows_tpm_repository_impl.h`
- Modify: `packages/biometric_cipher/windows/windows_tpm_repository_impl.cpp`
- Modify: `packages/biometric_cipher/windows/test/mocks/mock_ncrypt_wrapper.h`
- Test: `packages/biometric_cipher/windows/test/windows_tpm_repository_test.cpp`

**Interfaces:**
- Consumes: existing `NCryptWrapper::OpenStorageProvider`, `NCryptHandleFree`, `CheckStatus`, `StringUtil::ConvertWideStringToString`
- Produces (needed by Tasks 2 and 3):
  - Wrapper methods: `SECURITY_STATUS EnumKeys(NCryptHandleFree const& providerHandle, NCryptKeyName** ppKeyName, PVOID* ppEnumState, DWORD dwFlags) const` and `SECURITY_STATUS FreeBuffer(PVOID pvInput) const`
  - `struct TpmKeyInfo { std::string name; std::string algorithm; }` in namespace `biometric_cipher`
  - `virtual std::vector<TpmKeyInfo> ListTpmKeys() const` on `WindowsTpmRepository`

- [ ] **Step 1: Write the failing tests**

Add to the end of `namespace biometric_cipher { namespace test {` in `packages/biometric_cipher/windows/test/windows_tpm_repository_test.cpp` (after the `GetWindowsTpmVersion_OpenStorageProviderThrows` test, before the closing braces):

```cpp
		TEST_F(WindowsTpmRepositoryTest, ListTpmKeys_ReturnsAllTpmKeys)
		{
			EXPECT_CALL(*m_mockNCryptWrapper, OpenStorageProvider)
				.Times(1)
				.WillOnce([](NCryptHandleFree& providerHandle, LPCWSTR pszProviderName, DWORD dwFlags) -> SECURITY_STATUS
					{
						EXPECT_STREQ(pszProviderName, MS_PLATFORM_CRYPTO_PROVIDER);
						EXPECT_EQ(dwFlags, 0);

						return ERROR_SUCCESS;
					}
				);

			NCryptKeyName firstKey = {};
			firstKey.pszName = const_cast<LPWSTR>(L"tpm_key_one");
			firstKey.pszAlgid = const_cast<LPWSTR>(L"RSA");

			NCryptKeyName secondKey = {};
			secondKey.pszName = const_cast<LPWSTR>(L"tpm_key_two");
			secondKey.pszAlgid = const_cast<LPWSTR>(L"ECC");

			EXPECT_CALL(*m_mockNCryptWrapper, EnumKeys)
				.Times(3)
				.WillOnce([&firstKey](NCryptHandleFree const&, NCryptKeyName** ppKeyName, PVOID* ppEnumState, DWORD) -> SECURITY_STATUS
					{
						*ppKeyName = &firstKey;
						*ppEnumState = reinterpret_cast<PVOID>(1);

						return ERROR_SUCCESS;
					}
				)
				.WillOnce([&secondKey](NCryptHandleFree const&, NCryptKeyName** ppKeyName, PVOID* ppEnumState, DWORD) -> SECURITY_STATUS
					{
						*ppKeyName = &secondKey;
						*ppEnumState = reinterpret_cast<PVOID>(1);

						return ERROR_SUCCESS;
					}
				)
				.WillOnce([](NCryptHandleFree const&, NCryptKeyName**, PVOID* ppEnumState, DWORD) -> SECURITY_STATUS
					{
						*ppEnumState = reinterpret_cast<PVOID>(1);

						return NTE_NO_MORE_ITEMS;
					}
				);

			EXPECT_CALL(*m_mockNCryptWrapper, FreeBuffer)
				.Times(3)
				.WillRepeatedly([](PVOID pvInput) -> SECURITY_STATUS
					{
						EXPECT_NE(pvInput, nullptr);

						return ERROR_SUCCESS;
					}
				);

			// Act
			auto keys = m_Repository->ListTpmKeys();

			// Assert
			ASSERT_EQ(keys.size(), static_cast<size_t>(2));
			EXPECT_EQ(keys[0].name, "tpm_key_one");
			EXPECT_EQ(keys[0].algorithm, "RSA");
			EXPECT_EQ(keys[1].name, "tpm_key_two");
			EXPECT_EQ(keys[1].algorithm, "ECC");
		}

		TEST_F(WindowsTpmRepositoryTest, ListTpmKeys_ThrowsIfEnumKeysFails)
		{
			EXPECT_CALL(*m_mockNCryptWrapper, OpenStorageProvider)
				.Times(1)
				.WillOnce([](NCryptHandleFree& providerHandle, LPCWSTR pszProviderName, DWORD dwFlags) -> SECURITY_STATUS
					{
						return ERROR_SUCCESS;
					}
				);

			EXPECT_CALL(*m_mockNCryptWrapper, EnumKeys)
				.Times(1)
				.WillOnce([](NCryptHandleFree const&, NCryptKeyName** ppKeyName, PVOID* ppEnumState, DWORD) -> SECURITY_STATUS
					{
						*ppKeyName = nullptr;
						*ppEnumState = nullptr;

						return NTE_BAD_KEY;
					}
				);

			// Act & Assert
			EXPECT_THROW(
				m_Repository->ListTpmKeys(),
				winrt::hresult_error
			);
		}
```

- [ ] **Step 2: Run the tests to verify they fail to compile**

```bash
cd packages/biometric_cipher/example
fvm flutter build windows --debug
cmake --build build/windows --config Debug --target biometric_cipher_test
./build/windows/plugins/biometric_cipher/Debug/biometric_cipher_test.exe --gtest_filter=WindowsTpmRepositoryTest.ListTpmKeys_*
```

Expected: the `cmake --build` step FAILS with compile errors — `ListTpmKeys` is not a member of `WindowsTpmRepositoryImpl`, and `EnumKeys`/`FreeBuffer` are not members of `MockNCryptWrapper`. (If `fvm` is unavailable, use `flutter` instead. If the exe path differs, locate `biometric_cipher_test.exe` under `build/windows/plugins/biometric_cipher/`.)

- [ ] **Step 3: Add `TpmKeyInfo` and `ListTpmKeys` to the repository interface**

In `packages/biometric_cipher/windows/include/biometric_cipher/repositories/windows_tpm_repository.h`, replace the whole file content with:

```cpp
#pragma once

#include <string>
#include <vector>

namespace biometric_cipher
{
	struct TpmKeyInfo
	{
		std::string name;
		std::string algorithm;
	};

	struct WindowsTpmRepository
	{
		virtual ~WindowsTpmRepository() = default;

		virtual int GetWindowsTpmVersion() const = 0;

		virtual std::vector<TpmKeyInfo> ListTpmKeys() const = 0;
	};
}  // namespace biometric_cipher
```

- [ ] **Step 4: Add `EnumKeys` and `FreeBuffer` to the NCrypt wrapper interface**

In `packages/biometric_cipher/windows/include/biometric_cipher/wrappers/ncrypt_wrapper.h`, add before the closing `};` of `struct NCryptWrapper`:

```cpp
		virtual SECURITY_STATUS EnumKeys(
			NCryptHandleFree const& providerHandle,
			NCryptKeyName** ppKeyName,
			PVOID* ppEnumState,
			DWORD dwFlags
		) const = 0;

		virtual SECURITY_STATUS FreeBuffer(
			PVOID pvInput
		) const = 0;
```

In `packages/biometric_cipher/windows/include/biometric_cipher/wrappers/ncrypt_wrapper_impl.h`, add before the closing `};` of `class NCryptWrapperImpl`:

```cpp
		SECURITY_STATUS EnumKeys(
			NCryptHandleFree const& providerHandle,
			NCryptKeyName** ppKeyName,
			PVOID* ppEnumState,
			DWORD dwFlags
		) const override
		{
			return NCryptEnumKeys(providerHandle.get(), nullptr, ppKeyName, ppEnumState, dwFlags);
		}

		SECURITY_STATUS FreeBuffer(
			PVOID pvInput
		) const override
		{
			return NCryptFreeBuffer(pvInput);
		}
```

- [ ] **Step 5: Extend the mock NCrypt wrapper**

In `packages/biometric_cipher/windows/test/mocks/mock_ncrypt_wrapper.h`, add before the closing `};` of `MockNCryptWrapper`:

```cpp
			MOCK_METHOD(
				(SECURITY_STATUS),
				EnumKeys,
				(NCryptHandleFree const& providerHandle, NCryptKeyName** ppKeyName, PVOID* ppEnumState, DWORD dwFlags),
				(const, override)
			);

			MOCK_METHOD(
				(SECURITY_STATUS),
				FreeBuffer,
				(PVOID pvInput),
				(const, override)
			);
```

- [ ] **Step 6: Implement `ListTpmKeys`**

In `packages/biometric_cipher/windows/include/biometric_cipher/repositories/windows_tpm_repository_impl.h`, add after `int GetWindowsTpmVersion() const override;`:

```cpp
		std::vector<TpmKeyInfo> ListTpmKeys() const override;
```

In `packages/biometric_cipher/windows/windows_tpm_repository_impl.cpp`, add after the `GetWindowsTpmVersion` method body (inside `namespace biometric_cipher`):

```cpp
	std::vector<TpmKeyInfo> WindowsTpmRepositoryImpl::ListTpmKeys() const
	{
		SECURITY_STATUS status = ERROR_SUCCESS;

		NCryptHandleFree providerHandle;

		status = m_NCryptWrapper->OpenStorageProvider(providerHandle, MS_PLATFORM_CRYPTO_PROVIDER, 0);
		CheckStatus(error_tpm_unsupported, L"NCryptOpenStorageProvider failed", status);

		std::vector<TpmKeyInfo> keys;
		NCryptKeyName* keyName = nullptr;
		PVOID enumState = nullptr;

		while (true)
		{
			status = m_NCryptWrapper->EnumKeys(providerHandle, &keyName, &enumState, 0);
			if (status == NTE_NO_MORE_ITEMS)
			{
				break;
			}
			CheckStatus(error_tpm_unsupported, L"NCryptEnumKeys failed", status);

			if (keyName != nullptr)
			{
				keys.push_back(TpmKeyInfo{
					StringUtil::ConvertWideStringToString(keyName->pszName),
					StringUtil::ConvertWideStringToString(keyName->pszAlgid)
				});
				m_NCryptWrapper->FreeBuffer(keyName);
				keyName = nullptr;
			}
		}

		if (enumState != nullptr)
		{
			m_NCryptWrapper->FreeBuffer(enumState);
		}

		return keys;
	}
```

- [ ] **Step 7: Run the tests to verify they pass**

```bash
cd packages/biometric_cipher/example
cmake --build build/windows --config Debug --target biometric_cipher_test
./build/windows/plugins/biometric_cipher/Debug/biometric_cipher_test.exe --gtest_filter=WindowsTpmRepositoryTest.*
```

Expected: all `WindowsTpmRepositoryTest` tests PASS, including the two new `ListTpmKeys_*` tests and the three pre-existing `GetWindowsTpmVersion*` / `GetTPMStatusAsync_*` tests.

- [ ] **Step 8: Commit**

```bash
cd packages/biometric_cipher
git add windows/include/biometric_cipher/wrappers/ncrypt_wrapper.h windows/include/biometric_cipher/wrappers/ncrypt_wrapper_impl.h windows/include/biometric_cipher/repositories/windows_tpm_repository.h windows/include/biometric_cipher/repositories/windows_tpm_repository_impl.h windows/windows_tpm_repository_impl.cpp windows/test/mocks/mock_ncrypt_wrapper.h windows/test/windows_tpm_repository_test.cpp
git commit -m "Add TPM key enumeration to Windows TPM repository"
```

---

### Task 2: Native — service methods `GetTPMVersionAsync` and `ListKeys`

**Files:**
- Modify: `packages/biometric_cipher/windows/include/biometric_cipher/services/biometric_cipher_service.h`
- Modify: `packages/biometric_cipher/windows/biometric_cipher_service.cpp`
- Modify: `packages/biometric_cipher/windows/test/mocks/mock_windows_tpm_repository.h`
- Test: `packages/biometric_cipher/windows/test/biometric_cipher_service_test.cpp`

**Interfaces:**
- Consumes: `WindowsTpmRepository::GetWindowsTpmVersion()` (`int`), `WindowsTpmRepository::ListTpmKeys()` (`std::vector<TpmKeyInfo>`) from Task 1, `TpmKeyInfo { std::string name; std::string algorithm; }`
- Produces (needed by Task 3): `winrt::Windows::Foundation::IAsyncOperation<int> GetTPMVersionAsync() const` and `std::vector<TpmKeyInfo> ListKeys() const` on `BiometricCipherService`

- [ ] **Step 1: Write the failing tests**

Add to the end of `namespace biometric_cipher { namespace test {` in `packages/biometric_cipher/windows/test/biometric_cipher_service_test.cpp` (after the last `TEST_F`, before the closing braces):

```cpp
		TEST_F(BiometricCipherServiceTest, GetTPMVersionAsync_ReturnsTpmVersionFromRepository)
		{
			EXPECT_CALL(*m_WindowsTpmRepository, GetWindowsTpmVersion())
				.Times(1)
				.WillOnce([]() -> int
					{
						return 2;
					}
				);

			// Act
			auto asyncOp = m_Service->GetTPMVersionAsync();
			int result = asyncOp.get();

			// Assert
			EXPECT_EQ(result, 2);
		}

		TEST_F(BiometricCipherServiceTest, GetTPMVersionAsync_PropagatesRepositoryError)
		{
			EXPECT_CALL(*m_WindowsTpmRepository, GetWindowsTpmVersion())
				.Times(1)
				.WillOnce(testing::Throw(hresult_error(error_tpm_unsupported, L"Test exception")));

			// Act
			auto asyncOp = m_Service->GetTPMVersionAsync();

			// Assert
			EXPECT_THROW(asyncOp.get(), hresult_error);
		}

		TEST_F(BiometricCipherServiceTest, ListKeys_ReturnsRepositoryKeys)
		{
			std::vector<TpmKeyInfo> expectedKeys = {
				{"key_one", "RSA"},
				{"key_two", "ECC"}
			};

			EXPECT_CALL(*m_WindowsTpmRepository, ListTpmKeys())
				.Times(1)
				.WillOnce([expectedKeys]() -> std::vector<TpmKeyInfo>
					{
						return expectedKeys;
					}
				);

			// Act
			auto keys = m_Service->ListKeys();

			// Assert
			ASSERT_EQ(keys.size(), static_cast<size_t>(2));
			EXPECT_EQ(keys[0].name, "key_one");
			EXPECT_EQ(keys[0].algorithm, "RSA");
			EXPECT_EQ(keys[1].name, "key_two");
			EXPECT_EQ(keys[1].algorithm, "ECC");
		}
```

Note: `biometric_cipher_service_test.cpp` already includes `windows_tpm_repository.h` transitively via `mock_windows_tpm_repository.h`, so `TpmKeyInfo` is visible.

- [ ] **Step 2: Run the tests to verify they fail to compile**

```bash
cd packages/biometric_cipher/example
cmake --build build/windows --config Debug --target biometric_cipher_test
```

Expected: compile error — `GetTPMVersionAsync` and `ListKeys` are not members of `BiometricCipherService`, and `ListTpmKeys` is not a member of `MockWindowsTpmRepository`.

- [ ] **Step 3: Extend the mock Windows TPM repository**

In `packages/biometric_cipher/windows/test/mocks/mock_windows_tpm_repository.h`, replace the mock class body so it reads:

```cpp
		class MockWindowsTpmRepository : public WindowsTpmRepository {
		public:
			MOCK_METHOD(int, GetWindowsTpmVersion, (), (const, override));
			MOCK_METHOD((std::vector<TpmKeyInfo>), ListTpmKeys, (), (const, override));
		};
```

- [ ] **Step 4: Implement the service methods**

In `packages/biometric_cipher/windows/include/biometric_cipher/services/biometric_cipher_service.h`:

Add `#include <vector>` to the include block at the top (after `#include <string>`).

Add after the existing `GetTPMStatusAsync` declaration:

```cpp
		winrt::Windows::Foundation::IAsyncOperation<int> GetTPMVersionAsync() const;

		std::vector<TpmKeyInfo> ListKeys() const;
```

In `packages/biometric_cipher/windows/biometric_cipher_service.cpp`, add after the `GetTPMStatusAsync` method body:

```cpp
	IAsyncOperation<int> BiometricCipherService::GetTPMVersionAsync() const
	{
		co_return m_WindowsTpmRepository->GetWindowsTpmVersion();
	}

	std::vector<TpmKeyInfo> BiometricCipherService::ListKeys() const
	{
		return m_WindowsTpmRepository->ListTpmKeys();
	}
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
cd packages/biometric_cipher/example
cmake --build build/windows --config Debug --target biometric_cipher_test
./build/windows/plugins/biometric_cipher/Debug/biometric_cipher_test.exe --gtest_filter=BiometricCipherServiceTest.*
```

Expected: all `BiometricCipherServiceTest` tests PASS, including the three new tests and all pre-existing ones (the mock class change keeps existing `GetWindowsTpmVersion` expectations compatible).

- [ ] **Step 6: Commit**

```bash
cd packages/biometric_cipher
git add windows/include/biometric_cipher/services/biometric_cipher_service.h windows/biometric_cipher_service.cpp windows/test/mocks/mock_windows_tpm_repository.h windows/test/biometric_cipher_service_test.cpp
git commit -m "Add TPM version and key listing service methods"
```

---

### Task 3: Native — method channel dispatch for `getTPMVersion` and `listKeys`

**Files:**
- Modify: `packages/biometric_cipher/windows/include/biometric_cipher/enums/method_name.h`
- Modify: `packages/biometric_cipher/windows/method_name.cpp`
- Modify: `packages/biometric_cipher/windows/biometric_cipher_plugin.h`
- Modify: `packages/biometric_cipher/windows/biometric_cipher_plugin.cpp`

**Interfaces:**
- Consumes: `BiometricCipherService::GetTPMVersionAsync()` (`IAsyncOperation<int>`) and `BiometricCipherService::ListKeys()` (`std::vector<TpmKeyInfo>`) from Task 2
- Produces (needed by Task 4): method channel methods — `getTPMVersion` (no args, returns `int`) and `listKeys` (no args, returns a `List` of `{ "name": String, "algorithm": String }` maps); errors surface as `PlatformException` with codes `TPM_UNSUPPORTED` / `TPM_VERSION_ERROR` / `UNKNOWN_ERROR`

No unit test target exists for `BiometricCipherPlugin::HandleMethodCall` (consistent with all existing methods); the deliverable is a clean compile of the plugin through the full example build, which `/W4 /WX` gate Entry.

- [ ] **Step 1: Register the new method names**

In `packages/biometric_cipher/windows/include/biometric_cipher/enums/method_name.h`, replace the enum body:

```cpp
	enum class MethodName {
		kGetTPMStatus,
		kGetTPMVersion,
		kListKeys,
		kGetBiometryStatus,
		kGenerateKey,
		kEncrypt,
		kDecrypt,
		kDeleteKey,
		kConfigure,
		kIsKeyValid,
		kNotImplemented,
	};
```

In `packages/biometric_cipher/windows/method_name.cpp`, add to `METHOD_NAME_MAP` (keep the list order matching the enum):

```cpp
		{"getTPMStatus", MethodName::kGetTPMStatus},
		{"getTPMVersion", MethodName::kGetTPMVersion},
		{"listKeys", MethodName::kListKeys},
```

- [ ] **Step 2: Declare the plugin handlers**

In `packages/biometric_cipher/windows/biometric_cipher_plugin.h`, add after the `GetTPMStatus` declaration:

```cpp
	winrt::fire_and_forget GetTPMVersion(
		std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

	void ListKeys(
		std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
```

- [ ] **Step 3: Add the dispatch cases**

In `packages/biometric_cipher/windows/biometric_cipher_plugin.cpp`, add after the `case MethodName::kGetTPMStatus:` block in `HandleMethodCall`:

```cpp
	case MethodName::kGetTPMVersion:
	{
		GetTPMVersion(std::move(result));
		break;
	}

	case MethodName::kListKeys:
	{
		ListKeys(std::move(result));
		break;
	}
```

- [ ] **Step 4: Implement the handlers**

In `packages/biometric_cipher/windows/biometric_cipher_plugin.cpp`, add after the `GetTPMStatus` method body:

```cpp
winrt::fire_and_forget BiometricCipherPlugin::GetTPMVersion(
	std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
{
	try {
		auto tpmVersion = co_await m_SecureService->GetTPMVersionAsync();

		result->Success(tpmVersion);
	}
	catch (const hresult_error& e) {
		auto hr = e.code();
		auto message = e.message();
		auto errorMessage = StringUtil::ConvertHStringToString(message);
		result->Error(GetErrorCodeString(hr), errorMessage);
	}
}

void BiometricCipherPlugin::ListKeys(
	std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
{
	try {
		auto keys = m_SecureService->ListKeys();

		flutter::EncodableList encodedKeys;
		for (const auto& key : keys)
		{
			encodedKeys.emplace_back(flutter::EncodableValue(flutter::EncodableMap{
				{"name", flutter::EncodableValue(key.name)},
				{"algorithm", flutter::EncodableValue(key.algorithm)},
			}));
		}

		result->Success(flutter::EncodableValue(encodedKeys));
	}
	catch (const hresult_error& e) {
		auto hr = e.code();
		auto message = e.message();
		auto errorMessage = StringUtil::ConvertHStringToString(message);
		result->Error(GetErrorCodeString(hr), errorMessage);
	}
}
```

- [ ] **Step 5: Verify the full plugin builds warning-free**

```bash
cd packages/biometric_cipher/example
fvm flutter build windows --debug
cmake --build build/windows --config Debug --target biometric_cipher_test
./build/windows/plugins/biometric_cipher/Debug/biometric_cipher_test.exe
```

Expected: the app build succeeds with no compiler warnings (`/W4 /WX` treats warnings as errors, so a clean build is the gate), and the full test suite still passes.

- [ ] **Step 6: Commit**

```bash
cd packages/biometric_cipher
git add windows/include/biometric_cipher/enums/method_name.h windows/method_name.cpp windows/biometric_cipher_plugin.h windows/biometric_cipher_plugin.cpp
git commit -m "Add getTPMVersion and listKeys method channel handlers"
```

---

### Task 4: Dart — `TpmKeyInfo` model, platform API, and universal `encryptString`/`decryptString`

**Files:**
- Create: `packages/biometric_cipher/lib/data/tpm_key_info.dart`
- Modify: `packages/biometric_cipher/lib/biometric_cipher_platform_interface.dart`
- Modify: `packages/biometric_cipher/lib/biometric_cipher_method_channel.dart`
- Modify: `packages/biometric_cipher/lib/biometric_cipher.dart`
- Modify: `packages/biometric_cipher/test/mock_biometric_cipher_platform.dart`
- Test: `packages/biometric_cipher/test/biometric_cipher_test.dart`

**Interfaces:**
- Consumes: method channel methods `getTPMVersion` → `int` and `listKeys` → `List<Map>` from Task 3; existing `getTPMStatus`, `isKeyValid`, `generateKey`, `encrypt`, `decrypt`
- Produces (needed by Task 5 and tests): `TpmKeyInfo` class (`{ String name; String algorithm; }`), `BiometricCipher.getTpmVersion()` → `Future<int>`, `BiometricCipher.listKeys()` → `Future<List<TpmKeyInfo>>`, `BiometricCipher.encryptString({required String tag, required String data})` → `Future<String>` (Base64), `BiometricCipher.decryptString({required String tag, required String data})` → `Future<String>`

- [ ] **Step 1: Extend the mock platform first (tests need it)**

In `packages/biometric_cipher/test/mock_biometric_cipher_platform.dart`:

Add import:

```dart
import 'package:biometric_cipher/data/tpm_key_info.dart';
```

Add fields and overrides (after the `getTPMStatus` override — and change `getTPMStatus` to be field-backed so `encryptString`/`decryptString` failure paths are testable):

```dart
  /// The TPM status returned by [getTPMStatus].
  ///
  /// Defaults to [TPMStatus.supported]; tests may override it to simulate
  /// unsupported TPM states.
  TPMStatus tpmStatus = TPMStatus.supported;

  /// The TPM version returned by [getTPMVersion].
  int tpmVersion = 2;

  /// The keys returned by [listKeys].
  final List<TpmKeyInfo> tpmKeys = const [
    TpmKeyInfo(name: 'mock_key_one', algorithm: 'RSA'),
    TpmKeyInfo(name: 'mock_key_two', algorithm: 'ECC'),
  ];
```

Replace the existing `getTPMStatus` override (including its now-outdated `/// ... Always returns [TPMStatus.supported] in this mock.` doc comment) with:

```dart
  /// Retrieves the current TPM status from [tpmStatus].
  @override
  Future<TPMStatus> getTPMStatus() async => tpmStatus;

  /// Retrieves the TPM version from [tpmVersion].
  @override
  Future<int> getTPMVersion() async => tpmVersion;

  /// Retrieves the TPM keys from [tpmKeys].
  @override
  Future<List<TpmKeyInfo>> listKeys() async => tpmKeys;
```

- [ ] **Step 2: Write the failing tests**

In `packages/biometric_cipher/test/biometric_cipher_test.dart`:

Add import:

```dart
import 'package:biometric_cipher/data/tpm_key_info.dart';
import 'package:biometric_cipher/data/tpm_status.dart';
```

Add inside `group('BiometricCipher tests', ...)` (after the `isKeyValid` group):

```dart
    group('getTpmVersion', () {
      test('returns version from platform', () async {
        // Act
        final version = await biometricCipher.getTpmVersion();

        // Assert
        expect(version, equals(2));
      });
    });

    group('listKeys', () {
      test('returns keys from platform', () async {
        // Act
        final keys = await biometricCipher.listKeys();

        // Assert
        expect(keys, hasLength(2));
        expect(keys.first.name, equals('mock_key_one'));
        expect(keys.first.algorithm, equals('RSA'));
      });
    });

    group('encryptString', () {
      test('creates missing key and returns encrypted data', () async {
        // Arrange
        const tag = 'universal_tag';
        await biometricCipher.configure(
          config: const ConfigData(
            biometricPromptTitle: 'Title',
            biometricPromptSubtitle: 'Subtitle',
            windowsDataToSign: 'DataToSign',
          ),
        );
        expect(mockPlatform.keys.containsKey(tag), isFalse);

        // Act
        final encrypted = await biometricCipher.encryptString(tag: tag, data: 'secret');

        // Assert
        expect(encrypted, equals('encrypted_secret'));
        expect(mockPlatform.keys.containsKey(tag), isTrue);
      });

      test('uses existing key without regenerating it', () async {
        // Arrange
        const tag = 'existing_tag';
        await biometricCipher.configure(
          config: const ConfigData(
            biometricPromptTitle: 'Title',
            biometricPromptSubtitle: 'Subtitle',
            windowsDataToSign: 'DataToSign',
          ),
        );
        await biometricCipher.generateKey(tag: tag);

        // Act
        // If encryptString tried to regenerate the existing key, the mock
        // would throw keyAlreadyExists here.
        final encrypted = await biometricCipher.encryptString(tag: tag, data: 'secret');

        // Assert
        expect(encrypted, equals('encrypted_secret'));
      });

      test('throws tpmUnsupported when TPM is not supported', () async {
        // Arrange
        mockPlatform.tpmStatus = TPMStatus.unsupported;

        // Act & Assert
        expect(
          () => biometricCipher.encryptString(tag: 'tag', data: 'secret'),
          throwsA(
            predicate(
              (e) => e is BiometricCipherException && e.code == BiometricCipherExceptionCode.tpmUnsupported,
            ),
          ),
        );
      });

      test('throws if tag is empty', () {
        // Act & Assert
        expect(
          () => biometricCipher.encryptString(tag: '', data: 'secret'),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('decryptString', () {
      test('decrypts previously encrypted data', () async {
        // Arrange
        const tag = 'decrypt_universal_tag';
        await biometricCipher.configure(
          config: const ConfigData(
            biometricPromptTitle: 'Title',
            biometricPromptSubtitle: 'Subtitle',
            windowsDataToSign: 'DataToSign',
          ),
        );
        final encrypted = await biometricCipher.encryptString(tag: tag, data: 'secret');

        // Act
        final decrypted = await biometricCipher.decryptString(tag: tag, data: encrypted);

        // Assert
        expect(decrypted, equals('secret'));
      });

      test('throws keyNotFound when key is missing', () async {
        // Arrange
        await biometricCipher.configure(
          config: const ConfigData(
            biometricPromptTitle: 'Title',
            biometricPromptSubtitle: 'Subtitle',
            windowsDataToSign: 'DataToSign',
          ),
        );

        // Act & Assert
        expect(
          () => biometricCipher.decryptString(tag: 'missing_tag', data: 'encrypted_secret'),
          throwsA(
            predicate(
              (e) => e is BiometricCipherException && e.code == BiometricCipherExceptionCode.keyNotFound,
            ),
          ),
        );
      });

      test('throws tpmUnsupported when TPM version is incompatible', () async {
        // Arrange
        mockPlatform.tpmStatus = TPMStatus.tpmVersionUnsupported;

        // Act & Assert
        expect(
          () => biometricCipher.decryptString(tag: 'tag', data: 'encrypted_secret'),
          throwsA(
            predicate(
              (e) => e is BiometricCipherException && e.code == BiometricCipherExceptionCode.tpmUnsupported,
            ),
          ),
        );
      });

      test('throws if data is empty', () {
        // Act & Assert
        expect(
          () => biometricCipher.decryptString(tag: 'tag', data: ''),
          throwsA(isA<Exception>()),
        );
      });
    });
```

- [ ] **Step 3: Run the tests to verify they fail**

```bash
cd packages/biometric_cipher
fvm flutter test
```

Expected: compile error — `getTpmVersion`/`listKeys`/`encryptString`/`decryptString` are not defined on `BiometricCipher`, and `TpmKeyInfo` does not exist.

- [ ] **Step 4: Create the `TpmKeyInfo` model**

Create `packages/biometric_cipher/lib/data/tpm_key_info.dart`:

```dart
import 'package:biometric_cipher/data/biometric_cipher_exception.dart';
import 'package:biometric_cipher/data/biometric_cipher_exception_code.dart';

/// A TPM-resident key entry returned by [BiometricCipher.listKeys].
///
/// Lists all keys stored by the platform crypto provider for the current
/// user. Entries include keys created by other applications and the OS
/// itself; they cannot be mapped back to tags used by this plugin.
class TpmKeyInfo {
  /// Constructs a TPM key info with a [name] and an [algorithm].
  const TpmKeyInfo({required this.name, required this.algorithm});

  /// The TPM key container name.
  final String name;

  /// The algorithm identifier of the key, e.g. `RSA` or `ECC`.
  final String algorithm;

  /// Creates a [TpmKeyInfo] from a method channel [map].
  ///
  /// Throws [BiometricCipherException] with
  /// [BiometricCipherExceptionCode.unknown] if the map is malformed.
  static TpmKeyInfo fromMap(Map<Object?, Object?> map) {
    final name = map['name'];
    final algorithm = map['algorithm'];

    if (name is! String || algorithm is! String) {
      throw const BiometricCipherException(
        code: BiometricCipherExceptionCode.unknown,
        message: 'Invalid TPM key entry',
      );
    }

    return TpmKeyInfo(name: name, algorithm: algorithm);
  }

  @override
  bool operator ==(Object other) =>
      other is TpmKeyInfo && other.name == name && other.algorithm == algorithm;

  @override
  int get hashCode => Object.hash(name, algorithm);

  @override
  String toString() => 'TpmKeyInfo(name: $name, algorithm: $algorithm)';
}
```

- [ ] **Step 5: Extend the platform interface**

In `packages/biometric_cipher/lib/biometric_cipher_platform_interface.dart`:

Add import:

```dart
import 'package:biometric_cipher/data/tpm_key_info.dart';
```

Add after the `getTPMStatus` method:

```dart
  /// Retrieves the Trusted Platform Module (TPM) version of the device.
  ///
  /// Returns the major TPM version as an integer, e.g. `2` for TPM 2.0.
  ///
  /// Throws [BiometricCipherException] with
  /// [BiometricCipherExceptionCode.tpmUnsupported] if the TPM is not present.
  Future<int> getTPMVersion() {
    throw UnimplementedError('getTPMVersion() has not been implemented.');
  }

  /// Retrieves all TPM-resident keys stored by the platform crypto provider
  /// for the current user.
  ///
  /// The list is diagnostic: it includes keys created by other applications
  /// and the OS itself, and entries cannot be mapped to this plugin's tags.
  ///
  /// Throws [BiometricCipherException] with
  /// [BiometricCipherExceptionCode.tpmUnsupported] if the TPM is not present.
  Future<List<TpmKeyInfo>> listKeys() {
    throw UnimplementedError('listKeys() has not been implemented.');
  }
```

- [ ] **Step 6: Extend the method channel implementation**

In `packages/biometric_cipher/lib/biometric_cipher_method_channel.dart`:

Add import:

```dart
import 'package:biometric_cipher/data/tpm_key_info.dart';
```

Add after the `getTPMStatus` override:

```dart
  @override
  Future<int> getTPMVersion() async {
    try {
      final version = await methodChannel.invokeMethod<int>('getTPMVersion');

      if (version == null) {
        throw Exception('Failed to get TPM version');
      }

      return version;
    } on PlatformException catch (e) {
      throw _mapPlatformException(e);
    }
  }

  @override
  Future<List<TpmKeyInfo>> listKeys() async {
    try {
      final keys = await methodChannel.invokeMethod<List<Object?>>('listKeys');

      if (keys == null) {
        throw Exception('Failed to list TPM keys');
      }

      return keys.whereType<Map<Object?, Object?>>().map(TpmKeyInfo.fromMap).toList();
    } on PlatformException catch (e) {
      throw _mapPlatformException(e);
    }
  }
```

- [ ] **Step 7: Add the public API to `BiometricCipher`**

In `packages/biometric_cipher/lib/biometric_cipher.dart`:

Add import:

```dart
import 'package:biometric_cipher/data/tpm_key_info.dart';
```

Add after the `getTPMStatus` getter:

```dart
  /// Returns the major TPM version of the device, e.g. `2` for TPM 2.0.
  Future<int> getTpmVersion() => _instance.getTPMVersion();

  /// Returns all TPM-resident keys stored by the platform crypto provider.
  ///
  /// The list is diagnostic: it includes keys created by other applications
  /// and the OS itself, and entries cannot be mapped to this plugin's tags.
  Future<List<TpmKeyInfo>> listKeys() => _instance.listKeys();
```

Add after the `isKeyValid` method (end of class):

```dart
  /// Encrypts [data] with the key identified by [tag], handling TPM checks
  /// and key creation automatically.
  ///
  /// Checks that the TPM is present and supported, generates the key for
  /// [tag] if it does not exist yet, encrypts [data], and returns it as a
  /// Base64-encoded string.
  ///
  /// The plugin must be configured via [configure] before calling this method.
  ///
  /// Throws [BiometricCipherException] with:
  /// - [BiometricCipherExceptionCode.invalidArgument] if [tag] or [data] is empty.
  /// - [BiometricCipherExceptionCode.tpmUnsupported] if the TPM is not
  ///   present or its version is incompatible.
  /// - [BiometricCipherExceptionCode.encryptionError] if encryption fails.
  Future<String> encryptString({required String tag, required String data}) async {
    if (tag.isEmpty) {
      throw const BiometricCipherException(
        code: BiometricCipherExceptionCode.invalidArgument,
        message: 'Tag cannot be empty',
      );
    }

    if (data.isEmpty) {
      throw const BiometricCipherException(
        code: BiometricCipherExceptionCode.invalidArgument,
        message: 'Data cannot be empty',
      );
    }

    final status = await getTPMStatus();

    if (status != TPMStatus.supported) {
      throw const BiometricCipherException(
        code: BiometricCipherExceptionCode.tpmUnsupported,
        message: 'TPM is unsupported or has an incompatible version',
      );
    }

    if (!await isKeyValid(tag: tag)) {
      await generateKey(tag: tag);
    }

    final encryptedData = await encrypt(tag: tag, data: data);

    if (encryptedData == null) {
      throw const BiometricCipherException(
        code: BiometricCipherExceptionCode.encryptionError,
        message: 'Encryption failed',
      );
    }

    return encryptedData;
  }

  /// Decrypts the Base64-encoded [data] with the key identified by [tag].
  ///
  /// Checks that the TPM is present and supported, then decrypts [data] and
  /// returns the plaintext string. Unlike [encryptString], the key for [tag]
  /// is never created implicitly: decryption fails if the key is missing.
  ///
  /// The plugin must be configured via [configure] before calling this method.
  ///
  /// Throws [BiometricCipherException] with:
  /// - [BiometricCipherExceptionCode.invalidArgument] if [tag] or [data] is empty.
  /// - [BiometricCipherExceptionCode.tpmUnsupported] if the TPM is not
  ///   present or its version is incompatible.
  /// - [BiometricCipherExceptionCode.keyNotFound] if no key exists for [tag].
  /// - [BiometricCipherExceptionCode.decryptionError] if decryption fails.
  Future<String> decryptString({required String tag, required String data}) async {
    if (tag.isEmpty) {
      throw const BiometricCipherException(
        code: BiometricCipherExceptionCode.invalidArgument,
        message: 'Tag cannot be empty',
      );
    }

    if (data.isEmpty) {
      throw const BiometricCipherException(
        code: BiometricCipherExceptionCode.invalidArgument,
        message: 'Data cannot be empty',
      );
    }

    final status = await getTPMStatus();

    if (status != TPMStatus.supported) {
      throw const BiometricCipherException(
        code: BiometricCipherExceptionCode.tpmUnsupported,
        message: 'TPM is unsupported or has an incompatible version',
      );
    }

    if (!await isKeyValid(tag: tag)) {
      throw const BiometricCipherException(
        code: BiometricCipherExceptionCode.keyNotFound,
        message: 'Key not found for tag $tag',
      );
    }

    final decryptedData = await decrypt(tag: tag, data: data);

    if (decryptedData == null) {
      throw const BiometricCipherException(
        code: BiometricCipherExceptionCode.decryptionError,
        message: 'Decryption failed',
      );
    }

    return decryptedData;
  }
```

- [ ] **Step 8: Run the tests to verify they pass**

```bash
cd packages/biometric_cipher
fvm flutter test
```

Expected: ALL tests pass — the new `getTpmVersion`, `listKeys`, `encryptString`, `decryptString` groups plus every pre-existing test (the field-backed `tpmStatus` mock defaults to `supported`, preserving existing behavior).

- [ ] **Step 9: Verify analysis and formatting**

```bash
cd packages/biometric_cipher
fvm dart format lib/data/tpm_key_info.dart lib/biometric_cipher_platform_interface.dart lib/biometric_cipher_method_channel.dart lib/biometric_cipher.dart test/mock_biometric_cipher_platform.dart test/biometric_cipher_test.dart
fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .
```

Expected: formatter reports no changes or only the changed files; analyzer reports zero issues.

- [ ] **Step 10: Commit**

```bash
cd packages/biometric_cipher
git add lib/data/tpm_key_info.dart lib/biometric_cipher_platform_interface.dart lib/biometric_cipher_method_channel.dart lib/biometric_cipher.dart test/mock_biometric_cipher_platform.dart test/biometric_cipher_test.dart
git commit -m "Add TPM version, key listing, and universal encrypt/decrypt APIs"
```

---

### Task 5: Example app — UI for the new functionality

**Files:**
- Modify: `packages/biometric_cipher/example/lib/tpm_screen.dart`

**Interfaces:**
- Consumes: `BiometricCipher.getTpmVersion()`, `BiometricCipher.listKeys()`, `BiometricCipher.encryptString()`, `BiometricCipher.decryptString()`, `TpmKeyInfo` from Task 4
- Produces: user-facing demo buttons; no code consumed by other tasks

The example app is not covered by plugin analyzer/test gates for behavior — the deliverable is a clean analysis plus a successful manual run on Windows (Task 6 in-CLI verification lists the exact steps).

- [ ] **Step 1: Add state fields and import**

In `packages/biometric_cipher/example/lib/tpm_screen.dart`:

Add import after the existing `biometric_cipher.dart` import:

```dart
import 'package:biometric_cipher/data/tpm_key_info.dart';
```

Add state fields after `bool _isKeyGenerated = false;`:

```dart
  int? _tpmVersion;
  List<TpmKeyInfo> _tpmKeys = [];
  String _universalEncryptedString = '';
  String _universalDecryptedString = '';
```

- [ ] **Step 2: Add UI widgets**

In the `Column` inside `build`, insert a new section after the existing `FilledButton(onPressed: () => _onDeleteKeyPressed(context), child: const Text('Delete key by tag'))` and before the closing of the column's children:

```dart
                    const Divider(),
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                              text: 'TPM version: ',
                              style: Theme.of(context).textTheme.labelLarge),
                          if (_tpmVersion != null)
                            TextSpan(
                              text: '$_tpmVersion',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                        onPressed: () => _onVersionCheckPressed(context),
                        child: const Text('Check TPM version')),
                    const Divider(),
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                              text: 'TPM keys (${_tpmKeys.length}): ',
                              style: Theme.of(context).textTheme.labelLarge),
                          TextSpan(
                            text: _tpmKeys.map((key) => key.name).join(', '),
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                        onPressed: () => _onListKeysPressed(context),
                        child: const Text('List TPM keys')),
                    const Divider(),
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                              text: 'Universally encrypted data: ',
                              style: Theme.of(context).textTheme.labelLarge),
                          TextSpan(
                            text: _universalEncryptedString,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                        onPressed: () => _onUniversalEncryptPressed(context),
                        child: const Text('Universal encrypt')),
                    const Divider(),
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                              text: 'Universally decrypted data: ',
                              style: Theme.of(context).textTheme.labelLarge),
                          TextSpan(
                            text: _universalDecryptedString,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                        onPressed: () => _onUniversalDecryptPressed(context),
                        child: const Text('Universal decrypt')),
```

- [ ] **Step 3: Add the handlers**

Add after `_onDeleteKeyPressed` at the end of the state class:

```dart
  Future<void> _onVersionCheckPressed(BuildContext context) async {
    try {
      final version = await _biometricCipherPlugin.getTpmVersion();

      setState(() => _tpmVersion = version);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Check TPM version error: $e')));
      }
    }
  }

  Future<void> _onListKeysPressed(BuildContext context) async {
    try {
      final keys = await _biometricCipherPlugin.listKeys();

      setState(() => _tpmKeys = keys);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('List TPM keys error: $e')));
      }
    }
  }

  Future<void> _onUniversalEncryptPressed(BuildContext context) async {
    if (_tagTextController.text.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter tag for universal encryption')));

      return;
    }

    if (_textController.text.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter data for universal encryption')));

      return;
    }

    try {
      final encryptedString = await _biometricCipherPlugin.encryptString(
        tag: _tagTextController.text,
        data: _textController.text,
      );

      setState(() => _universalEncryptedString = encryptedString);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Universal encryption error: $e')));
      }
    }
  }

  Future<void> _onUniversalDecryptPressed(BuildContext context) async {
    if (_tagTextController.text.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter tag for universal decryption')));

      return;
    }

    if (_universalEncryptedString.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Universal encryption data is empty! Universal encrypt data before decryption')),
      );

      return;
    }

    try {
      final decryptedString = await _biometricCipherPlugin.decryptString(
        tag: _tagTextController.text,
        data: _universalEncryptedString,
      );

      setState(() => _universalDecryptedString = decryptedString);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Universal decryption error: $e')));
      }
    }
  }
```

- [ ] **Step 4: Verify analysis and formatting**

```bash
cd packages/biometric_cipher
fvm dart format example/lib/tpm_screen.dart
fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .
```

Expected: analyzer reports zero issues across the plugin and example.

- [ ] **Step 5: Commit**

```bash
cd packages/biometric_cipher
git add example/lib/tpm_screen.dart
git commit -m "Add TPM version, key list, and universal encrypt UI to plugin example"
```

---

### Task 6: Final verification — build, run, and exercise the POC end to end

**Files:** none (verification only)

- [ ] **Step 1: Run the complete quality gate**

```bash
cd packages/biometric_cipher
fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .
fvm flutter test
cd example
fvm flutter build windows --debug
cmake --build build/windows --config Debug --target biometric_cipher_test
./build/windows/plugins/biometric_cipher/Debug/biometric_cipher_test.exe
```

Expected: zero analyzer findings; all Dart tests pass; native test suite exits 0.

- [ ] **Step 2: Manual POC verification on Windows**

```bash
cd packages/biometric_cipher/example
fvm flutter run -d windows
```

In the running app, exercise in order:
1. "Check Secure Enclave availability" → shows available (TPM present)
2. "Check TPM version" → shows `2` (or the actual TPM major version)
3. "List TPM keys" → shows a count and comma-separated opaque key names
4. Delete any existing key for the current tag ("Delete key by tag") so the universal path creates one
5. Type text, press "Universal encrypt" → shows a Base64 string; the "Key is generated" indicator confirms key creation by the universal path
6. Press "Universal decrypt" → shows the original plaintext
7. Delete the key again, press "Universal decrypt" → shows an error snackbar (key missing — no implicit creation), matching the spec

Note: "Universal encrypt" and "Universal decrypt" trigger the Windows Hello prompt because key derivation signs the configured challenge; approve the prompt when it appears.

- [ ] **Step 3: Final commit of any remaining changes (if any) and summary**

If verification surfaced fixes, commit them:

```bash
git status
git add <changed files>
git commit -m "Fix issues found during TPM POC verification"
```

Otherwise no commit — report the verification results.
