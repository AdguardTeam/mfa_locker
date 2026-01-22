@testable import secure_mnemonic

/// A mock implementation of KeychainServiceProtocol for unit tests.
/// This allows forcing errors or specific return values in our SecureEnclaveManager tests.
final class MockKeychainService: KeychainServiceProtocol {
    // MARK: - Properties
    
    var createRandomKeyResult: SecKey? = nil
    var createRandomKeyError: KeychainServiceError? = nil
    
    var deleteItemError: KeychainServiceError? = nil
    
    var copyPublicKeyResult: SecKey?
    
    var isAlgorithmSupportedResult: Bool = true
    
    var encryptDataResult: Data?
    var decryptDataResult: Data?
    
    // MARK: - KeychainServiceProtocol Methods
    
    func createRandomKey(_ attributes: CFDictionary) throws -> SecKey {
        if let error = createRandomKeyError {
            throw error
        }
        guard let key = createRandomKeyResult else {
            throw KeychainServiceError.failedToCreateRandomKey(nil)
        }
        return key
    }
    
    func deleteItem(_ query: CFDictionary) throws {
        if let error = deleteItemError {
            throw error
        }
        // Successful deletion does not require any action
    }
    
    func getPrivateKey(_ query: CFDictionary) -> SecKey? {
        if createRandomKeyError != nil {
            return nil
        }
        guard let key = createRandomKeyResult else {
            return nil
        }
        return key
    }
    
    func copyPublicKey(_ key: SecKey) throws -> SecKey {
        guard let publicKey = copyPublicKeyResult else {
            throw KeychainServiceError.failedToCopyPublicKey
        }
        return publicKey
    }
    
    func isAlgorithmSupported(key: SecKey, operation: SecKeyOperationType, algorithm: SecKeyAlgorithm) -> Bool {
        return isAlgorithmSupportedResult
    }
    
    func encryptData(key: SecKey, algorithm: SecKeyAlgorithm, data: Data) throws -> Data {
        guard let encryptedData = encryptDataResult else {
            throw KeychainServiceError.failedToEncryptData(nil)
        }
        return encryptedData
    }
    
    func decryptData(key: SecKey, algorithm: SecKeyAlgorithm, data: Data) throws -> Data {
        guard let decryptedData = decryptDataResult else {
            throw KeychainServiceError.failedToDecryptData(nil)
        }
        return decryptedData
    }
}
