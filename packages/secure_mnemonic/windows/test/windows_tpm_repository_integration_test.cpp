#include <gtest/gtest.h>

#include <winrt/base.h>

#include "include/secure_mnemonic/repositories/windows_tpm_repository_impl.h"

namespace secure_mnemonic {
	namespace test {
		class WindowsTpmRepositoryIntegrationTest : public ::testing::Test {
		protected:
			WindowsTpmRepositoryImpl m_Repository;
		};

		// Example test that calls the actual system's TPM provider
		TEST_F(WindowsTpmRepositoryIntegrationTest, GetWindowsTpmVersion_SanityCheck) {
			// This test will pass only if you're running on a system that actually
			// supports MS_PLATFORM_CRYPTO_PROVIDER and has a valid TPM version string.
			try {
				auto version = m_Repository.GetWindowsTpmVersion();

				// Typical valid TPM versions are '1' or '2'. 
				// We'll just check for a non-zero or > 0 value.
				// Adjust expectations as appropriate for your environment.
				EXPECT_GE(version, 1) << "Expected TPM version >= 1";
			}
			catch (const winrt::hresult_error &e) {
				// If your system doesn't have TPM or if something else went wrong,
				// you can check the exception message, but typically you'd fail the test.
				ADD_FAILURE() << L"TpmRepositoryException thrown: " << e.message().c_str();
			}
		}
	} // namespace test
}  // namespace secure_mnemonic
