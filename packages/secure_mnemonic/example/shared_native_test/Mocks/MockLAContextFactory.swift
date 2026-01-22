@testable import secure_mnemonic

/// Mock for LAContextFactoryProtocol.
class MockLAContextFactory: LAContextFactoryProtocol {
    var mockContext: LAContextProtocol
    
    init(mockContext: LAContextProtocol) {
        self.mockContext = mockContext
    }
    
    func createContext() -> LAContextProtocol {
        return mockContext
    }
}
