#include <gtest/gtest.h>
#include <gmock/gmock.h>

#include "include/biometric_cipher/enums/tpm_status.h"
#include "include/biometric_cipher/enums/biometry_status.h"

// Include mock
#include "mocks/mock_windows_hello_wrapper.h"

// Include the code under test
#include "include/biometric_cipher/repositories/windows_hello_repository_impl.h"

namespace biometric_cipher {
	namespace test {

		using namespace biometric_cipher;

		struct FakeKeyCredentialRetrievalResult
			: winrt::implements<FakeKeyCredentialRetrievalResult, KeyCredentialRetrievalResult>
		{
		public:
			// We store the status we want to report.
			KeyCredentialStatus m_status = KeyCredentialStatus::Success;

			// If needed, store a real or fake KeyCredential object. For now, we can return nullptr.
			KeyCredential m_credential{ nullptr };

			// Implement the interface
			KeyCredentialStatus Status() const
			{
				return m_status;
			}

			KeyCredential Credential() const
			{
				return m_credential;
			}
		};

		class WindowsHelloRepositoryTest : public ::testing::Test {
		protected:
			inline IAsyncOperation<bool> MakeCompletedAsyncBool(bool value)
			{
				co_return value;
			}

			inline IAsyncOperation<UserConsentVerifierAvailability>
				MakeCompletedAsyncUserConsent(UserConsentVerifierAvailability value)
			{
				co_return value;
			}

			inline IAsyncOperation<KeyCredentialRetrievalResult>
				MakeCompletedAsyncKeyCredentialResult(KeyCredentialRetrievalResult const& value)
			{
				co_return value;
			}

			inline IAsyncAction MakeCompletedAsyncAction()
			{
				co_return;
			}

			// Shared pointers to mocks
			std::shared_ptr<MockWindowsHelloWrapper> m_mockHelloWrapper;

			// The repository under test
			std::unique_ptr<WindowsHelloRepositoryImpl> m_Repository;

			void SetUp() override
			{
				m_mockHelloWrapper = std::make_shared<MockWindowsHelloWrapper>();
				// Inject the mock into the repository
				m_Repository = std::make_unique<WindowsHelloRepositoryImpl>(m_mockHelloWrapper);
			}

		};

		// Test that `GetWindowsHelloStatusAsync` returns 'kSupported' if `IsSupportedAsync` returns true
		TEST_F(WindowsHelloRepositoryTest, GetWindowsHelloStatusAsync_ReturnsSupportedIfIsSupportedAsyncTrue)
		{
			// Arrange
			EXPECT_CALL(*m_mockHelloWrapper, IsSupportedAsync())
				.Times(1)
				.WillOnce(testing::Return(MakeCompletedAsyncBool(true)));

			// Act
			auto result = m_Repository->GetWindowsHelloStatusAsync().get();

			// Assert
			EXPECT_EQ(result, TpmStatusToInteger(TpmStatus::kSupported));
		}

		// Test that `GetWindowsHelloStatusAsync` checks availability if `IsSupportedAsync` is false
		// Suppose we set the availability to `DeviceNotPresent`
		TEST_F(WindowsHelloRepositoryTest, GetWindowsHelloStatusAsync_ReturnsDeviceNotPresentIfNotSupported)
		{
			// Arrange
			EXPECT_CALL(*m_mockHelloWrapper, IsSupportedAsync())
				.Times(1)
				.WillOnce(testing::Return(MakeCompletedAsyncBool(false)));

			EXPECT_CALL(*m_mockHelloWrapper, CheckAvailabilityAsync())
				.Times(1)
				.WillOnce(
					testing::Return(
					MakeCompletedAsyncUserConsent(UserConsentVerifierAvailability::DeviceNotPresent)
					)
				);

			// Act
			auto result = m_Repository->GetWindowsHelloStatusAsync().get();

			// Assert
			EXPECT_EQ(result, BiometryStatusToInteger(BiometryStatus::kDeviceNotPresent));
		}

		// Test that `CreateCredentialAsync` calls `RequestCreateAsync` on the wrapper and succeeds.
		TEST_F(WindowsHelloRepositoryTest, CreateCredentialAsync_CallsWrapperRequestCreateAsync)
		{
			auto fakeResult = winrt::make<FakeKeyCredentialRetrievalResult>();
			fakeResult.as<FakeKeyCredentialRetrievalResult>()->m_status = KeyCredentialStatus::Success;

			// Arrange
			EXPECT_CALL(*m_mockHelloWrapper, IsSupportedAsync())
				.Times(1)
				.WillOnce(testing::Return(MakeCompletedAsyncBool(true)));

			EXPECT_CALL(*m_mockHelloWrapper, RequestCreateAsync)
				.Times(1)
				.WillOnce(testing::Return(MakeCompletedAsyncKeyCredentialResult(fakeResult.as<KeyCredentialRetrievalResult>())));

			// Act
			// WindowsHelloRepositoryImpl::CreateCredentialAsync co_awaits -> no direct result
			m_Repository->CreateCredentialAsync(L"myCredential").get();

			// If no exception is thrown, we consider it a pass
			SUCCEED();
		}

		// Test that if the KeyCredentialStatus is NotFound in SignAsync, we throw an exception
		TEST_F(WindowsHelloRepositoryTest, SignAsync_ThrowsIfKeyCredentialNotFound)
		{
			auto fakeResult = winrt::make<FakeKeyCredentialRetrievalResult>();
			fakeResult.as<FakeKeyCredentialRetrievalResult>()->m_status = KeyCredentialStatus::NotFound;

			// Arrange
			EXPECT_CALL(*m_mockHelloWrapper, IsSupportedAsync())
				.WillOnce(testing::Return(MakeCompletedAsyncBool(true)));

			EXPECT_CALL(*m_mockHelloWrapper, OpenAsync)
				.WillOnce(testing::Return(MakeCompletedAsyncKeyCredentialResult(fakeResult.as<KeyCredentialRetrievalResult>())));

			// Act & Assert
			EXPECT_THROW(
				{
					m_Repository->SignAsync(L"nonexistent", nullptr).get();
				},
				winrt::hresult_error);
		}
	}
}
