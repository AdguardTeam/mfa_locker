package com.adguard.cryptowallet.secure_mnemonic.repositories

import android.app.Activity
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import androidx.biometric.BiometricPrompt
import androidx.fragment.app.FragmentActivity
import com.adguard.cryptowallet.secure_mnemonic.exceptions.AuthenticationException
import com.adguard.cryptowallet.secure_mnemonic.factories.BiometricPromptFactory
import com.adguard.cryptowallet.secure_mnemonic.model.BiometricPromptData
import kotlinx.coroutines.suspendCancellableCoroutine
import javax.crypto.Cipher

class AuthenticationRepositoryImpl(
    private val biometricManager: BiometricManager,
    private val biometricPromptFactory: BiometricPromptFactory
) : AuthenticationRepository {
    override fun canAuthenticate(): Int =
        biometricManager.canAuthenticate(BIOMETRIC_STRONG)

    override suspend fun authenticateUser(
        activity: Activity,
        promptData: BiometricPromptData,
        cipher: Cipher
    ): Cipher = suspendCancellableCoroutine { continuation ->
        val fragmentActivity = activity as FragmentActivity

        val biometricPrompt = biometricPromptFactory.createBiometricPrompt(
            fragmentActivity,
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                    val authCipher = result.cryptoObject?.cipher
                    if (authCipher != null) {
                        continuation.resumeWith(Result.success(authCipher))
                    } else {
                        continuation.resumeWith(
                            Result.failure(
                                AuthenticationException.AuthenticationError(
                                    Exception("Cipher is null")
                                )
                            )
                        )
                    }
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    when (errorCode) {
                        BiometricPrompt.ERROR_USER_CANCELED,
                        BiometricPrompt.ERROR_NEGATIVE_BUTTON -> {
                            continuation.resumeWith(
                                Result.failure(
                                    AuthenticationException.AuthenticationUserCanceled(
                                        Exception("$errorCode: $errString")
                                    )
                                )
                            )
                        }

                        else -> {
                            continuation.resumeWith(
                                Result.failure(
                                    AuthenticationException.AuthenticationError(
                                        Exception("$errorCode: $errString")
                                    )
                                )
                            )
                        }
                    }
                }
            }
        )

        val promptInfoBuilder = BiometricPrompt.PromptInfo.Builder()
            .setTitle(promptData.title)
            .setSubtitle(promptData.subtitle)
            .setNegativeButtonText(promptData.negativeButtonText)
            .setAllowedAuthenticators(BIOMETRIC_STRONG)
            .apply {
                if (promptData.description.isNotEmpty()) {
                    setDescription(promptData.description)
                }
            }

        biometricPrompt.authenticate(
            promptInfoBuilder.build(),
            BiometricPrompt.CryptoObject(cipher)
        )
    }
}
