package com.adguard.cryptowallet.biometric_cipher.services

import com.adguard.cryptowallet.biometric_cipher.enums.TPMStatus

interface SecureService {
    fun getTPMStatus(): TPMStatus

    fun generateKey(tag: String)

    suspend fun encrypt(tag: String, data: String): String

    suspend fun decrypt(tag: String, data: String): String

    fun deleteKey(tag: String)
}
