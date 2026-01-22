#include "include/secure_mnemonic/enums/tpm_status.h"

#include <winrt/base.h>

namespace secure_mnemonic
{
	const int TpmStatusToInteger(TpmStatus tmpStatus) {
		return static_cast<int>(tmpStatus);
	}

	const TpmStatus IntegerToTpmStatus(int value) {
		constexpr int kMinValue = static_cast<int>(TpmStatus::kSupported);
		constexpr int kMaxValue = static_cast<int>(TpmStatus::kTPMVersionUnsupported);

		if (value < kMinValue || value > kMaxValue) {
			throw winrt::hresult_error(winrt::impl::error_invalid_argument, L"Invalid TPM status value");
		}

		return static_cast<TpmStatus>(value);
	}
} // namespace secure_mnemonic
