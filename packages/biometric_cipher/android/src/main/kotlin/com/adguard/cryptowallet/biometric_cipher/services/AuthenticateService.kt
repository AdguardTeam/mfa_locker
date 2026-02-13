package com.adguard.cryptowallet.biometric_cipher.services

import com.adguard.cryptowallet.biometric_cipher.enums.BiometricStatus
import javax.crypto.Cipher

interface AuthenticateService {
    fun getBiometryStatus(): BiometricStatus

    suspend fun authenticateUser(cipher: Cipher): Cipher
}
