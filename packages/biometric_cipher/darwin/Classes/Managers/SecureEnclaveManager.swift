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
    private let userDefaults: UserDefaults

    init(keychainService: KeychainServiceProtocol = KeychainService(),
         laContextFactory: LAContextFactoryProtocol = LAContextFactory(),
         userDefaults: UserDefaults = .standard) {
        self.keychainService = keychainService
        self.laContextFactory = laContextFactory
        self.userDefaults = userDefaults
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
        saveEnrollmentState(tag: privateKeyTag)
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
        deleteEnrollmentState(tag: privateKeyTag)
    }

    /// Checks whether a Secure Enclave key with the given tag exists in the keychain
    /// without triggering any biometric prompt.
    ///
    /// - Parameter tag: A string representing the unique tag of the key to check.
    /// - Returns: `true` if the key exists and has not been invalidated, `false` otherwise.
    func isKeyValid(tag: String) -> Bool {
        guard let tagData = try? getTagData(tag: tag) else {
            return false
        }
        guard keyExists(tag: tagData) else {
            return false
        }
        // On macOS, invalidated Secure Enclave keys may remain in the Keychain
        // with status errSecInteractionNotAllowed, indistinguishable from valid
        // keys. Detect enrollment changes via LAContext domain state.
        if hasEnrollmentChanged(tag: tagData) {
            return false
        }
        return true
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
            if !keyExists(tag: privateKeyTag) {
                throw SecureEnclaveManagerError.keyPermanentlyInvalidated
            }
            throw SecureEnclaveManagerError.failedGetPrivateKey
        }

        let algorithm: SecKeyAlgorithm = .eciesEncryptionCofactorX963SHA256AESGCM

        // Checking decryption algorithm support for private key
        guard keychainService.isAlgorithmSupported(key: privateKey,
                                                   operation: .decrypt,
                                                   algorithm: algorithm) else {
            throw SecureEnclaveManagerError.decryptionAlgorithmNotSupported
        }

        let decryptedData: Data
        do {
            decryptedData = try keychainService.decryptData(key: privateKey,
                                                            algorithm: algorithm,
                                                            data: encryptedData)
        } catch let error as KeychainServiceError {
            if case .authenticationUserCanceled = error {
                throw error
            }
            if !isKeyValid(tag: tag) {
                throw SecureEnclaveManagerError.keyPermanentlyInvalidated
            }
            if case .failedToDecryptData(let underlying) = error,
               (underlying as? NSError)?.code == Int(errSecAuthFailed) {
                throw SecureEnclaveManagerError.authenticationFailed
            }
            throw error
        }

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

    /// Returns `true` if a Secure Enclave key item with the given tag exists in the keychain,
    /// regardless of whether the caller can authenticate to use it.
    ///
    /// Uses `kSecUseAuthenticationUISkip` to suppress any biometric prompt.
    func keyExists(tag: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:              kSecClassKey,
            kSecAttrKeyType as String:        kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrTokenID as String:        kSecAttrTokenIDSecureEnclave,
            kSecAttrApplicationTag as String: tag,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip,
            kSecReturnAttributes as String:   true,
        ]
        // errSecSuccess              -> item found and accessible -> key still present
        // errSecInteractionNotAllowed -> item exists but requires auth UI (suppressed) -> key still present
        // errSecItemNotFound          -> item deleted by OS after biometric change -> key gone
        return keychainService.itemExists(query as CFDictionary)
    }

    // MARK: - Biometric enrollment state tracking

    /// Saves the current biometric enrollment state for the given key tag.
    ///
    /// Uses `LAContext.evaluatedPolicyDomainState` to capture a snapshot of the
    /// biometric enrollment. This is compared later in `isKeyValid()` to detect
    /// enrollment changes that invalidate `.biometryCurrentSet` keys.
    private func saveEnrollmentState(tag: Data) {
        let laContext = laContextFactory.createContext()
        var error: NSError?
        guard laContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error),
              let domainState = laContext.evaluatedPolicyDomainState else {
            return
        }
        let key = AppConstants.enrollmentStateKeyPrefix + tag.base64EncodedString()
        userDefaults.set(domainState, forKey: key)
    }

    /// Returns `true` if biometric enrollment has changed since the key was created.
    ///
    /// Compares the current `evaluatedPolicyDomainState` with the snapshot saved
    /// during key generation. On macOS, this is the only reliable way to detect
    /// key invalidation without triggering a biometric prompt.
    private func hasEnrollmentChanged(tag: Data) -> Bool {
        let laContext = laContextFactory.createContext()
        var error: NSError?
        guard laContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error),
              let currentState = laContext.evaluatedPolicyDomainState else {
            return false
        }
        let key = AppConstants.enrollmentStateKeyPrefix + tag.base64EncodedString()
        guard let savedState = userDefaults.data(forKey: key) else {
            return false
        }
        return savedState != currentState
    }

    /// Removes the stored enrollment state for the given key tag.
    private func deleteEnrollmentState(tag: Data) {
        let key = AppConstants.enrollmentStateKeyPrefix + tag.base64EncodedString()
        userDefaults.removeObject(forKey: key)
    }
}
