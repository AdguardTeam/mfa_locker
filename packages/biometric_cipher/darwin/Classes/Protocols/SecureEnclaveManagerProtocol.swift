/// A protocol that manages Secure Enclave key pair operations and data encryption/decryption.
protocol SecureEnclaveManagerProtocol {
    /// Sets the authentication prompt title shown during biometric key access.
    func configure(authTitle: String) throws

    /// Returns whether the Secure Enclave is available on this device.
    func isSecureEnclaveSupported() -> Bool

    /// Generates a new key pair in the Secure Enclave identified by `tag`.
    func generateKeyPair(tag: String) throws

    /// Deletes the key pair identified by `tag` from the Secure Enclave.
    func deleteKey(tag: String) throws

    /// Checks whether the key identified by `tag` exists and is usable.
    func isKeyValid(tag: String) -> Bool

    /// Encrypts a string using the public key associated with `tag`.
    func encrypt(_ encryptionString: String, tag: String) throws -> Data

    /// Decrypts data using the private key associated with `tag`.
    func decrypt(_ encryptedData: Data, tag: String) throws -> String
}
