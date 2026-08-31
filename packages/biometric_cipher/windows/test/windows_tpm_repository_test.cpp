#include <gtest/gtest.h>
#include <gmock/gmock.h>

#include "include/biometric_cipher/enums/tpm_status.h"

#include <winrt/base.h>

// Include mock
#include "mocks/mock_ncrypt_wrapper.h"

// Include the code under test
#include "include/biometric_cipher/repositories/windows_tpm_repository_impl.h"

namespace biometric_cipher {
	namespace test {

		using namespace biometric_cipher;

		class WindowsTpmRepositoryTest : public ::testing::Test {
		protected:
			// Shared pointers to mocks
			std::shared_ptr<MockNCryptWrapper> m_mockNCryptWrapper;

			// The repository under test
			std::unique_ptr<WindowsTpmRepositoryImpl> m_Repository;

			void SetUp() override 
			{
				m_mockNCryptWrapper = std::make_shared<MockNCryptWrapper>();
				// Inject the mock into the repository
				m_Repository = std::make_unique<WindowsTpmRepositoryImpl>(m_mockNCryptWrapper);
			}
		};

		TEST_F(WindowsTpmRepositoryTest, GetTPMStatusAsync_ReturnsNotSupportedIfWindowsHelloNotSupported)
		{		
			// Provide a fake "TPM-Version:2.0" wide string
			const std::wstring fakeData = L"TPM-Version:2.0";
			const size_t sizeInBytes = (wcslen(fakeData.c_str()) + 1) * sizeof(wchar_t);

			// 1) OpenStorageProvider = > ERROR_SUCCESS
			EXPECT_CALL(*m_mockNCryptWrapper, OpenStorageProvider)
				.Times(1)
				.WillOnce([] (NCryptHandleFree& providerHandle, LPCWSTR pszProviderName, DWORD dwFlags) -> SECURITY_STATUS
					{
						// Assert
						EXPECT_STREQ(pszProviderName, MS_PLATFORM_CRYPTO_PROVIDER);
						EXPECT_EQ(dwFlags, 0);

						return ERROR_SUCCESS;
					}
				);
			// 2) First GetProperty => needed to get size (cbPlatformType)
			EXPECT_CALL(*m_mockNCryptWrapper, GetProperty)
				.Times(2)
				.WillOnce([sizeInBytes](NCryptHandleFree const&, LPCWSTR pszProperty, PBYTE, DWORD, DWORD* pcbResult, DWORD)
				{
						// Assert
						EXPECT_STREQ(pszProperty, NCRYPT_PCP_PLATFORM_TYPE_PROPERTY);

						*pcbResult = static_cast<DWORD>(sizeInBytes);;

						return ERROR_SUCCESS;
				})
			// 3) Second GetProperty => retrieve the actual data
				.WillOnce([fakeData, sizeInBytes] (NCryptHandleFree const&, LPCWSTR pszProperty, PBYTE pbOutput, DWORD, DWORD* pcbResult, DWORD)
				{
						// Assert
						EXPECT_STREQ(pszProperty, NCRYPT_PCP_PLATFORM_TYPE_PROPERTY);

						memcpy(pbOutput, fakeData.c_str(), sizeInBytes);

						*pcbResult = static_cast<DWORD>(sizeInBytes);

						return ERROR_SUCCESS;
				});

			// Act
			auto tpmVersion = m_Repository->GetWindowsTpmVersion();

			// Assert
			EXPECT_EQ(tpmVersion, 2);
		}

		// Test that throws when "TPM-Version:" is not found
		TEST_F(WindowsTpmRepositoryTest, GetWindowsTpmVersion_ThrowsIfVersionNotFound)
		{
			const std::wstring fakeData = L"No mention of version here";
			const size_t sizeInBytes = (wcslen(fakeData.c_str()) + 1) * sizeof(wchar_t);

			// Mock success for opening provider, property calls, but return string without "TPM-Version:"
			EXPECT_CALL(*m_mockNCryptWrapper, OpenStorageProvider)
				.Times(1)
				.WillOnce([](NCryptHandleFree& providerHandle, LPCWSTR pszProviderName, DWORD dwFlags) -> SECURITY_STATUS
					{
						// Assert
						EXPECT_STREQ(pszProviderName, MS_PLATFORM_CRYPTO_PROVIDER);
						EXPECT_EQ(dwFlags, 0);

						return ERROR_SUCCESS;
					}
				);

			// 2) First GetProperty => needed to get size (cbPlatformType)
			EXPECT_CALL(*m_mockNCryptWrapper, GetProperty)
				.Times(2)
				.WillOnce([sizeInBytes](NCryptHandleFree const&, LPCWSTR pszProperty, PBYTE, DWORD, DWORD* pcbResult, DWORD)
					{
						// Assert
						EXPECT_STREQ(pszProperty, NCRYPT_PCP_PLATFORM_TYPE_PROPERTY);

						*pcbResult = static_cast<DWORD>(sizeInBytes);;

						return ERROR_SUCCESS;
					})
				// 3) Second GetProperty => retrieve the actual data
				.WillOnce([fakeData, sizeInBytes](NCryptHandleFree const&, LPCWSTR pszProperty, PBYTE pbOutput, DWORD, DWORD* pcbResult, DWORD)
					{
						// Assert
						EXPECT_STREQ(pszProperty, NCRYPT_PCP_PLATFORM_TYPE_PROPERTY);

						memcpy(pbOutput, fakeData.c_str(), sizeInBytes);

						*pcbResult = static_cast<DWORD>(sizeInBytes);

						return ERROR_SUCCESS;
					});

			// Act & Assert
			EXPECT_THROW(
				m_Repository->GetWindowsTpmVersion(),
				winrt::hresult_error
			);
		}

		// Test that throws if NCryptOpenStorageProvider fails
		TEST_F(WindowsTpmRepositoryTest, GetWindowsTpmVersion_OpenStorageProviderThrows)
		{
			EXPECT_CALL(*m_mockNCryptWrapper, OpenStorageProvider)
				.Times(1)
				.WillOnce([](NCryptHandleFree& providerHandle, LPCWSTR pszProviderName, DWORD dwFlags) -> SECURITY_STATUS
					{
						// Assert
						EXPECT_STREQ(pszProviderName, MS_PLATFORM_CRYPTO_PROVIDER);
						EXPECT_EQ(dwFlags, 0);

						return NTE_BAD_KEY;
					}
				);

			// Act & Assert
			EXPECT_THROW(
				m_Repository->GetWindowsTpmVersion(),
				winrt::hresult_error
			);
		}

		TEST_F(WindowsTpmRepositoryTest, ListTpmKeys_ReturnsAllTpmKeys)
		{
			EXPECT_CALL(*m_mockNCryptWrapper, OpenStorageProvider)
				.Times(1)
				.WillOnce([](NCryptHandleFree& providerHandle, LPCWSTR pszProviderName, DWORD dwFlags) -> SECURITY_STATUS
					{
						EXPECT_STREQ(pszProviderName, MS_PLATFORM_CRYPTO_PROVIDER);
						EXPECT_EQ(dwFlags, 0);

						return ERROR_SUCCESS;
					}
				);

			NCryptKeyName firstKey = {};
			firstKey.pszName = const_cast<LPWSTR>(L"tpm_key_one");
			firstKey.pszAlgid = const_cast<LPWSTR>(L"RSA");

			NCryptKeyName secondKey = {};
			secondKey.pszName = const_cast<LPWSTR>(L"tpm_key_two");
			secondKey.pszAlgid = const_cast<LPWSTR>(L"ECC");

			EXPECT_CALL(*m_mockNCryptWrapper, EnumKeys)
				.Times(3)
				.WillOnce([&firstKey](NCryptHandleFree const&, NCryptKeyName** ppKeyName, PVOID* ppEnumState, DWORD) -> SECURITY_STATUS
					{
						*ppKeyName = &firstKey;
						*ppEnumState = reinterpret_cast<PVOID>(1);

						return ERROR_SUCCESS;
					}
				)
				.WillOnce([&secondKey](NCryptHandleFree const&, NCryptKeyName** ppKeyName, PVOID* ppEnumState, DWORD) -> SECURITY_STATUS
					{
						*ppKeyName = &secondKey;
						*ppEnumState = reinterpret_cast<PVOID>(1);

						return ERROR_SUCCESS;
					}
				)
				.WillOnce([](NCryptHandleFree const&, NCryptKeyName**, PVOID* ppEnumState, DWORD) -> SECURITY_STATUS
					{
						*ppEnumState = reinterpret_cast<PVOID>(1);

						return NTE_NO_MORE_ITEMS;
					}
				);

			EXPECT_CALL(*m_mockNCryptWrapper, FreeBuffer)
				.Times(3)
				.WillRepeatedly([](PVOID pvInput) -> SECURITY_STATUS
					{
						EXPECT_NE(pvInput, nullptr);

						return ERROR_SUCCESS;
					}
				);

			// Act
			auto keys = m_Repository->ListTpmKeys();

			// Assert
			ASSERT_EQ(keys.size(), static_cast<size_t>(2));
			EXPECT_EQ(keys[0].name, "tpm_key_one");
			EXPECT_EQ(keys[0].algorithm, "RSA");
			EXPECT_EQ(keys[1].name, "tpm_key_two");
			EXPECT_EQ(keys[1].algorithm, "ECC");
		}

		TEST_F(WindowsTpmRepositoryTest, ListTpmKeys_ThrowsIfEnumKeysFails)
		{
			EXPECT_CALL(*m_mockNCryptWrapper, OpenStorageProvider)
				.Times(1)
				.WillOnce([](NCryptHandleFree& providerHandle, LPCWSTR pszProviderName, DWORD dwFlags) -> SECURITY_STATUS
					{
						return ERROR_SUCCESS;
					}
				);

			EXPECT_CALL(*m_mockNCryptWrapper, EnumKeys)
				.Times(1)
				.WillOnce([](NCryptHandleFree const&, NCryptKeyName** ppKeyName, PVOID* ppEnumState, DWORD) -> SECURITY_STATUS
					{
						*ppKeyName = nullptr;
						*ppEnumState = nullptr;

						return NTE_BAD_KEY;
					}
				);

			// Act & Assert
			EXPECT_THROW(
				m_Repository->ListTpmKeys(),
				winrt::hresult_error
			);
		}
	}
}
