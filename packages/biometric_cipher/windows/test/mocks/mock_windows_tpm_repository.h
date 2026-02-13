#pragma once

#include <gmock/gmock.h>

#include "include/biometric_cipher/repositories/windows_tpm_repository.h"

namespace biometric_cipher {
	namespace test {
		class MockWindowsTpmRepository : public WindowsTpmRepository {
		public:
			MOCK_METHOD(int, GetWindowsTpmVersion, (), (const, override));
		};
	}
}
