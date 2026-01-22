#pragma once

#include "include/secure_mnemonic/storages/config_storage.h"
#include "include/secure_mnemonic/repositories/windows_hello_repository.h"
#include "include//secure_mnemonic/repositories/windows_tpm_repository.h"
#include "include/secure_mnemonic/repositories/winrt_encrypt_repository.h"

#include <memory>
#include <string>
#include <winrt/windows.foundation.h>

namespace secure_mnemonic
{
	class SecureMnemonicService
	{

	public:
		SecureMnemonicService(
			std::shared_ptr<ConfigStorage> configStorage,
			std::shared_ptr<WindowsHelloRepository> windowsHelloRepository,
			std::shared_ptr<WindowsTpmRepository> windowsTpmRepository,
			std::shared_ptr<WinrtEncryptRepository> winrtEncryptRepository
		) 
			: m_ConfigStorage(configStorage),
			m_WindowsHelloRepository(std::move(windowsHelloRepository)),
			m_WindowsTpmRepository(std::move(windowsTpmRepository)),
			m_WinrtEncryptRepository(std::move(winrtEncryptRepository))
		{}

		winrt::Windows::Foundation::IAsyncOperation<int> GetTPMStatusAsync() const;

		winrt::Windows::Foundation::IAsyncOperation<int> GetBiometryStatusAsync() const;

		winrt::Windows::Foundation::IAsyncAction GenerateKeyAsync(const std::string& tag) const;

		winrt::Windows::Foundation::IAsyncAction DeleteKeyAsync(const std::string& tag) const;

		winrt::Windows::Foundation::IAsyncOperation<winrt::hstring> EncryptAsync(const std::string& tag, const std::string& data) const;

		winrt::Windows::Foundation::IAsyncOperation<winrt::hstring> DecryptAsync(const std::string& tag, const std::string& data) const;

	private:
		winrt::Windows::Foundation::IAsyncOperation<winrt::Windows::Security::Cryptography::Core::CryptographicKey> 
			CreateAESKeyAsync(
				const winrt::hstring hTag,
				const winrt::Windows::Storage::Streams::IBuffer signature) const;

		std::shared_ptr<ConfigStorage> m_ConfigStorage;
		std::shared_ptr<WindowsHelloRepository> m_WindowsHelloRepository;
		std::shared_ptr<WindowsTpmRepository> m_WindowsTpmRepository;
		std::shared_ptr<WinrtEncryptRepository> m_WinrtEncryptRepository;
	};
}  // namespace secure_mnemonic
