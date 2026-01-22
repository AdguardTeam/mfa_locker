#pragma once

#include <gmock/gmock.h>

#include "include/secure_mnemonic/repositories/windows_tpm_repository.h"

namespace secure_mnemonic {
	namespace test {
		class MockWindowsTpmRepository : public WindowsTpmRepository {
		public:
			MOCK_METHOD(int, GetWindowsTpmVersion, (), (const, override));
		};
	}
}
