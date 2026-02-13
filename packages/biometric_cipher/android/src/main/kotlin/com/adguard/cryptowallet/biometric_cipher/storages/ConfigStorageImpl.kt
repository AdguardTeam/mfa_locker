package com.adguard.cryptowallet.biometric_cipher.storages

import com.adguard.cryptowallet.biometric_cipher.exceptions.ConfigureException
import com.adguard.cryptowallet.biometric_cipher.model.BiometricPromptData
import com.adguard.cryptowallet.biometric_cipher.model.ConfigData

class ConfigStorageImpl() : ConfigStorage {
    private var biometricPromptData = BiometricPromptData(
        title = "",
        subtitle = "",
        negativeButtonText = "",
        description = "",
    )

    override var isConfigured: Boolean = false
        private set

    override fun getBiometricPromptData(): BiometricPromptData = biometricPromptData

    @Throws(Exception::class)
    override fun setConfigData(configData: ConfigData) {
        isConfigured = false
        val androidConfig = configData.androidConfig


        if (androidConfig.negativeButtonText.isEmpty()) {
            throw ConfigureException.NegativeButtonNotConfigured()
        }

        biometricPromptData = BiometricPromptData(
            title = androidConfig.promptTitle,
            subtitle = androidConfig.promptSubtitle,
            negativeButtonText = androidConfig.negativeButtonText,
            description = androidConfig.promptDescription,
        )
        isConfigured = true
    }

    @Throws(Exception::class)
    private fun validatePromptData(title: String, subtitle: String, type: String) {
        if (title.isEmpty()) {
            throw ConfigureException.TitlePromptNotConfigured()
        }
        if (subtitle.isEmpty()) {
            throw ConfigureException.SubtitlePromptNotConfigured()
        }
    }
}
