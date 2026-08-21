import Cocoa
import FlutterMacOS
import SwiftUI
import LocalAuthentication
import _LocalAuthentication_SwiftUI

/// AW-3216 in-window biometric bridge (macOS 13+).
///
/// A Flutter platform view embedding a SwiftUI `LocalAuthenticationView` inside
/// the app window. On success it hands the shared, OS-authorized `LAContext` to
/// `SecureEnclaveManager.setAuthorizedContext`, so the subsequent
/// `SecKeyCreateDecryptedData` (master-key wrap unwrap) reuses it and does NOT
/// show a second system prompt.
///
/// Events to Dart (channel `biometric_cipher/in_app_view_<viewId>`):
///   - `onSuccess`  — in-window biometric accepted, authorized context stored
///   - `onFailure`  — cancel/error (context cleared)
#if os(macOS)

@available(macOS 13.0, *)
final class BiometricInAppViewFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger
    private let manager: SecureEnclaveManagerProtocol

    init(messenger: FlutterBinaryMessenger, manager: SecureEnclaveManagerProtocol) {
        self.messenger = messenger
        self.manager = manager
        super.init()
    }

    func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
        return BiometricInAppView(messenger: messenger, viewId: viewId, manager: manager)
    }
}

@available(macOS 13.0, *)
final class BiometricInAppView: NSView {
    private let context = LAContext()
    private let channel: FlutterMethodChannel
    private let manager: SecureEnclaveManagerProtocol

    init(messenger: FlutterBinaryMessenger, viewId: Int64, manager: SecureEnclaveManagerProtocol) {
        self.manager = manager
        self.channel = FlutterMethodChannel(
            name: "biometric_cipher/in_app_view_\(viewId)",
            binaryMessenger: messenger
        )
        super.init(frame: .zero)

        let handler: (Result<Void, Error>) -> Void = { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                // Reuse the exact context the in-window view used for the SE-key op.
                self.manager.setAuthorizedContext(self.context)
                self.channel.invokeMethod("onSuccess", arguments: nil)
            case .failure(let error):
                self.manager.resetAuthorizedContext()
                self.channel.invokeMethod("onFailure", arguments: error.localizedDescription)
            }
        }

        let root = BiometricInAppContent(context: context, handler: handler)
        let hosting = NSHostingView(rootView: root)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosting.topAnchor.constraint(equalTo: topAnchor),
            hosting.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@available(macOS 13.0, *)
struct BiometricInAppContent: View {
    let context: LAContext
    let handler: (Result<Void, Error>) -> Void

    var body: some View {
        LocalAuthenticationView(
            "Continue with Touch ID",
            reason: Text("Unlock the wallet with biometrics"),
            context: context
        ) { result in
            handler(result)
        }
        .controlSize(.large)
        .frame(minWidth: 280, minHeight: 200)
        .padding(16)
    }
}
#endif
