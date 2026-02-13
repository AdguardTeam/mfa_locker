#pragma once

#include <string>

namespace biometric_cipher {

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
