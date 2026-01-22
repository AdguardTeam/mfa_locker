#pragma once

#include <string>

namespace secure_mnemonic {

	enum class MethodName {
		kGetTPMStatus,
		kGetBiometryStatus,
		kGenerateKey,
		kEncrypt,
		kDecrypt,
		kDeleteKey,
		kConfigure,
		kNotImplemented,
	};

	MethodName GetMethodName(const std::string& methodName);
}
