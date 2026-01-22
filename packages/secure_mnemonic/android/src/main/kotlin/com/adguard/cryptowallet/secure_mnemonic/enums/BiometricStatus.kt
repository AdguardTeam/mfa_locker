package com.adguard.cryptowallet.secure_mnemonic.enums

import androidx.biometric.BiometricManager.*

enum class BiometricStatus(val value: Int) {
    SUPPORTED(0),
    UNSUPPORTED(1),
    DEVICE_NOT_PRESENT(2),
    NOT_CONFIGURED_FOR_USER(3),
    DISABLED_BY_POLICY(4),
    DEVICE_BUSY(5),
    ANDROID_BIOMETRIC_ERROR_SECURITY_UPDATE_REQUIRED(6);

    companion object {
        fun fromBiometricManagerValue(value: Int) = when (value) {
            BIOMETRIC_SUCCESS -> SUPPORTED
            BIOMETRIC_ERROR_HW_UNAVAILABLE -> UNSUPPORTED
            BIOMETRIC_ERROR_NONE_ENROLLED -> NOT_CONFIGURED_FOR_USER
            BIOMETRIC_ERROR_NO_HARDWARE -> DEVICE_NOT_PRESENT
            BIOMETRIC_ERROR_SECURITY_UPDATE_REQUIRED -> ANDROID_BIOMETRIC_ERROR_SECURITY_UPDATE_REQUIRED
            else -> UNSUPPORTED
        }
    }
}
