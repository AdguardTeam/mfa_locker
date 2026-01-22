protocol SecureEnclaveManagerProtocol{
    func configure(authTitle: String) throws
    func isSecureEnclaveSupported() -> Bool
    func generateKeyPair(tag: String) throws
    func deleteKey(tag: String) throws
    func encrypt(_ encryptionString: String, tag: String) throws -> Data
    func decrypt(_ encryptedData: Data, tag: String) throws -> String
}
