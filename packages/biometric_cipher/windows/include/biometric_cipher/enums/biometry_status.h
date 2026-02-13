#pragma once

namespace biometric_cipher
{
	enum class BiometryStatus : int
	{
		kSupported = 0,
		kUnsupported = 1,
		kDeviceNotPresent = 2,
		kNotConfiguredForUser = 3,
		kDisabledByPolicy = 4,
		kDeviceBusy = 5,
		kAndroidBiometricErrorSecurityUpdateRequired = 6,
	};

	const int BiometryStatusToInteger(BiometryStatus biometryStatus);

	const BiometryStatus IntegerToBiometryStatus(int value);
} // namespace biometric_cipher
