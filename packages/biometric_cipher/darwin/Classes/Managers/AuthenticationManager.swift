import LocalAuthentication

/// Provides methods for biometric and passcode authentication as well as access control management.
struct AuthenticationManager {
    
    /// Determines whether biometric authentication is supported on the device.
    ///
    /// This method checks if the device supports biometric authentication (e.g., Face ID, Touch ID).
    /// - Parameter context: An `LAContextProtocol` instance used to evaluate policy.
    /// - Returns: `true` if biometric authentication is supported, otherwise `false`.
    /// - Throws: `AuthenticationError.evaluatingBiometryError` if an error occurs while evaluating biometric support.
    static func isBiometrySupported(_ context: LAContextProtocol) throws -> Bool {
        var error: NSError?
        let isSupported = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        
        if let error = error {
            throw AuthenticationError.evaluatingBiometryError(error)
        }
        
        return isSupported
    }
    
    /// Creates a `SecAccessControl` object with specified access flags.
    ///
    /// This method configures a secure access control policy for private keys, ensuring operations 
    /// require either biometric authentication or user presence, depending on device capabilities.
    /// - Parameter context: An `LAContextProtocol` instance used to check biometric availability.
    /// - Returns: A `SecAccessControl` object configured for secure access control.
    /// - Throws: `AuthenticationError.secAccessCreateControl` if the `SecAccessControl` object cannot be created.
    ///   If no underlying error is available, the cause is considered unknown.
    static func getAccessControl(_ context: LAContextProtocol) throws -> SecAccessControl {
        // Check for biometric support
        let isBiometrySupported = try isBiometrySupported(context)
        
        // Define access control flags
        var accessFlags: SecAccessControlCreateFlags = [.privateKeyUsage]
        if isBiometrySupported {
            accessFlags.insert(.biometryCurrentSet)
        } else {
            accessFlags.insert(.userPresence)
        }
        
        // Attempt to create the SecAccessControl object
        var error: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            accessFlags,
            &error
        ) else {
            throw AuthenticationError.secAccessCreateControl(error?.takeRetainedValue() as Error?)
        }
        
        return accessControl
    }

    /// Prompts the user for biometric authentication using Face ID or Touch ID.
    ///
    /// On first use, the system may also show the Face ID permission dialog
    /// (requires `NSFaceIDUsageDescription` in the host app).
    /// - Parameters:
    ///   - context: An `LAContextProtocol` instance used to evaluate the policy.
    ///   - reason: The user-facing message shown in the authentication prompt.
    /// - Throws: `AuthenticationError` if biometry is unavailable, authentication fails,
    ///   or the user cancels the prompt.
    static func requestBiometricAuthentication(
        _ context: LAContextProtocol,
        reason: String
    ) throws {
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw AuthenticationError.evaluatingBiometryError(error)
        }

        var policySuccess = false
        var policyError: Error?
        let semaphore = DispatchSemaphore(value: 0)

        context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: reason
        ) { success, error in
            policySuccess = success
            policyError = error
            semaphore.signal()
        }

        semaphore.wait()

        if policySuccess {
            return
        }

        throw AuthenticationError.authenticationFailed(policyError)
    }
}
