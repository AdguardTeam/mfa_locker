#include "include/biometric_cipher/repositories/windows_tpm_repository_impl.h"
#include "include/biometric_cipher/common/memory_deallocation.h"
#include "include/biometric_cipher/enums/tpm_status.h"
#include "include/biometric_cipher/errors/error_codes.h"

#include <windows.h>
#include <winrt/base.h>
#include <sstream>
#include <iomanip>
#include <vector>
#include <exception>

#pragma comment(lib, "ncrypt.lib")

using namespace winrt;
using namespace winrt::impl;


namespace biometric_cipher
{
	int WindowsTpmRepositoryImpl::GetWindowsTpmVersion() const
	{
		SECURITY_STATUS status = ERROR_SUCCESS;

		NCryptHandleFree providerHandle;

		status = m_NCryptWrapper->OpenStorageProvider(providerHandle, MS_PLATFORM_CRYPTO_PROVIDER, 0);
		CheckStatus(error_tpm_unsupported,  L"NCryptOpenStorageProvider failed", status);

		//// If we have successfully opened the Platform Crypto Provider, it means TPM is present.
		//// Now, let's check the TPM version.
		DWORD cbPlatformType = 0;
		status = m_NCryptWrapper->GetProperty(providerHandle, NCRYPT_PCP_PLATFORM_TYPE_PROPERTY, NULL, NULL, &cbPlatformType, 0);
		CheckStatus(error_tpm_version, L"NCryptGetProperty failed", status);

		std::vector<BYTE> platformType(cbPlatformType);
		status = m_NCryptWrapper->GetProperty(providerHandle, NCRYPT_PCP_PLATFORM_TYPE_PROPERTY, platformType.data(), (DWORD)platformType.size(), &cbPlatformType, 0);
		CheckStatus(error_tpm_version, L"NCryptGetProperty failed", status);

		auto version = std::wstring(reinterpret_cast<wchar_t*>(platformType.data()), cbPlatformType / sizeof(wchar_t));
		auto type = ParsePlatformType(version);

		try {
			auto result = std::stoi(type);
			return result;
		}
		catch (const std::exception) {
			throw hresult_error(error_tpm_version, L"Incorrect TPM version");
		}
	}

	const std::wstring WindowsTpmRepositoryImpl::ParsePlatformType(const std::wstring& platformVersion)
	{
		const std::wstring key = L"TPM-Version:";
		auto start = platformVersion.find(key);
		if (start == std::wstring::npos) {
			throw hresult_error(error_tpm_version, L"TPM version not found");
		}
		start += key.size();
		auto end = platformVersion.find(L".", start);

		return platformVersion.substr(start, end - start);
	}

	void WindowsTpmRepositoryImpl::CheckStatus(const hresult hr, const std::wstring& message, const int errorCode)
	{
		if (errorCode != ERROR_SUCCESS) {
			std::wostringstream woss;
			woss << message << L": 0x" << std::hex << std::uppercase << errorCode;

			throw hresult_error(hr, woss.str());
		}
	}
}  // namespace biometric_cipher
