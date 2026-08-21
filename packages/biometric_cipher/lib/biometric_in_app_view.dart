import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// AW-3216 embeddable in-window biometric (macOS 13+).
///
/// Renders the native `LocalAuthenticationView` inside the app window via the
/// `biometric_in_app_view` platform view. On success the native side stores the
/// authorized `LAContext` on `SecureEnclaveManager` and fires `onSuccess`; the
/// subsequent Secure-Enclave decrypt (master-key wrap unwrap) then reuses that
/// context — no second system prompt.
///
/// On platforms other than macOS this widget renders a disabled placeholder.
class BiometricInAppView extends StatefulWidget {
  const BiometricInAppView({
    super.key,
    required this.onSuccess,
    this.onCancel,
    this.placeholder = const SizedBox.shrink(),
  });

  /// Called when the in-window biometric was accepted (authorized context stored).
  final VoidCallback onSuccess;

  /// Called on cancel/error (authorized context cleared).
  final VoidCallback? onCancel;

  /// Shown on unsupported platforms.
  final Widget placeholder;

  @override
  State<BiometricInAppView> createState() => _BiometricInAppViewState();
}

class _BiometricInAppViewState extends State<BiometricInAppView> {
  MethodChannel? _channel;
  // One-shot per view: fire onSuccess/onFailure only once, so a rebuild of the
  // platform view cannot dispatch a duplicate unlock (AW-3216 real-app fix).
  bool _resolved = false;

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> _onPlatformViewCreated(int id) async {
    final channel = MethodChannel('biometric_cipher/in_app_view_$id');
    _channel = channel;
    channel.setMethodCallHandler((call) async {
      if (_resolved) {
        return;
      }
      _resolved = true;
      switch (call.method) {
        case 'onSuccess':
          widget.onSuccess();
        case 'onFailure':
          widget.onCancel?.call();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isMacOS) {
      return widget.placeholder;
    }
    // macOS platform view (matches the AW-3216 spike's AppKitView usage).
    return AppKitView(
      viewType: 'biometric_in_app_view',
      onPlatformViewCreated: _onPlatformViewCreated,
    );
  }
}

/// Safe helper: whether the in-window biometric platform view was registered.
@visibleForTesting
String biometricInAppViewType = 'biometric_in_app_view';
