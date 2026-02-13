import XCTest
import LocalAuthentication

@testable import biometric_cipher

/// Integration test class for verifying real-world encryption using the Secure Enclave.
///
/// This test ensures:
/// - The encryption of the same plaintext produces different ciphertexts (non-deterministic behavior).
/// - Each ciphertext is non-empty.
/// - Both ciphertexts can be correctly decrypted back to the original plaintext.
/// - The generated key is removed after the test to maintain a clean Keychain environment.
///
/// Note:
/// - This test must be run on a real device with Secure Enclave support,
///   as simulators may not fully support Secure Enclave.
/// - This test validates actual encryption operations (real encryption), not mocked ones.
final class SecureEnclaveManagerRealEncryptionIntegrationTests: XCTestCase {
    
    private var manager: SecureEnclaveManager!
    
    /// Set up the SecureEnclaveManager with real services (KeychainService and LAContextFactory)
    /// and configure the authentication title.
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Initialize the manager with real Keychain and LAContext services
        manager = SecureEnclaveManager(
            keychainService: KeychainService(),
            laContextFactory: LAContextFactory()
        )
        
        // Configure the manager with an authentication title for biometric prompts
        try manager.configure(authTitle: "Integration Test Authentication")
    }
    
    /// Clean up the test environment by deallocating the manager.
    override func tearDownWithError() throws {
        manager = nil
        try super.tearDownWithError()
    }
    
    /// Tests real-world encryption using the Secure Enclave.
    ///
    /// Steps:
    /// 1. Generate a unique key pair in the Secure Enclave using a unique tag.
    /// 2. Encrypt the same plaintext twice.
    /// 3. Assert that:
    ///    - Both ciphertexts are non-empty.
    ///    - The ciphertexts differ from each other (confirming non-deterministic encryption).
    ///    - Decrypting each ciphertext returns the original plaintext.
    /// 4. Clean up the generated key from the Keychain.
    ///
    /// Requirements:
    /// - Must run on a device supporting Secure Enclave.
    /// - The user may be prompted for biometric authentication if required.
    func testNonDeterministicEncryption() throws {
        // Generate a unique tag using UUID to avoid key conflicts
        let testTag = "integration.nondet.test.\(UUID().uuidString)"
        
        // Generate a new key pair in the Secure Enclave.
        try manager.generateKeyPair(tag: testTag)
        
        // Define the plaintext to be encrypted.
        let plaintext = "Hello, Secure Enclave!"
        
        // Encrypt the plaintext twice.
        let ciphertext1 = try manager.encrypt(plaintext, tag: testTag)
        let ciphertext2 = try manager.encrypt(plaintext, tag: testTag)
        
        // Assert that both ciphertexts are non-empty.
        XCTAssertFalse(ciphertext1.isEmpty, "Ciphertext1 should not be empty.")
        XCTAssertFalse(ciphertext2.isEmpty, "Ciphertext2 should not be empty.")
        
        // Verify that the ciphertexts differ, confirming non-deterministic encryption.
        XCTAssertNotEqual(ciphertext1, ciphertext2,
                          "Ciphertext must differ on repeated encryption calls (non-deterministic behavior).")
        
        // Decrypt both ciphertexts and verify that they match the original plaintext.
        let decrypted1 = try manager.decrypt(ciphertext1, tag: testTag)
        let decrypted2 = try manager.decrypt(ciphertext2, tag: testTag)
        
        XCTAssertEqual(decrypted1, plaintext,
                       "The decrypted text should match the original plaintext.")
        XCTAssertEqual(decrypted2, plaintext,
                       "The decrypted text should match the original plaintext.")
        
        // Clean up: remove the generated key from the Keychain.
        try manager.deleteKey(tag: testTag)
    }
}
