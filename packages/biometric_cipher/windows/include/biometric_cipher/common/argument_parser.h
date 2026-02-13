#pragma once

#include "include/biometric_cipher/enums/argument_name.h"
#include "include/biometric_cipher/enums/method_name.h"

#include <flutter/encodable_value.h>
#include <string>
#include <exception>
#include <unordered_map>

namespace biometric_cipher {
	struct ParsedArguments {
		std::string stringArgument;
	};

	class ArgumentParser {
	public: 
		std::unordered_map<ArgumentName, ParsedArguments>
			Parse(const MethodName methodName, const flutter::EncodableValue* args) const;

	private:
		static ParsedArguments FetchAndValidateArgument(const flutter::EncodableMap& argumentMap, biometric_cipher::ArgumentName argumentName);

		static std::wstring CreateMissingArgumentMessage(const std::string& argName);

		static std::wstring CreateMissingArgumentTypeMessage(const std::string& argName);
	};
}
