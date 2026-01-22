@testable import secure_mnemonic

struct MockError: BaseError {
    var code: String
    var errorDescription: String
}