package com.adguard.cryptowallet.secure_mnemonic.factories

import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity

class BiometricPromptFactoryImpl: BiometricPromptFactory {
    override fun createBiometricPrompt(
        activity: FragmentActivity,
        callback: BiometricPrompt.AuthenticationCallback
    ): BiometricPrompt {
        val executor = ContextCompat.getMainExecutor(activity)

        return BiometricPrompt(activity, executor, callback)
    }
}
