#include "include/secure_mnemonic/errors/error_codes.h"

using namespace winrt;
using namespace winrt::impl;

const std::string secure_mnemonic::GetErrorCodeString(hresult hr)
{
	switch (hr)
	{
	case error_tpm_unsupported:
		return "TPM_UNSUPPORTED";

	case error_tpm_version:
		return "TPM_VERSION_ERROR";

	case error_biometry_not_supported:
		return "BIOMETRY_NOT_SUPPORTED";

	case error_configure:
		return "CONFIGURE_ERROR";

	case error_generate_key:
		return "GENERATE_KEY_ERROR";

	case error_key_not_found:
		return "KEY_NOT_FOUND";

	case error_key_already_exists:
		return "KEY_ALREADY_EXISTS";

	case error_delete_key:
		return "DELETE_KEY_ERROR";

	case error_encrypt:
		return "ENCRYPT_ERROR";

	case error_decrypt:
		return "DECRYPT_ERROR";

	case error_authentication_canceled:
		return "AUTHENTICATION_USER_CANCELED";

	case error_user_prefers_password:
		return "USER_PREFERS_PASSWORD";

	case error_secure_device_locked:
		return "SECURE_DEVICE_LOCKED";

	case error_converting_string:
		return "CONVERTING_STRING_ERROR";

	default:
		return "UNKNOWN_ERROR";
	}
}
