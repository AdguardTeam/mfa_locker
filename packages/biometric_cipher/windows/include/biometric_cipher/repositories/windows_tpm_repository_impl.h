#pragma once

#include "include/biometric_cipher/repositories/windows_tpm_repository.h"
#include "include/biometric_cipher/wrappers/ncrypt_wrapper_impl.h"

#include <string>
#include <memory>

namespace biometric_cipher
{
	class WindowsTpmRepositoryImpl : public WindowsTpmRepository
	{
	public:
		explicit WindowsTpmRepositoryImpl(std::shared_ptr<NCryptWrapper> ncrypWrapper = nullptr)
			: m_NCryptWrapper(ncrypWrapper ? ncrypWrapper : std::make_shared<NCryptWrapperImpl>()) {}

		int GetWindowsTpmVersion() const override;

	private:
		static void CheckStatus(const winrt::hresult hr, const std::wstring& message, const int errorCode);

		static const std::wstring ParsePlatformType(const std::wstring& platformVersion);

		std::shared_ptr<NCryptWrapper> m_NCryptWrapper;
	};
}  // namespace biometric_cipher
