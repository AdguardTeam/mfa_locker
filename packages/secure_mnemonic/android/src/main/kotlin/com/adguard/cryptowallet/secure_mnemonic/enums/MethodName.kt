package com.adguard.cryptowallet.secure_mnemonic.enums

enum class MethodName {
    GET_TPM_STATUS,
    GET_BIOMETRY_STATUS,
    GENERATE_KEY,
    ENCRYPT,
    DECRYPT,
    DELETE_KEY,
    CONFIGURE;

    override fun toString(): String =
        when (this) {
            GET_TPM_STATUS -> "getTPMStatus"
            GET_BIOMETRY_STATUS -> "getBiometryStatus"
            GENERATE_KEY -> "generateKey"
            ENCRYPT -> "encrypt"
            DECRYPT -> "decrypt"
            DELETE_KEY -> "deleteKey"
            CONFIGURE -> "configure"
        }
}
