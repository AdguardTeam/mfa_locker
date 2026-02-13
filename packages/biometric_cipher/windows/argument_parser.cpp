#include "include/biometric_cipher/common/argument_parser.h"
#include "include/biometric_cipher/common/string_util.h"

#include <sstream>
#include <winrt/base.h>


using namespace winrt;
using namespace winrt::impl;

using biometric_cipher::ArgumentParser;
using biometric_cipher::ParsedArguments;
using biometric_cipher::GetArgumentName;

namespace biometric_cipher
{
	std::unordered_map<ArgumentName, ParsedArguments>
		ArgumentParser::Parse(const MethodName methodName, const flutter::EncodableValue* args) const
	{
		std::unordered_map<ArgumentName, ParsedArguments> result;

		if (args == nullptr) {
			throw hresult_error(error_invalid_argument, L"Arguments are null.");
		}

		const auto* argumentMap = std::get_if<flutter::EncodableMap>(args);
		if (argumentMap == nullptr) {
			throw hresult_error(error_invalid_argument, L"Arguments must be a map.");
		}

		switch (methodName)
		{
		case MethodName::kEncrypt:
		case MethodName::kDecrypt:
			result[ArgumentName::kTag] = FetchAndValidateArgument(*argumentMap, ArgumentName::kTag);
			result[ArgumentName::kData] = FetchAndValidateArgument(*argumentMap, ArgumentName::kData);
			break;


		case MethodName::kGenerateKey:
		case MethodName::kDeleteKey:
			result[ArgumentName::kTag] = FetchAndValidateArgument(*argumentMap, ArgumentName::kTag);
			break;

		case MethodName::kConfigure:
			result[ArgumentName::kWindowsDataToSign] = FetchAndValidateArgument(*argumentMap, ArgumentName::kWindowsDataToSign);
			break;

		default:
			throw hresult_error(error_invalid_argument, L"Not implemented method name");
		}

		return result;
	}

	ParsedArguments ArgumentParser::FetchAndValidateArgument(const flutter::EncodableMap& argumentMap, ArgumentName argumentName)
	{
		ParsedArguments argument;

		auto argName = GetArgumentName(argumentName);
		auto it = argumentMap.find(flutter::EncodableValue(argName));
		if (it == argumentMap.end()) {
			auto message = CreateMissingArgumentMessage(argName);
			throw hresult_error(error_invalid_argument, message.c_str());			
		}
		if (const auto* argStr = std::get_if<std::string>(&it->second)) {
			argument.stringArgument = *argStr;
		}
		else {
			auto message = CreateMissingArgumentMessage(argName);
			throw hresult_error(error_invalid_argument, message.c_str());
		}

		return argument;
	}

	std::wstring ArgumentParser::CreateMissingArgumentMessage(const std::string& argName)
	{
		std::wostringstream woss;
		auto message = StringUtil::ConvertStringToWideString(argName);
		woss << L"Argument " << message << L" is missing.";

		return woss.str();
	}

	std::wstring ArgumentParser::CreateMissingArgumentTypeMessage(const std::string& argName)
	{
		std::wostringstream woss;
		auto message = StringUtil::ConvertStringToWideString(argName);
		woss << L"Argument " << message << L" must be a string.";

		return woss.str();
	}
}
