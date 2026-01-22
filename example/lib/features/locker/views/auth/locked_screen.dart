import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mfa_demo/features/locker/bloc/locker_bloc.dart';
import 'package:mfa_demo/features/locker/data/models/authentication_result.dart';
import 'package:mfa_demo/features/locker/views/widgets/authentication_bottom_sheet.dart';
import 'package:mfa_demo/features/locker/views/widgets/loading_overlay.dart';
import 'package:mfa_demo/features/locker/views/widgets/locker_bloc_biometric_stream.dart';

/// Screen shown when storage is locked
class LockedScreen extends StatelessWidget {
  const LockedScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Unlock Storage'),
      automaticallyImplyLeading: false,
    ),
    body: BlocBuilder<LockerBloc, LockerState>(
      buildWhen: (previous, current) =>
          previous.loadState != current.loadState || previous.biometricState != current.biometricState,
      builder: (context, state) => Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 32),
                const Icon(Icons.lock, size: 80, color: Colors.grey),
                const SizedBox(height: 24),
                const Text(
                  'Storage Locked',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Enter your password to unlock',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 48),
                ElevatedButton(
                  onPressed: state.loadState == LoadState.loading
                      ? null
                      : () => _showAuthenticationSheet(context, state),
                  child: Text(
                    state.biometricState.isEnabled ? 'Unlock Storage' : 'Unlock with Password',
                  ),
                ),
              ],
            ),
          ),
          if (state.loadState == LoadState.loading) const LoadingOverlay(message: 'Unlocking storage...'),
        ],
      ),
    ),
  );

  Future<void> _showAuthenticationSheet(BuildContext context, LockerState state) async {
    final bloc = context.read<LockerBloc>();

    final result = await showModalBottomSheet<AuthenticationResult?>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (context) => AuthenticationBottomSheet(
        title: 'Unlock Storage',
        showBiometricButton: state.biometricState.isEnabled,
        biometricResultStream: bloc.biometricResultStream,
        onBiometricPressed: state.biometricState.isEnabled
            ? () => bloc.add(const LockerEvent.unlockWithBiometricRequested())
            : null,
      ),
    );

    if (!context.mounted) {
      return;
    }

    if (result?.password != null) {
      context.read<LockerBloc>().add(
        LockerEvent.unlockPasswordSubmitted(password: result!.password!),
      );
    }
  }
}
