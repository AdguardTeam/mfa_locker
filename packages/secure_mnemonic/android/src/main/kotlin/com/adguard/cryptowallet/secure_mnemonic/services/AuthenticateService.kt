package com.adguard.cryptowallet.secure_mnemonic.services

import com.adguard.cryptowallet.secure_mnemonic.enums.BiometricStatus
import javax.crypto.Cipher

interface AuthenticateService {
    fun getBiometryStatus(): BiometricStatus

    suspend fun authenticateUser(cipher: Cipher): Cipher
}
