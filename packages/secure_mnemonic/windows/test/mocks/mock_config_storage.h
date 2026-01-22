#pragma once

#include <gmock/gmock.h>

#include "include/secure_mnemonic/storages/config_storage.h"

namespace secure_mnemonic {
	namespace test {
		class MockConfigStorage : public ConfigStorage {
		public:
			MOCK_METHOD(bool, getIsConfigured, (), (const, override));
			MOCK_METHOD(void, SetConfigData, (const ConfigData& configData), (override));
			MOCK_METHOD(const ConfigData&, GetConfig, (), (const, override));
		};
	}
}
