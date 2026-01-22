package com.adguard.cryptowallet.secure_mnemonic.enums

enum class TPMStatus(val value: Int) {
    SUPPORTED(0),
    UNSUPPORTED(1),
    TPM_VERSION_UNSUPPORTED(2),
}
