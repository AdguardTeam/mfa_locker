@testable import biometric_cipher

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
