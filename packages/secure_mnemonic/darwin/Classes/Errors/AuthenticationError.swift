/// Defines the possible errors that can occur during authentication or access control operations.
enum AuthenticationError: BaseError {
    
    /// Error evaluating biometric support.
    case evaluatingBiometryError(Error?)
    
    /// Error creating a `SecAccessControl` object.
    case secAccessCreateControl(Error?)
    
    /// Returns a machine-readable error code.
    var code: String {
        switch self {
        case .evaluatingBiometryError:
            return "ERROR_EVALUATING_BIOMETRY"
        case .secAccessCreateControl:
            return "FAILED_CREATE_SEC_ACCESS_CONTROL"
        }
    }
    
    /// Returns a human-readable description of the error.
    var errorDescription: String {
        switch self {
        case .evaluatingBiometryError(let error):
            return "An error occurred while evaluating biometric support: \(error?.localizedDescription ?? "Unknown error")."
        case .secAccessCreateControl(let error):
            return "Failed to create the SecAccessControl object: \(error?.localizedDescription ?? "Unknown error")."
        }
    }
}
