package com.adguard.cryptowallet.biometric_cipher.services

import android.app.Activity
import com.adguard.cryptowallet.biometric_cipher.exceptions.ActivityException
import com.adguard.cryptowallet.biometric_cipher.exceptions.ConfigureException
import com.adguard.cryptowallet.biometric_cipher.model.BiometricPromptData
import com.adguard.cryptowallet.biometric_cipher.repositories.AuthenticationRepository
import com.adguard.cryptowallet.biometric_cipher.storages.ConfigStorage
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertThrows
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.kotlin.eq
import org.mockito.kotlin.mock
import org.mockito.kotlin.verify
import org.mockito.kotlin.whenever
import org.robolectric.RobolectricTestRunner
import javax.crypto.Cipher

@RunWith(RobolectricTestRunner::class)
class AuthenticateServiceTest {
    // Dependencies:
    private lateinit var authenticationRepository: AuthenticationRepository
    private lateinit var activityStateFlow: MutableStateFlow<Activity?>
    private lateinit var configStorage: ConfigStorage

    // Class under test:
    private lateinit var authenticateService: AuthenticateService

    @Before
    fun setUp() {
        // Create mocks:
        authenticationRepository = mock()
        activityStateFlow = MutableStateFlow(null)
        configStorage = mock()

        // Instantiate the service with mocks:
        authenticateService = AuthenticateServiceImpl(
            authenticationRepository,
            activityStateFlow,
            configStorage
        )
    }

    // ------------------------------------------------------------------------
    //  authenticateUser
    // ------------------------------------------------------------------------
    @Test
    fun `authenticateUser throws ConfigureException if configStorage_isConfigured is false`() = runTest {
        whenever(configStorage.isConfigured).thenReturn(false)

        // Check that calling authenticateUser throws ConfigureException
        assertThrows(ConfigureException.BiometricPromptNotConfigured::class.java) {
            runBlocking {
                val cipher = Cipher.getInstance("AES")
                authenticateService.authenticateUser(cipher)
            }
        }
    }

    @Test
    fun `authenticateUser throws ActivityNotSetException if activityStateFlow is null`() = runTest {
        // activityStateFlow.value is null by default in setup()

        whenever(configStorage.isConfigured).thenReturn(true)

        // Check that calling authenticateUser throws ActivityNotSetException
        assertThrows(ActivityException.ActivityNotSet::class.java) {
            runBlocking {
                val cipher = Cipher.getInstance("AES")
                authenticateService.authenticateUser(cipher)
            }
        }
    }

    @Test
    fun `authenticateUser calls repository_authenticateUser if activity is set`() = runTest {
        // Given
        val mockActivity = mock<Activity>()
        activityStateFlow.value = mockActivity

        // Suppose configStorage returns some BiometricPromptData and isConfigured is true
        val biometricPromptData = BiometricPromptData(
            title = "Test Title",
            subtitle = "Test Subtitle",
            negativeButtonText = "Test Negative Button",
            description = "Test Description"
        )
        whenever(configStorage.getBiometricPromptData()).thenReturn(biometricPromptData)
        whenever(configStorage.isConfigured).thenReturn(true)


        //When
        val cipher = Cipher.getInstance("AES")
        authenticateService.authenticateUser(cipher)

        //Then
        verify(authenticationRepository).authenticateUser(
            eq(mockActivity),
            eq(biometricPromptData),
            eq(cipher)
        )
    }
}
