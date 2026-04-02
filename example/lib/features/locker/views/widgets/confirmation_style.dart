import 'package:flutter/material.dart';

/// Style for confirmation dialogs indicating the severity of the action.
enum ConfirmationStyle {
  /// Warning style with orange icon for less destructive actions.
  warning(iconColor: Colors.orange),

  /// Danger style with red icon for destructive actions.
  danger(iconColor: Colors.red);

  const ConfirmationStyle({required this.iconColor});

  final Color iconColor;
}
