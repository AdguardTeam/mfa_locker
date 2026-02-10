/// Exception codes for secure mnemonic operations.
enum SecureMnemonicExceptionCode {
  /// An invalid argument was provided to the operation.
  invalidArgument,

  /// The requested cryptographic key was not found in storage.
  keyNotFound,

  /// A key with the given identifier already exists.
  keyAlreadyExists,

  /// Biometric authentication is not supported on this device.
  biometricNotSupported,

  /// The user canceled the biometric authentication prompt.
  authenticationUserCanceled,

  /// Biometric or device authentication failed.
  authenticationError,

  /// Data encryption failed.
  encryptionError,

  /// Data decryption failed.
  decryptionError,

  /// Cryptographic key generation failed.
  keyGenerationError,

  /// Cryptographic key deletion failed.
  keyDeletionError,

  /// The Secure Enclave is unavailable on this device.
  secureEnclaveUnavailable,

  /// The device TPM is unsupported or has an incompatible version.
  tpmUnsupported,

  /// Platform plugin configuration failed.
  configureError,

  /// An unknown or unclassified error occurred.
  unknown;

  static SecureMnemonicExceptionCode fromString(String code) => switch (code) {
    'INVALID_ARGUMENT' => invalidArgument,

    'KEY_NOT_FOUND' || 'FAILED_GET_PRIVATE_KEY' || 'FAILED_GET_PUBLIC_KEY' => keyNotFound,

    'KEY_ALREADY_EXISTS' => keyAlreadyExists,

    'BIOMETRIC_NOT_SUPPORTED' || 'BIOMETRY_NOT_SUPPORTED' || 'BIOMETRY_NOT_AVAILABLE' => biometricNotSupported,

    'AUTHENTICATION_USER_CANCELED' => authenticationUserCanceled,

    'AUTHENTICATION_ERROR' ||
    'ERROR_EVALUATING_BIOMETRY' ||
    'USER_PREFERS_PASSWORD' ||
    'SECURE_DEVICE_LOCKED' => authenticationError,

    'ENCRYPT_ERROR' ||
    'ENCRYPTION_ERROR' ||
    'FAILED_TO_ENCRYPT_DATA' ||
    'ENCRYPTION_ALGORITHM_NOT_SUPPORTED' ||
    'INVALID_ENCRYPTION_DATA' => encryptionError,

    'DECRYPT_ERROR' ||
    'DECRYPTION_ERROR' ||
    'FAILED_TO_DECRYPT_DATA' ||
    'DECRYPTION_ALGORITHM_NOT_SUPPORTED' ||
    'DECODE_DECRYPTED_DATA_ERROR' ||
    'DECODE_DATA_INVALID_SIZE' => decryptionError,

    'GENERATE_KEY_ERROR' ||
    'KEY_GENERATION_ERROR' ||
    'FAILED_TO_CREATE_RANDOM_KEY' ||
    'FAILED_TO_COPY_PUBLIC_KEY' => keyGenerationError,

    'DELETE_KEY_ERROR' || 'KEY_DELETION_ERROR' || 'FAILED_TO_DELETE_ITEM' => keyDeletionError,

    'SECURE_ENCLAVE_UNAVAILABLE' => secureEnclaveUnavailable,

    'TPM_UNSUPPORTED' || 'TPM_VERSION_ERROR' => tpmUnsupported,

    'CONFIGURE_ERROR' ||
    'CONFIGURE_BIOMETRIC_ERROR' ||
    'CONFIGURE_NEGATIVE_BUTTON_ERROR' ||
    'CONFIGURE_TITLE_PROMPT_ERROR' ||
    'CONFIGURE_SUBTITLE_PROMPT_ERROR' ||
    'FAILED_CREATE_SEC_ACCESS_CONTROL' ||
    'INVALID_TAG_ERROR' ||
    'INVALID_AUTH_TITLE_ERROR' ||
    'ACTIVITY_NOT_SET' => configureError,

    'UNKNOWN_ERROR' || 'UNKNOWN_EXCEPTION' || 'CONVERTING_STRING_ERROR' || _ => unknown,
  };
}
