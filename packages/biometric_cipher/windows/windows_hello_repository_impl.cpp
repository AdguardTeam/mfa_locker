#include "include/biometric_cipher/repositories/windows_hello_repository_impl.h"
#include "include/biometric_cipher/errors/error_codes.h"
#include "include/biometric_cipher/enums/biometry_status.h"

#include <windows.h>
#include <winrt/windows.security.credentials.ui.h>

using namespace winrt;
using namespace winrt::impl;
using namespace Windows::Foundation;
using namespace Windows::Security::Cryptography;
using namespace Windows::Security::Cryptography::Core;
using namespace Windows::Security::Credentials;
using namespace Windows::Storage::Streams;
using namespace Windows::Security::Credentials::UI;

namespace biometric_cipher
{
	IAsyncOperation<int> WindowsHelloRepositoryImpl::GetWindowsHelloStatusAsync() const
	{
		auto isSupported = co_await m_HelloWrapper->IsSupportedAsync();

		if (isSupported) {
			co_return BiometryStatusToInteger(BiometryStatus::kSupported);
		}

		auto availability = co_await m_HelloWrapper->CheckAvailabilityAsync();
		switch (availability) {
		case UserConsentVerifierAvailability::Available:
			co_return BiometryStatusToInteger(BiometryStatus::kSupported);

		case UserConsentVerifierAvailability::DeviceNotPresent:
			co_return BiometryStatusToInteger(BiometryStatus::kDeviceNotPresent);

		case UserConsentVerifierAvailability::NotConfiguredForUser:
			co_return BiometryStatusToInteger(BiometryStatus::kNotConfiguredForUser);

		case UserConsentVerifierAvailability::DisabledByPolicy:
			co_return BiometryStatusToInteger(BiometryStatus::kDisabledByPolicy);

		case UserConsentVerifierAvailability::DeviceBusy:
			co_return BiometryStatusToInteger(BiometryStatus::kDeviceBusy);
		}

		throw hresult_error(error_fail, L"Unknown error occurred.");
	}

	IAsyncOperation<IBuffer> WindowsHelloRepositoryImpl::SignAsync(const winrt::hstring tag, const IBuffer data) const
	{
		co_await CheckWindowsHelloIsStatusAsync();

		auto&& keyCredentialRetrievalResult = co_await m_HelloWrapper->OpenAsync(tag);
		CheckKeyCredentialStatus(keyCredentialRetrievalResult.Status());

		auto&& keyCredential = keyCredentialRetrievalResult.Credential();

		AllowSetForegroundWindow(ASFW_ANY);

		HHOOK hook = SetWindowsHookEx(WH_CBT, [](int nCode, WPARAM wParam, LPARAM lParam) -> LRESULT {
			if (nCode == HCBT_ACTIVATE || nCode == HCBT_CREATEWND) {
				AllowSetForegroundWindow(ASFW_ANY);
			}
			return CallNextHookEx(nullptr, nCode, wParam, lParam);
		}, nullptr, GetCurrentThreadId());

		auto&& signatureResult = co_await keyCredential.RequestSignAsync(data);

		if (hook) {
			UnhookWindowsHookEx(hook);
		}

		CheckKeyCredentialStatus(signatureResult.Status());

		co_return signatureResult.Result();
	}

	IAsyncAction WindowsHelloRepositoryImpl::CreateCredentialAsync(const winrt::hstring tag) const
	{
		co_await CheckWindowsHelloIsStatusAsync();

		AllowSetForegroundWindow(ASFW_ANY);

		HHOOK hook = SetWindowsHookEx(WH_CBT, [](int nCode, WPARAM wParam, LPARAM lParam) -> LRESULT {
			if (nCode == HCBT_ACTIVATE || nCode == HCBT_CREATEWND) {
				AllowSetForegroundWindow(ASFW_ANY);
			}
			return CallNextHookEx(nullptr, nCode, wParam, lParam);
		}, nullptr, GetCurrentThreadId());

		auto&& keyCredentialResult = co_await m_HelloWrapper->RequestCreateAsync(tag, KeyCredentialCreationOption::FailIfExists);

		if (hook) {
			UnhookWindowsHookEx(hook);
		}

		CheckKeyCredentialStatus(keyCredentialResult.Status());

		co_return;
	}

	IAsyncAction WindowsHelloRepositoryImpl::DeleteCredentialAsync(const winrt::hstring tag) const
	{
		co_await CheckWindowsHelloIsStatusAsync();

		AllowSetForegroundWindow(ASFW_ANY);

		HHOOK hook = SetWindowsHookEx(WH_CBT, [](int nCode, WPARAM wParam, LPARAM lParam) -> LRESULT {
			if (nCode == HCBT_ACTIVATE || nCode == HCBT_CREATEWND) {
				AllowSetForegroundWindow(ASFW_ANY);
			}
			return CallNextHookEx(nullptr, nCode, wParam, lParam);
		}, nullptr, GetCurrentThreadId());

		co_await m_HelloWrapper->DeleteAsync(tag);

		if (hook) {
			UnhookWindowsHookEx(hook);
		}

		co_return;
	}

	IAsyncOperation<bool> WindowsHelloRepositoryImpl::IsKeyValidAsync(const winrt::hstring tag) const
	{
		co_await CheckWindowsHelloIsStatusAsync();

		auto&& keyCredentialRetrievalResult = co_await m_HelloWrapper->OpenAsync(tag);
		auto status = keyCredentialRetrievalResult.Status();

		co_return status == KeyCredentialStatus::Success;
	}

	IAsyncAction WindowsHelloRepositoryImpl::CheckWindowsHelloIsStatusAsync() const
	{
		auto biometryStatusValue = co_await GetWindowsHelloStatusAsync();
		if (IntegerToBiometryStatus(biometryStatusValue) != BiometryStatus::kSupported) {
			throw hresult_error(error_biometry_not_supported, L"Windows Hello is not supported.");
		}

		co_return;
	}

	void WindowsHelloRepositoryImpl::CheckKeyCredentialStatus(KeyCredentialStatus status)
	{
		switch (status) {
		case KeyCredentialStatus::Success:
			break;

		case KeyCredentialStatus::NotFound:
			throw hresult_error(error_key_not_found, L"Key credential not found.");

		case KeyCredentialStatus::UserCanceled:
			throw hresult_error(error_authentication_canceled, L"User canceled the operation.");

		case KeyCredentialStatus::UnknownError:
			throw hresult_error(error_fail, L"An unknown error occurred.");

		case KeyCredentialStatus::UserPrefersPassword:
			throw hresult_error(error_user_prefers_password, L"User prefers password.");

		case KeyCredentialStatus::CredentialAlreadyExists:
			throw hresult_error(error_key_already_exists, L"Key credential already exists.");

		case KeyCredentialStatus::SecurityDeviceLocked:
			throw hresult_error(error_secure_device_locked, L"Security device is locked.");

		default:
			throw hresult_error(error_fail, L"Unknown key credential status.");
		}
	}
}
