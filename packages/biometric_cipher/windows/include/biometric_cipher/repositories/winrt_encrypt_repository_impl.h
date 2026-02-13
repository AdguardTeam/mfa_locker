#pragma once

#include "include/biometric_cipher/repositories/winrt_encrypt_repository.h"

#include <memory>
#include <winrt/base.h>
#include <winrt/windows.foundation.h>
#include <winrt/windows.security.cryptography.core.h>
#include <winrt/windows.storage.streams.h>

namespace biometric_cipher
{
	class WinrtEncryptRepositoryImpl : public WinrtEncryptRepository
	{
	public:
		winrt::Windows::Security::Cryptography::Core::CryptographicKey CreateAESKey(const winrt::Windows::Storage::Streams::IBuffer signature) const override;

		winrt::hstring Encrypt(
			const winrt::Windows::Security::Cryptography::Core::CryptographicKey key,
			const winrt::hstring data) const override;

		winrt::hstring Decrypt(
			const winrt::Windows::Security::Cryptography::Core::CryptographicKey key,
			const winrt::hstring data) const override;
	private:
		static const uint32_t NONCE_LENGTH = 12;

		static const uint32_t TAG_LENGTH = 16;
	};
}
