#pragma once

#include <winrt/base.h>
#include <winrt/windows.foundation.h>
#include <winrt/windows.security.credentials.h>
#include <winrt/windows.security.cryptography.core.h>
#include <winrt/windows.storage.streams.h>

namespace secure_mnemonic
{
	struct WindowsHelloRepository
	{
		virtual winrt::Windows::Foundation::IAsyncOperation<int> GetWindowsHelloStatusAsync() const = 0;

		virtual winrt::Windows::Foundation::IAsyncOperation<winrt::Windows::Storage::Streams::IBuffer> SignAsync(
			const winrt::hstring tag,
			const winrt::Windows::Storage::Streams::IBuffer data) const = 0;

		virtual winrt::Windows::Foundation::IAsyncAction CreateCredentialAsync(const winrt::hstring tag) const = 0;

		virtual winrt::Windows::Foundation::IAsyncAction DeleteCredentialAsync(const winrt::hstring tag) const = 0;
	};
}
