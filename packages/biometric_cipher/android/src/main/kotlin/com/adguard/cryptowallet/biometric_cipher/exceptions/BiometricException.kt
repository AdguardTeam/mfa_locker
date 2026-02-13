package com.adguard.cryptowallet.biometric_cipher.exceptions

import com.adguard.cryptowallet.biometric_cipher.errors.ErrorType

sealed class BiometricException(
    code: String,
    message: String,
    cause: Throwable? = null
) : BaseException(code, message, cause) {

    data class BiometricNotSupported(
        val originalCause: Throwable? = null
    ) :
        BiometricException(
            code = ErrorType.BIOMETRIC_NOT_SUPPORTED.name,
            message = ErrorType.BIOMETRIC_NOT_SUPPORTED.errorDescription,
            cause = originalCause
        )
}
