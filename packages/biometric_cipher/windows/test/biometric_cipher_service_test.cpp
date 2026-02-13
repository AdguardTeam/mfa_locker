#include <gtest/gtest.h>
#include <windows.h>

#include <memory>
#include <string>

#include "include/biometric_cipher/enums/tpm_status.h"
#include "include/biometric_cipher/enums/biometry_status.h"
#include "include/biometric_cipher/errors/error_codes.h"

// Include mock
#include "mocks/mock_config_storage.h"
#include "mocks/mock_windows_hello_repository.h"
#include "mocks/mock_windows_tpm_repository.h"
#include "mocks/mock_winrt_encrypt_repository.h"

// Include the code under test
#include "include/biometric_cipher/services/biometric_cipher_service.h"



namespace biometric_cipher {
	namespace test {

		using namespace biometric_cipher;
		using namespace winrt;
		using namespace winrt::impl;
		using namespace Windows::Foundation;
		using namespace Windows::Security::Cryptography::Core;

		class BiometricCipherServiceTest : public ::testing::Test  {
		protected:
			ConfigData m_ConfigData;

			// Shared pointers to mocks
			std::shared_ptr<MockConfigStorage> m_ConfigStorage;
			std::shared_ptr<MockWindowsHelloRepository> m_WindowsHelloRepository;
			std::shared_ptr<MockWindowsTpmRepository> m_WindowsTpmRepository;
			std::shared_ptr<MockWinrtEncryptRepository> m_WinrtEncryptRepository;

			// The service under test
			std::unique_ptr<BiometricCipherService> m_Service;
		
			void SetUp() override {
				// Initialize mocks
				m_ConfigStorage = std::make_shared<MockConfigStorage>();
				m_WindowsHelloRepository = std::make_shared<MockWindowsHelloRepository>();
				m_WindowsTpmRepository = std::make_shared<MockWindowsTpmRepository>();
				m_WinrtEncryptRepository = std::make_shared<MockWinrtEncryptRepository>();

				// Create the service
				m_Service = std::make_unique<BiometricCipherService>(
					m_ConfigStorage,
					m_WindowsHelloRepository,
					m_WindowsTpmRepository,
					m_WinrtEncryptRepository
				);
			}
		};

		TEST_F(BiometricCipherServiceTest, GetTPMStatusAsync_ReturnsUnsupportedIfWindowsTpmRepositoryThrows)
		{
			// Set expectations
			EXPECT_CALL(*m_WindowsTpmRepository, GetWindowsTpmVersion())
				.Times(1)
				.WillOnce(testing::Throw(hresult_error(error_tpm_unsupported, L"Test exception")));

			// Act: create an instance and call the function that triggers mock calls.
			auto asyncOp = m_Service->GetTPMStatusAsync();
			int result = asyncOp.get();
			// Assert
			EXPECT_EQ(result, TpmStatusToInteger(TpmStatus::kUnsupported));
		}

		TEST_F(BiometricCipherServiceTest, GetTPMStatusAsync_ReturnsUnsupportedIfWindowsTpmRepositoryVersionThrows)
		{
			// Set expectations
			EXPECT_CALL(*m_WindowsTpmRepository, GetWindowsTpmVersion())
				.Times(1)
				.WillOnce(testing::Throw(hresult_error(error_tpm_version, L"Test exception")));

			// Act: create an instance and call the function that triggers mock calls.
			auto asyncOp = m_Service->GetTPMStatusAsync();
			int result = asyncOp.get();
			// Assert
			EXPECT_EQ(result, TpmStatusToInteger(TpmStatus::kTPMVersionUnsupported));
		}

		TEST_F(BiometricCipherServiceTest, GetTPMStatusAsync_ReturnsTPMVersionUnsupportedIfTpmVersionLessThan2)
		{
			auto tpmVersion = 1;
			// Set expectations
			EXPECT_CALL(*m_WindowsTpmRepository, GetWindowsTpmVersion())
				.Times(1)
				.WillOnce([&, tpmVersion]() -> int
					{
						return tpmVersion;
					}
				);

			// Act: create an instance and call the function that triggers mock calls.
			auto asyncOp = m_Service->GetTPMStatusAsync();
			int result = asyncOp.get();
			// Assert
			EXPECT_EQ(result, TpmStatusToInteger(TpmStatus::kTPMVersionUnsupported));
		}

		TEST_F(BiometricCipherServiceTest, GetBiometryStatusAsync_ReturnsNotSupportedIfWindowsHelloUnsupported) {
			// Set expectations
			auto status = BiometryStatus::kUnsupported;
			EXPECT_CALL(*m_WindowsHelloRepository, GetWindowsHelloStatusAsync())
				.Times(1)
				.WillOnce([&, status]() -> IAsyncOperation<int>
					{
						co_return BiometryStatusToInteger(status);
					}
				);

			// Act: create an instance and call the function that triggers mock calls.
			auto asyncOp = m_Service->GetBiometryStatusAsync();
			int result = asyncOp.get();

			// Assert
			EXPECT_EQ(result, BiometryStatusToInteger(status));
		}

		TEST_F(BiometricCipherServiceTest, GetBiometryStatusAsync_ReturnsSupportedIfWindowsHelloSupported) {
			// Set expectations
			auto status = BiometryStatus::kSupported;
			EXPECT_CALL(*m_WindowsHelloRepository, GetWindowsHelloStatusAsync())
				.Times(1)
				.WillOnce([&, status]() -> IAsyncOperation<int>
					{
						co_return BiometryStatusToInteger(status);
					}
				);

			// Act: create an instance and call the function that triggers mock calls.
			auto asyncOp = m_Service->GetBiometryStatusAsync();
			int result = asyncOp.get();

			// Assert
			EXPECT_EQ(result, BiometryStatusToInteger(status));
		}

		TEST_F(BiometricCipherServiceTest, GenerateKeyAsync_CallsCreateCredentialWithCorrectTag) {
			// Arrange
			std::string testTag = "test_tag";
			std::wstring wTestTag(testTag.begin(), testTag.end());

			EXPECT_CALL(*m_WindowsHelloRepository, CreateCredentialAsync)
				.Times(1)
				.WillOnce([&, wTestTag](const winrt::hstring& hTag) -> IAsyncAction
					{
						// Convert back to std::wstring or std::string to compare
						std::wstring wTag(hTag.c_str());
						EXPECT_TRUE(wTag.find(wTestTag) != std::wstring::npos);
						co_return;
					}
				);

			// Act
			auto asyncOp = m_Service->GenerateKeyAsync(testTag);
			asyncOp.get();

			// Assert
			// The expectation with EXPECT_CALL is enough to verify correctness here.
		}

		TEST_F(BiometricCipherServiceTest, DeleteKeyAsync_CallsDeleteCredentialWithCorrectTag)
		{
			// Arrange
			std::string testTag = "delete_tag";
			std::wstring wTestTag(testTag.begin(), testTag.end());

			EXPECT_CALL(*m_WindowsHelloRepository, DeleteCredentialAsync)
				.Times(1)
				.WillOnce([&, wTestTag](const winrt::hstring& hTag) -> winrt::Windows::Foundation::IAsyncAction
					{
						std::wstring wTag(hTag.c_str());
						EXPECT_TRUE(wTag.find(wTestTag) != std::wstring::npos);
						co_return;
					});

			// Act
			auto asyncOp = m_Service->DeleteKeyAsync(testTag);
			asyncOp.get();

			// Assert
			// Again, the mock verification ensures correctness.
		}

		TEST_F(BiometricCipherServiceTest, EncryptAsync_ThrowsIfDataToSignEmpty)
		{
			// Arrange
			m_ConfigData.dataToSign = "";
			EXPECT_CALL(*m_ConfigStorage, getIsConfigured())
				.Times(1)
				.WillOnce(testing::Return(false));

			// Act & Assert
			EXPECT_THROW(
				m_Service->EncryptAsync("testTag", "someData").get(),
				winrt::hresult_error
			);
		}

		TEST_F(BiometricCipherServiceTest, EncryptAsync_ReturnsEncryptedString)
		{
			const std::wstring encryptedString = L"encrypted_base64_string";

			m_ConfigData.dataToSign = "dataToSign";
			EXPECT_CALL(*m_ConfigStorage, getIsConfigured())
				.Times(1)
				.WillOnce(testing::Return(true));

			EXPECT_CALL(*m_ConfigStorage, GetConfig())
				.Times(1)
				.WillOnce(testing::ReturnRef(m_ConfigData));

			// When CreateAESKeyAsync() is called, it calls:
			//   1) SignAsync(hTag, signature)
			//   2) CreateAESKey(signedData)
			// So let's mock them in the repository:

			// 1) Mock SignAsync
			EXPECT_CALL(*m_WindowsHelloRepository, SignAsync)
				.Times(1)
				.WillOnce([](auto, auto) -> IAsyncOperation<IBuffer>
					{
						// Return some fake IBuffer
						co_return nullptr; 
					}
				);

			// 2) Mock CreateAESKey
			CryptographicKey fakeAesKey = nullptr;
			EXPECT_CALL(*m_WinrtEncryptRepository, CreateAESKey)
				.Times(1)
				.WillOnce([&](auto)
					{
						return fakeAesKey;
					}
				);

			// Finally, mock the Encrypt call
			// Suppose the repository's Encrypt returns an encrypted base64 string
			EXPECT_CALL(*m_WinrtEncryptRepository, Encrypt)
				.Times(1)
				.WillOnce([&](auto, auto)
					{
						return winrt::to_hstring(encryptedString.c_str());
					}
				);

			auto asyncOp = m_Service->EncryptAsync("testTag", "someData");
			auto result = asyncOp.get();

			// Assert
			std::wstring resultW(result.c_str());
			EXPECT_EQ(resultW, encryptedString);
		}

		TEST_F(BiometricCipherServiceTest, DecryptAsync_ReturnsDecryptedString)
		{
			const std::wstring decryptedString = L"decrypted_plaintext";

			m_ConfigData.dataToSign = "dataToSign";
			EXPECT_CALL(*m_ConfigStorage, getIsConfigured())
				.Times(1)
				.WillOnce(testing::Return(true));

			EXPECT_CALL(*m_ConfigStorage, GetConfig())
				.Times(1)
				.WillOnce(testing::ReturnRef(m_ConfigData));

			// Mock the same interactions as encryption: SignAsync & CreateAESKey
			EXPECT_CALL(*m_WindowsHelloRepository, SignAsync)
				.Times(1)
				.WillOnce([](auto, auto)-> IAsyncOperation<IBuffer>
					{
						co_return nullptr;
					}
				);
			CryptographicKey fakeAesKey = nullptr;
			EXPECT_CALL(*m_WinrtEncryptRepository, CreateAESKey)
				.Times(1)
				.WillOnce([&](auto)
					{
						return fakeAesKey;
					}
				);
			// Mock the Decrypt call
			EXPECT_CALL(*m_WinrtEncryptRepository, Decrypt)
				.Times(1)
				.WillOnce([&](auto, auto)
					{
						return winrt::to_hstring(decryptedString.c_str());
					}
				);

			// Act
			auto asyncOp = m_Service->DecryptAsync("tag", "ciphertext_data");
			auto result = asyncOp.get();

			// Assert
			std::wstring resultW(result.c_str());
			EXPECT_EQ(resultW, decryptedString);
		}
	}  // namespace test
}  // namespace biometric_cipher
