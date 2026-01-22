#pragma once

namespace secure_mnemonic
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
