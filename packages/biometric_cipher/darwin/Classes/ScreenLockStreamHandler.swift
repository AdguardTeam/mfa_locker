#if os(iOS)
import Flutter
import UIKit
#elseif os(macOS)
import Cocoa
import FlutterMacOS
#endif

/// Listens for device screen lock events and forwards them through a Flutter EventChannel.
///
/// - iOS: Observes `protectedDataWillBecomeUnavailableNotification` on `NotificationCenter`.
/// - macOS: Observes `com.apple.screenIsLocked` on `DistributedNotificationCenter`.
class ScreenLockStreamHandler: NSObject, FlutterStreamHandler {

    private var eventSink: FlutterEventSink?

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events

        #if os(iOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onScreenLocked),
            name: UIApplication.protectedDataWillBecomeUnavailableNotification,
            object: nil
        )
        #elseif os(macOS)
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(onScreenLocked),
            name: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil
        )
        #endif

        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        #if os(iOS)
        NotificationCenter.default.removeObserver(self)
        #elseif os(macOS)
        DistributedNotificationCenter.default().removeObserver(self)
        #endif

        eventSink = nil
        return nil
    }

    @objc private func onScreenLocked() {
        eventSink?(true)
    }
}
