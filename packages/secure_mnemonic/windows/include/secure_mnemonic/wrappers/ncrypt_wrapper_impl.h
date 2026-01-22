#pragma once

#include "include/secure_mnemonic/wrappers/ncrypt_wrapper.h"

namespace secure_mnemonic
{
	class NCryptWrapperImpl : public NCryptWrapper
	{
	public:
		virtual ~NCryptWrapperImpl() = default;

		SECURITY_STATUS OpenStorageProvider(
			NCryptHandleFree& providerHandle,
			LPCWSTR pszProviderName,
			DWORD dwFlags
		) const override
		{
			return NCryptOpenStorageProvider(providerHandle.put(), pszProviderName, dwFlags);
		}

		SECURITY_STATUS GetProperty(
			NCryptHandleFree const& providerHandle,
			LPCWSTR pszProperty,
			PBYTE pbOutput,
			DWORD cbOutput,
			DWORD* pcbResult,
			DWORD dwFlags
		) const override
		{
			return NCryptGetProperty(providerHandle.get(), pszProperty, pbOutput, cbOutput, pcbResult, dwFlags);
		}
	};
}
