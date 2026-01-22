import Foundation

/// Enumeration of errors that can occur when using `KeychainService`.
enum KeychainServiceError: BaseError {
    
    /// Failed to create a random key, with a possible underlying error.
    case failedToCreateRandomKey(Error?)
    
    /// Error occurred while deleting an item from the Keychain.
    case failedToDeleteItem
    
    /// Failed to retrieve the public key from a private key.
    case failedToCopyPublicKey
    
    /// Error occurred while encrypting data, with a possible underlying error.
    case failedToEncryptData(Error?)
    
    /// Error occurred while decrypting data, with a possible underlying error.
    case failedToDecryptData(Error?)
    
    /// Authentication was canceled by the user.
    case authenticationUserCanceled
    
    /// Returns a machine-readable error code.
    var code: String {
        switch self {
        case .failedToCreateRandomKey:
            return "FAILED_TO_CREATE_RANDOM_KEY"
        case .failedToDeleteItem:
            return "FAILED_TO_DELETE_ITEM"
        case .failedToCopyPublicKey:
            return "FAILED_TO_COPY_PUBLIC_KEY"
        case .failedToEncryptData:
            return "FAILED_TO_ENCRYPT_DATA"
        case .failedToDecryptData:
            return "FAILED_TO_DECRYPT_DATA"
        case .authenticationUserCanceled:
            return "AUTHENTICATION_USER_CANCELED"
        }
    }
    
    /// Returns a human-readable error description.
    var errorDescription: String {
        switch self {
        case .failedToCreateRandomKey(let error):
            return "Failed to create a random key. Error details: \(error?.localizedDescription ?? "no details available")."
        case .failedToDeleteItem:
            return "Failed to delete an item from the Keychain."
        case .failedToCopyPublicKey:
            return "Failed to retrieve the public key from the private key."
        case .failedToEncryptData(let error):
            return "Error occurred while encrypting data. Error details: \(error?.localizedDescription ?? "no details available")."
        case .failedToDecryptData(let error):
            return "Error occurred while decrypting data. Error details: \(error?.localizedDescription ?? "no details available")."
        case .authenticationUserCanceled:
            return "Authentication was canceled by the user."
        }
    }
}
