import Combine
import Foundation
import LocalAuthentication
import Security

/// Holds the probe state and drives the Secure-Enclave key lifecycle.
/// The single `LAContext` is shared between the SwiftUI `LocalAuthenticationView`
/// and the subsequent key operation, so we can observe whether reusing the
/// evaluated context prevents a second prompt.
final class ProbeModel: ObservableObject {
  @Published var statusText = "Preparing…"

  /// IMPORTANT: one shared context. After `LocalAuthenticationView` evaluates a
  /// policy (or its view state is reached), we hand THIS SAME context to
  /// `SecItemCopyMatching`/`SecKeyCreateDecryptedData` to test LAContext reuse.
  let context = LAContext()

  private let keyTagData = "com.adguard.probe.biokey".data(using: .utf8)!
  private var encryptedSample: Data?

  func appReady() {
    setupKeyAndSample()
  }

  // MARK: - UI actions

  /// Called after the in-window LocalAuthenticationView completes.
  func handleLAVResult(_ result: Result<Void, Error>) {
    switch result {
    case .success:
      statusText = "✅ LocalAuthenticationView succeeded → reusing context for decrypt…"
      runDecryptWithContext()
    case .failure(let error):
      statusText = "❌ LocalAuthenticationView failed: \(describeError(error))"
    }
  }

  /// Manual fallback path: evaluate a policy on the SAME context directly
  /// (system passcode/biometry), then decrypt with that context.
  func passwordFallback() {
    statusText = "Trying deviceOwnerAuthentication fallback…"
    context.evaluatePolicy(
      .deviceOwnerAuthentication,
      localizedReason: "Authorize biometric probe (fallback)"
    ) { [weak self] success, error in
      DispatchQueue.main.async {
        guard let self else { return }
        if success {
          self.statusText = "✅ Fallback authorized → decrypt with context…"
          self.runDecryptWithContext()
        } else {
          self.statusText = "❌ Fallback failed / canceled: \(self.describeError(error))"
        }
      }
    }
  }

  // MARK: - Secure Enclave key + sample

  private func setupKeyAndSample() {
    // Delete any stale key from earlier runs so the test is deterministic.
    let deleteQuery: [String: Any] = [
      kSecClass as String: kSecClassKey,
      kSecAttrApplicationTag as String: keyTagData,
    ]
    SecItemDelete(deleteQuery as CFDictionary)

    guard let accessControl = SecAccessControlCreateWithFlags(
      kCFAllocatorDefault,
      kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
      [.privateKeyUsage, .biometryCurrentSet],
      nil
    ) else {
      statusText = "❌ SecAccessControlCreateWithFlags failed"
      return
    }

    let query: [String: Any] = [
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrKeySizeInBits as String: 256,
      kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
      kSecAttrApplicationTag as String: keyTagData,
      kSecPrivateKeyAttrs as String: [
        kSecAttrIsPermanent as String: true,
        kSecAttrApplicationTag as String: keyTagData,
        kSecAttrAccessControl as String: accessControl,
      ],
    ]

    var error: Unmanaged<CFError>?
    guard let privateKey = SecKeyCreateRandomKey(query as CFDictionary, &error) else {
      let detail = error.map { String(describing: $0.takeRetainedValue()) } ?? "no error info"
      statusText = "❌ Could not create Secure Enclave key: \(detail)\n\n" +
        "If you see -34018 (errSecMissingEntitlement): run via `./run.sh` " +
        "(it signs the binary with keychain entitlements) instead of `swift run`."
      return
    }

    guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
      statusText = "❌ Could not copy public key"
      return
    }

    let plaintext = "AW-3216 in-app biometric probe — decrypt me".data(using: .utf8)!
    guard let cipher = SecKeyCreateEncryptedData(
      publicKey,
      .eciesEncryptionCofactorX963SHA256AESGCM,
      plaintext as CFData,
      &error
    ) else {
      let detail = error.map { String(describing: $0.takeRetainedValue()) } ?? "no error info"
      statusText = "❌ Encrypt failed: \(detail)"
      return
    }

    encryptedSample = cipher as Data
    statusText = """
    ✅ Secure Enclave key created; sample encrypted.

    Touch the sensor via the in-window control below,
    or press “Use Password…” to exercise the fallback.
    """
  }

  /// Performs decryption reusing the (already authorized) shared `LAContext`.
  /// If the context reuse works, this completes WITHOUT a second system prompt
  /// (status == errSecSuccess, no new dialog). If a prompt is required, macOS
  /// returns errSecInteractionNotAllowed / shows a system sheet — we log it.
  private func runDecryptWithContext() {
    guard let cipher = encryptedSample else {
      statusText = "❌ No encrypted sample (setup failed earlier)."
      return
    }

    var query: [String: Any] = [
      kSecClass as String: kSecClassKey,
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
      kSecAttrApplicationTag as String: keyTagData,
      kSecReturnRef as String: true,
      kSecUseAuthenticationContext as String: context,
    ]

    var item: CFTypeRef?
    let matchStatus = SecItemCopyMatching(query as CFDictionary, &item)

    guard matchStatus == errSecSuccess else {
      statusText = "⚠️ SecItemCopyMatching(status=\(matchStatus)) — a second " +
        "system prompt was REQUIRED (LAContext reuse NOT suppressing it). " +
        describeOSStatus(matchStatus)
      return
    }

    let privateKey = item as! SecKey

    var decryptError: Unmanaged<CFError>?
    guard let plain = SecKeyCreateDecryptedData(
      privateKey,
      .eciesEncryptionCofactorX963SHA256AESGCM,
      cipher as CFData,
      &decryptError
    ) else {
      let detail = decryptError.map { String(describing: $0.takeRetainedValue()) } ?? "no error info"
      statusText = "❌ Decrypt failed: \(detail)"
      return
    }

    let text = String(data: plain as Data, encoding: .utf8) ?? "<non-utf8>"
    statusText = "🎉 SUCCESS — decrypted in-app with reused LAContext, " +
      "no second prompt (status=errSecSuccess). Plaintext: \"\(text)\""
  }

  // MARK: - Error helpers

  private func describeError(_ error: Error?) -> String {
    guard let error else { return "unknown error" }
    let nsError = error as NSError
    return "\(nsError.domain) — code \(nsError.code) (\(nsError.localizedDescription))"
  }

  private func describeOSStatus(_ status: OSStatus) -> String {
    if status == errSecInteractionNotAllowed {
      return "(errSecInteractionNotAllowed — needs a fresh auth prompt)"
    }
    if status == errSecAuthFailed {
      return "(errSecAuthFailed)"
    }
    return "(\(status))"
  }
}
