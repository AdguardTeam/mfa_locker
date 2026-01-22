import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mfa_demo/features/locker/bloc/locker_bloc.dart';

class BiometricUnlockButton extends StatelessWidget {
  const BiometricUnlockButton({super.key});

  @override
  Widget build(BuildContext context) => BlocBuilder<LockerBloc, LockerState>(
    buildWhen: (previous, current) =>
        previous.biometricState != current.biometricState || previous.loadState != current.loadState,
    builder: (context, state) {
      if (!state.biometricState.isEnabled) {
        return const SizedBox.shrink();
      }

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: OutlinedButton.icon(
          icon: const Icon(Icons.fingerprint),
          label: const Text('Unlock with Biometric'),
          onPressed: state.loadState == LoadState.loading
              ? null
              : () {
                  context.read<LockerBloc>().add(
                    const LockerEvent.unlockWithBiometricRequested(),
                  );
                },
        ),
      );
    },
  );
}
