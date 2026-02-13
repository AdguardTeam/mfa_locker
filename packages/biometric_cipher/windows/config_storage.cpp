#include "include/biometric_cipher/storages/config_storage.h"
#include "include/biometric_cipher/errors/error_codes.h"

#include <winrt/base.h>

using namespace winrt;
using namespace winrt::impl;

namespace biometric_cipher
{
	const ConfigData& ConfigStorage::GetConfig() const
	{
		return m_ConfigData;
	}

	bool ConfigStorage::getIsConfigured() const
	{
		return m_isConfigured;
	}

	void ConfigStorage::SetConfigData(const ConfigData& configData)
	{
		m_isConfigured = false;
		if (configData.dataToSign.empty()) {
			throw hresult_error(error_configure, L"Field 'dataToSign' can't be empty");
		}

		m_ConfigData = configData;
		m_isConfigured = true;
	}
}
