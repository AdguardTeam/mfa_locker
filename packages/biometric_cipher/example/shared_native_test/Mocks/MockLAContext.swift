import LocalAuthentication

@testable import biometric_cipher

class MockLAContext: LAContextProtocol {
    var localizedReason: String?
    var canEvaluatePolicyResult: Bool = true
    var evaluatePolicySuccess: Bool = true
    var evaluatePolicyError: NSError? = nil
    
    func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool {
        if let errorPointer = error, let error = evaluatePolicyError {
            errorPointer.pointee = error
        }
        return canEvaluatePolicyResult
    }
    
    func evaluatePolicy(_ policy: LAPolicy, localizedReason: String, reply: @escaping (Bool, Error?) -> Void) {
        reply(evaluatePolicySuccess, evaluatePolicyError)
    }
}
