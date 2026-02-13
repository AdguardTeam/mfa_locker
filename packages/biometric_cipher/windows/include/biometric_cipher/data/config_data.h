#pragma once

#include <string>

namespace biometric_cipher
{
	struct ConfigData {
		std::string dataToSign;
		
		ConfigData() : dataToSign("") {}
		ConfigData(const std::string& dataToSign) : dataToSign(dataToSign) {}
	};
}
