package com.adguard.cryptowallet.secure_mnemonic.services

import android.app.Activity
import com.adguard.cryptowallet.secure_mnemonic.enums.BiometricStatus
import com.adguard.cryptowallet.secure_mnemonic.exceptions.ActivityException
import com.adguard.cryptowallet.secure_mnemonic.exceptions.ConfigureException
import com.adguard.cryptowallet.secure_mnemonic.repositories.AuthenticationRepository
import com.adguard.cryptowallet.secure_mnemonic.storages.ConfigStorage
import kotlinx.coroutines.flow.StateFlow
import javax.crypto.Cipher

class AuthenticateServiceImpl(
    private val authenticationRepository: AuthenticationRepository,
    private val activityStateFlow: StateFlow<Activity?>,
    private val configStorage: ConfigStorage
) : AuthenticateService {
    override fun getBiometryStatus(): BiometricStatus {
        val biometricManagerValue = authenticationRepository.canAuthenticate()

        return BiometricStatus.fromBiometricManagerValue(biometricManagerValue)
    }

    override suspend fun authenticateUser(cipher: Cipher): Cipher {
        if (!configStorage.isConfigured) {
            throw ConfigureException.BiometricPromptNotConfigured()
        }

        val activity = activityStateFlow.value ?: throw ActivityException.ActivityNotSet()

        val biometricPromptData = configStorage.getBiometricPromptData()

        return authenticationRepository.authenticateUser(activity, biometricPromptData, cipher)
    }
}
