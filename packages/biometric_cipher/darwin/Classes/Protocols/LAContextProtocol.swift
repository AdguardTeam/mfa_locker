import LocalAuthentication

/// A protocol describing the required functionality of the LAContext.
protocol LAContextProtocol {
    var localizedReason: String? { get set }
    func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool
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
