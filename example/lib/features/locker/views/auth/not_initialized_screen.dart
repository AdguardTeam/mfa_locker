import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mfa_demo/features/locker/bloc/locker_bloc.dart';

/// Screen shown when storage is not initialized
class NotInitializedScreen extends StatelessWidget {
  const NotInitializedScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('MFA Demo'),
    ),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.lock_outline,
            size: 80,
            color: Colors.grey,
          ),
          const SizedBox(height: 24),
          const Text(
            'Storage Not Initialized',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Initialize secure storage to get started',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 48),
          ElevatedButton(
            onPressed: () => _initializeStorage(context),
            child: const Text('Initialize Storage'),
          ),
        ],
      ),
    ),
  );

  void _initializeStorage(BuildContext context) =>
      context.read<LockerBloc>().add(const LockerEvent.initializeRequested());
}
