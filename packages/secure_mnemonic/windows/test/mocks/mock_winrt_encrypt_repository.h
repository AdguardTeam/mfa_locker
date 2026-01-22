#pragma once

#include <gmock/gmock.h>

#include "include/secure_mnemonic/repositories/winrt_encrypt_repository.h"

namespace secure_mnemonic {
	namespace test {

		using namespace winrt;
		using namespace winrt::impl;
		using namespace Windows::Foundation;
		using namespace Windows::Security::Cryptography;
		using namespace Windows::Security::Cryptography::Core;
		using namespace Windows::Storage::Streams;

		class MockWinrtEncryptRepository : public WinrtEncryptRepository {
		public:
			MOCK_METHOD(
				(CryptographicKey),
				CreateAESKey,
				(const IBuffer signature),
				(const, override)
			);

			MOCK_METHOD(
				(hstring),
				Encrypt,
				(const CryptographicKey key, const hstring data),
				(const, override)
			);

			MOCK_METHOD(
				(hstring),
				Decrypt,
				(const CryptographicKey key, const hstring data),
				(const, override)
			);
		};
	}
}
