#pragma once

#include "include/secure_mnemonic/data/config_data.h"

namespace secure_mnemonic {

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
