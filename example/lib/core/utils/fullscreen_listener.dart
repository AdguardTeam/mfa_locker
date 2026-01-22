import 'dart:io';

import 'package:macos_window_utils/macos/ns_window_delegate.dart';
import 'package:macos_window_utils/ns_window_delegate_handler/ns_window_delegate_handle.dart';
import 'package:macos_window_utils/window_manipulator.dart';

/// Listener for macOS full-screen transitions.
/// Used to prevent false auto-locks during full-screen toggle.
class FullscreenListener {
  final void Function() onTransitionStart;
  final void Function() onTransitionEnd;
  final void Function() onExitComplete;

  FullscreenListener({
    required this.onTransitionStart,
    required this.onTransitionEnd,
    required this.onExitComplete,
  });

  NSWindowDelegateHandle? _handle;

  /// Initializes the listener. Must be called before use.
  void init() {
    if (!Platform.isMacOS) {
      return;
    }
    final delegate = _MacOSWindowDelegate(
      onWillEnter: onTransitionStart,
      onDidEnter: onTransitionEnd,
      onWillExit: onTransitionStart,
      onDidExit: onExitComplete,
    );
    _handle = WindowManipulator.addNSWindowDelegate(delegate);
  }

  /// Disposes the listener. Must be called when no longer needed.
  void dispose() {
    _handle?.removeFromHandler();
    _handle = null;
  }
}

/// NSWindowDelegate implementation for detecting macOS full-screen transitions.
class _MacOSWindowDelegate extends NSWindowDelegate {
  final void Function() onWillEnter;
  final void Function() onDidEnter;
  final void Function() onWillExit;
  final void Function() onDidExit;

  _MacOSWindowDelegate({
    required this.onWillEnter,
    required this.onDidEnter,
    required this.onWillExit,
    required this.onDidExit,
  });

  @override
  void windowWillEnterFullScreen() {
    onWillEnter();
    super.windowWillEnterFullScreen();
  }

  @override
  void windowDidEnterFullScreen() {
    onDidEnter();
    super.windowDidEnterFullScreen();
  }

  @override
  void windowWillExitFullScreen() {
    onWillExit();
    super.windowWillExitFullScreen();
  }

  @override
  void windowDidExitFullScreen() {
    onDidExit();
    super.windowDidExitFullScreen();
  }
}
