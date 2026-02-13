#include "include/biometric_cipher/common/string_util.h"
#include "include/biometric_cipher/errors/error_codes.h"

#include <windows.h>
#include <wincrypt.h>

using namespace winrt;
using namespace winrt::impl;

namespace biometric_cipher 
{
	std::string StringUtil::ConvertWideStringToString(const std::wstring& wideString)
	{
		if (wideString.empty())
		{
			return std::string();
		}

		auto size_needed = WideCharToMultiByte(CP_UTF8, 0, wideString.c_str(), (int)wideString.size(), nullptr, 0, nullptr, nullptr);
		if (size_needed == 0) {
			throw hresult_error(error_converting_string, L"WideCharToMultiByte failed to calculate size.");
		}

		std::string strTo(size_needed, 0);
		auto bytes_written = WideCharToMultiByte(CP_UTF8, 0, wideString.c_str(), (int)wideString.size(), strTo.data(), size_needed, nullptr, nullptr);
		if (bytes_written == 0) {
			throw hresult_error(error_converting_string, L"WideCharToMultiByte failed to convert.");
		}

		return strTo;
	}

	std::wstring StringUtil::ConvertStringToWideString(const std::string& string)
	{
		if (string.empty())
		{
			return std::wstring();
		}

		auto size_needed = MultiByteToWideChar(CP_UTF8, 0, string.c_str(), (int)string.size(), nullptr, 0);
		if (size_needed == 0) {
			throw hresult_error(error_converting_string, L"MultiByteToWideChar failed to calculate size.");
		}

		std::wstring wstrTo(size_needed, 0);
		auto bytes_written = MultiByteToWideChar(CP_UTF8, 0, string.c_str(), (int)string.size(), wstrTo.data(), size_needed);
		if (bytes_written == 0) {
			throw hresult_error(error_converting_string, L"MultiByteToWideChar failed to convert.");
		}

		return wstrTo;
	}

	std::string StringUtil::ConvertHStringToString(const winrt::hstring& hstring)
	{
		if (hstring.empty())
		{
			return std::string();
		}

		auto size_needed = WideCharToMultiByte(CP_UTF8, 0, hstring.c_str(), (int)hstring.size(), nullptr, 0, nullptr, nullptr);
		if (size_needed == 0) {
			throw hresult_error(error_converting_string, L"WideCharToMultiByte failed to calculate size.");
		}

		std::string strTo(size_needed, 0);
		auto bytes_written = WideCharToMultiByte(CP_UTF8, 0, hstring.c_str(), (int)hstring.size(), strTo.data(), size_needed, nullptr, nullptr);
		if (bytes_written == 0) {
			throw hresult_error(error_converting_string, L"WideCharToMultiByte failed to convert.");
		}

		return strTo;
	}

	winrt::hstring StringUtil::ConvertStringToHString(const std::string& string) 
	{
		return winrt::to_hstring(string);
	}
}
