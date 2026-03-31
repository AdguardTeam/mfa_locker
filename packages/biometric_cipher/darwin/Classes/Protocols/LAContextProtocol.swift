import LocalAuthentication

/// A protocol describing the required functionality of the LAContext.
protocol LAContextProtocol {
    /// The user-facing reason string displayed in the biometric authentication prompt.
    var localizedReason: String? { get set }

    /// Opaque data representing the current biometric enrollment state.
    var evaluatedPolicyDomainState: Data? { get }

    /// Checks whether the given authentication policy can be evaluated on this device.
    func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool

    /// Evaluates the given policy asynchronously and returns the result via `reply`.
    func evaluatePolicy(_ policy: LAPolicy, localizedReason: String, reply: @escaping (Bool, Error?) -> Void)
}

extension LAContext: LAContextProtocol {
    private struct AssociatedKeys {
        static var localizedReasonKey: UInt8 = 0
    }
    
    var localizedReason: String? {
        get {
            return objc_getAssociatedObject(self, &AssociatedKeys.localizedReasonKey) as? String
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.localizedReasonKey, newValue, .OBJC_ASSOCIATION_COPY_NONATOMIC)
        }
    }
}
