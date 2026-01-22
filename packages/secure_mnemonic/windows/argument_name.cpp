#include "include/secure_mnemonic/enums/argument_name.h"

#include <unordered_map>
#include <winrt/base.h>

using namespace winrt;
using namespace winrt::impl;

using secure_mnemonic::ArgumentName;

namespace secure_mnemonic {
	const std::string secure_mnemonic::GetArgumentName(ArgumentName argumentName)
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
