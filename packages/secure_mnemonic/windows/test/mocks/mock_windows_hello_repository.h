#pragma once

#include <gmock/gmock.h>

#include "include/secure_mnemonic/repositories/windows_hello_repository.h"

namespace secure_mnemonic {
	namespace test {

		using namespace winrt;
		using namespace winrt::impl;
		using namespace Windows::Foundation;
		using namespace Windows::Security::Cryptography;
		using namespace Windows::Security::Cryptography::Core;
		using namespace Windows::Security::Credentials;
		using namespace Windows::Storage::Streams;

		class MockWindowsHelloRepository : public WindowsHelloRepository {
		public:
			MOCK_METHOD(
				(IAsyncOperation<int>),
				GetWindowsHelloStatusAsync,
				(),
				(const, override)
			);

			MOCK_METHOD(
				(IAsyncOperation<IBuffer>),
				SignAsync,
				(const hstring tag, const IBuffer data),
				(const, override)
			);

			MOCK_METHOD(
				(IAsyncAction),
				CreateCredentialAsync,
				(const hstring tag),
				(const, override)
			);

			MOCK_METHOD(
				(IAsyncAction),
				DeleteCredentialAsync,
				(const hstring tag),
				(const, override)
			);
		};
	}
}
