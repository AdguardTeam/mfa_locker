#pragma once

#include <string>

namespace secure_mnemonic {

	enum class ArgumentName {
		kTag,
		kData,
		kWindowsDataToSign,
	};

	const std::string GetArgumentName(ArgumentName methodName);
}
