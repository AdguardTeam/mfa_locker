#pragma once

#include <string>
#include <winrt/base.h>

namespace winrt::impl 
{
	inline constexpr hresult error_tpm_unsupported{ static_cast<hresult>(0xA0082001) };
    inline constexpr hresult error_tpm_version{ static_cast<hresult>(0xA0082002) };
    inline constexpr hresult error_biometry_not_supported{ static_cast<hresult>(0xA0082003) };
    inline constexpr hresult error_configure{ static_cast<hresult>(0xA0082004) };
    inline constexpr hresult error_generate_key{ static_cast<hresult>(0xA0082005) };
	inline constexpr hresult error_key_not_found{ static_cast<hresult>(0xA0082006) };
    inline constexpr hresult error_key_already_exists{ static_cast<hresult>(0xA0082007) };
    inline constexpr hresult error_delete_key{ static_cast<hresult>(0xA0082008) };
    inline constexpr hresult error_encrypt{ static_cast<hresult>(0xA0082009) };
    inline constexpr hresult error_decrypt{ static_cast<hresult>(0xA008200A) };
    inline constexpr hresult error_authentication_canceled{ static_cast<hresult>(0xA008200B) };
    inline constexpr hresult error_user_prefers_password{ static_cast<hresult>(0xA008200C) };
	inline constexpr hresult error_secure_device_locked{ static_cast<hresult>(0xA008200D) };    
	inline constexpr hresult error_converting_string{ static_cast<hresult>(0xA008200E) };
}

namespace biometric_cipher {
	const std::string GetErrorCodeString(winrt::hresult hr);
}
