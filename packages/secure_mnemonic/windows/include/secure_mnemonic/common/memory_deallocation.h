#pragma once

#include <windows.h>
#include <memory>
#include <ncrypt.h>
#include <winrt/windows.foundation.h>
#include <winrt/base.h>

namespace secure_mnemonic
{
	struct NCryptHandleFreeTraits
	{
		using type = NCRYPT_HANDLE;

		static void close(type handle) noexcept
		{
			if (handle != NULL) {
				NCryptFreeObject(handle);
			}
		}
		static constexpr type invalid() noexcept
		{
			return NULL;
		}
	};

	using NCryptHandleFree = winrt::handle_type<NCryptHandleFreeTraits>;
}  // namespace secure_mnemonic
