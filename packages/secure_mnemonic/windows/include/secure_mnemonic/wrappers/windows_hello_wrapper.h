#pragma once

#include <winrt/Windows.Security.Credentials.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/Windows.Security.Credentials.UI.h>

namespace secure_mnemonic {
	struct WindowsHelloWrapper {
		virtual ~WindowsHelloWrapper() = default;

        // Corresponds to KeyCredentialManager::IsSupportedAsync()
        virtual winrt::Windows::Foundation::IAsyncOperation<bool> IsSupportedAsync() const = 0;

        // Corresponds to UserConsentVerifier::CheckAvailabilityAsync()
        virtual winrt::Windows::Foundation::IAsyncOperation<winrt::Windows::Security::Credentials::UI::UserConsentVerifierAvailability>
            CheckAvailabilityAsync() const = 0;

        // Corresponds to KeyCredentialManager::OpenAsync(...)
        virtual winrt::Windows::Foundation::IAsyncOperation<winrt::Windows::Security::Credentials::KeyCredentialRetrievalResult>
            OpenAsync(const winrt::hstring tag) const = 0;

        // Corresponds to KeyCredentialManager::RequestCreateAsync(...)
        virtual winrt::Windows::Foundation::IAsyncOperation<winrt::Windows::Security::Credentials::KeyCredentialRetrievalResult>
            RequestCreateAsync(const winrt::hstring tag,
                winrt::Windows::Security::Credentials::KeyCredentialCreationOption option) const = 0;

        // Corresponds to KeyCredentialManager::DeleteAsync(...)
        virtual winrt::Windows::Foundation::IAsyncAction DeleteAsync(const winrt::hstring tag) const = 0;
    };
}
