#pragma once

#include <windows.h>
#include <ncrypt.h>

#include "include/biometric_cipher/common/memory_deallocation.h"

namespace biometric_cipher
{
	struct NCryptWrapper {
		virtual ~NCryptWrapper() = default;

		virtual SECURITY_STATUS OpenStorageProvider(
			NCryptHandleFree& providerHandle,
			LPCWSTR pszProviderName,
			DWORD dwFlags
		) const = 0;

		virtual SECURITY_STATUS GetProperty(
			NCryptHandleFree const& providerHandle,
			LPCWSTR pszProperty,
			PBYTE pbOutput,
			DWORD cbOutput,
			DWORD * pcbResult,
			DWORD dwFlags
		) const = 0;
	};
}
