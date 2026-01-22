import LocalAuthentication

/// Provides cryptographic operations using the Secure Enclave.
///
/// The `SecureEnclaveManager` class implements methods for managing keys, encryption,
/// and decryption using the Secure Enclave. It conforms to the `SecureEnclaveManagerProtocol`.
///
/// - Note: Secure Enclave functionality is available only on supported devices.
final class SecureEnclaveManager : SecureEnclaveManagerProtocol {
    
    var authTitle: String?
    
    private let keychainService: KeychainServiceProtocol
    private let laContextFactory: LAContextFactoryProtocol
    
    init(keychainService: KeychainServiceProtocol = KeychainService(),
         laContextFactory: LAContextFactoryProtocol = LAContextFactory()) {
        self.keychainService = keychainService
        self.laContextFactory = laContextFactory
    }
    
    /// Configures a Secure Enclave with the specified header for biometric authentication.
    ///
    /// - Parameter authTitle: Title to display to the user during authentication.
    func configure(authTitle: String) throws {
        if (authTitle.isEmpty){
            throw SecureEnclaveManagerError.invalidAuthTitle
        }
        
        self.authTitle = authTitle
    }
    
    /// Checks if the Secure Enclave is available on the device.
    ///
    /// - Returns: `true` if the Secure Enclave is supported, otherwise `false`.
    /// - Note: This method attempts to create a test key to verify Secure Enclave support.
    func isSecureEnclaveSupported()  -> Bool {
        let laContext = laContextFactory.createContext()
        guard let accessControl = try? AuthenticationManager.getAccessControl(laContext) else {
            return false
        }
        
        // Define attributes for the key
        let attributes: [CFString: Any] = [
            kSecAttrKeyType:           kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits:     256,
            kSecAttrTokenID:           kSecAttrTokenIDSecureEnclave,
            kSecAttrAccessControl:     accessControl,
            kSecPrivateKeyAttrs: [
                // Making the key temporary and preventing it from being stored, which increases security and reduces the risk of key leakage.
                kSecAttrIsPermanent: false
            ]
        ]
        
        // Attempt to create a key in the Secure Enclave
        let key = try? keychainService.createRandomKey(attributes as CFDictionary)
        
        // Key successfully created, Secure Enclave is available.
        return key != nil
    }
    
    /// Generates a cryptographic key pair in the Secure Enclave.
    ///
    /// If a key pair already exists with the specified tag, the method does nothing.
    ///
    /// - Throws: An error if key pair generation fails or if the Secure Enclave is unavailable.
    func generateKeyPair(tag: String) throws {
        let privateKeyTag = try getTagData(tag: tag)
        
        // Check if a private key already exists
        if let _ = getPrivateKey(tag: privateKeyTag) {
            // A key with the specified tag already exists, so terminate the current function
            throw SecureEnclaveManagerError.keyAlreadyExists
        }
        
        let laContext = laContextFactory.createContext()
        let accessControl = try AuthenticationManager.getAccessControl(laContext)
        
        // Attributes for the private key
        let privateKeyAttributes: [String: Any] = [
            kSecAttrIsPermanent as String:      true,
            kSecAttrApplicationTag as String:   privateKeyTag,
            kSecAttrAccessControl as String:    accessControl
        ]
        
        // Attributes for a key pair
        let attributes: [String: Any] = [
            kSecAttrKeyType as String:        kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String:  256,
            kSecAttrTokenID as String:        kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String:    privateKeyAttributes
        ]
        
        // Generating a key pair
        _ = try keychainService.createRandomKey(attributes as CFDictionary)
    }
    
    /// Deletes a cryptographic key from the Keychain.
    ///
    /// - Parameter tag: A string representing the unique tag of the key to delete.
    /// - Throws: An error if the tag is invalid or if the key deletion fails.
    func deleteKey(tag: String) throws {
        let privateKeyTag = try getTagData(tag: tag)
        
        let query: [String: Any] = [
            kSecClass as String:                kSecClassKey,
            kSecAttrApplicationTag as String:   privateKeyTag,
            kSecAttrKeyType as String:          kSecAttrKeyTypeECSECPrimeRandom
        ]
        
        _ = try keychainService.deleteItem(query as CFDictionary)
    }
    
    /// Encrypts a string using the Secure Enclave's public key.
    ///
    /// - Parameter encryptionString: The string to be encrypted.
    /// - Returns: The encrypted data in `Data` format.
    /// - Throws: An error if the encryption fails or if the Secure Enclave is unavailable.
    func encrypt(_ encryptionString: String, tag: String) throws -> Data {
        let privateKeyTag = try getTagData(tag: tag)
        
        guard let privateKey = getPrivateKey(tag: privateKeyTag) else {
            throw SecureEnclaveManagerError.failedGetPrivateKey
        }
        
        guard let publicKey = try getPublicKey(privateKey: privateKey) else {
            throw SecureEnclaveManagerError.failedGetPublicKey
        }
        
        guard let encryptionData = encryptionString.data(using: .utf8) else {
            throw SecureEnclaveManagerError.invalidEncryptionData
        }
        
        let algorithm: SecKeyAlgorithm = .eciesEncryptionCofactorX963SHA256AESGCM
        
        // Verification of encryption algorithm support for the public key
        guard keychainService.isAlgorithmSupported(key: publicKey,
                                                   operation: .encrypt,
                                                   algorithm: algorithm) else {
            throw SecureEnclaveManagerError.encryptionAlgorithmNotSupported
        }
        
        let encryptedData = try keychainService.encryptData(key: publicKey,
                                                            algorithm: algorithm,
                                                            data: encryptionData)
        
        return encryptedData as Data
    }
    
    /// Decrypts encrypted data using the Secure Enclave's private key.
    ///
    /// - Parameter encryptedData: The encrypted data in `Data` format.
    /// - Returns: The decrypted string.
    /// - Throws: An error if the decryption fails or if the Secure Enclave is unavailable.
    func decrypt(_ encryptedData: Data, tag: String) throws -> String {
        let privateKeyTag = try getTagData(tag: tag)
        
        guard let privateKey = getPrivateKey(tag: privateKeyTag) else {
            throw SecureEnclaveManagerError.failedGetPrivateKey
        }
        
        let algorithm: SecKeyAlgorithm = .eciesEncryptionCofactorX963SHA256AESGCM
        
        // Checking decryption algorithm support for private key
        guard keychainService.isAlgorithmSupported(key: privateKey,
                                                   operation: .decrypt,
                                                   algorithm: algorithm) else {
            throw SecureEnclaveManagerError.decryptionAlgorithmNotSupported
        }
        
        let decryptedData = try keychainService.decryptData(key: privateKey,
                                                            algorithm: algorithm,
                                                            data: encryptedData)
        
        // Converting decrypted data to a string
        guard let decryptedString = String(data: decryptedData as Data, encoding: .utf8) else {
            throw SecureEnclaveManagerError.decodeEncryptedDataFailed
        }
        
        return decryptedString
    }
    
    /// Retrieves the public key corresponding to the provided private key.
    ///
    /// - Parameter privateKey: The private key stored in the Secure Enclave.
    /// - Returns: The public key as a `SecKey` object.
    /// - Throws: An error if the public key cannot be retrieved.
    private func getPublicKey(privateKey: SecKey) throws -> SecKey? {
        return try keychainService.copyPublicKey(privateKey)
    }
    
    /// Retrieves the private key stored in the Secure Enclave.
    ///
    /// - Returns: The private key as a `SecKey` object, or `nil` if the key does not exist.
    /// - Throws: An error if the private key cannot be retrieved.
    private func getPrivateKey(tag: Data) -> SecKey? {
        var query: [String: Any] = [
            kSecClass as String:                kSecClassKey,
            kSecAttrKeyType as String:          kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrTokenID as String:          kSecAttrTokenIDSecureEnclave,
            kSecAttrApplicationTag as String:   tag,
            kSecReturnRef as String:            true
        ]
        
        if let authTitle = authTitle {
            var laContext = laContextFactory.createContext()
            laContext.localizedReason = authTitle
            query[kSecUseAuthenticationContext as String] = laContext
        }
        
        let privateKey = keychainService.getPrivateKey(query as CFDictionary)
        
        return privateKey
    }
    
    private func getTagData(tag: String) throws -> Data{
        if (tag.isEmpty){
            throw SecureEnclaveManagerError.invalidTag
        }
        
        guard let privateKeyTag = ("\(AppConstants.privateKeyTag).\(tag)").data(using: .utf8) else {
            throw SecureEnclaveManagerError.invalidTag
        }
        
        return privateKeyTag
    }
}
