#pragma once

#include "include/secure_mnemonic/enums/argument_name.h"
#include "include/secure_mnemonic/enums/method_name.h"

#include <flutter/encodable_value.h>
#include <string>
#include <exception>
#include <unordered_map>

namespace secure_mnemonic {
	struct ParsedArguments {
		std::string stringArgument;
	};

	class ArgumentParser {
	public: 
		std::unordered_map<ArgumentName, ParsedArguments>
			Parse(const MethodName methodName, const flutter::EncodableValue* args) const;

	private:
		static ParsedArguments FetchAndValidateArgument(const flutter::EncodableMap& argumentMap, secure_mnemonic::ArgumentName argumentName);

		static std::wstring CreateMissingArgumentMessage(const std::string& argName);

		static std::wstring CreateMissingArgumentTypeMessage(const std::string& argName);
	};
}
