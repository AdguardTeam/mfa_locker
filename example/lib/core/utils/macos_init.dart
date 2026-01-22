import 'dart:io';

import 'package:macos_window_utils/window_manipulator.dart';

/// Initializes macOS-specific features.
/// No-op on non-macOS platforms.
Future<void> initMacOS() async {
  if (!Platform.isMacOS) {
    return;
  }
  await WindowManipulator.initialize(enableWindowDelegate: true);
}
