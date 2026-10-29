import 'package:flutter/foundation.dart';

/// Whether the `biometric_cipher` plugin has an implementation on this platform.
bool get isBiometricCipherSupported => switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.macOS => true,
      _ => false,
    };
