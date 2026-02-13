/// A protocol that abstracts low-level Keychain and Secure Enclave operations.
protocol KeychainServiceProtocol {
    func createRandomKey(_ attributes: CFDictionary) throws -> SecKey
    func deleteItem(_ query: CFDictionary) throws
    func getPrivateKey(_ query: CFDictionary) -> SecKey?
    func copyPublicKey(_ key: SecKey) throws -> SecKey
    func isAlgorithmSupported(key: SecKey, operation: SecKeyOperationType, algorithm: SecKeyAlgorithm) -> Bool
    func encryptData(key: SecKey, algorithm: SecKeyAlgorithm, data: Data) throws -> Data
    func decryptData(key: SecKey, algorithm: SecKeyAlgorithm, data: Data) throws -> Data
}
