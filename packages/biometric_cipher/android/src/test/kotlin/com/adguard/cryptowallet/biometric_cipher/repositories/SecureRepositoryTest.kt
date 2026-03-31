package com.adguard.cryptowallet.biometric_cipher.repositories

import android.content.pm.PackageManager
import android.util.Base64
import androidx.biometric.BiometricManager
import com.adguard.cryptowallet.biometric_cipher.errors.ErrorType
import com.adguard.cryptowallet.biometric_cipher.exceptions.CryptographicException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.kotlin.mock
import org.mockito.kotlin.whenever
import org.robolectric.RobolectricTestRunner
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.IllegalBlockSizeException

@RunWith(RobolectricTestRunner::class)
class SecureRepositoryTest {

    private lateinit var packageManager: PackageManager
    private lateinit var biometricManager: BiometricManager
    private lateinit var repository: SecureRepositoryImpl

    @Before
    fun setUp() {
        packageManager = mock()
        biometricManager = mock()
        repository = SecureRepositoryImpl(packageManager, biometricManager)
    }

    // ------------------------------------------------------------------------
    //  encrypt — doFinal failure wrapping
    // ------------------------------------------------------------------------
    @Test
    fun `encrypt throws EncryptionFailed when cipher doFinal throws AEADBadTagException`() {
        val cipher = mock<Cipher>()
        whenever(cipher.iv).thenReturn(ByteArray(12))
        whenever(cipher.doFinal(PLAINTEXT.toByteArray(Charsets.UTF_8)))
            .thenThrow(AEADBadTagException("tag mismatch"))

        val exception = assertThrows(CryptographicException.EncryptionFailed::class.java) {
            repository.encrypt(cipher, PLAINTEXT)
        }

        assertEquals(ErrorType.ENCRYPTION_ERROR.name, exception.code)
    }

    @Test
    fun `encrypt throws EncryptionFailed when cipher doFinal throws IllegalBlockSizeException`() {
        val cipher = mock<Cipher>()
        whenever(cipher.iv).thenReturn(ByteArray(12))
        whenever(cipher.doFinal(PLAINTEXT.toByteArray(Charsets.UTF_8)))
            .thenThrow(IllegalBlockSizeException("invalid block size"))

        val exception = assertThrows(CryptographicException.EncryptionFailed::class.java) {
            repository.encrypt(cipher, PLAINTEXT)
        }

        assertEquals(ErrorType.ENCRYPTION_ERROR.name, exception.code)
    }

    // ------------------------------------------------------------------------
    //  decrypt — doFinal failure wrapping
    // ------------------------------------------------------------------------
    @Test
    fun `decrypt throws DecryptionFailed when cipher doFinal throws AEADBadTagException`() {
        val iv = ByteArray(12) { 0x01 }
        val fakeCiphertext = ByteArray(16) { 0x02 }
        val encoded = Base64.encodeToString(iv + fakeCiphertext, Base64.NO_WRAP)

        val cipher = mock<Cipher>()
        whenever(cipher.doFinal(fakeCiphertext)).thenThrow(AEADBadTagException("tag mismatch"))

        val exception = assertThrows(CryptographicException.DecryptionFailed::class.java) {
            repository.decrypt(cipher, encoded)
        }

        assertEquals(ErrorType.DECRYPTION_ERROR.name, exception.code)
    }

    @Test
    fun `decrypt throws DecryptionFailed when cipher doFinal throws IllegalBlockSizeException`() {
        val iv = ByteArray(12) { 0x01 }
        val fakeCiphertext = ByteArray(16) { 0x02 }
        val encoded = Base64.encodeToString(iv + fakeCiphertext, Base64.NO_WRAP)

        val cipher = mock<Cipher>()
        whenever(cipher.doFinal(fakeCiphertext)).thenThrow(IllegalBlockSizeException("bad block"))

        val exception = assertThrows(CryptographicException.DecryptionFailed::class.java) {
            repository.decrypt(cipher, encoded)
        }

        assertEquals(ErrorType.DECRYPTION_ERROR.name, exception.code)
    }

    @Test
    fun `decrypt throws DecodeDataSizeInvalid when data is too short`() {
        val tooShort = Base64.encodeToString(ByteArray(5), Base64.NO_WRAP)
        val cipher = mock<Cipher>()

        assertThrows(CryptographicException.DecodeDataSizeInvalid::class.java) {
            repository.decrypt(cipher, tooShort)
        }
    }

    companion object {
        private const val PLAINTEXT = "test data"
    }
}
