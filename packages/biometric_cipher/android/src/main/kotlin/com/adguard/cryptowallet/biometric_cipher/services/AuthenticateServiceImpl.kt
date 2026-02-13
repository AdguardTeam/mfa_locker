package com.adguard.cryptowallet.biometric_cipher.services

import android.app.Activity
import com.adguard.cryptowallet.biometric_cipher.enums.BiometricStatus
import com.adguard.cryptowallet.biometric_cipher.exceptions.ActivityException
import com.adguard.cryptowallet.biometric_cipher.exceptions.ConfigureException
import com.adguard.cryptowallet.biometric_cipher.repositories.AuthenticationRepository
import com.adguard.cryptowallet.biometric_cipher.storages.ConfigStorage
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
