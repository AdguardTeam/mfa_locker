package com.adguard.cryptowallet.secure_mnemonic.handlers

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger

interface SecureMethodCallHandler {
    fun startListening(context: Context, binaryMessenger: BinaryMessenger)

    fun stopListening()
}
