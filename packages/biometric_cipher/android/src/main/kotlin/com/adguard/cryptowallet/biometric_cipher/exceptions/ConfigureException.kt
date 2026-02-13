package com.adguard.cryptowallet.biometric_cipher.exceptions

import com.adguard.cryptowallet.biometric_cipher.errors.ErrorType

sealed class ConfigureException(
    code: String,
    message: String,
    cause: Throwable? = null
) : BaseException(code, message, cause) {

    data class BiometricPromptNotConfigured(
        val originalCause: Throwable? = null
    ) : CryptographicException(
        code = ErrorType.CONFIGURE_BIOMETRIC_ERROR.name,
        message = ErrorType.CONFIGURE_BIOMETRIC_ERROR.errorDescription,
        cause = originalCause
    )

    data class NegativeButtonNotConfigured(
        val originalCause: Throwable? = null
    ) : CryptographicException(
        code = ErrorType.CONFIGURE_NEGATIVE_BUTTON_ERROR.name,
        message = ErrorType.CONFIGURE_NEGATIVE_BUTTON_ERROR.errorDescription,
        cause = originalCause
    )

    data class TitlePromptNotConfigured(
        val originalCause: Throwable? = null
    ) : CryptographicException(
        code = ErrorType.CONFIGURE_TITLE_PROMPT_ERROR.name,
        message = ErrorType.CONFIGURE_TITLE_PROMPT_ERROR.errorDescription,
        cause = originalCause
    )

    data class SubtitlePromptNotConfigured(
        val originalCause: Throwable? = null
    ) : CryptographicException(
        code = ErrorType.CONFIGURE_SUBTITLE_PROMPT_ERROR.name,
        message = ErrorType.CONFIGURE_SUBTITLE_PROMPT_ERROR.errorDescription,
        cause = originalCause
    )
}
