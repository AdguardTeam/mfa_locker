#pragma once

#include <gmock/gmock.h>

#include "include/secure_mnemonic/wrappers/ncrypt_wrapper.h"

namespace secure_mnemonic{
	namespace test {
		class MockNCryptWrapper : public NCryptWrapper {
		public:
			MOCK_METHOD(
				(SECURITY_STATUS),
				OpenStorageProvider,
				(NCryptHandleFree& providerHandle, LPCWSTR pszProviderName, DWORD dwFlags),
				(const, override)
			);

			MOCK_METHOD(
				(SECURITY_STATUS),
				GetProperty,
				(const NCryptHandleFree& providerHandle, LPCWSTR pszProperty, PBYTE pbOutput, DWORD cbOutput, DWORD* pcbResult, DWORD dwFlags),
				(const, override)
			);
		};
	}  // namespace test
}  // namespace secure_mnemonic
