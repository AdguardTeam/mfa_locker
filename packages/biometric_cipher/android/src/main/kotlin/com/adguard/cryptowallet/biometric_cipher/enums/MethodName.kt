package com.adguard.cryptowallet.biometric_cipher.enums

enum class MethodName {
    GET_TPM_STATUS,
    GET_BIOMETRY_STATUS,
    GENERATE_KEY,
    ENCRYPT,
    DECRYPT,
    DELETE_KEY,
    IS_KEY_VALID,
    CONFIGURE;

    override fun toString(): String =
        when (this) {
            GET_TPM_STATUS -> "getTPMStatus"
            GET_BIOMETRY_STATUS -> "getBiometryStatus"
            GENERATE_KEY -> "generateKey"
            ENCRYPT -> "encrypt"
            DECRYPT -> "decrypt"
            DELETE_KEY -> "deleteKey"
            IS_KEY_VALID -> "isKeyValid"
            CONFIGURE -> "configure"
        }
}
