import AppKit
import SwiftUI

/// Standalone verification harness for the AW-3216 question:
/// can `LocalAuthenticationView` (macOS 13+) render the Touch ID request
/// INSDIE the app window (Keychain-like), with the authorized `LAContext`
/// reused so `SecKeyCreateDecryptedData` does not show a second prompt?
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var window: NSWindow!
  private let model = ProbeModel()

  func applicationDidFinishLaunching(_ notification: Notification) {
    let hosting = NSHostingView(rootView: ContentView().environmentObject(model))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 440, height: 320),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "BiometricInAppProbe — AW-3216"
    window.contentView = hosting
    window.center()
    window.makeKeyAndOrderFront(nil)
    self.window = window
    NSApp.activate(ignoringOtherApps: true)
    model.appReady()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }
}
