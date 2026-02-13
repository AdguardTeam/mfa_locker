package com.adguard.cryptowallet.biometric_cipher.repositories

import android.app.Activity
import com.adguard.cryptowallet.biometric_cipher.model.BiometricPromptData
import javax.crypto.Cipher

interface AuthenticationRepository {
    fun canAuthenticate(): Int

    suspend fun authenticateUser(
        activity: Activity,
        promptData: BiometricPromptData,
        cipher: Cipher
    ): Cipher
}
