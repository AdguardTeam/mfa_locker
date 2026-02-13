package com.adguard.cryptowallet.biometric_cipher.exceptions

import com.adguard.cryptowallet.biometric_cipher.errors.ErrorType

sealed class ActivityException(
    code: String,
    message: String,
    cause: Throwable? = null
) : BaseException(code, message, cause) {

    data class ActivityNotSet(
        val originalCause: Throwable? = null
    ) : ActivityException(
        code = ErrorType.ACTIVITY_NOT_SET.name,
        message = ErrorType.ACTIVITY_NOT_SET.errorDescription,
        cause = originalCause
    )
}
