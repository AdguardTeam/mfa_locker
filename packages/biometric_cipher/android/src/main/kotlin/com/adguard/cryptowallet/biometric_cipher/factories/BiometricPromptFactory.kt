package com.adguard.cryptowallet.biometric_cipher.factories

import androidx.biometric.BiometricPrompt
import androidx.biometric.BiometricPrompt.AuthenticationCallback
import androidx.fragment.app.FragmentActivity

interface BiometricPromptFactory {
    fun createBiometricPrompt(
        activity: FragmentActivity,
        callback: AuthenticationCallback
    ): BiometricPrompt
}
