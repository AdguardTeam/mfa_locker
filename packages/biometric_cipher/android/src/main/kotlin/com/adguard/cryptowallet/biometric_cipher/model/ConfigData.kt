package com.adguard.cryptowallet.biometric_cipher.model

data class ConfigData(
    val biometricPromptTitle: String,
    val biometricPromptSubtitle: String,
    val androidConfig: AndroidConfig
)
