/// A protocol that abstracts low-level Keychain and Secure Enclave operations.
protocol KeychainServiceProtocol {
    /// Generates a random cryptographic key with the given attributes.
    func createRandomKey(_ attributes: CFDictionary) throws -> SecKey

    /// Deletes the Keychain item matching the query.
    func deleteItem(_ query: CFDictionary) throws

    /// Retrieves a private key from the Keychain matching the query, or `nil` if not found.
    func getPrivateKey(_ query: CFDictionary) -> SecKey?

    /// Derives and returns the public key from the given private key.
    func copyPublicKey(_ key: SecKey) throws -> SecKey

    /// Checks whether the given algorithm is supported for the specified key and operation type.
    func isAlgorithmSupported(key: SecKey, operation: SecKeyOperationType, algorithm: SecKeyAlgorithm) -> Bool

    /// Encrypts the data using the given key and algorithm.
    func encryptData(key: SecKey, algorithm: SecKeyAlgorithm, data: Data) throws -> Data

    /// Decrypts the data using the given key and algorithm.
    func decryptData(key: SecKey, algorithm: SecKeyAlgorithm, data: Data) throws -> Data

    /// Returns whether a Keychain item matching the query exists.
    func itemExists(_ query: CFDictionary) -> Bool
}
