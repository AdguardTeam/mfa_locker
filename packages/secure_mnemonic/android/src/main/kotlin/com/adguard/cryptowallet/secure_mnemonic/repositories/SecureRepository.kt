package com.adguard.cryptowallet.secure_mnemonic.repositories

import javax.crypto.Cipher
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

interface SecureRepository {
    fun generateKey(tag: String)

    fun getSecretKey(tag: String): SecretKey

    fun getCipher(secretKey: SecretKey, optMode: Int, spec: GCMParameterSpec? = null): Cipher

    fun encrypt(cipher: Cipher, data: String): String

    fun getGCMParameterSpec(data: String): GCMParameterSpec

    fun decrypt(cipher: Cipher, data: String): String

    fun deleteKey(tag: String)
}
