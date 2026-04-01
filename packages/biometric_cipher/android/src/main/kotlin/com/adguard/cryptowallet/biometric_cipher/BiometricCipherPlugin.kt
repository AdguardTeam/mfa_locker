package com.adguard.cryptowallet.biometric_cipher

import android.app.Activity
import androidx.biometric.BiometricManager
import com.adguard.cryptowallet.biometric_cipher.factories.BiometricPromptFactoryImpl
import com.adguard.cryptowallet.biometric_cipher.handlers.ScreenLockStreamHandler
import com.adguard.cryptowallet.biometric_cipher.handlers.SecureMethodCallHandler
import com.adguard.cryptowallet.biometric_cipher.handlers.SecureMethodCallHandlerImpl
import com.adguard.cryptowallet.biometric_cipher.repositories.AuthenticationRepositoryImpl
import com.adguard.cryptowallet.biometric_cipher.repositories.SecureRepositoryImpl
import com.adguard.cryptowallet.biometric_cipher.services.AuthenticateServiceImpl
import com.adguard.cryptowallet.biometric_cipher.services.SecureServiceImpl
import com.adguard.cryptowallet.biometric_cipher.storages.ConfigStorageImpl
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.flow.MutableStateFlow

/** BiometricCipherPlugin */
class BiometricCipherPlugin : FlutterPlugin, ActivityAware {
    private lateinit var biometricCipherMethodCallHandler: SecureMethodCallHandler

    private val activityStateFlow = MutableStateFlow<Activity?>(null)

    private var screenLockEventChannel: EventChannel? = null
    private var screenLockStreamHandler: ScreenLockStreamHandler? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        val context = flutterPluginBinding.applicationContext

        val packageManager = context.packageManager
        val biometricManager = BiometricManager.from(context)

        val secureRepository = SecureRepositoryImpl(
            packageManager = packageManager,
            biometricManager = biometricManager

        )
        val biometricPromptFactory = BiometricPromptFactoryImpl()
        val authenticationRepository = AuthenticationRepositoryImpl(
            biometricManager = biometricManager,
            biometricPromptFactory = biometricPromptFactory
        )

        val configStorage = ConfigStorageImpl()

        val authenticateService = AuthenticateServiceImpl(
            activityStateFlow = activityStateFlow,
            configStorage = configStorage,
            authenticationRepository = authenticationRepository
        )

        val secureService = SecureServiceImpl(
            secureRepository = secureRepository,
            authenticateService = authenticateService
        )
        biometricCipherMethodCallHandler = SecureMethodCallHandlerImpl(
            configStorage = configStorage,
            secureService = secureService,
            authenticateService = authenticateService
        )
        biometricCipherMethodCallHandler.startListening(
            flutterPluginBinding.applicationContext,
            flutterPluginBinding.binaryMessenger
        )

        val streamHandler = ScreenLockStreamHandler(flutterPluginBinding.applicationContext)
        val eventChannel = EventChannel(
            flutterPluginBinding.binaryMessenger,
            "biometric_cipher/screen_lock",
        )
        eventChannel.setStreamHandler(streamHandler)
        screenLockEventChannel = eventChannel
        screenLockStreamHandler = streamHandler
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityStateFlow.value = binding.activity
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        biometricCipherMethodCallHandler.stopListening()
        screenLockEventChannel?.setStreamHandler(null)
        screenLockEventChannel = null
        screenLockStreamHandler = null
    }

    override fun onDetachedFromActivity() {
        activityStateFlow.value = null
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityStateFlow.value = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activityStateFlow.value = binding.activity
    }
}
