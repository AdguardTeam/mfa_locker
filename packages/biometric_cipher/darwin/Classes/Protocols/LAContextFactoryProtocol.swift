/// A protocol describing the functionality of the factory to create a LAContext.
protocol LAContextFactoryProtocol {
    /// Creates and returns a new ``LAContextProtocol`` instance.
    func createContext() -> LAContextProtocol
}
