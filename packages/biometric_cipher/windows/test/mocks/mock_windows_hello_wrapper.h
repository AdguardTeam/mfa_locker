#pragma once

#include <gmock/gmock.h>

#include "include/biometric_cipher/wrappers/windows_hello_wrapper.h"

namespace biometric_cipher {
	namespace test {

        using namespace winrt;
        using namespace winrt::impl;
        using namespace Windows::Foundation;
        using namespace Windows::Security::Cryptography;
        using namespace Windows::Security::Cryptography::Core;
        using namespace Windows::Security::Credentials;
        using namespace Windows::Storage::Streams;
        using namespace Windows::Security::Credentials::UI;

		class MockWindowsHelloWrapper : public WindowsHelloWrapper {
		public:
            MOCK_METHOD(
                (IAsyncOperation<bool>),
                IsSupportedAsync, 
                (), 
                (const, override)
            );

            MOCK_METHOD(
                (IAsyncOperation<UserConsentVerifierAvailability>),
                CheckAvailabilityAsync,
                (),
                (const, override)
            );

            MOCK_METHOD(
                (IAsyncOperation<KeyCredentialRetrievalResult>),
                OpenAsync,
                ((const winrt::hstring)), 
                (const, override)
            );

            MOCK_METHOD(
                (IAsyncOperation<KeyCredentialRetrievalResult>),
                RequestCreateAsync,
                ((const winrt::hstring), KeyCredentialCreationOption),
                (const, override)
            );

            MOCK_METHOD(
                IAsyncAction,
                DeleteAsync,
                ((const winrt::hstring)),
                (const, override)
            );
		};
	}
}
