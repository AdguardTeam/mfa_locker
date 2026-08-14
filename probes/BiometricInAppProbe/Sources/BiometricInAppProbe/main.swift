import AppKit
import SwiftUI

/// Standalone verification harness for the AW-3216 question:
/// can `LocalAuthenticationView` (macOS 13+) render the Touch ID request
/// INSDIE the app window (Keychain-like), with the authorized `LAContext`
/// reused so `SecKeyCreateDecryptedData` does not show a second prompt?
///
/// Entry point (no app bundle): boots NSApplication, hosts the SwiftUI view.
let application = NSApplication.shared
application.setActivationPolicy(.regular)

// Keep a strong reference — NSApplication.delegate is weak and would be
// deallocated immediately otherwise.
let delegate = AppDelegate()
application.delegate = delegate
application.run()
