#pragma once

#include <winrt/base.h>
#include <winrt/windows.foundation.h>
#include <winrt/windows.security.credentials.h>
#include <winrt/windows.security.cryptography.core.h>
#include <winrt/windows.storage.streams.h>

namespace biometric_cipher
{
	struct WinrtEncryptRepository
	{
		virtual winrt::Windows::Security::Cryptography::Core::CryptographicKey CreateAESKey(const winrt::Windows::Storage::Streams::IBuffer signature) const = 0;

		virtual winrt::hstring Encrypt(
			const winrt::Windows::Security::Cryptography::Core::CryptographicKey key,
			const winrt::hstring data) const = 0;

		virtual winrt::hstring Decrypt(
			const winrt::Windows::Security::Cryptography::Core::CryptographicKey key,
			const winrt::hstring data) const = 0;
	};
}
