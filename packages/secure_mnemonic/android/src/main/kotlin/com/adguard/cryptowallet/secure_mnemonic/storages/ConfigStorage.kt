package com.adguard.cryptowallet.secure_mnemonic.storages

import com.adguard.cryptowallet.secure_mnemonic.model.BiometricPromptData
import com.adguard.cryptowallet.secure_mnemonic.model.ConfigData

interface ConfigStorage {
    val isConfigured: Boolean

    fun getBiometricPromptData(): BiometricPromptData

    fun setConfigData(configData: ConfigData)
}
