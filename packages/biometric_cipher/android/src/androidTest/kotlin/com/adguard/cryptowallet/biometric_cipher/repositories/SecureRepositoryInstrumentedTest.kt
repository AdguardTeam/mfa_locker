package com.adguard.cryptowallet.biometric_cipher.repositories

// Android SDK
import android.content.pm.PackageManager
import android.security.keystore.KeyProperties

// AndroidX
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import androidx.biometric.BiometricManager.BIOMETRIC_SUCCESS
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry

// Javax
import javax.crypto.Cipher

// JUnit & Test Frameworks
import junit.framework.TestCase.assertEquals
import junit.framework.TestCase.fail
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

// Project-specific imports
import com.adguard.cryptowallet.biometric_cipher.errors.ErrorType
import com.adguard.cryptowallet.biometric_cipher.exceptions.CryptographicException

/**
 * Instrumentation test (runs on a device/emulator).
 * Verifies the SecureRepositoryImpl under real or near-real Android conditions.
 *
 * Note:
 * - This file contains tests that use both mocks (for negative scenarios) and real data
 *   for encryption/decryption.
 * - The testNonDeterministicEncryption() method verifies that encrypting the same plaintext
 *   twice produces different, non-empty ciphertexts, and that decryption correctly recovers
 *   the original plaintext.
 */
@RunWith(AndroidJUnit4::class)
class SecureRepositoryInstrumentedTest {
    private lateinit var packageManager: PackageManager
    private lateinit var biometricManager: BiometricManager
    private lateinit var repository: SecureRepository

    @Before
    fun setUp() {
        // Acquire real context-based objects or mock them if you prefer.
        // But note that instrumentation tests can use the actual context if needed.
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        packageManager = context.packageManager

        biometricManager = BiometricManager.from(context)

        repository = SecureRepositoryImpl(packageManager, biometricManager)
    }

    // ------------------------------------------------------------------------
    //  Cipher Management (getCipher)
    // ------------------------------------------------------------------------
    @Test
    fun getCipher_initializesCipherCorrectly() {
        assumeTrue(canAuthenticate())
        repository.generateKey(TEST_KEY_ALIAS)
        val secretKey = repository.getSecretKey(TEST_KEY_ALIAS)

        val cipher = repository.getCipher(secretKey, Cipher.ENCRYPT_MODE)
        val expectedAlgorithm = "AES/GCM/NoPadding"

        assertEquals(expectedAlgorithm, cipher.algorithm)
        deleteTestKey()
    }

    // ------------------------------------------------------------------------
    //  Key Management (generateKey, getSecretKey, deleteKey)
    // ------------------------------------------------------------------------
    @Test(expected = CryptographicException::class)
    fun getSecretKey_throwsKeyNotFoundExceptionWhenKeyAliasNotFound() {
        // Attempt to retrieve a key that hasn't been generated
        repository.getSecretKey("non_existent_tag")
    }

    @Test
    fun generateKey_thenGetSecretKey_returnsValidKey() {
        // Conditionally run the test only if canAuthenticate is BIOMETRIC_SUCCESS
        assumeTrue(canAuthenticate())

        repository.generateKey(TEST_KEY_ALIAS)
        val secretKey = repository.getSecretKey(TEST_KEY_ALIAS)

        deleteTestKey()

        // We expect an AES algorithm from SecureObjects.TRANSFORMATION by default
        assertEquals(KeyProperties.KEY_ALGORITHM_AES, secretKey.algorithm)
    }

    @Test(expected = IllegalArgumentException::class)
    fun getGCMParameterSpec_withInvalidData_throwsException() {
        repository.getGCMParameterSpec("InvalidBase64Data")
    }

    @Test
    fun deleteKey_removesExistingKey() {
        // Conditionally run the test only if canAuthenticate is BIOMETRIC_SUCCESS
        assumeTrue(canAuthenticate())

        generateTestKey()
        // Make sure it exists
        val secretKey = repository.getSecretKey(TEST_KEY_ALIAS)
        assertEquals(KeyProperties.KEY_ALGORITHM_AES, secretKey.algorithm)

        // Now delete
        repository.deleteKey(TEST_KEY_ALIAS)

        // Subsequent call to getSecretKey should fail
        try {
            repository.getSecretKey(TEST_KEY_ALIAS)
            fail("Expected KeyNotFoundException after deleting key.")
        } catch (ex: CryptographicException.KeyNotFound) {
            assertEquals(ErrorType.KEY_NOT_FOUND.name, ex.code)
            assertEquals(ErrorType.KEY_NOT_FOUND.errorDescription, ex.message)
        }
    }

    // ------------------------------------------------------------------------
    //  Real Encryption/Decryption (non-deterministic behavior)
    // ------------------------------------------------------------------------
    /**
     * Tests real encryption using the SecureRepository.
     *
     * Steps:
     * 1. Generate a new key with a unique alias.
     * 2. Retrieve the secret key and create two separate Cipher instances for encryption.
     * 3. Encrypt the same plaintext twice using different Cipher instances.
     * 4. Assert that:
     *    - Both ciphertexts are non-null and non-empty.
     *    - The ciphertexts differ from each other (confirming non-deterministic encryption).
     * 5. For each ciphertext, retrieve the corresponding GCMParameterSpec,
     *    create a decryption Cipher, and decrypt the ciphertext.
     * 6. Verify that the decrypted texts match the original plaintext.
     * 7. Clean up by deleting the generated key.
     *
     * Note:
     * - This test must be run on a device/emulator with proper biometric/keystore support.
     */
    @Test
    fun testNonDeterministicEncryption() {
        // Generate a unique key alias to avoid conflicts.
        val uniqueKeyAlias = "integration_test_${TEST_KEY_ALIAS}_${System.currentTimeMillis()}"
        assumeTrue(canAuthenticate())
        repository.generateKey(uniqueKeyAlias)

        val plaintext = "Hello, Secure Repository!"

        // Retrieve the secret key.
        val secretKey = repository.getSecretKey(uniqueKeyAlias)

        // --- Encryption ---
        // First encryption
        val encryptCipher1 = repository.getCipher(secretKey, Cipher.ENCRYPT_MODE)
        val ciphertext1 = repository.encrypt(encryptCipher1, plaintext)

        // Second encryption
        val encryptCipher2 = repository.getCipher(secretKey, Cipher.ENCRYPT_MODE)
        val ciphertext2 = repository.encrypt(encryptCipher2, plaintext)

        // Assert that both ciphertexts are non-empty.
        assertTrue("Ciphertext1 should not be null or empty", ciphertext1.isNotEmpty())
        assertTrue("Ciphertext2 should not be null or empty", ciphertext2.isNotEmpty())

        // Verify that the ciphertexts differ, confirming non-deterministic encryption.
        assertNotEquals("Ciphertext should differ on repeated encryption calls", ciphertext1, ciphertext2)

        // --- Decryption for ciphertext1 ---
        val spec1 = repository.getGCMParameterSpec(ciphertext1)
        val decryptCipher1 = repository.getCipher(secretKey, Cipher.DECRYPT_MODE, spec1)
        val decrypted1 = repository.decrypt(decryptCipher1, ciphertext1)

        // --- Decryption for ciphertext2 ---
        val spec2 = repository.getGCMParameterSpec(ciphertext2)
        val decryptCipher2 = repository.getCipher(secretKey, Cipher.DECRYPT_MODE, spec2)
        val decrypted2 = repository.decrypt(decryptCipher2, ciphertext2)

        // Verify that decrypted texts match the original plaintext.
        assertEquals("Decrypted text should match original plaintext", plaintext, decrypted1)
        assertEquals("Decrypted text should match original plaintext", plaintext, decrypted2)

        // Clean up: delete the generated key.
        repository.deleteKey(uniqueKeyAlias)
    }

    private fun deleteTestKey() {
        try {
            repository.deleteKey(TEST_KEY_ALIAS)
        } catch (_: Exception) {
        }
    }

    private fun generateTestKey() {
        try {
            repository.generateKey(TEST_KEY_ALIAS)
        } catch (_: Exception) {
        }
    }

    private fun canAuthenticate(): Boolean =
        biometricManager.canAuthenticate(BIOMETRIC_STRONG) == BIOMETRIC_SUCCESS

    companion object {
        private const val TEST_KEY_ALIAS = "test_key_alias"
    }
}
