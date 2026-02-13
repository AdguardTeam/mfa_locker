package com.adguard.cryptowallet.biometric_cipher.repositories

import android.content.pm.PackageManager
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.annotation.RequiresApi
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import com.adguard.cryptowallet.biometric_cipher.exceptions.CryptographicException
import com.adguard.cryptowallet.biometric_cipher.objects.SecureObjects
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class SecureRepositoryImpl(
    private val packageManager: PackageManager, private val biometricManager: BiometricManager
) : SecureRepository {
    @RequiresApi(Build.VERSION_CODES.P)
    override fun generateKey(tag: String) {
        val keyStore = KeyStore.getInstance(SecureObjects.ANDROID_KEYSTORE)
        keyStore.load(null)

        val keyAlias = getKeyAliasFromTag(tag)
        if (keyStore.containsAlias(keyAlias)) {
            throw CryptographicException.KeyAlreadyExists()
        }


        val keyGenerator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES, SecureObjects.ANDROID_KEYSTORE
        )

        val keyGenParameterSpecBuilder = KeyGenParameterSpec.Builder(
            keyAlias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        ).setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setRandomizedEncryptionRequired(true)

        keyGenParameterSpecBuilder.setIsStrongBoxBacked(isStrongBoxAvailable())

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            if (biometricManager.canAuthenticate(BIOMETRIC_STRONG) == BiometricManager.BIOMETRIC_SUCCESS) {
                keyGenParameterSpecBuilder.setUserAuthenticationParameters(
                    AUTHENTICATION_TIMEOUT, KeyProperties.AUTH_BIOMETRIC_STRONG
                )
            } else {
                keyGenParameterSpecBuilder.setUserAuthenticationParameters(
                    AUTHENTICATION_TIMEOUT, KeyProperties.AUTH_DEVICE_CREDENTIAL
                )
            }
        } else {
            @Suppress("DEPRECATION")
            keyGenParameterSpecBuilder.setUserAuthenticationValidityDurationSeconds(
                AUTHENTICATION_TIMEOUT
            )
        }
        keyGenParameterSpecBuilder.setUserAuthenticationRequired(true)

        keyGenerator.init(keyGenParameterSpecBuilder.build())

        keyGenerator.generateKey()

        return
    }

    @Throws(Exception::class)
    override fun getSecretKey(tag: String): SecretKey {
        val keyStore = KeyStore.getInstance(SecureObjects.ANDROID_KEYSTORE)
        keyStore.load(null)

        val keyAlias = getKeyAliasFromTag(tag)
        if (!keyStore.containsAlias(keyAlias)) {
            throw CryptographicException.KeyNotFound()
        }

        val secretKeyEntry = keyStore.getEntry(
            keyAlias, null
        ) as KeyStore.SecretKeyEntry

        return secretKeyEntry.secretKey
    }

    override fun getCipher(secretKey: SecretKey, optMode: Int, spec: GCMParameterSpec?): Cipher =
        Cipher.getInstance(SecureObjects.TRANSFORMATION).apply {
            if (spec != null) {
                init(optMode, secretKey, spec)
            } else {
                init(optMode, secretKey)
            }
        }

    override fun encrypt(cipher: Cipher, data: String): String {
        val iv = cipher.iv
        val encryptedData = cipher.doFinal(data.toByteArray(Charsets.UTF_8))
        val encryptedDataWithIv = iv + encryptedData
        val encodedData = Base64.encodeToString(encryptedDataWithIv, Base64.NO_WRAP)

        return encodedData
    }

    @Throws(Exception::class)
    override fun getGCMParameterSpec(data: String): GCMParameterSpec {
        val decodedData = Base64.decode(data, Base64.NO_WRAP)
        if (decodedData.size <= IV_LENGTH) {
            throw CryptographicException.DecodeDataSizeInvalid()
        }

        val iv = decodedData.sliceArray(0 until IV_LENGTH)
        val spec = GCMParameterSpec(AUTHENTICATION_TAG_LENGTH, iv)

        return spec
    }

    @Throws(Exception::class)
    override fun decrypt(cipher: Cipher, data: String): String {
        val decodedData = Base64.decode(data, Base64.NO_WRAP)
        if (decodedData.size <= IV_LENGTH) {
            throw CryptographicException.DecodeDataSizeInvalid()
        }
        val cipherText = decodedData.sliceArray(IV_LENGTH until decodedData.size)
        val decryptedData = cipher.doFinal(cipherText)

        return String(decryptedData, Charsets.UTF_8)
    }

    override fun deleteKey(tag: String) {
        val keyStore = KeyStore.getInstance(SecureObjects.ANDROID_KEYSTORE)
        keyStore.load(null)

        keyStore.deleteEntry(getKeyAliasFromTag(tag))
    }

    private fun isStrongBoxAvailable(): Boolean =
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            false
        } else {
            packageManager.hasSystemFeature(PackageManager.FEATURE_STRONGBOX_KEYSTORE)
        }

    private fun getKeyAliasFromTag(tag: String): String = "${SecureObjects.KEY_PREFIX}$tag"

    companion object {
        private const val AUTHENTICATION_TIMEOUT = 0
        private const val IV_LENGTH = 12
        private const val AUTHENTICATION_TAG_LENGTH = 128
    }
}
