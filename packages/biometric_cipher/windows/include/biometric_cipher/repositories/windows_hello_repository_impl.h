#pragma once

#include "include/biometric_cipher/repositories/windows_hello_repository.h"
#include "include/biometric_cipher/wrappers/windows_hello_wrapper_impl.h"

#include <memory>
#include <winrt/base.h>
#include <winrt/windows.foundation.h>
#include <winrt/windows.security.credentials.h>
#include <winrt/windows.security.cryptography.core.h>
#include <winrt/windows.storage.streams.h>

namespace biometric_cipher
{
	class WindowsHelloRepositoryImpl : public WindowsHelloRepository
	{
	public:
		explicit WindowsHelloRepositoryImpl(std::shared_ptr<WindowsHelloWrapper> helloWrapper = nullptr)
			: m_HelloWrapper(helloWrapper ? helloWrapper : std::make_shared<WindowsHelloWrapperImpl>()) { }

		winrt::Windows::Foundation::IAsyncOperation<int> GetWindowsHelloStatusAsync() const override;

		winrt::Windows::Foundation::IAsyncOperation<winrt::Windows::Storage::Streams::IBuffer> SignAsync(
			const winrt::hstring tag,
			const winrt::Windows::Storage::Streams::IBuffer data) const override;

		winrt::Windows::Foundation::IAsyncAction CreateCredentialAsync(const winrt::hstring tag) const override;

		winrt::Windows::Foundation::IAsyncAction DeleteCredentialAsync(const winrt::hstring tag) const override;
	private:
		static const uint32_t NONCE_LENGTH = 12;

		static const uint32_t TAG_LENGTH = 16;

		static void CheckKeyCredentialStatus(winrt::Windows::Security::Credentials::KeyCredentialStatus status);

		std::shared_ptr<WindowsHelloWrapper> m_HelloWrapper;

		winrt::Windows::Foundation::IAsyncAction CheckWindowsHelloIsStatusAsync() const;
	};
}
