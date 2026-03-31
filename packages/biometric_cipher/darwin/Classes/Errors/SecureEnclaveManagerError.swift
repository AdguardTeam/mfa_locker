/// An enumeration of errors that can occur while using `SecureEnclaveManager`.
enum SecureEnclaveManagerError: BaseError {

    /// Indicates an invalid tag was encountered.
    case invalidTag

    /// The biometric authentication title provided to `configure()` was empty.
    /// A non-empty title is required to display the system biometric prompt.
    case invalidAuthTitle

    /// Indicates a failure to retrieve the private key from storage.
    case failedGetPrivateKey

    /// Indicates a failure to retrieve the public key from storage.
    case failedGetPublicKey

    /// Indicates that the encryption data provided is invalid.
    case invalidEncryptionData

    /// Indicates that the encryption algorithm is not supported.
    case encryptionAlgorithmNotSupported

    /// Indicates that the decryption algorithm is not supported.
    case decryptionAlgorithmNotSupported

    /// Indicates a failure to decode decrypted data.
    case decodeEncryptedDataFailed

    /// Represents an error when attempting to create a key that already exists.
    case keyAlreadyExists

    /// The biometric key has been permanently invalidated due to a biometric enrollment change.
    case keyPermanentlyInvalidated

    /// Biometric or device authentication failed (e.g., wrong fingerprint or device password).
    case authenticationFailed

    /// Returns a machine-readable error code.
    var code: String {
        switch self {
        case .invalidTag:
            return "INVALID_TAG_ERROR"
        case .invalidAuthTitle:
            return "INVALID_AUTH_TITLE_ERROR"
        case .failedGetPrivateKey:
            return "FAILED_GET_PRIVATE_KEY"
        case .failedGetPublicKey:
            return "FAILED_GET_PUBLIC_KEY"
        case .invalidEncryptionData:
            return "INVALID_ENCRYPTION_DATA"
        case .encryptionAlgorithmNotSupported:
            return "ENCRYPTION_ALGORITHM_NOT_SUPPORTED"
        case .decryptionAlgorithmNotSupported:
            return "DECRYPTION_ALGORITHM_NOT_SUPPORTED"
        case .decodeEncryptedDataFailed:
            return "DECODE_DECRYPTED_DATA_ERROR"
        case .keyAlreadyExists:
            return "KEY_ALREADY_EXISTS"
        case .keyPermanentlyInvalidated:
            return "KEY_PERMANENTLY_INVALIDATED"
        case .authenticationFailed:
            return "AUTHENTICATION_ERROR"
        }
    }

    /// Returns a human-readable description of the error.
    var errorDescription: String {
        switch self {
        case .invalidTag:
            return "Invalid tag."
        case .invalidAuthTitle:
            return "Invalid auth title."
        case .failedGetPrivateKey:
            return "Failed to get private key from storage."
        case .failedGetPublicKey:
            return "Failed to get public key from storage."
        case .invalidEncryptionData:
            return "Invalid encryption data."
        case .encryptionAlgorithmNotSupported:
            return "The encryption algorithm is not supported."
        case .decryptionAlgorithmNotSupported:
            return "The decryption algorithm is not supported."
        case .decodeEncryptedDataFailed:
            return "Failed to decode decrypted data."
        case .keyAlreadyExists:
            return "A key with the same tag already exists."
        case .keyPermanentlyInvalidated:
            return "Biometric key has been permanently invalidated."
        case .authenticationFailed:
            return "Biometric or device authentication failed."
        }
    }
}
