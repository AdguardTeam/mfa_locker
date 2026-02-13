#pragma once

#include <string>
#include <winrt/base.h>

namespace biometric_cipher {
	class StringUtil {
	public:
		static std::string ConvertWideStringToString(const std::wstring& wideString);
		static std::wstring ConvertStringToWideString(const std::string& string);
		static std::string ConvertHStringToString(const winrt::hstring& hstring);
		static winrt::hstring ConvertStringToHString(const std::string& string);
	};
}
