package com.adguard.cryptowallet.biometric_cipher.handlers

import android.content.Context
import android.util.Log
import com.adguard.cryptowallet.biometric_cipher.enums.ArgumentName
import com.adguard.cryptowallet.biometric_cipher.enums.MethodName
import com.adguard.cryptowallet.biometric_cipher.objects.SecureObjects
import com.adguard.cryptowallet.biometric_cipher.errors.ErrorType
import com.adguard.cryptowallet.biometric_cipher.exceptions.BaseException
import com.adguard.cryptowallet.biometric_cipher.model.AndroidConfig
import com.adguard.cryptowallet.biometric_cipher.model.ConfigData
import com.adguard.cryptowallet.biometric_cipher.services.AuthenticateService
import com.adguard.cryptowallet.biometric_cipher.services.SecureService
import com.adguard.cryptowallet.biometric_cipher.storages.ConfigStorage
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

class SecureMethodCallHandlerImpl(
    private val configStorage: ConfigStorage,
    private val secureService: SecureService,
    private val authenticateService: AuthenticateService
) : MethodChannel.MethodCallHandler, SecureMethodCallHandler {
    private val coroutineScope = CoroutineScope(Dispatchers.Main + Job())

    private var channel: MethodChannel? = null
    private var context: Context? = null

    override fun startListening(context: Context, binaryMessenger: BinaryMessenger) {
        if (channel != null) {
            Log.w(TAG, "Setting a method call handler before the last was disposed.")
            stopListening()
        }

        channel = MethodChannel(binaryMessenger, SecureObjects.CHANNEL_NAME)
        channel?.setMethodCallHandler(this)
        this.context = context
    }

    override fun stopListening() {
        coroutineScope.cancel()
        if (channel == null) {
            Log.w(TAG, "Tried to stop listening when no MethodChannel had been initialized.")
            return
        }
        channel?.setMethodCallHandler(null)
        channel = null
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            MethodName.GET_TPM_STATUS.toString() -> {
                executeOperation(operationName = MethodName.GET_TPM_STATUS.toString(),
                    operation = { secureService.getTPMStatus() },
                    onSuccess = { result.success(it.value) },
                    onError = { errorCode, errorMessage ->
                        result.error(errorCode, errorMessage, null)
                    })
            }

            MethodName.GET_BIOMETRY_STATUS.toString() -> {
                executeOperation(operationName = MethodName.GET_BIOMETRY_STATUS.toString(),
                    operation = { authenticateService.getBiometryStatus() },
                    onSuccess = { result.success(it.value) },
                    onError = { errorCode, errorMessage ->
                        result.error(errorCode, errorMessage, null)
                    })
            }

            MethodName.GENERATE_KEY.toString() -> {
                if (!checkArgument(call, ArgumentName.TAG, result)) {
                    return
                }

                val tag: String = call.argument<String>(ArgumentName.TAG.toString())!!

                executeOperation(operationName = MethodName.GENERATE_KEY.toString(),
                    operation = { secureService.generateKey(tag) },
                    onSuccess = { result.success(null) },
                    onError = { errorCode, errorMessage ->
                        result.error(errorCode, errorMessage, null)
                    })
            }

            MethodName.ENCRYPT.toString() -> {
                if (!checkArgument(call, ArgumentName.TAG, result) || !checkArgument(
                        call,
                        ArgumentName.DATA,
                        result
                    )
                ) {
                    return
                }

                val tag: String = call.argument<String>(ArgumentName.TAG.toString())!!
                val data: String = call.argument<String>(ArgumentName.DATA.toString())!!

                executeOperation(operationName = MethodName.ENCRYPT.toString(),
                    operation = { secureService.encrypt(tag, data) },
                    onSuccess = { result.success(it) },
                    onError = { errorCode, errorMessage ->
                        result.error(errorCode, errorMessage, null)
                    })
            }

            MethodName.DECRYPT.toString() -> {
                if (!checkArgument(call, ArgumentName.TAG, result) || !checkArgument(
                        call,
                        ArgumentName.DATA,
                        result
                    )
                ) {
                    return
                }

                val tag: String = call.argument<String>(ArgumentName.TAG.toString())!!
                val data: String = call.argument<String>(ArgumentName.DATA.toString())!!

                executeOperation(operationName = MethodName.DECRYPT.toString(),
                    operation = { secureService.decrypt(tag, data) },
                    onSuccess = { result.success(it) },
                    onError = { errorCode, errorMessage ->
                        result.error(errorCode, errorMessage, null)
                    })
            }

            MethodName.DELETE_KEY.toString() -> {
                if (!checkArgument(call, ArgumentName.TAG, result)) {
                    return
                }

                val tag: String = call.argument<String>(ArgumentName.TAG.toString())!!

                executeOperation(operationName = MethodName.DELETE_KEY.toString(),
                    operation = { secureService.deleteKey(tag) },
                    onSuccess = { result.success(null) },
                    onError = { errorCode, errorMessage ->
                        result.error(errorCode, errorMessage, null)
                    })
            }

            MethodName.CONFIGURE.toString() -> {
                val biometricPromptTitle: String =
                    call.argument<String?>(ArgumentName.BIOMETRIC_PROMPT_TITLE.toString()) ?: ""

                val biometricPromptSubtitle: String =
                    call.argument<String?>(ArgumentName.BIOMETRIC_PROMPT_SUBTITLE.toString()) ?: ""

                val androidConfigMap =
                    call.argument<Map<String, Any?>>(ArgumentName.ANDROID_CONFIG.toString())
                val androidConfig = AndroidConfig(
                    promptTitle = androidConfigMap?.get("promptTitle") as? String ?: "",
                    promptSubtitle = androidConfigMap?.get("promptSubtitle") as? String ?: "",
                    promptDescription = androidConfigMap?.get("promptDescription") as? String ?: "",
                    negativeButtonText = androidConfigMap?.get("negativeButtonText") as? String
                        ?: ""
                )
                val configData = ConfigData(
                    biometricPromptTitle = biometricPromptTitle,
                    biometricPromptSubtitle = biometricPromptSubtitle,
                    androidConfig = androidConfig
                )
                executeOperation(operationName = MethodName.CONFIGURE.toString(),
                    operation = { configStorage.setConfigData(configData) },
                    onSuccess = { result.success(null) },
                    onError = { errorCode, errorMessage ->
                        result.error(errorCode, errorMessage, null)
                    })
            }

            else -> {
                Log.e(TAG, "Unknown method call: " + call.method)
                result.notImplemented()
            }
        }
    }

    private fun checkArgument(
        call: MethodCall,
        argumentName: ArgumentName,
        result: MethodChannel.Result,
    ): Boolean {
        val argumentString = argumentName.toString()
        if (!call.hasArgument(argumentString)) {
            Log.e(TAG, "The $argumentString is required but was not provided.")
            result.error(
                ErrorType.INVALID_ARGUMENT.toString(),
                "The $argumentString is required but was not provided.",
                null,
            )
            return false
        }

        val argument: String = call.argument<String>(argumentString)!!
        if (argument.isEmpty()) {
            Log.e(TAG, "The $argumentString is empty")
            result.error(
                ErrorType.INVALID_ARGUMENT.toString(),
                "The $argumentString cannot be empty",
                null,
            )
            return false
        }
        return true
    }

    private fun <T> executeOperation(
        operationName: String,
        operation: suspend () -> T,
        onSuccess: (T) -> Unit,
        onError: (String, String) -> Unit
    ) {
        coroutineScope.launch {
            try {
                val result = operation()
                onSuccess(result)
            } catch (e: Exception) {
                val errorCode = when (e) {
                    is BaseException -> {
                        e.code
                    }

                    else -> {
                        operationName
                    }
                }
                val errorMessage = e.message ?: ErrorType.UNKNOWN_EXCEPTION.errorDescription
                Log.e(TAG, "Error during '$operationName': $errorCode, details: $errorMessage")
                onError(errorCode, errorMessage)
            }
        }
    }

    companion object {
        private val TAG = SecureMethodCallHandlerImpl::class.java.simpleName
    }
}
