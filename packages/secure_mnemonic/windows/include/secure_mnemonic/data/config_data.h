#pragma once

#include <string>

namespace secure_mnemonic
{
	struct ConfigData {
		std::string dataToSign;
		
		ConfigData() : dataToSign("") {}
		ConfigData(const std::string& dataToSign) : dataToSign(dataToSign) {}
	};
}
