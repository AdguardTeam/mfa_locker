package com.adguard.cryptowallet.biometric_cipher.handlers

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import io.flutter.plugin.common.EventChannel

class ScreenLockStreamHandler(
    private val applicationContext: Context,
) : EventChannel.StreamHandler {

    private var receiver: BroadcastReceiver? = null
    private var eventSink: EventChannel.EventSink? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        unregisterReceiver()

        eventSink = events

        val screenOffReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == Intent.ACTION_SCREEN_OFF) {
                    eventSink?.success(true)
                }
            }
        }

        val filter = IntentFilter(Intent.ACTION_SCREEN_OFF)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            applicationContext.registerReceiver(screenOffReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            applicationContext.registerReceiver(screenOffReceiver, filter)
        }
        receiver = screenOffReceiver
    }

    override fun onCancel(arguments: Any?) {
        unregisterReceiver()
        eventSink = null
    }

    fun dispose() {
        unregisterReceiver()
        eventSink?.endOfStream()
        eventSink = null
    }

    private fun unregisterReceiver() {
        receiver?.let {
            try {
                applicationContext.unregisterReceiver(it)
            } catch (_: IllegalArgumentException) {
                // Already unregistered
            }
        }
        receiver = null
    }
}
