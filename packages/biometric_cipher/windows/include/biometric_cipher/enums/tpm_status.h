#pragma once

namespace biometric_cipher
{
	enum class TpmStatus: int
	{
		kSupported = 0,
		kUnsupported = 1,
		kTPMVersionUnsupported = 2,
	};

	const int TpmStatusToInteger(TpmStatus tmpStatus);

	const TpmStatus IntegerToTpmStatus(int value);
}
