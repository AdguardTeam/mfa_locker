/// An enumeration of errors that can occur while using `SecureEnclaveManager`.
enum SecureEnclaveManagerError: BaseError {

    /// Indicates an invalid tag was encountered.
    case invalidTag
    
    //TODO: add docs
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
        }
    }
}
