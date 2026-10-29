import 'package:flutter/foundation.dart';

/// The plugin ships native code for Android, iOS and macOS only. On every other
/// platform its method channel has no handler, so a call fails before it ever
/// reaches native code.
bool get isBiometricCipherSupported =>
    !kIsWeb &&
    switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.macOS => true,
      _ => false,
    };
