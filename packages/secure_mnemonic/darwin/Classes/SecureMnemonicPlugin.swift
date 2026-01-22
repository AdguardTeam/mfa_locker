
#if os(iOS)
import Flutter
#elseif os(macOS)
import Cocoa
import FlutterMacOS
#endif

/// A Flutter plugin for managing cryptographic operations using Secure Enclave.
public class SecureMnemonicPlugin: NSObject, FlutterPlugin {
    
    private let secureEnclaveManager: SecureEnclaveManagerProtocol
    private let laContextFactory: LAContextFactoryProtocol
    
    public override init() {
        self.laContextFactory = LAContextFactory()
        self.secureEnclaveManager = SecureEnclaveManager(laContextFactory: self.laContextFactory)
        super.init()
    }
    
    /// Registers the plugin with the Flutter engine.
    ///
    /// - Parameter registrar: The Flutter plugin registrar.
    public static func register(with registrar: FlutterPluginRegistrar) {
#if os(iOS)
        let channel = FlutterMethodChannel(name: "secure_mnemonic", binaryMessenger: registrar.messenger())
#elseif os(macOS)
        let channel = FlutterMethodChannel(name: "secure_mnemonic", binaryMessenger: registrar.messenger)
#endif
        let instance = SecureMnemonicPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    /// Handles incoming Flutter method calls and routes them to the appropriate functionality.
    ///
    /// - Parameters:
    ///   - call: A `FlutterMethodCall` containing the method name and arguments.
    ///   - result: A callback used to send the result (or error) back to the Flutter side.
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "configure":
            configure(arguments: call.arguments, result: result)
        case "getTPMStatus":
            getTPMStatus(result: result)
        case "getBiometryStatus":
            getBiometryStatus(result: result)
        case "generateKey":
            generateKeyPair(arguments: call.arguments, result: result)
        case "deleteKey":
            deleteKey(arguments: call.arguments, result: result)
        case "encrypt":
            encrypt(arguments: call.arguments, result: result)
        case "decrypt":
            decrypt(arguments: call.arguments, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - Private Methods
    
    /// Configures Secure Enclave usage, including the prompt title for biometric authentication.
    ///
    /// Expects `arguments` to contain a dictionary with the key `"biometricPromptTitle"` (a `String`).
    ///
    /// - Parameters:
    ///   - arguments: The arguments sent from the Flutter side, typically a dictionary.
    ///   - result: A callback for sending a result or an error back to Flutter.
    private func configure(arguments: Any?, result: @escaping FlutterResult) {
        guard let args = arguments as? [String: Any],
              let authTitle = args["biometricPromptTitle"] as? String else {
            let flutterError = getFlutterError(SecureEnclavePluginError.invalidArgument)
            result(flutterError)
            
            return
        }
        
        try? secureEnclaveManager.configure(authTitle: authTitle)
        result(nil)
    }
    
    /// Checks whether the Secure Enclave is available on the current device.
    ///
    /// Returns `0` if supported, `1` otherwise (as per the existing plugin contract).
    ///
    /// - Parameter result: A callback that returns `0` if the Secure Enclave is supported, or `1` if it is not.
    private func getTPMStatus(result: @escaping FlutterResult) {
        let isSupported = secureEnclaveManager.isSecureEnclaveSupported()
        let value = isSupported ? 0 : 1
        result(value)
    }
    
    /// Checks the availability of biometric authentication on the device.
    ///
    /// Determines whether biometric authentication (such as Face ID or Touch ID) is supported on the device.
    /// Returns `0` if biometric authentication is available, otherwise returns `1`.
    ///
    /// - Parameter result: A callback that returns `0` if biometric authentication is supported, or an error if it is not available.
    private func getBiometryStatus(result: @escaping FlutterResult) {
        let laContext = laContextFactory.createContext()
        
        do {
            let isBiometrySupported = try AuthenticationManager.isBiometrySupported(laContext)
            let value = isBiometrySupported ? 0 : 1
            result(value)
        } catch {
            let flutterError = getFlutterError(SecureEnclavePluginError.biometryNotAvailable)
            result(flutterError)
            return
        }
    }
    
    /// Generates a cryptographic key pair using the Secure Enclave.
    ///
    /// Expects `arguments` to contain a dictionary with the key `"tag"` (a `String`).
    ///
    /// - Parameters:
    ///   - arguments: The arguments sent from Flutter, typically a dictionary with the `tag`.
    ///   - result: A callback that returns `nil` on success, or an error on failure.
    private func generateKeyPair(arguments: Any?, result: @escaping FlutterResult) {
        guard secureEnclaveManager.isSecureEnclaveSupported() else {
            let flutterError = getFlutterError(SecureEnclavePluginError.secureEnclaveNoAvailable)
            result(flutterError)
            
            return
        }
        
        guard let args = arguments as? [String: Any],
              let tag = args["tag"] as? String else {
            let flutterError = getFlutterError(SecureEnclavePluginError.invalidArgument)
            result(flutterError)
            
            return
        }
        
        do {
            try secureEnclaveManager.generateKeyPair(tag: tag)
            result(nil)
        } catch let error as SecureEnclaveManagerError where error == .keyAlreadyExists {
            let flutterError = getFlutterError(error as BaseError)
            result(flutterError)
        } catch {
            let flutterError = getFlutterError(SecureEnclavePluginError.keyGenerationError(error: error))
            result(flutterError)
        }
    }
    
    /// Deletes a cryptographic key associated with a given tag.
    ///
    /// Expects `arguments` to contain a dictionary with the key `"tag"` (a `String`).
    ///
    /// - Parameters:
    ///   - arguments: The arguments sent from Flutter, typically a dictionary with the `tag`.
    ///   - result: A callback that returns `nil` on success, or an error on failure.
    private func deleteKey(arguments: Any?, result: @escaping FlutterResult){
        guard secureEnclaveManager.isSecureEnclaveSupported() else {
            let flutterError = getFlutterError(SecureEnclavePluginError.secureEnclaveNoAvailable)
            result(flutterError)
            
            return
        }
        
        guard let args = arguments as? [String: Any],
              let tag = args["tag"] as? String else {
            let flutterError = getFlutterError(SecureEnclavePluginError.invalidArgument)
            result(flutterError)
            
            return
        }
        
        do{
            try secureEnclaveManager.deleteKey(tag: tag)
            result(nil)
        } catch {
            let flutterError = getFlutterError(SecureEnclavePluginError.keyDeletionError(error: error))
            result(flutterError)
        }
    }
    
    /// Encrypts a string using the Secure Enclave's public key.
    ///
    /// Expects `arguments` to contain:
    /// - `"data"`: A `String` representing the plaintext to encrypt.
    /// - `"tag"`: The key tag associated with the stored key.
    ///
    /// - Parameters:
    ///   - arguments: A dictionary from the Flutter side.
    ///   - result: A callback that returns the encrypted data as a Base64 string on success, or an error on failure.
    private func encrypt(arguments: Any?, result: @escaping FlutterResult) {
        guard secureEnclaveManager.isSecureEnclaveSupported() else {
            let flutterError = getFlutterError(SecureEnclavePluginError.secureEnclaveNoAvailable)
            result(flutterError)
            
            return
        }
        
        guard let args = arguments as? [String: Any],
              let data = args["data"] as? String,
              let tag = args["tag"] as? String else {
            let flutterError = getFlutterError(SecureEnclavePluginError.invalidArgument)
            result(flutterError)
            
            return
        }
        
        do{
            let encryptedData = try secureEnclaveManager.encrypt(data, tag: tag)
            let encryptedDatabase64String = try Base64Codec.encode(encryptedData)
            
            result(encryptedDatabase64String)
        } catch {
            let flutterError = getFlutterError(SecureEnclavePluginError.encryptionError(error: error))
            result(flutterError)
        }
    }
    
    /// Decrypts a Base64-encoded string using the Secure Enclave's private key.
    ///
    /// Expects `arguments` to contain:
    /// - `"data"`: A Base64-encoded `String` representing the encrypted data.
    /// - `"tag"`: The key tag associated with the stored key.
    ///
    /// - Parameters:
    ///   - arguments: A dictionary from the Flutter side.
    ///   - result: A callback that returns the decrypted plaintext on success, or an error on failure.
    private func decrypt(arguments: Any?, result: @escaping FlutterResult) {
        guard secureEnclaveManager.isSecureEnclaveSupported() else {
            let flutterError = getFlutterError(SecureEnclavePluginError.secureEnclaveNoAvailable)
            result(flutterError)
            
            return
        }
        
        guard let args = arguments as? [String: Any],
              let data = args["data"] as? String,
              let tag = args["tag"] as? String else {
            let flutterError = getFlutterError(SecureEnclavePluginError.invalidArgument)
            result(flutterError)
            
            return
        }
        
        do {
            let decryptedDatabase64Data = try Base64Codec.decode(data)
            let decryptedData = try secureEnclaveManager.decrypt(decryptedDatabase64Data, tag: tag)
            
            result(decryptedData)
        } catch let error as KeychainServiceError {
            switch error {
            case .authenticationUserCanceled:
                let flutterError = getFlutterError(error)
                result(flutterError)
            default:
                let flutterError = getFlutterError(SecureEnclavePluginError.decryptionError(error: error))
                result(flutterError)
            }
        } catch {
            let flutterError = getFlutterError(SecureEnclavePluginError.decryptionError(error: error))
            result(flutterError)
        }
    }
    
    /// Converts a `BaseError` into a `FlutterError`, suitable for returning to the Flutter layer.
    ///
    /// - Parameters:
    ///   - error: An error conforming to `BaseError`.
    ///   - details: Optional additional details about the error.
    /// - Returns: A `FlutterError` object containing the error code, message, and details.
    private func getFlutterError(_ error: BaseError ,details: Any? = nil) -> FlutterError {
        return FlutterError(
            code: error.code,
            message: error.errorDescription,
            details: details
        )
    }
}
