#pragma once

#include <string>

namespace biometric_cipher
{
	struct WindowsTpmRepository
	{
		virtual ~WindowsTpmRepository() = default;

		virtual int GetWindowsTpmVersion() const = 0;
	};
}  // namespace biometric_cipher
