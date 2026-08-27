import XCTest
import LocalAuthentication

@testable import biometric_cipher

/// Unit tests for `AuthenticationManager`.
final class AuthenticationManagerTests: XCTestCase {
    
    var mockLAContext: MockLAContext!
    
    override func setUp() {
        super.setUp()
        mockLAContext = MockLAContext()
    }
    
    override func tearDown() {
        mockLAContext = nil
        super.tearDown()
    }
    
    // MARK: - isBiometrySupported Tests
    
    /// Positive scenario: biometry is supported.
    func testIsBiometrySupported_Supported() {        
        XCTAssertNoThrow(try AuthenticationManager.isBiometrySupported(mockLAContext), "Should not throw an error when biometry is supported.")
        XCTAssertTrue(try! AuthenticationManager.isBiometrySupported(mockLAContext), "Biometry should be supported.")
    }
    
    /// Negative scenario: biometry is not supported.
    func testIsBiometrySupported_NotSupported() {
        let expectedNSError = NSError(
            domain: "MockAuthError",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Authentication failed."]
        )
        
        mockLAContext.canEvaluatePolicyResult = false
        mockLAContext.evaluatePolicySuccess = false
        mockLAContext.evaluatePolicyError = expectedNSError
        
        XCTAssertThrowsError(try AuthenticationManager.isBiometrySupported(mockLAContext)) { error in
            guard case AuthenticationError.evaluatingBiometryError = error else {
                return XCTFail("Expected AuthenticationError.evaluatingBiometryError, but got \(error).")
            }
        }
    }
    
    // MARK: - getAccessControl Tests
    
    /// Positive scenario: biometry is supported and access control is created successfully.
    func testGetAccessControl_BiometrySupported() {
        XCTAssertNoThrow(try AuthenticationManager.getAccessControl(mockLAContext), "Should not throw an error when access control is created successfully.")
        
        let accessControl = try? AuthenticationManager.getAccessControl(mockLAContext)
        XCTAssertNotNil(accessControl, "AccessControl should not be nil.")
    }

    // MARK: - requestBiometricAuthentication Tests

    func testRequestBiometricAuthentication_Success() {
        XCTAssertNoThrow(
            try AuthenticationManager.requestBiometricAuthentication(mockLAContext, reason: "Enable biometric access"),
            "Should not throw when biometric authentication succeeds."
        )
    }

    func testRequestBiometricAuthentication_BiometryUnavailable() {
        mockLAContext.canEvaluatePolicyResult = false
        mockLAContext.evaluatePolicyError = NSError(
            domain: "MockAuthError",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Biometry unavailable."]
        )

        XCTAssertThrowsError(
            try AuthenticationManager.requestBiometricAuthentication(mockLAContext, reason: "Enable biometric access")
        ) { error in
            guard case AuthenticationError.evaluatingBiometryError = error else {
                return XCTFail("Expected AuthenticationError.evaluatingBiometryError, but got \(error).")
            }
        }
    }

    func testRequestBiometricAuthentication_UserCanceled() {
        mockLAContext.evaluatePolicySuccess = false
        mockLAContext.evaluatePolicyError = NSError(
            domain: LAError.errorDomain,
            code: LAError.userCancel.rawValue,
            userInfo: nil
        )

        XCTAssertThrowsError(
            try AuthenticationManager.requestBiometricAuthentication(mockLAContext, reason: "Enable biometric access")
        ) { error in
            guard case AuthenticationError.authenticationFailed = error else {
                return XCTFail("Expected AuthenticationError.authenticationFailed, but got \(error).")
            }
        }
    }

    func testRequestBiometricAuthentication_AuthenticationFailed() {
        mockLAContext.evaluatePolicySuccess = false
        mockLAContext.evaluatePolicyError = NSError(
            domain: LAError.errorDomain,
            code: LAError.authenticationFailed.rawValue,
            userInfo: nil
        )

        XCTAssertThrowsError(
            try AuthenticationManager.requestBiometricAuthentication(mockLAContext, reason: "Enable biometric access")
        ) { error in
            guard case AuthenticationError.authenticationFailed = error else {
                return XCTFail("Expected AuthenticationError.authenticationFailed, but got \(error).")
            }
        }
    }
}
