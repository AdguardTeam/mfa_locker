#pragma once

#include "include/secure_mnemonic/wrappers/windows_hello_wrapper.h"

namespace secure_mnemonic {
	class WindowsHelloWrapperImpl : public WindowsHelloWrapper {
	public:
        winrt::Windows::Foundation::IAsyncOperation<bool> IsSupportedAsync() const override
        {
            co_return co_await winrt::Windows::Security::Credentials::KeyCredentialManager::IsSupportedAsync();
        }

        winrt::Windows::Foundation::IAsyncOperation<winrt::Windows::Security::Credentials::UI::UserConsentVerifierAvailability>
            CheckAvailabilityAsync() const override
        {
            co_return co_await winrt::Windows::Security::Credentials::UI::UserConsentVerifier::CheckAvailabilityAsync();
        }

        winrt::Windows::Foundation::IAsyncOperation<winrt::Windows::Security::Credentials::KeyCredentialRetrievalResult>
            OpenAsync(const winrt::hstring tag) const override
        {
            co_return co_await winrt::Windows::Security::Credentials::KeyCredentialManager::OpenAsync(tag);
        }

        winrt::Windows::Foundation::IAsyncOperation<winrt::Windows::Security::Credentials::KeyCredentialRetrievalResult>
            RequestCreateAsync(
                const winrt::hstring tag,
                winrt::Windows::Security::Credentials::KeyCredentialCreationOption option
            ) const override
        {
            co_return co_await winrt::Windows::Security::Credentials::KeyCredentialManager::RequestCreateAsync(tag, option);
        }

        winrt::Windows::Foundation::IAsyncAction DeleteAsync(const winrt::hstring tag) const override
        {
            co_await winrt::Windows::Security::Credentials::KeyCredentialManager::DeleteAsync(tag);
        }
    };
}
