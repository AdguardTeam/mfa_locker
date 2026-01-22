/// A collection of application-wide constant values.
///
/// The `AppConstants` enum is used to store static constants that are shared across the application.
enum AppConstants {
    /// A unique tag used to identify the private key in the Secure Enclave.
    ///
    /// This tag is used as a key to retrieve, manage, and delete the private key stored securely in the Secure Enclave.
    static let privateKeyTag = "com.adguard.tpm.secureEnclavePrivateKey"
}
