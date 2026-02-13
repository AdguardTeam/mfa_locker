package com.adguard.cryptowallet.biometric_cipher.services

import com.adguard.cryptowallet.biometric_cipher.enums.BiometricStatus
import com.adguard.cryptowallet.biometric_cipher.enums.TPMStatus
import com.adguard.cryptowallet.biometric_cipher.exceptions.BiometricException
import com.adguard.cryptowallet.biometric_cipher.repositories.SecureRepository
import javax.crypto.Cipher

class SecureServiceImpl(
    private val secureRepository: SecureRepository,
    private val authenticateService: AuthenticateService
) : SecureService {
    override fun getTPMStatus(): TPMStatus = TPMStatus.SUPPORTED

    @Throws(Exception::class)
    override fun generateKey(tag: String) {
        if (!checkCryptoStatus()) {
            throw BiometricException.BiometricNotSupported()
        }

        secureRepository.generateKey(tag)
    }

    @Throws(Exception::class)
    override suspend fun encrypt(tag: String, data: String): String {
        if (!checkCryptoStatus()) {
            throw BiometricException.BiometricNotSupported()
        }

        val secretKey = secureRepository.getSecretKey(tag)
        val cipher = secureRepository.getCipher(secretKey, Cipher.ENCRYPT_MODE)
        val authCipher = authenticateService.authenticateUser(cipher)
        val encryptedData = secureRepository.encrypt(authCipher, data)

        return encryptedData
    }

    @Throws(Exception::class)
    override suspend fun decrypt(tag: String, data: String): String {
        if (!checkCryptoStatus()) {
            throw BiometricException.BiometricNotSupported()
        }

        val secretKey = secureRepository.getSecretKey(tag)
        val spec = secureRepository.getGCMParameterSpec(data)
        val cipher = secureRepository.getCipher(secretKey, Cipher.DECRYPT_MODE, spec)
        val authCipher = authenticateService.authenticateUser(cipher)
        val decryptedData = secureRepository.decrypt(authCipher, data)

        return decryptedData
    }

    @Throws(Exception::class)
    override fun deleteKey(tag: String) {
        if (!checkCryptoStatus()) {
            throw BiometricException.BiometricNotSupported()
        }

        secureRepository.deleteKey(tag)
    }

    private fun checkCryptoStatus(): Boolean =
        getTPMStatus() == TPMStatus.SUPPORTED
                && authenticateService.getBiometryStatus() == BiometricStatus.SUPPORTED

}
