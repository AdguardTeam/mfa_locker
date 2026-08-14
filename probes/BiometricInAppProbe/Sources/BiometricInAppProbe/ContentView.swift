import _LocalAuthentication_SwiftUI
import LocalAuthentication
import SwiftUI

/// Embeds `LocalAuthenticationView` — the KEY part of the probe. This view
/// renders the Touch ID request INSIDE the app window (macOS 13+), and we
/// hand it the shared `ProbeModel.context` so the same context can be reused
/// for the Secure-Enclave key operation afterwards.
struct ContentView: View {
  @EnvironmentObject var model: ProbeModel

  var body: some View {
    VStack(spacing: 24) {
      LocalAuthenticationView(
        "Continue with Touch ID",
        reason: Text("Authorize the AW-3216 biometric probe"),
        context: model.context
      ) { result in
        model.handleLAVResult(result)
      }
      .controlSize(.large)

      Button("Use Password…") {
        model.passwordFallback()
      }
      .controlSize(.large)

      ScrollView {
        Text(model.statusText)
          .font(.callout)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(minHeight: 120)
    }
    .padding(24)
    .frame(minWidth: 400, minHeight: 320)
  }
}
