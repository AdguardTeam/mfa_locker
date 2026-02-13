/// A utility for encoding and decoding Base64 data.
///
/// The `Base64Codec` provides static methods to encode data into a Base64 string
/// and decode a Base64 string back into raw data. It includes error handling for
/// invalid inputs or decoding issues.
struct Base64Codec {
    
    /// Encodes data into a Base64 string.
    ///
    /// - Parameter data: The raw `Data` object to be encoded.
    /// - Returns: A `String` representation of the data in Base64 format.
    /// - Throws: This method does not throw errors but relies on Swift's built-in Base64 encoding.
    static func encode(_ data: Data) throws -> String {
        // Convert public key data into Base64 string
        return data.base64EncodedString()
    }
    
    
    /// Decodes a Base64 string into a `Data` object.
    ///
    /// - Parameter base64String: The `String` in Base64 format to decode.
    /// - Throws: An `NSError` if the input string is empty or if decoding fails.
    ///     - **Error Domain**: "INVALID_STRING" for empty input.
    ///     - **Error Domain**: "BASE64_DECODE_ERROR" for decoding failure.
    /// - Returns: A `Data` object if the decoding succeeds.
    static func decode(_ base64String: String) throws -> Data {
        guard !base64String.isEmpty else {
            throw NSError(
                domain: "INVALID_STRING",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Incorrect Base64 string format."]
            )
        }
        
        guard let data = Data(base64Encoded: base64String) else {
            throw NSError(
                domain: "BASE64_DECODE_ERROR",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to decode Base64 string."]
            )
        }
        
        return data
    }
}
