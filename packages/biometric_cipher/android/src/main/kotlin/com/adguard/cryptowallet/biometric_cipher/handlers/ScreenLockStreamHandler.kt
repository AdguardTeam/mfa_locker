package com.adguard.cryptowallet.biometric_cipher.handlers

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import io.flutter.plugin.common.EventChannel

class ScreenLockStreamHandler(
    private val applicationContext: Context,
) : EventChannel.StreamHandler {

    private var receiver: BroadcastReceiver? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        val screenOffReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == Intent.ACTION_SCREEN_OFF) {
                    events?.success(true)
                }
            }
        }

        val filter = IntentFilter(Intent.ACTION_SCREEN_OFF)
        applicationContext.registerReceiver(screenOffReceiver, filter)
        receiver = screenOffReceiver
    }

    override fun onCancel(arguments: Any?) {
        receiver?.let { applicationContext.unregisterReceiver(it) }
        receiver = null
    }
}
