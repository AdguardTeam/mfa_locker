#pragma once

#include "include/biometric_cipher/data/config_data.h"

namespace biometric_cipher {

	class ConfigStorage
	{
	public:
		virtual bool getIsConfigured() const;
		virtual void SetConfigData(const ConfigData& configData);
		virtual const ConfigData& GetConfig() const;

	private:
		bool m_isConfigured = false;
		ConfigData m_ConfigData;
	};
}
