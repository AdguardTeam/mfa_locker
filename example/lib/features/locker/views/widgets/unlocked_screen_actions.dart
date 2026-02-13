import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mfa_demo/core/extensions/context_extensions.dart';
import 'package:mfa_demo/features/locker/bloc/locker_bloc.dart';
import 'package:mfa_demo/features/locker/views/auth/change_password_screen.dart';
import 'package:mfa_demo/features/settings/views/settings_screen.dart';
import 'package:mfa_demo/features/tpm_test/views/tpm_test_screen.dart';

class UnlockedScreenActions extends StatelessWidget {
  const UnlockedScreenActions({
    required this.onClearAll,
    super.key,
  });

  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        tooltip: 'Settings',
        onPressed: () => context.push(const SettingsScreen()),
        icon: const Icon(Icons.settings_outlined),
      ),
      PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'change_password') {
            context.push(const ChangePasswordScreen());
          } else if (value == 'lock') {
            context.read<LockerBloc>().add(const LockerEvent.lockRequested());
          } else if (value == 'clear_all') {
            onClearAll();
          } else if (value == 'tpm_test') {
            context.push(const TPMTestScreen());
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'lock',
            child: Row(
              children: [
                Icon(Icons.lock),
                SizedBox(width: 8),
                Text('Lock'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'change_password',
            child: Row(
              children: [
                Icon(Icons.lock_reset),
                SizedBox(width: 8),
                Text('Change Password'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'tpm_test',
            child: Row(
              children: [
                Icon(Icons.security),
                SizedBox(width: 8),
                Text('TPM Test'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'clear_all',
            child: Row(
              children: [
                Icon(Icons.delete_forever, color: Colors.red),
                SizedBox(width: 8),
                Text('Clear All Data', style: TextStyle(color: Colors.red)),
              ],
            ),
          ),
        ],
      ),
    ],
  );
}
