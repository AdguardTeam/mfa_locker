import LocalAuthentication

@testable import biometric_cipher

class MockLAContext: LAContextProtocol {
    var localizedReason: String?
    var canEvaluatePolicyResult: Bool = true
    var evaluatePolicySuccess: Bool = true
    var evaluatePolicyError: NSError? = nil
    var evaluatedPolicyDomainStateValue: Data? = nil

    var evaluatedPolicyDomainState: Data? {
        return evaluatedPolicyDomainStateValue
    }

    func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool {
        // Real `LAContext` only populates the error out-param when the policy
        // cannot be evaluated. Mirror that so a configured `evaluatePolicyError`
        // (intended for the `evaluatePolicy` reply) does not leak into callers
        // that probe support, e.g. `isBiometrySupported`.
        if !canEvaluatePolicyResult, let errorPointer = error, let error = evaluatePolicyError {
            errorPointer.pointee = error
        }
        return canEvaluatePolicyResult
    }
    
    func evaluatePolicy(_ policy: LAPolicy, localizedReason: String, reply: @escaping (Bool, Error?) -> Void) {
        reply(evaluatePolicySuccess, evaluatePolicyError)
    }
}
