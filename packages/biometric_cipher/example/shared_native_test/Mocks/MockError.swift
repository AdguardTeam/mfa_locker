@testable import biometric_cipher

struct MockError: BaseError {
    var code: String
    var errorDescription: String
}