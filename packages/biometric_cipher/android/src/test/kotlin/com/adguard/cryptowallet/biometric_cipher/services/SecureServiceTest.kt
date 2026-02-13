package com.adguard.cryptowallet.biometric_cipher.services

import com.adguard.cryptowallet.biometric_cipher.enums.BiometricStatus
import com.adguard.cryptowallet.biometric_cipher.enums.TPMStatus
import com.adguard.cryptowallet.biometric_cipher.exceptions.BiometricException
import com.adguard.cryptowallet.biometric_cipher.repositories.SecureRepository
import junit.framework.TestCase.assertEquals
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertThrows
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.ArgumentMatchers.anyString
import org.mockito.Mockito
import org.mockito.kotlin.any
import org.mockito.kotlin.mock
import org.mockito.kotlin.never
import org.mockito.kotlin.verify
import org.mockito.kotlin.whenever
import org.robolectric.RobolectricTestRunner
import javax.crypto.Cipher
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

@RunWith(RobolectricTestRunner::class)
class SecureServiceTest {

    //Dependencies:
    private lateinit var secureRepository: SecureRepository
    private lateinit var authenticateService: AuthenticateService

    // Class under test:
    private lateinit var secureService: SecureService

    @Before
    fun setUp() {
        // Create mocks:
        secureRepository = mock()
        authenticateService = mock()

        secureService = SecureServiceImpl(secureRepository, authenticateService)
    }

    // ------------------------------------------------------------------------
    //  getTPMStatus
    // ------------------------------------------------------------------------
    @Test
    fun `getTPMStatus returns SUPPORTED `() {
        val status = secureService.getTPMStatus()

        assertEquals(TPMStatus.SUPPORTED, status)
    }

    // ------------------------------------------------------------------------
    //  generateKey
    // ------------------------------------------------------------------------
    @Test
    fun `generateKey throws BiometricNotSupportedException if authenticateService_getBiometricStatus returns UNSUPPORTED`() {
        whenever(authenticateService.getBiometryStatus()).thenReturn(BiometricStatus.UNSUPPORTED)

        assertThrows(BiometricException.BiometricNotSupported::class.java) {
            secureService.generateKey(TEST_KEY_ALIAS)
        }

        verify(secureRepository, Mockito.never()).generateKey(TEST_KEY_ALIAS)
    }

    @Test
    fun `generateKey calls repository_generateKey if authenticateService_getBiometricStatus returns SUPPORTED`() {
        whenever(authenticateService.getBiometryStatus()).thenReturn(BiometricStatus.SUPPORTED)

        secureService.generateKey(TEST_KEY_ALIAS)

        verify(authenticateService).getBiometryStatus()
        verify(secureRepository).generateKey(TEST_KEY_ALIAS)
    }

    // ------------------------------------------------------------------------
    //  encrypt (suspend function)
    // ------------------------------------------------------------------------
    @Test
    fun `encrypt throws BiometricNotSupportedException if authenticateService_getBiometricStatus returns UNSUPPORTED`() =
        runTest {
            whenever(authenticateService.getBiometryStatus()).thenReturn(BiometricStatus.UNSUPPORTED)

            assertThrows(BiometricException.BiometricNotSupported::class.java) {
                runBlocking {
                    secureService.encrypt(TEST_KEY_ALIAS, TEST_DATA)
                }
            }

            verify(authenticateService).getBiometryStatus()
            verify(authenticateService, never()).authenticateUser(any())
            verify(secureRepository, never()).getSecretKey(anyString())
            verify(secureRepository, never()).encrypt(any(), anyString())
        }

    @Test
    fun `encrypt calls authenticateService_getBiometricStatus, then repository_getSecretKey, then repository_encrypt`() =
        runTest {
            val secretKey = Mockito.mock(SecretKey::class.java)
            val cipher = Mockito.mock(Cipher::class.java)

            whenever(authenticateService.getBiometryStatus()).thenReturn(BiometricStatus.SUPPORTED)
            whenever(secureRepository.getSecretKey(TEST_KEY_ALIAS)).thenReturn(secretKey)
            whenever(secureRepository.getCipher(secretKey, Cipher.ENCRYPT_MODE)).thenReturn(cipher)
            whenever(authenticateService.authenticateUser(cipher)).thenReturn(cipher)
            whenever(secureRepository.encrypt(cipher, TEST_DATA)).thenReturn(TEST_ENCRYPTED_DATA)

            val result = secureService.encrypt(TEST_KEY_ALIAS, TEST_DATA)

            assertEquals(TEST_ENCRYPTED_DATA, result)

            verify(authenticateService).getBiometryStatus()
            verify(authenticateService).authenticateUser(cipher)
            verify(secureRepository).getSecretKey(TEST_KEY_ALIAS)
            verify(secureRepository).getCipher(secretKey, Cipher.ENCRYPT_MODE)
            verify(secureRepository).encrypt(cipher, TEST_DATA)
        }

    // ------------------------------------------------------------------------
    //  decrypt (suspend function)
    // ------------------------------------------------------------------------
    @Test
    fun `decrypt throws BiometricNotSupportedException if authenticateService_getBiometricStatus returns UNSUPPORTED`() =
        runTest {
            whenever(authenticateService.getBiometryStatus()).thenReturn(BiometricStatus.UNSUPPORTED)

            assertThrows(BiometricException.BiometricNotSupported::class.java) {
                runBlocking {
                    secureService.decrypt(TEST_KEY_ALIAS, TEST_ENCRYPTED_DATA)
                }
            }

            verify(authenticateService).getBiometryStatus()
            verify(authenticateService, never()).authenticateUser(any())
            verify(secureRepository, never()).getSecretKey(anyString())
            verify(secureRepository, never()).decrypt(any(), anyString())
        }

    @Test
    fun `decrypt calls authenticateService_getBiometricStatus, then repository_getSecretKey, then repository_decrypt`() =
        runTest {
            val secretKey = Mockito.mock(SecretKey::class.java)
            val cipher = Mockito.mock(Cipher::class.java)
            val spec = Mockito.mock(GCMParameterSpec::class.java)

            whenever(authenticateService.getBiometryStatus()).thenReturn(BiometricStatus.SUPPORTED)
            whenever(secureRepository.getSecretKey(TEST_KEY_ALIAS)).thenReturn(secretKey)
            whenever(secureRepository.getGCMParameterSpec(TEST_ENCRYPTED_DATA)).thenReturn(spec)
            whenever(secureRepository.getCipher(secretKey, Cipher.DECRYPT_MODE, spec)).thenReturn(
                cipher
            )
            whenever(authenticateService.authenticateUser(cipher)).thenReturn(cipher)
            whenever(secureRepository.decrypt(cipher, TEST_ENCRYPTED_DATA))
                .thenReturn(TEST_DATA)

            val result = secureService.decrypt(TEST_KEY_ALIAS, TEST_ENCRYPTED_DATA)

            assertEquals(TEST_DATA, result)

            verify(authenticateService).getBiometryStatus()
            verify(authenticateService).authenticateUser(cipher)
            verify(secureRepository).getSecretKey(TEST_KEY_ALIAS)
            verify(secureRepository).getGCMParameterSpec(TEST_ENCRYPTED_DATA)
            verify(secureRepository).getCipher(secretKey, Cipher.DECRYPT_MODE, spec)
            verify(secureRepository).decrypt(cipher, TEST_ENCRYPTED_DATA)
        }

    // ------------------------------------------------------------------------
    //  deleteKey
    // ------------------------------------------------------------------------
    @Test
    fun `deleteKey throws BiometricNotSupportedException if authenticateService_getBiometricStatus returns UNSUPPORTED`() {
        whenever(authenticateService.getBiometryStatus()).thenReturn(BiometricStatus.UNSUPPORTED)

        assertThrows(BiometricException.BiometricNotSupported::class.java) {
            secureService.deleteKey(TEST_KEY_ALIAS)
        }

        verify(authenticateService).getBiometryStatus()
        verify(secureRepository, never()).deleteKey(TEST_KEY_ALIAS)
    }

    @Test
    fun `deleteKey calls repository_deleteKey if authenticateService_getBiometricStatus returns SUPPORTED`() {
        whenever(authenticateService.getBiometryStatus()).thenReturn(BiometricStatus.SUPPORTED)

        secureService.deleteKey(TEST_KEY_ALIAS)

        verify(authenticateService).getBiometryStatus()
        verify(secureRepository).deleteKey(TEST_KEY_ALIAS)
    }

    companion object {
        private const val TEST_KEY_ALIAS = "test_key_alias"
        private const val TEST_DATA = "test_data"
        private const val TEST_ENCRYPTED_DATA = "test_encrypted_data"
    }

}
