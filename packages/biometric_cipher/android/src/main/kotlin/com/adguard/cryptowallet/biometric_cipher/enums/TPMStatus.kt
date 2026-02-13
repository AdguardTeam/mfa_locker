package com.adguard.cryptowallet.biometric_cipher.enums

enum class TPMStatus(val value: Int) {
    SUPPORTED(0),
    UNSUPPORTED(1),
    TPM_VERSION_UNSUPPORTED(2),
}
