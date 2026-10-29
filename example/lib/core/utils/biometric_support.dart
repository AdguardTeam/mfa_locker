import 'package:flutter/foundation.dart';

/// Whether the `biometric_cipher` plugin has an implementation on this platform.
///
/// The plugin ships native code for Android, iOS and macOS only. On every other
/// platform its method channel has no handler, so a call fails before it ever
/// reaches native code — which is why the app must not offer biometric features
/// where this is `false`.
bool get isBiometricCipherSupported => switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.macOS => true,
      _ => false,
    };
