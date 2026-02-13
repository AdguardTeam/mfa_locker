#include "include/biometric_cipher/enums/biometry_status.h"

#include <winrt/base.h>

namespace biometric_cipher
{
	const int BiometryStatusToInteger(BiometryStatus biometryStatus) {
		return static_cast<int>(biometryStatus);
	}
	const BiometryStatus IntegerToBiometryStatus(int value) {
		constexpr int kMinValue = static_cast<int>(BiometryStatus::kSupported);
		constexpr int kMaxValue = static_cast<int>(BiometryStatus::kAndroidBiometricErrorSecurityUpdateRequired);
		if (value < kMinValue || value > kMaxValue) {
			throw winrt::hresult_error(winrt::impl::error_invalid_argument, L"Invalid biometry status value");
		}
		return static_cast<BiometryStatus>(value);
	}
} // namespace biometric_cipher
