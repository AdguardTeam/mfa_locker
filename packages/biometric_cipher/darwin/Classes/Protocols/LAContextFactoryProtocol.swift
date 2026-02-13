/// A protocol describing the functionality of the factory to create a LAContext.
protocol LAContextFactoryProtocol {
    func createContext() -> LAContextProtocol
}
