import LocalAuthentication

class KeychainService: KeychainServiceProtocol {
    func createRandomKey(_ attributes: CFDictionary) throws -> SecKey {
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes, &error) else {
            throw KeychainServiceError.failedToCreateRandomKey(error?.takeRetainedValue())
        }
        return key
    }
    
    func deleteItem(_ query: CFDictionary) throws {
        let status = SecItemDelete(query)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainServiceError.failedToDeleteItem
        }
    }

    func getPrivateKey(_ query: CFDictionary) -> SecKey? {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query, &item)
        
        guard status == errSecSuccess else {
            return nil
        }
        
        let key = item as! SecKey

        return key
    }
    
    func copyPublicKey(_ key: SecKey) throws -> SecKey {
        guard let publicKey = SecKeyCopyPublicKey(key) else {
            throw KeychainServiceError.failedToCopyPublicKey
        }
        return publicKey
    }
    
    func isAlgorithmSupported(key: SecKey, operation: SecKeyOperationType, algorithm: SecKeyAlgorithm) -> Bool {
        return SecKeyIsAlgorithmSupported(key, operation, algorithm)
    }
    
    func encryptData(key: SecKey, algorithm: SecKeyAlgorithm, data: Data) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let encryptedData = SecKeyCreateEncryptedData(key, algorithm, data as CFData, &error) else {
            throw KeychainServiceError.failedToEncryptData(error?.takeRetainedValue())
        }
        return encryptedData as Data
    }
    
    func decryptData(key: SecKey, algorithm: SecKeyAlgorithm, data: Data) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let decryptedData = SecKeyCreateDecryptedData(key, algorithm, data as CFData, &error) else {
            if let cfError = error?.takeRetainedValue() {
                let errorCode = CFErrorGetCode(cfError)
                switch errorCode {
                case Int(errSecUserCanceled), Int(LAError.userCancel.rawValue):
                    throw KeychainServiceError.authenticationUserCanceled
                default:
                    throw KeychainServiceError.failedToDecryptData(cfError)
                }
            }
            throw KeychainServiceError.failedToDecryptData(nil)
        }
        return decryptedData as Data
    }
}
