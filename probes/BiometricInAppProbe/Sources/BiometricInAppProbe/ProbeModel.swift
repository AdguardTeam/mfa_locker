import Combine
import Foundation
import LocalAuthentication
import Security

/// Holds the probe state and drives the Secure-Enclave key lifecycle.
/// The single `LAContext` is shared between the SwiftUI `LocalAuthenticationView`
/// and the subsequent key operation, so we can observe whether reusing the
/// evaluated context prevents a second prompt.
final class ProbeModel: ObservableObject {
  @Published var statusText = "Preparing…" {
    didSet {
      // Mirror every status transition to stderr (unbuffered) so the probe can
      // be driven and observed in a terminal/headless context (status also
      // shows in the window).
      FileHandle.standardError.write(("[AW3216] \(statusText)\n").data(using: .utf8)!)
    }
  }

  /// IMPORTANT: one shared context. After `LocalAuthenticationView` evaluates a
  /// policy (or its view state is reached), we hand THIS SAME context to
  /// `SecItemCopyMatching`/`SecKeyCreateDecryptedData` to test LAContext reuse.
  let context = LAContext()

  private let keyTagData = "com.adguard.probe.biokey".data(using: .utf8)!
  private var encryptedSample: Data?

  /// True when the Secure Enclave key could not be created (e.g. running the
  /// bare `swift run` binary, which is unsigned and lacks the keychain-access-
  /// groups entitlement -> errSecMissingEntitlement -34018). In that "lite
  /// mode" the in-window LocalAuthenticationView UX still works and can be
  /// demonstrated; only the "no second prompt on decrypt" step needs the
  /// Xcode-signed build (see README).
  private(set) var liteMode = false

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
      liteMode = true
      statusText = "⚠️ LITE MODE: Secure Enclave key unavailable (\(detail)).\n\n" +
        "The in-window biometric UX below still works — try touching the sensor.\n" +
        "Only the 'no second prompt on decrypt' step needs a signed app.\n" +
        "For the full check open BiometricInAppProbe.xcodeproj in Xcode, select your " +
        "Team, and Run (see README)."
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
      // Lite mode: no SE key, so there is nothing to decrypt — report clearly
      // instead of pretending the step ran.
      statusText = "⚠️ LITE MODE: Secure Enclave key was not created, so the " +
        "decrypt / no-second-prompt check can't run here.\n" +
        "The in-window biometric control above still works — touch the sensor to try it.\n" +
        "Full check: ./run.sh app (Xcode) → pick your Team → Run — or run in the real app."
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
