#include "include/biometric_cipher/enums/argument_name.h"

#include <unordered_map>
#include <winrt/base.h>

using namespace winrt;
using namespace winrt::impl;

using biometric_cipher::ArgumentName;

namespace biometric_cipher {
	const std::string biometric_cipher::GetArgumentName(ArgumentName argumentName)
	{
		switch (argumentName)
		{
		case ArgumentName::kTag:
			return "tag";

		case ArgumentName::kData:
			return "data";

		case ArgumentName::kWindowsDataToSign:
			return "windowsDataToSign";

		default:
			throw hresult_error(error_invalid_argument, L"Invalid argument name");
		}
	}
}
