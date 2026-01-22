protocol BaseError: Error {
    /// A unique code identifying the error.
    var code: String { get }
    
    /// A message describing the error that occurred.
    var errorDescription: String { get }
}
