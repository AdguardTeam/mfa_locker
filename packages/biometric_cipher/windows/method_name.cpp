#include "include/biometric_cipher/enums/method_name.h"

#include <unordered_map>
#include <stdexcept>

using biometric_cipher::MethodName;

namespace biometric_cipher {
	const std::unordered_map<std::string, MethodName> METHOD_NAME_MAP = {
		{"getTPMStatus", MethodName::kGetTPMStatus},
		{"getBiometryStatus", MethodName::kGetBiometryStatus},
		{"generateKey", MethodName::kGenerateKey},
		{"encrypt", MethodName::kEncrypt},
		{"decrypt", MethodName::kDecrypt},
		{"deleteKey", MethodName::kDeleteKey},
		{"configure", MethodName::kConfigure},
		{"notImplemented", MethodName::kNotImplemented},
	};

	MethodName GetMethodName(const std::string& methodName)
	{
		auto it = METHOD_NAME_MAP.find(methodName);
		if (it != METHOD_NAME_MAP.end())
		{
			return it->second;
		}
		else {
			return MethodName::kNotImplemented;
		}
	}
}
