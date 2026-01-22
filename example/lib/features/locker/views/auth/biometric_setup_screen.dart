import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mfa_demo/features/locker/bloc/locker_bloc.dart';

/// Screen that offers optional biometric setup during initialization
class BiometricSetupScreen extends StatelessWidget {
  const BiometricSetupScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Enable Biometric?'),
    ),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Biometric icon
          const Icon(
            Icons.fingerprint,
            size: 120,
            color: Colors.blue,
          ),
          const SizedBox(height: 32),

          // Title
          const Text(
            'Enable Biometric Authentication?',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),

          // Description
          const Text(
            'Use your fingerprint or face ID to quickly and securely access your storage.',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),

          // Info text
          const Text(
            'You can change this later in Settings',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey,
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),

          // Enable button
          ElevatedButton(
            onPressed: () => _onEnablePressed(context),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text(
              'Enable Biometric',
              style: TextStyle(fontSize: 16),
            ),
          ),
          const SizedBox(height: 12),

          // Skip button
          OutlinedButton(
            onPressed: () => _onSkipPressed(context),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text(
              'Skip for now',
              style: TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    ),
  );

  void _onEnablePressed(BuildContext context) =>
      context.read<LockerBloc>().add(const LockerEvent.biometricSetupAccepted());

  void _onSkipPressed(BuildContext context) =>
      context.read<LockerBloc>().add(const LockerEvent.biometricSetupSkipped());
}
