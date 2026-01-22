#pragma once

#include <string>

namespace secure_mnemonic
{
	struct WindowsTpmRepository
	{
		virtual ~WindowsTpmRepository() = default;

		virtual int GetWindowsTpmVersion() const = 0;
	};
}  // namespace secure_mnemonic
