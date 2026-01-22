package com.adguard.cryptowallet.secure_mnemonic.repositories

import android.app.Activity
import com.adguard.cryptowallet.secure_mnemonic.model.BiometricPromptData
import javax.crypto.Cipher

interface AuthenticationRepository {
    fun canAuthenticate(): Int

    suspend fun authenticateUser(
        activity: Activity,
        promptData: BiometricPromptData,
        cipher: Cipher
    ): Cipher
}
