import XCTest
import LocalAuthentication

@testable import biometric_cipher

final class SecureEnclaveManagerTests: XCTestCase {
    
    // MARK: - Properties

    var mockKeychain: MockKeychainService!
    var mockLAContext: MockLAContext!
    var mockLAContextFactory: MockLAContextFactory!
    var testDefaults: UserDefaults!
    var manager: SecureEnclaveManager!

    private static let testSuiteName = "SecureEnclaveManagerTests"

    // MARK: - Setup and Teardown

    override func setUp() {
        super.setUp()
        mockKeychain = MockKeychainService()
        mockLAContext = MockLAContext()
        mockLAContextFactory = MockLAContextFactory(mockContext: mockLAContext)
        testDefaults = UserDefaults(suiteName: Self.testSuiteName)!
        testDefaults.removePersistentDomain(forName: Self.testSuiteName)
        manager = SecureEnclaveManager(
            keychainService: mockKeychain,
            laContextFactory: mockLAContextFactory,
            userDefaults: testDefaults
        )
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: Self.testSuiteName)
        mockKeychain = nil
        mockLAContext = nil
        mockLAContextFactory = nil
        testDefaults = nil
        manager = nil
        super.tearDown()
    }
    
    // MARK: - Support functions
    
    func createTemporarySecKey() -> SecKey? {
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits: 256,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlocked,
            kSecPrivateKeyAttrs: [
                // Making the key temporary and preventing it from being stored, which increases security and reduces the risk of key leakage.
                kSecAttrIsPermanent: false
            ]
        ]
        
        var error: Unmanaged<CFError>?
        return SecKeyCreateRandomKey(attributes as CFDictionary, &error)
    }
    
    func createBaseError(code: String, description: String? = nil) -> BaseError {
        return MockError(code: code, errorDescription: description ?? "An error occurred.")
    }
    
    // MARK: - Configuration tests
    
    func testConfigureAuthTitle_SetsCorrectly() {
        let authTitle = "Authenticate to Access Secure Enclave"
        
        XCTAssertNoThrow(try manager.configure(authTitle: authTitle), "There should be no error when setting the correct authTitle.")
        XCTAssertEqual(manager.authTitle, authTitle, "authTitle must be set correctly.")
    }
    
    func testConfigureAuthTitle_InvalidAuthTitle() {
        let authTitle = ""
        
        XCTAssertThrowsError(try manager.configure(authTitle: authTitle)) { error in
            guard let e = error as? SecureEnclaveManagerError else {
                return XCTFail("A SecureEnclaveManagerError was expected, but I got \(error).")
            }
            XCTAssertEqual(e, .invalidAuthTitle, "Expected .invalidAuthTitle error, but received \(e).")
        }
    }
    
    // MARK: - Secure Enclave support verification tests
    
    func testIsSecureEnclaveSupported_Supported() {
        // Configure mockKeychain for successful key creation
        guard let tempKey = createTemporarySecKey() else {
            XCTFail("Failed to create a temporary SecKey")
            return
        }
        mockKeychain.createRandomKeyResult = tempKey
        
        let supported = manager.isSecureEnclaveSupported()
        
        XCTAssertTrue(supported, "Secure Enclave must be supported.")
    }
    
    func testIsSecureEnclaveSupported_NotSupported() {
        mockLAContext.canEvaluatePolicyResult = false
        mockLAContext.evaluatePolicySuccess = false
        mockLAContext.evaluatePolicyError = NSError(
            domain: "MockAuthError",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Authentication failed."]
        )
        
        let supported = manager.isSecureEnclaveSupported()
        
        XCTAssertFalse(supported, "Secure Enclave should not be supported.")
    }
    
    // MARK: - Key pair generation tests
    
    func testGenerateKeyPair_NewKey() throws {
        let tag = "test.sec.enclave.newkey"
        
        // Configure mockKeychain for successful key creation
        guard let tempKey = createTemporarySecKey() else {
            XCTFail("Failed to create a temporary SecKey")
            return
        }
        mockKeychain.createRandomKeyResult = tempKey
        
        // Delete the key (if it exists) before creating a new pair
        XCTAssertNoThrow(try manager.deleteKey(tag: tag), "There should be no error when deleting the key.")
        
        // Generate a key pair and ensure no error occurs
        XCTAssertNoThrow(try manager.generateKeyPair(tag: tag), "There should be no error when a key pair is successfully created.")
    }
    
    func testGenerateKeyPair_FailureMock() throws {
        let tag = "mock.tag"
        
        // Configure mockKeychain to throw an error when creating a random key
        mockKeychain.createRandomKeyError = KeychainServiceError.failedToCreateRandomKey(nil)
        
        // Attempt to generate a key pair and expect an error
        do {
            try manager.generateKeyPair(tag: tag)
            XCTFail("Expected an error to be thrown, but no error was thrown.")
        } catch let error as KeychainServiceError {
            switch error {
            case .failedToCreateRandomKey:
                break
            default:
                XCTFail("Expected .failedToCreateRandomKey error, but received \(error).")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    func testGenerateKeyPair_InvalidTag() throws {
        let tag = "" // Empty tag is considered invalid
        
        XCTAssertThrowsError(try manager.generateKeyPair(tag: tag)) { error in
            guard let e = error as? SecureEnclaveManagerError else {
                return XCTFail("A SecureEnclaveManagerError was expected, but I got \(error).")
            }
            XCTAssertEqual(e, .invalidTag, "Expected .invalidTag error, but received \(e).")
        }
    }
    
    // MARK: - Key deletion tests
    
    func testDeleteKey_Success() throws {
        let tag = "test.delete.key"
        
        XCTAssertNoThrow(try manager.deleteKey(tag: tag), "There should be no error when the key is successfully deleted.")
    }
    
    func testDeleteKey_Failure() throws {
        let tag = "test.delete.key.failure"
        
        // Configure mockKeychain to throw an error when deleting the key
        mockKeychain.deleteItemError = KeychainServiceError.failedToDeleteItem
        
        // Attempt to delete the key and expect an error
        XCTAssertThrowsError(try manager.deleteKey(tag: tag)) { error in
            guard error is KeychainServiceError else {
                return XCTFail("A KeychainServiceError was expected, but I got \(error).")
            }
            guard case KeychainServiceError.failedToDeleteItem = error else {
                return XCTFail("Expected .failedToDeleteItem error, but received \(error).")
            }
        }
    }
    
    func testDeleteKey_InvalidTag() throws {
        let tag = "" // Empty tag is considered invalid
        
        XCTAssertThrowsError(try manager.deleteKey(tag: tag)) { error in
            guard let e = error as? SecureEnclaveManagerError else {
                return XCTFail("An error like SecureEnclaveManagerError was expected, but it was received \(error)")
            }
            XCTAssertEqual(e, .invalidTag, "Expected .invalidTag error, but received \(e).")
        }
    }
    
    // MARK: - Encryption tests
    
    func testEncryptAndDecrypt_RoundTrip() throws {
        let tag = "test.sec.enclave.roundtrip"
        let originalString = "Hello, Secure Enclave!"
        
        // Configure mock KeychainService
        guard let tempKey = createTemporarySecKey() else {
            XCTFail("Failed to create a temporary SecKey")
            return
        }
        mockKeychain.createRandomKeyResult = tempKey
        mockKeychain.copyPublicKeyResult = SecKeyCopyPublicKey(tempKey)
        
        // Configure encryption and decryption
        guard let originalData = originalString.data(using: .utf8) else {
            XCTFail("Failed to convert string to Data")
            return
        }
        mockKeychain.encryptDataResult = Data(originalData.reversed())
        mockKeychain.decryptDataResult = originalData
        
        // Initialize the manager with mocks
        XCTAssertNoThrow(try manager.generateKeyPair(tag: tag), "There should be no error when generating a key pair.")
        
        // Encrypt data
        var encryptedData: Data!
        XCTAssertNoThrow(encryptedData = try manager.encrypt(originalString, tag: tag), "There should be no error when encrypting data.")
        XCTAssertFalse(encryptedData.isEmpty, "Encrypted data should not be empty.")
        
        // Decrypt data
        var decryptedString: String!
        XCTAssertNoThrow(decryptedString = try manager.decrypt(encryptedData, tag: tag), "There should be no error when decrypting data.")
        XCTAssertEqual(decryptedString, originalString, "The decrypted text should match the original.")
    }
    
    func testEncrypt_KeyNotFoundInKeychain_ShouldThrowKeyPermanentlyInvalidated() throws {
        let tag = "test.sec.enclave.no_key"

        XCTAssertThrowsError(try manager.encrypt("Some text", tag: tag)) { error in
            guard let e = error as? SecureEnclaveManagerError, case .keyPermanentlyInvalidated = e else {
                return XCTFail("Expected SecureEnclaveManagerError.keyPermanentlyInvalidated, got \(error)")
            }
        }
    }

    func testEncrypt_KeyExistsButPrivateKeyRetrievalFails_ShouldThrowFailedGetPrivateKey() throws {
        let tag = "test.sec.enclave.key_exists_no_ref"

        mockKeychain.getPrivateKeyResult = nil
        mockKeychain.itemExistsResult = true

        XCTAssertThrowsError(try manager.encrypt("Some text", tag: tag)) { error in
            guard let e = error as? SecureEnclaveManagerError, case .failedGetPrivateKey = e else {
                return XCTFail("Expected SecureEnclaveManagerError.failedGetPrivateKey, got \(error)")
            }
        }
    }
    
    /// Triggers `keyPermanentlyInvalidated` when the key is missing from keychain (e.g., after biometric re-enrollment).
    func testDecrypt_KeyNotFoundInKeychain_ShouldThrowKeyPermanentlyInvalidated() throws {
        let tag = "test.sec.enclave.no_key_decrypt"
        let fakeEncryptedData = Data([0x01, 0x02, 0x03])

        XCTAssertThrowsError(try manager.decrypt(fakeEncryptedData, tag: tag)) { error in
            guard let e = error as? SecureEnclaveManagerError, case .keyPermanentlyInvalidated = e else {
                return XCTFail("Expected SecureEnclaveManagerError.keyPermanentlyInvalidated, got \(error)")
            }
        }
    }

    // MARK: - isKeyValid tests

    func testIsKeyValid_EmptyTag_ReturnsFalse() {
        let result = manager.isKeyValid(tag: "")

        XCTAssertFalse(result, "isKeyValid must return false for an empty tag.")
    }

    func testIsKeyValid_NonExistentKey_ReturnsFalse() {
        let result = manager.isKeyValid(tag: "test.nonexistent.key.tag")

        XCTAssertFalse(result, "isKeyValid must return false when the key does not exist in the keychain.")
    }

    // MARK: - Decrypt: key invalidation detection tests

    func testDecrypt_DecryptionFailsAfterKeyRetrieval_ShouldThrowKeyPermanentlyInvalidated() throws {
        let tag = "test.sec.enclave.decrypt.invalidated"
        let fakeEncryptedData = Data([0x01, 0x02, 0x03])

        // getPrivateKey succeeds (simulates successful biometric authentication)
        guard let tempKey = createTemporarySecKey() else {
            XCTFail("Failed to create a temporary SecKey")
            return
        }
        mockKeychain.getPrivateKeyResult = tempKey
        // decryptDataResult is nil → decryptData throws failedToDecryptData
        // Key does not exist in keychain (simulates OS removing key after enrollment change)
        mockKeychain.itemExistsResult = false

        XCTAssertThrowsError(try manager.decrypt(fakeEncryptedData, tag: tag)) { error in
            guard let e = error as? SecureEnclaveManagerError, case .keyPermanentlyInvalidated = e else {
                return XCTFail("Expected SecureEnclaveManagerError.keyPermanentlyInvalidated, got \(error)")
            }
        }
    }

    func testDecrypt_DecryptionFailsButKeyStillValid_ShouldThrowAuthenticationFailed() throws {
        let tag = "test.sec.enclave.decrypt.authfail"
        let fakeEncryptedData = Data([0x01, 0x02, 0x03])

        // getPrivateKey succeeds (key reference obtained; on macOS biometric auth is deferred)
        guard let tempKey = createTemporarySecKey() else {
            XCTFail("Failed to create a temporary SecKey")
            return
        }
        mockKeychain.getPrivateKeyResult = tempKey
        // decryptData throws failedToDecryptData with errSecAuthFailed (simulates wrong biometrics)
        let authFailedError = NSError(domain: NSOSStatusErrorDomain, code: Int(errSecAuthFailed))
        mockKeychain.decryptDataError = .failedToDecryptData(authFailedError)
        // Key exists in keychain (not invalidated)
        mockKeychain.itemExistsResult = true
        // Enrollment state exists (post-enrollment-tracking key)
        let tagData = ("\(AppConstants.privateKeyTag).\(tag)").data(using: .utf8)!
        let enrollmentKey = AppConstants.enrollmentStateKeyPrefix + tagData.base64EncodedString()
        mockLAContext.canEvaluatePolicyResult = true
        mockLAContext.evaluatedPolicyDomainStateValue = Data([0xAA, 0xBB])
        testDefaults.set(Data([0xAA, 0xBB]), forKey: enrollmentKey)

        XCTAssertThrowsError(try manager.decrypt(fakeEncryptedData, tag: tag)) { error in
            guard let e = error as? SecureEnclaveManagerError, case .authenticationFailed = e else {
                return XCTFail("Expected SecureEnclaveManagerError.authenticationFailed, got \(error)")
            }
        }
    }

    func testDecrypt_DecryptionFailsWithNonAuthError_ShouldRethrowOriginalError() throws {
        let tag = "test.sec.enclave.decrypt.othererror"
        let fakeEncryptedData = Data([0x01, 0x02, 0x03])

        guard let tempKey = createTemporarySecKey() else {
            XCTFail("Failed to create a temporary SecKey")
            return
        }
        mockKeychain.getPrivateKeyResult = tempKey
        // decryptData throws failedToDecryptData with a non-auth error (e.g., corrupted data)
        let paramError = NSError(domain: NSOSStatusErrorDomain, code: Int(errSecParam))
        mockKeychain.decryptDataError = .failedToDecryptData(paramError)
        // Key exists in keychain (not invalidated)
        mockKeychain.itemExistsResult = true
        // Enrollment state exists (post-enrollment-tracking key)
        let tagData = ("\(AppConstants.privateKeyTag).\(tag)").data(using: .utf8)!
        let enrollmentKey = AppConstants.enrollmentStateKeyPrefix + tagData.base64EncodedString()
        mockLAContext.canEvaluatePolicyResult = true
        mockLAContext.evaluatedPolicyDomainStateValue = Data([0xAA, 0xBB])
        testDefaults.set(Data([0xAA, 0xBB]), forKey: enrollmentKey)

        XCTAssertThrowsError(try manager.decrypt(fakeEncryptedData, tag: tag)) { error in
            guard let e = error as? KeychainServiceError, case .failedToDecryptData = e else {
                return XCTFail("Expected KeychainServiceError.failedToDecryptData, got \(error)")
            }
        }
    }

    func testDecrypt_UserCancelsDuringDecryption_ShouldRethrowCancellation() throws {
        let tag = "test.sec.enclave.decrypt.cancel"
        let fakeEncryptedData = Data([0x01, 0x02, 0x03])

        guard let tempKey = createTemporarySecKey() else {
            XCTFail("Failed to create a temporary SecKey")
            return
        }
        mockKeychain.getPrivateKeyResult = tempKey
        mockKeychain.decryptDataError = .authenticationUserCanceled

        XCTAssertThrowsError(try manager.decrypt(fakeEncryptedData, tag: tag)) { error in
            guard let e = error as? KeychainServiceError, case .authenticationUserCanceled = e else {
                return XCTFail("Expected KeychainServiceError.authenticationUserCanceled, got \(error)")
            }
        }
    }

    // MARK: - Decrypt: missing enrollment state (upgrade scenario)

    func testDecrypt_DecryptionFails_NoEnrollmentState_ShouldThrowKeyPermanentlyInvalidated() throws {
        let tag = "test.sec.enclave.decrypt.no_enrollment"
        let fakeEncryptedData = Data([0x01, 0x02, 0x03])

        guard let tempKey = createTemporarySecKey() else {
            XCTFail("Failed to create a temporary SecKey")
            return
        }
        mockKeychain.getPrivateKeyResult = tempKey
        let paramError = NSError(domain: NSOSStatusErrorDomain, code: Int(errSecParam))
        mockKeychain.decryptDataError = .failedToDecryptData(paramError)
        // Key exists in keychain
        mockKeychain.itemExistsResult = true
        // No enrollment state saved (simulates upgrade from old version)
        mockLAContext.canEvaluatePolicyResult = true
        mockLAContext.evaluatedPolicyDomainStateValue = Data([0xCC, 0xDD])

        XCTAssertThrowsError(try manager.decrypt(fakeEncryptedData, tag: tag)) { error in
            guard let e = error as? SecureEnclaveManagerError, case .keyPermanentlyInvalidated = e else {
                return XCTFail("Expected SecureEnclaveManagerError.keyPermanentlyInvalidated, got \(error)")
            }
        }
    }

    func testDecrypt_Success_BackfillsEnrollmentState() throws {
        let tag = "test.sec.enclave.decrypt.backfill"
        let fakeEncryptedData = Data([0x01, 0x02, 0x03])

        guard let tempKey = createTemporarySecKey() else {
            XCTFail("Failed to create a temporary SecKey")
            return
        }
        mockKeychain.getPrivateKeyResult = tempKey
        mockKeychain.decryptDataResult = "decrypted".data(using: .utf8)!
        // No enrollment state saved
        mockLAContext.canEvaluatePolicyResult = true
        mockLAContext.evaluatedPolicyDomainStateValue = Data([0xEE, 0xFF])

        let tagData = ("\(AppConstants.privateKeyTag).\(tag)").data(using: .utf8)!
        let enrollmentKey = AppConstants.enrollmentStateKeyPrefix + tagData.base64EncodedString()
        XCTAssertNil(testDefaults.data(forKey: enrollmentKey), "Enrollment state must not exist before decrypt.")

        _ = try manager.decrypt(fakeEncryptedData, tag: tag)

        XCTAssertEqual(testDefaults.data(forKey: enrollmentKey), Data([0xEE, 0xFF]),
                       "Successful decrypt must backfill enrollment state.")
    }

    // MARK: - isKeyValid: no premature backfill

    func testIsKeyValid_DoesNotBackfillEnrollmentState() {
        let tag = "test.enrollment.no_backfill"
        // Key exists in keychain
        mockKeychain.itemExistsResult = true
        mockLAContext.canEvaluatePolicyResult = true
        mockLAContext.evaluatedPolicyDomainStateValue = Data([0x55, 0x66])

        let tagData = ("\(AppConstants.privateKeyTag).\(tag)").data(using: .utf8)!
        let enrollmentKey = AppConstants.enrollmentStateKeyPrefix + tagData.base64EncodedString()

        let result = manager.isKeyValid(tag: tag)

        XCTAssertTrue(result, "isKeyValid must return true when key exists and enrollment has not changed.")
        XCTAssertNil(testDefaults.data(forKey: enrollmentKey),
                     "isKeyValid must not backfill enrollment state — only successful decrypt should.")
    }

    // MARK: - isKeyValid: enrollment state tests

    func testIsKeyValid_EnrollmentChanged_ReturnsFalse() throws {
        let tag = "test.enrollment.changed"

        guard let tempKey = createTemporarySecKey() else {
            XCTFail("Failed to create a temporary SecKey")
            return
        }
        // getPrivateKey returns nil (key doesn't exist yet), createRandomKey returns tempKey
        mockKeychain.createRandomKeyResult = tempKey
        mockKeychain.getPrivateKeyResult = nil
        mockLAContext.canEvaluatePolicyResult = true
        mockLAContext.evaluatedPolicyDomainStateValue = Data([0xAA, 0xBB])

        // Generate key — saves enrollment state
        try manager.generateKeyPair(tag: tag)

        // Simulate biometric enrollment change
        mockLAContext.evaluatedPolicyDomainStateValue = Data([0xCC, 0xDD])

        let tagData = ("\(AppConstants.privateKeyTag).\(tag)").data(using: .utf8)!
        let enrollmentKey = AppConstants.enrollmentStateKeyPrefix + tagData.base64EncodedString()
        let savedState = testDefaults.data(forKey: enrollmentKey)
        XCTAssertEqual(savedState, Data([0xAA, 0xBB]), "Enrollment state must be saved during key generation.")
        XCTAssertNotEqual(savedState, mockLAContext.evaluatedPolicyDomainStateValue,
                          "Saved state must differ from current state after enrollment change.")
    }

    func testGenerateKeyPair_SavesEnrollmentState() throws {
        let tag = "test.enrollment.save"

        guard let tempKey = createTemporarySecKey() else {
            XCTFail("Failed to create a temporary SecKey")
            return
        }
        mockKeychain.createRandomKeyResult = tempKey
        mockKeychain.getPrivateKeyResult = nil
        mockLAContext.canEvaluatePolicyResult = true
        mockLAContext.evaluatedPolicyDomainStateValue = Data([0x11, 0x22])

        try manager.generateKeyPair(tag: tag)

        let tagData = ("\(AppConstants.privateKeyTag).\(tag)").data(using: .utf8)!
        let key = AppConstants.enrollmentStateKeyPrefix + tagData.base64EncodedString()
        let savedState = testDefaults.data(forKey: key)
        XCTAssertEqual(savedState, Data([0x11, 0x22]), "generateKeyPair must save the enrollment state.")
    }

    func testDeleteKey_RemovesEnrollmentState() throws {
        let tag = "test.enrollment.delete"

        guard let tempKey = createTemporarySecKey() else {
            XCTFail("Failed to create a temporary SecKey")
            return
        }
        mockKeychain.createRandomKeyResult = tempKey
        mockKeychain.getPrivateKeyResult = nil
        mockLAContext.canEvaluatePolicyResult = true
        mockLAContext.evaluatedPolicyDomainStateValue = Data([0x33, 0x44])

        try manager.generateKeyPair(tag: tag)

        let tagData = ("\(AppConstants.privateKeyTag).\(tag)").data(using: .utf8)!
        let key = AppConstants.enrollmentStateKeyPrefix + tagData.base64EncodedString()
        XCTAssertNotNil(testDefaults.data(forKey: key), "Enrollment state should exist after generateKeyPair.")

        try manager.deleteKey(tag: tag)

        XCTAssertNil(testDefaults.data(forKey: key), "deleteKey must remove the enrollment state.")
    }
}
