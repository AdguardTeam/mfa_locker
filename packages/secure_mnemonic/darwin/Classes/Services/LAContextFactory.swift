import LocalAuthentication

class LAContextFactory: LAContextFactoryProtocol {
    func createContext() -> LAContextProtocol {
        return LAContext()
    }
}
