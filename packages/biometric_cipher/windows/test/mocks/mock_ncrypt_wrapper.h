#pragma once

#include <gmock/gmock.h>

#include "include/biometric_cipher/wrappers/ncrypt_wrapper.h"

namespace biometric_cipher{
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
}  // namespace biometric_cipher
