#pragma once

#include <string>

namespace biometric_cipher {

	enum class MethodName {
		kGetTPMStatus,
		kGetTPMVersion,
		kListKeys,
		kGetBiometryStatus,
		kGenerateKey,
		kEncrypt,
		kDecrypt,
		kDeleteKey,
		kConfigure,
		kIsKeyValid,
		kNotImplemented,
	};

	MethodName GetMethodName(const std::string& methodName);
}
