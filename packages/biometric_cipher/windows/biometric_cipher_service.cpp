#include "include/biometric_cipher/services/biometric_cipher_service.h"
#include "include/biometric_cipher/common/string_util.h"
#include "include/biometric_cipher/enums/tpm_status.h"
#include "include/biometric_cipher/errors/error_codes.h"

#include <windows.h>
#include <winrt/windows.security.cryptography.h>

using namespace winrt;
using namespace winrt::impl;
using namespace Windows::Foundation;
using namespace Windows::Security::Cryptography;
using namespace Windows::Security::Cryptography::Core;
using namespace Windows::Storage::Streams;

namespace biometric_cipher
{
	IAsyncOperation<int> BiometricCipherService::GetTPMStatusAsync() const
	{		
		try
		{
			auto tpmVersion = m_WindowsTpmRepository->GetWindowsTpmVersion();
			if (tpmVersion < 2)
			{
				co_return TpmStatusToInteger(TpmStatus::kTPMVersionUnsupported);
			}
		}
		catch (const hresult_error& e)
		{
			auto hr = e.code();
			switch (hr.value)
			{
			case error_tpm_unsupported:
				co_return TpmStatusToInteger(TpmStatus::kUnsupported);

			case error_tpm_version:
				co_return TpmStatusToInteger(TpmStatus::kTPMVersionUnsupported);
			}

			throw;
		}

		co_return TpmStatusToInteger(TpmStatus::kSupported);
	}

	winrt::Windows::Foundation::IAsyncOperation<int> BiometricCipherService::GetBiometryStatusAsync() const
	{
		return m_WindowsHelloRepository->GetWindowsHelloStatusAsync();
	}

	IAsyncAction BiometricCipherService::GenerateKeyAsync(const std::string& tag) const
	{
		auto hTag = StringUtil::ConvertStringToHString(tag);

		co_await m_WindowsHelloRepository->CreateCredentialAsync(hTag);

		co_return;
	}

	IAsyncAction BiometricCipherService::DeleteKeyAsync(const std::string& tag) const 
	{
		auto hTag = StringUtil::ConvertStringToHString(tag);

		try {
			co_await m_WindowsHelloRepository->DeleteCredentialAsync(hTag);
		}
		catch (const hresult_error& e) {
			auto code = e.code();
			if (code.value != NTE_NO_KEY) {
				throw;
			}
		}

		co_return;
	}

	IAsyncOperation<winrt::hstring> BiometricCipherService::EncryptAsync(const std::string& tag, const std::string& data) const 
	{
		if (!m_ConfigStorage->getIsConfigured()) {
			throw winrt::hresult_error(error_invalid_argument, L"Data to sign is empty");
		}

		auto& configData = m_ConfigStorage->GetConfig();
		auto dataToSign = StringUtil::ConvertStringToHString(configData.dataToSign);

		auto hTag = StringUtil::ConvertStringToHString(tag);
		auto hData = StringUtil::ConvertStringToHString(data);

		auto&& signature = CryptographicBuffer::ConvertStringToBinary(dataToSign, BinaryStringEncoding::Utf16LE);

		auto&& aesKey = co_await CreateAESKeyAsync(hTag, signature);

		auto&& encryptedBase64String = m_WinrtEncryptRepository->Encrypt(aesKey, hData);

		co_return encryptedBase64String;
	}

	IAsyncOperation<hstring> BiometricCipherService::DecryptAsync(const std::string& tag, const std::string& data) const
	{
		if (!m_ConfigStorage->getIsConfigured()) {
			throw hresult_error(error_decrypt, L"Data to sign is empty");
		}

		auto& configData = m_ConfigStorage->GetConfig();
		auto dataToSign = StringUtil::ConvertStringToHString(configData.dataToSign);

		auto hTag = StringUtil::ConvertStringToHString(tag);
		auto hData = StringUtil::ConvertStringToHString(data);

		auto&& signature = CryptographicBuffer::ConvertStringToBinary(dataToSign, BinaryStringEncoding::Utf16LE);

		auto&& aesKey = co_await CreateAESKeyAsync(hTag, signature);

		auto&& decryptedData = m_WinrtEncryptRepository->Decrypt(aesKey, hData);

		co_return decryptedData;
	}


	IAsyncOperation<CryptographicKey> BiometricCipherService::CreateAESKeyAsync(const winrt::hstring hTag, const IBuffer signature) const
	{
		auto&& signedData = co_await m_WindowsHelloRepository->SignAsync(hTag, signature);

		auto&& aesKey = m_WinrtEncryptRepository->CreateAESKey(signedData);

		co_return aesKey;
	}
}
