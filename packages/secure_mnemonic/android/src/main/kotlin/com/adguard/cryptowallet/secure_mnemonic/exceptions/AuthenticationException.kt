package com.adguard.cryptowallet.secure_mnemonic.exceptions

import com.adguard.cryptowallet.secure_mnemonic.errors.ErrorType

sealed class AuthenticationException(
    code: String,
    message: String,
    cause: Throwable? = null
) : BaseException(code, message, cause) {

    data class AuthenticationError(
        val originalCause: Throwable? = null
    ) : AuthenticationException(
        code = ErrorType.AUTHENTICATION_ERROR.name,
        message = ErrorType.AUTHENTICATION_ERROR.errorDescription,
        cause = originalCause
    )

    data class AuthenticationUserCanceled(
        val originalCause: Throwable? = null
    ) : AuthenticationException(
        code = ErrorType.AUTHENTICATION_USER_CANCELED.name,
        message = ErrorType.AUTHENTICATION_USER_CANCELED.errorDescription,
        cause = originalCause
    )
}
