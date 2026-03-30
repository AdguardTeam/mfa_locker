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

    func configure(authTitle: String) throws {
        if (authTitle.isEmpty){
            throw SecureEnclaveManagerError.invalidAuthTitle
        }

        self.authTitle = authTitle
    }

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

    func encrypt(_ encryptionString: String, tag: String) throws -> Data {
        let privateKeyTag = try getTagData(tag: tag)
        let privateKey = try requirePrivateKey(tag: privateKeyTag)

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

    func decrypt(_ encryptedData: Data, tag: String) throws -> String {
        let privateKeyTag = try getTagData(tag: tag)
        let privateKey = try requirePrivateKey(tag: privateKeyTag)

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
            // Capture before isKeyValid() which may backfill the state
            let enrollmentTracked = enrollmentStateExists(tag: privateKeyTag)
            if !isKeyValid(tag: tag) {
                throw SecureEnclaveManagerError.keyPermanentlyInvalidated
            }
            // Key predates enrollment tracking — a decrypt failure most likely
            // means the key was invalidated before tracking was introduced.
            if !enrollmentTracked {
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

        // Backfill enrollment state for keys that predate enrollment tracking
        if !enrollmentStateExists(tag: privateKeyTag) {
            saveEnrollmentState(tag: privateKeyTag)
        }

        return decryptedString
    }

    /// Returns the private key for the given tag, distinguishing
    /// "key permanently invalidated" from "failed to retrieve."
    private func requirePrivateKey(tag: Data) throws -> SecKey {
        if let key = getPrivateKey(tag: tag) {
            return key
        }
        if !keyExists(tag: tag) {
            throw SecureEnclaveManagerError.keyPermanentlyInvalidated
        }
        throw SecureEnclaveManagerError.failedGetPrivateKey
    }

    private func getPublicKey(privateKey: SecKey) throws -> SecKey? {
        return try keychainService.copyPublicKey(privateKey)
    }

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

    func keyExists(tag: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:              kSecClassKey,
            kSecAttrKeyType as String:        kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrTokenID as String:        kSecAttrTokenIDSecureEnclave,
            kSecAttrApplicationTag as String: tag,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip,
            kSecReturnAttributes as String:   true,
        ]
        return keychainService.itemExists(query as CFDictionary)
    }

    // MARK: - Biometric enrollment state tracking

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

    private func deleteEnrollmentState(tag: Data) {
        let key = AppConstants.enrollmentStateKeyPrefix + tag.base64EncodedString()
        userDefaults.removeObject(forKey: key)
    }

    private func enrollmentStateExists(tag: Data) -> Bool {
        let key = AppConstants.enrollmentStateKeyPrefix + tag.base64EncodedString()
        return userDefaults.data(forKey: key) != nil
    }
}
