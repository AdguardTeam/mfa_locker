package com.adguard.cryptowallet.biometric_cipher.exceptions

open class BaseException(
    val code: String,
    message: String,
    cause: Throwable? = null
) : Exception(message, cause)
