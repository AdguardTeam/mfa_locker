package com.adguard.cryptowallet.secure_mnemonic.errors

enum class ErrorType {
    INVALID_ARGUMENT,
    KEY_NOT_FOUND,
    KEY_ALREADY_EXISTS,
    BIOMETRIC_NOT_SUPPORTED,
    CONFIGURE_BIOMETRIC_ERROR,
    CONFIGURE_NEGATIVE_BUTTON_ERROR,
    CONFIGURE_TITLE_PROMPT_ERROR,
    CONFIGURE_SUBTITLE_PROMPT_ERROR,
    ACTIVITY_NOT_SET,
    DECODE_DATA_INVALID_SIZE,
    AUTHENTICATION_USER_CANCELED,
    AUTHENTICATION_ERROR,
    UNKNOWN_EXCEPTION;

    val errorDescription
        get() =
            when (this) {
                INVALID_ARGUMENT -> "Invalid argument"
                KEY_NOT_FOUND -> "Key not found"
                KEY_ALREADY_EXISTS -> "Key already exists"
                BIOMETRIC_NOT_SUPPORTED -> "Biometric not supported"
                CONFIGURE_BIOMETRIC_ERROR -> "Biometric prompt data is not configured"
                CONFIGURE_NEGATIVE_BUTTON_ERROR -> "Negative button text is not configured"
                CONFIGURE_TITLE_PROMPT_ERROR -> "Title text is not configured"
                CONFIGURE_SUBTITLE_PROMPT_ERROR -> "Subtitle text is not configured"
                ACTIVITY_NOT_SET -> "Activity not set"
                DECODE_DATA_INVALID_SIZE -> "Decode data invalid size"
                AUTHENTICATION_USER_CANCELED -> "Authentication user canceled"
                AUTHENTICATION_ERROR -> "Authentication error"
                UNKNOWN_EXCEPTION -> "Unknown exception"
            }
}
