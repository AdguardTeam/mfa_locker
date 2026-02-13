package com.adguard.cryptowallet.biometric_cipher.enums

enum class ArgumentName {
    TAG,
    DATA,
    BIOMETRIC_PROMPT_TITLE,
    BIOMETRIC_PROMPT_SUBTITLE,
    ANDROID_CONFIG;

    override fun toString(): String =
        when (this) {
            TAG -> "tag"
            DATA -> "data"
            BIOMETRIC_PROMPT_TITLE -> "biometricPromptTitle"
            BIOMETRIC_PROMPT_SUBTITLE -> "biometricPromptSubtitle"
            ANDROID_CONFIG -> "androidConfig"
        }
}
