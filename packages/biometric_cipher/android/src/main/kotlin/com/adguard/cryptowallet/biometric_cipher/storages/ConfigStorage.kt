package com.adguard.cryptowallet.biometric_cipher.storages

import com.adguard.cryptowallet.biometric_cipher.model.BiometricPromptData
import com.adguard.cryptowallet.biometric_cipher.model.ConfigData

interface ConfigStorage {
    val isConfigured: Boolean

    fun getBiometricPromptData(): BiometricPromptData

    fun setConfigData(configData: ConfigData)
}
