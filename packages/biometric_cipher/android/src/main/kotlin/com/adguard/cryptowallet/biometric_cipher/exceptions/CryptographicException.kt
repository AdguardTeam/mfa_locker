package com.adguard.cryptowallet.biometric_cipher.exceptions

import com.adguard.cryptowallet.biometric_cipher.errors.ErrorType

sealed class CryptographicException(
    code: String,
    message: String,
    cause: Throwable? = null
) : BaseException(code, message, cause) {

    data class KeyAlreadyExists(
        val originCause: Throwable? = null
    ) : CryptographicException(
        code = ErrorType.KEY_ALREADY_EXISTS.name,
        message = ErrorType.KEY_ALREADY_EXISTS.errorDescription,
        cause = originCause
    )

    data class KeyNotFound(
        val originCause: Throwable? = null
    ) : CryptographicException(
        code = ErrorType.KEY_NOT_FOUND.name,
        message = ErrorType.KEY_NOT_FOUND.errorDescription,
        cause = originCause
    )

    data class DecodeDataSizeInvalid(
        val originCause: Throwable? = null
    ) : CryptographicException(
        code = ErrorType.DECODE_DATA_INVALID_SIZE.name,
        message = ErrorType.DECODE_DATA_INVALID_SIZE.errorDescription,
        cause = originCause
    )
}
