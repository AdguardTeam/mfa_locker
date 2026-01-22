package com.adguard.cryptowallet.secure_mnemonic.exceptions

open class BaseException(
    val code: String,
    message: String,
    cause: Throwable? = null
) : Exception(message, cause)
