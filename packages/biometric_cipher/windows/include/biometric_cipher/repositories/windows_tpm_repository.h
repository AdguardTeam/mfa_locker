#pragma once

#include <string>
#include <vector>

namespace biometric_cipher
{
	struct TpmKeyInfo
	{
		std::string name;
		std::string algorithm;
	};

	struct WindowsTpmRepository
	{
		virtual ~WindowsTpmRepository() = default;

		virtual int GetWindowsTpmVersion() const = 0;

		virtual std::vector<TpmKeyInfo> ListTpmKeys() const = 0;
	};
}  // namespace biometric_cipher
