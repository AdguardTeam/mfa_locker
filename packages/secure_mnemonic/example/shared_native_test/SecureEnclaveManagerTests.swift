import XCTest
import LocalAuthentication

@testable import secure_mnemonic

/// Unit tests for `SecureEnclaveManager`.
/// This class covers both positive (happy path) and negative scenarios.
/// Negative scenarios often require mocking Keychain/Secure Enclave calls.
final class SecureEnclaveManagerTests: XCTestCase {
    
    // MARK: - Properties
    
    var mockKeychain: MockKeychainService!
    var mockLAContext: MockLAContext!
    var mockLAContextFactory: MockLAContextFactory!
    var manager: SecureEnclaveManager!
    
    // MARK: - Setup and Teardown
    
    override func setUp() {
        super.setUp()
        mockKeychain = MockKeychainService()
        mockLAContext = MockLAContext()
        mockLAContextFactory = MockLAContextFactory(mockContext: mockLAContext)
        manager = SecureEnclaveManager(keychainService: mockKeychain, laContextFactory: mockLAContextFactory)
    }
    
    override func tearDown() {
        mockKeychain = nil
        mockLAContext = nil
        mockLAContextFactory = nil
        manager = nil
        super.tearDown()
    }
    
    // MARK: - Support functions
    
    /// Creates a temporary SecKey for testing purposes.
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
    
    /// Creates an error corresponding to `BaseError`.
    func createBaseError(code: String, description: String? = nil) -> BaseError {
        return MockError(code: code, errorDescription: description ?? "An error occurred.")
    }
    
    // MARK: - Configuration tests
    
    /// Positive scenario: correctly setting `authTitle`.
    func testConfigureAuthTitle_SetsCorrectly() {
        let authTitle = "Authenticate to Access Secure Enclave"
        
        XCTAssertNoThrow(try manager.configure(authTitle: authTitle), "There should be no error when setting the correct authTitle.")
        XCTAssertEqual(manager.authTitle, authTitle, "authTitle must be set correctly.")
    }
    
    /// Negative scenario: setting an empty `authTitle`.
    /// Expects `SecureEnclaveManagerError.invalidAuthTitle`.
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
    
    /// Positive scenario: Secure Enclave is supported.
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
    
    /// Negative scenario: Secure Enclave is not supported.
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
    
    /// Positive scenario: successful generation of a new key pair.
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
    
    /// Negative scenario: forced `createRandomKey` crash.
    /// Expects `KeychainServiceError.failedToCreateRandomKey`.
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
    
    /// Negative scenario: attempt to generate a key pair with an invalid tag.
    /// Expects `SecureEnclaveManagerError.invalidTag`.
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
    
    /// Positive scenario: successful key removal.
    func testDeleteKey_Success() throws {
        let tag = "test.delete.key"
        
        XCTAssertNoThrow(try manager.deleteKey(tag: tag), "There should be no error when the key is successfully deleted.")
    }
    
    /// Negative scenario: error when deleting a key.
    /// Expects `KeychainServiceError.failedToDeleteItem`.
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
    
    /// Negative scenario: attempt to delete a key with an invalid tag.
    /// Expects `SecureEnclaveManagerError.invalidTag`.
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
    
    /// Positive scenario: encrypting and decrypting data (Round Trip).
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
    
    /// Negative scenario: no private key for the given tag => `.failedGetPrivateKey`.
    func testEncrypt_NoPrivateKey_ShouldThrow() throws {
        let tag = "test.sec.enclave.no_key"
        
        XCTAssertThrowsError(try manager.encrypt("Some text", tag: tag)) { error in
            guard let e = error as? SecureEnclaveManagerError, case .failedGetPrivateKey = e else {
                return XCTFail("Expected SecureEnclaveManagerError.failedGetPrivateKey, got \(error)")
            }
        }
    }
    
    /// Negative scenario: no private key for the given tag => `.failedGetPrivateKey` when decrypting.
    func testDecrypt_NoPrivateKey_ShouldThrow() throws {
        let tag = "test.sec.enclave.no_key_decrypt"
        let fakeEncryptedData = Data([0x01, 0x02, 0x03])
        
        XCTAssertThrowsError(try manager.decrypt(fakeEncryptedData, tag: tag)) { error in
            guard let e = error as? SecureEnclaveManagerError, case .failedGetPrivateKey = e else {
                return XCTFail("Expected SecureEnclaveManagerError.failedGetPrivateKey, got \(error)")
            }
        }
    }
}
