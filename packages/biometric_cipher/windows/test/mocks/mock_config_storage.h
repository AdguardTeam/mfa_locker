#pragma once

#include <gmock/gmock.h>

#include "include/biometric_cipher/storages/config_storage.h"

namespace biometric_cipher {
	namespace test {
		class MockConfigStorage : public ConfigStorage {
		public:
			MOCK_METHOD(bool, getIsConfigured, (), (const, override));
			MOCK_METHOD(void, SetConfigData, (const ConfigData& configData), (override));
			MOCK_METHOD(const ConfigData&, GetConfig, (), (const, override));
		};
	}
}
