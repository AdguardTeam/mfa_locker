#pragma once

#include "include/biometric_cipher/wrappers/ncrypt_wrapper.h"

namespace biometric_cipher
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

		SECURITY_STATUS EnumKeys(
			NCryptHandleFree const& providerHandle,
			NCryptKeyName** ppKeyName,
			PVOID* ppEnumState,
			DWORD dwFlags
		) const override
		{
			return NCryptEnumKeys(providerHandle.get(), nullptr, ppKeyName, ppEnumState, dwFlags);
		}

		SECURITY_STATUS FreeBuffer(
			PVOID pvInput
		) const override
		{
			return NCryptFreeBuffer(pvInput);
		}
	};
}
