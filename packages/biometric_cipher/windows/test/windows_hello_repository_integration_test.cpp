#include <gtest/gtest.h>

#include "include/biometric_cipher/repositories/windows_hello_repository_impl.h"
#include "include/biometric_cipher/enums/tpm_status.h"

namespace biometric_cipher
{
	namespace test {
		class WindowsHelloRepositoryIntegrationTest : public ::testing::Test {
		protected:
			// The real object under test
			WindowsHelloRepositoryImpl m_Repository;
		};

		// Example: Check if Windows Hello is supported on this machine.
		// This test will likely PASS on a system configured with Windows Hello.
		// It may fail on a system that doesn't have Windows Hello set up.
		TEST_F(WindowsHelloRepositoryIntegrationTest, GetWindowsHelloStatusAsync_Supported) {
			try {
				// Call the real method
				auto asyncOp = m_Repository.GetWindowsHelloStatusAsync();
				auto status = asyncOp.get();

				// If your TpmStatus::kSupported => 0, or some other code, check accordingly.
				// Here we just print it out for demonstration.
				std::cout << "Windows Hello status: " << static_cast<int>( status ) << std::endl;

				EXPECT_EQ(status, TpmStatusToInteger(TpmStatus::kSupported)) << "Expected Windows Hello to be supported";

			}
			catch (const winrt::hresult_error & ex) {
				ADD_FAILURE() << "Exception thrown: " << winrt::to_string(ex.message());
			}
		}

		// WARNING: This might prompt user interaction or fail if your system 
		// already has credentials with the same tag, etc.
		// This test requires user interaction. (Windows Hello PIN, etc.) 
		// It's disabled by default. For manual testing only. (Remove DISABLED_ to enable or run whit flag `--gtest_also_run_disabled_tests`) 
		TEST_F(WindowsHelloRepositoryIntegrationTest, DISABLED_CreateAndDeleteCredential_SmokeTest) {
			try {
				winrt::hstring tag = L"integration_test_tag";

				// Create a credential
				auto createOp = m_Repository.CreateCredentialAsync(tag);
				createOp.get();
				std::cout << "Credential created successfully." << std::endl;

				// Delete the credential
				auto deleteOp = m_Repository.DeleteCredentialAsync(tag);
				deleteOp.get();
				std::cout << "Credential deleted successfully." << std::endl;

				// If we got here, the test passed.
				SUCCEED() << "Credential deleted successfully.";
			}
			catch (const winrt::hresult_error & ex) {
				ADD_FAILURE() << "Exception thrown: " << winrt::to_string(ex.message());
			}
		}
	}
}
