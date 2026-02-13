#pragma once

#include <string>

namespace biometric_cipher {

	enum class ArgumentName {
		kTag,
		kData,
		kWindowsDataToSign,
	};

	const std::string GetArgumentName(ArgumentName methodName);
}
