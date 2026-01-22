package com.adguard.cryptowallet.secure_mnemonic.repositories

import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import com.adguard.cryptowallet.secure_mnemonic.errors.ErrorType
import com.adguard.cryptowallet.secure_mnemonic.exceptions.AuthenticationException
import com.adguard.cryptowallet.secure_mnemonic.factories.BiometricPromptFactory
import com.adguard.cryptowallet.secure_mnemonic.model.BiometricPromptData
import junit.framework.TestCase.assertEquals
import junit.framework.TestCase.assertNotNull
import junit.framework.TestCase.fail
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.Mock
import org.mockito.MockedStatic
import org.mockito.Mockito.mockStatic
import org.mockito.MockitoAnnotations
import org.mockito.kotlin.any
import org.mockito.kotlin.argumentCaptor
import org.mockito.kotlin.mock
import org.mockito.kotlin.verify
import org.mockito.kotlin.verifyNoInteractions
import org.mockito.kotlin.whenever
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import java.util.concurrent.Executor
import javax.crypto.Cipher

@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
class AuthenticationRepositoryTest {
    @Mock
    private lateinit var mockBiometricPrompt: BiometricPrompt

    @Mock
    private lateinit var mockBiometricPromptFactory: BiometricPromptFactory

    @Mock
    private lateinit var mockBiometricManager: BiometricManager

    @Mock
    private lateinit var mockCipher: Cipher

    private lateinit var repository: AuthenticationRepository
    private lateinit var contextCompatMockedStatic: MockedStatic<ContextCompat>

    private lateinit var realActivity: FragmentActivity

    // Initialize the ArgumentCaptor correctly
    private val authenticationCallbackCaptor =
        argumentCaptor<BiometricPrompt.AuthenticationCallback>()

    @Before
    fun setUp() {
        // Initialize Mockito annotations
        MockitoAnnotations.openMocks(this)

        // Mock the static method ContextCompat.getMainExecutor first
        contextCompatMockedStatic = mockStatic(ContextCompat::class.java)
        contextCompatMockedStatic.`when`<Executor> {
            ContextCompat.getMainExecutor(any())
        }.thenReturn(Executor { it.run() })

        // Stub the BiometricPromptFactory to return the mocked BiometricPrompt
        whenever(mockBiometricPromptFactory.createBiometricPrompt(any(), any()))
            .thenReturn(mockBiometricPrompt)

        // Initialize the repository **after** stubbing the factory
        repository = AuthenticationRepositoryImpl(
            biometricManager = mockBiometricManager,
            biometricPromptFactory = mockBiometricPromptFactory
        )

        // Create a real FragmentActivity instance using Robolectric
        realActivity = Robolectric.buildActivity(FragmentActivity::class.java).create().get()

        // Verify that realActivity is not null
        assertNotNull("realActivity should be initialized", realActivity)

        // Verify that mockBiometricPromptFactory is not null
        assertNotNull(
            "mockBiometricPromptFactory should be initialized",
            mockBiometricPromptFactory
        )
    }

    @After
    fun tearDown() {
        // Close the static mock to avoid memory leaks
        contextCompatMockedStatic.close()
    }

    @Test
    fun canAuthenticate_returnsBiometricManagerResponse() {
        val mockResponse = BiometricManager.BIOMETRIC_SUCCESS
        whenever(mockBiometricManager.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG))
            .thenReturn(mockResponse)

        val result = repository.canAuthenticate()

        assertEquals(mockResponse, result)
    }

    @Test
    fun authenticateUser_successfulCallback_completesWithoutError() = runTest {
        // Ensure no interactions have occurred yet
        verifyNoInteractions(mockBiometricPromptFactory)

        // Act: Start `authenticateUser` in a coroutine that we can await/verify
        val job = launch {
            repository.authenticateUser(
                activity = realActivity,
                promptData = BIOMETRIC_PROMPT_DATA,
                cipher = mockCipher
            )
        }

        // Advance the coroutine scheduler to ensure `authenticateUser` starts executing
        advanceUntilIdle()

        // Now verify that createBiometricPrompt() was indeed called
        verify(mockBiometricPromptFactory).createBiometricPrompt(
            any(),
            authenticationCallbackCaptor.capture()
        )

        val capturedCallback = authenticationCallbackCaptor.firstValue
        // Ensure that the captured callback is not null
        assertNotNull("Captured callback should not be null", capturedCallback)

        // Simulate a successful authentication
        val mockCryptoObject = BiometricPrompt.CryptoObject(mockCipher)
        val mockResult = mock<BiometricPrompt.AuthenticationResult>().apply {
            whenever(this.cryptoObject).thenReturn(mockCryptoObject)
        }
        capturedCallback.onAuthenticationSucceeded(mockResult)

        // Let the coroutine process the callback
        advanceUntilIdle()

        // Await the coroutine to ensure it completes
        job.join()
    }

    @Test
    fun authenticateUser_cipher_null_throwsAuthenticationException() = runTest {
        // Ensure no interactions have occurred yet
        verifyNoInteractions(mockBiometricPromptFactory)

        // Act: Start `authenticateUser` in a coroutine that we can await/verify
        val job = launch {
            try {
                repository.authenticateUser(
                    activity = realActivity,
                    promptData = BIOMETRIC_PROMPT_DATA,
                    cipher = mockCipher
                )
                fail("Expected AuthenticationException to be thrown")
            } catch (ex: AuthenticationException.AuthenticationError) {
                assertEquals(ErrorType.AUTHENTICATION_ERROR.name, ex.code)
                assertEquals(ErrorType.AUTHENTICATION_ERROR.errorDescription, ex.message)
                assertEquals("Cipher is null", ex.originalCause?.message)
            }
        }

        // Advance the coroutine scheduler to ensure `authenticateUser` starts executing
        advanceUntilIdle()

        // Now verify that createBiometricPrompt() was indeed called
        verify(mockBiometricPromptFactory).createBiometricPrompt(
            any(),
            authenticationCallbackCaptor.capture()
        )

        val capturedCallback = authenticationCallbackCaptor.firstValue
        // Ensure that the captured callback is not null
        assertNotNull("Captured callback should not be null", capturedCallback)

        // Simulate an authentication with CryptoObject is null
        val mockResult = mock<BiometricPrompt.AuthenticationResult>()
        capturedCallback.onAuthenticationSucceeded(mockResult)

        // Let the coroutine process the callback
        advanceUntilIdle()

        // Await the coroutine to ensure it completes
        job.join()
    }

    @Test
    fun authenticateUser_errorCallback_throwsAuthenticationException() = runTest {
        // Ensure no interactions have occurred yet
        verifyNoInteractions(mockBiometricPromptFactory)

        val errorCode = BiometricPrompt.ERROR_NEGATIVE_BUTTON
        val errorString = "Authentication canceled"
        // Act: Start `authenticateUser` in a coroutine that we can await/verify
        val job = launch {
            try {
                repository.authenticateUser(
                    activity = realActivity,
                    promptData = BIOMETRIC_PROMPT_DATA,
                    cipher = mockCipher
                )
                fail("Expected AuthenticationCancelException to be thrown")
            } catch (ex: AuthenticationException.AuthenticationUserCanceled) {
                assertEquals(ErrorType.AUTHENTICATION_USER_CANCELED.name, ex.code)
                assertEquals(ErrorType.AUTHENTICATION_USER_CANCELED.errorDescription, ex.message)
                assertEquals("$errorCode: $errorString", ex.originalCause?.message)
            }
        }

        // Advance the coroutine scheduler to ensure `authenticateUser` starts executing
        advanceUntilIdle()

        // Now verify that createBiometricPrompt() was indeed called
        verify(mockBiometricPromptFactory).createBiometricPrompt(
            any(),
            authenticationCallbackCaptor.capture()
        )

        val capturedCallback = authenticationCallbackCaptor.firstValue
        // Ensure that the captured callback is not null
        assertNotNull("Captured callback should not be null", capturedCallback)

        // Simulate an authentication error
        capturedCallback.onAuthenticationError(errorCode, errorString)

        // Let the coroutine process the callback
        advanceUntilIdle()

        // Await the coroutine to ensure it completes
        job.join()
    }

    companion object {
        private val BIOMETRIC_PROMPT_DATA = BiometricPromptData(
            title = "Test Title",
            subtitle = "Test Subtitle",
            negativeButtonText = "Test Negative Button",
            description = "Test Description"
        )
    }
}
