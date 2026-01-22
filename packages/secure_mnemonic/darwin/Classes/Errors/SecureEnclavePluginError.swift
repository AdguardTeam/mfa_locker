/// An enumeration representing the errors that can occur in the Secure Enclave plugin.
///
/// These errors cover scenarios such as the unavailability of Secure Enclave,
/// invalid input arguments, and failures during cryptographic operations.
enum SecureEnclavePluginError: BaseError {
    
    /// Indicates that the Secure Enclave is unavailable on the device.
    case secureEnclaveNoAvailable

    /// Indicates that biometric authentication is not available on the device.
    case biometryNotAvailable
    
    /// Indicates that the provided arguments are invalid.
    case invalidArgument
    
    /// Represents an error that occurred during key pair generation or export.
    /// - Parameter error: The underlying error that caused the failure.
    case keyGenerationError(error: Error)
    
    /// Represents an error that occurred during encryption.
    /// - Parameter error: The underlying error that caused the failure.
    case encryptionError(error: Error)
    
    /// Represents an error that occurred during decryption.
    /// - Parameter error: The underlying error that caused the failure.
    case decryptionError(error: Error)

    /// Represents an error that occurred during key deletion.
    /// - Parameter error: The underlying error that caused the failure.
    case keyDeletionError(error: Error)
    
    /// Represents an unknown error.
    case unknown
    
    /// A unique string representing the error code.
    var code: String {
        switch self {
        case .secureEnclaveNoAvailable:
            return "SECURE_ENCLAVE_UNAVAILABLE"
        case .biometryNotAvailable:
            return "BIOMETRY_NOT_AVAILABLE"
        case .invalidArgument:
            return "INVALID_ARGUMENT"
        case .keyGenerationError:
            return "KEY_GENERATION_ERROR"
        case .encryptionError:
            return "ENCRYPTION_ERROR"
        case .decryptionError:
            return "DECRYPTION_ERROR"
        case .keyDeletionError:
            return "KEY_DELETION_ERROR"
        case .unknown:
            return "UNKNOWN_ERROR"
        }
    }
    
    /// A message describing the error.
    var errorDescription: String {
        switch self {
        case .secureEnclaveNoAvailable:
            return "Secure Enclave is not available on this device."
        case .biometryNotAvailable:
            return "Biometric authentication is not available on this device."
        case .invalidArgument:
            return "Invalid argument provided."
        case .keyGenerationError(let error):
            return "Failed to generate or export key pair: \(error.localizedDescription)"
        case .encryptionError(let error):
            return "Failed to encrypt data: \(error.localizedDescription)"
        case .decryptionError(let error):
            return "Failed to decrypt data: \(error.localizedDescription)"
        case .keyDeletionError(let error):
            return "Failed to delete key: \(error.localizedDescription)"
        case .unknown:
            return "An unknown error occurred."
        }
    }
}
