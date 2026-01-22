package com.adguard.cryptowallet.secure_mnemonic.services

import com.adguard.cryptowallet.secure_mnemonic.enums.TPMStatus

interface SecureService {
    fun getTPMStatus(): TPMStatus

    fun generateKey(tag: String)

    suspend fun encrypt(tag: String, data: String): String

    suspend fun decrypt(tag: String, data: String): String

    fun deleteKey(tag: String)
}
