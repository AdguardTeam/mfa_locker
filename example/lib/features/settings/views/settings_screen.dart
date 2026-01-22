import 'package:action_bloc/action_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:locker/locker/models/biometric_state.dart';
import 'package:mfa_demo/core/constants/app_constants.dart';
import 'package:mfa_demo/core/extensions/context_extensions.dart';
import 'package:mfa_demo/features/locker/bloc/locker_bloc.dart';
import 'package:mfa_demo/features/locker/data/models/authentication_result.dart';
import 'package:mfa_demo/features/locker/views/widgets/authentication_bottom_sheet.dart';
import 'package:mfa_demo/features/locker/views/widgets/authentication_bottom_sheet_content.dart';
import 'package:mfa_demo/features/locker/views/widgets/loading_overlay.dart';
import 'package:mfa_demo/features/locker/views/widgets/settings_bloc_biometric_stream.dart';
import 'package:mfa_demo/features/locker/views/widgets/timeout_picker_dialog.dart';
import 'package:mfa_demo/features/settings/bloc/settings_bloc.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) => context.blocFactory.settingsBloc..add(const SettingsEvent.loadSettingsRequested()),
    child: const _SettingsView(),
  );
}

class _SettingsView extends StatefulWidget {
  const _SettingsView();

  @override
  State<_SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<_SettingsView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      context.read<LockerBloc>().add(const LockerEvent.checkBiometricAvailabilityRequested());
    });
  }

  @override
  Widget build(BuildContext context) => BlocActionListener<SettingsBloc, SettingsState, SettingsAction>(
    listener: (context, action) => action.whenOrNull(
      showError: context.showErrorSnackBar,
      showSuccess: context.showSuccessSnackBar,
    ),
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: BlocBuilder<LockerBloc, LockerState>(
        builder: (context, lockerState) => Stack(
          children: [
            BlocBuilder<SettingsBloc, SettingsState>(
              builder: (context, state) => Column(
                children: [
                  if (state.loadingState == LoadingState.loading)
                    const LinearProgressIndicator(
                      minHeight: 2,
                    ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                      children: [
                        Card(
                          child: _AutoLockTimeoutTile(state: state),
                        ),
                        const SizedBox(height: 12),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: BlocBuilder<LockerBloc, LockerState>(
                              buildWhen: (previous, current) => previous.biometricState != current.biometricState,
                              builder: (context, innerLockerState) => Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SwitchListTile.adaptive(
                                    title: const Text('Biometric authentication'),
                                    subtitle: Text(
                                      _getBiometricStateDescription(innerLockerState.biometricState),
                                    ),
                                    value: innerLockerState.biometricState.isEnabled,
                                    onChanged: _canToggleBiometric(innerLockerState) ? _handleBiometricToggle : null,
                                  ),
                                  if (innerLockerState.biometricState.isEnabled)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16),
                                      child: Text(
                                        'Your biometric credentials can unlock the vault.',
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (lockerState.loadState == LoadState.loading) const LoadingOverlay(message: 'Processing...'),
          ],
        ),
      ),
    ),
  );

  bool _canToggleBiometric(LockerState state) =>
      state.biometricState.isAvailable && state.loadState != LoadState.loading;

  Future<void> _handleBiometricToggle(bool value) async {
    final result = await showModalBottomSheet<AuthenticationResult?>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (context) => AuthenticationBottomSheetContent(
        title: value ? 'Enable Biometric Authentication' : 'Disable Biometric Authentication',
        showBiometricButton: false,
      ),
    );

    if (!mounted || !result.hasValidPassword) {
      return;
    }

    final lockerBloc = context.read<LockerBloc>();

    if (value) {
      lockerBloc.add(
        LockerEvent.enableBiometricRequested(password: result!.password!),
      );
    } else {
      lockerBloc.add(
        LockerEvent.disableBiometricRequested(password: result!.password!),
      );
    }
  }

  String _getBiometricStateDescription(BiometricState biometricState) => switch (biometricState) {
    BiometricState.tpmUnsupported => 'Secure storage not available on this device',
    BiometricState.tpmVersionIncompatible => 'Device security version incompatible',
    BiometricState.hardwareUnavailable => 'Biometric authentication not supported',
    BiometricState.notEnrolled => 'Please set up fingerprint/face in device settings',
    BiometricState.disabledByPolicy => 'Biometric authentication disabled by administrator',
    BiometricState.securityUpdateRequired => 'Security update required',
    BiometricState.availableButDisabled => 'Enable biometric unlock',
    BiometricState.enabled => 'Biometric unlock enabled',
  };
}

class _AutoLockTimeoutTile extends StatelessWidget {
  const _AutoLockTimeoutTile({
    required this.state,
  });

  final SettingsState state;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.timer_outlined),
    title: const Text('Auto-Lock Timeout'),
    subtitle: Text(_formatDuration(state.autoLockTimeout)),
    trailing: state.loadingState == LoadingState.loading
        ? const SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.chevron_right),
    onTap: state.loadingState == LoadingState.loading ? null : () => _showTimeoutDialog(context, state.autoLockTimeout),
  );

  String _formatDuration(Duration duration) {
    if (duration == AppConstants.lockTimeoutDisabledDuration) {
      return 'Never';
    }

    final minutes = duration.inMinutes;

    return minutes == 1 ? '1 minute' : '$minutes minutes';
  }

  Future<void> _showTimeoutDialog(BuildContext context, Duration currentSelection) async {
    final timeout = await showTimeoutPickerDialog(
      context,
      currentSelection: currentSelection,
    );

    if (timeout == null || !context.mounted) {
      return;
    }

    final lockerBloc = context.read<LockerBloc>();
    final isBiometricEnabled = lockerBloc.state.biometricState.isEnabled;

    if (isBiometricEnabled) {
      lockerBloc.add(
        const LockerEvent.biometricOperationStateChanged(
          biometricOperationState: BiometricOperationState.inProgress,
        ),
      );
    }

    final settingsBloc = context.read<SettingsBloc>();

    final result = await showModalBottomSheet<AuthenticationResult?>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (context) => AuthenticationBottomSheet(
        title: 'Set Auto-Lock Timeout',
        showBiometricButton: isBiometricEnabled,
        biometricResultStream: settingsBloc.biometricResultStream,
        onBiometricPressed: isBiometricEnabled
            ? () => settingsBloc.add(
                SettingsEvent.autoLockTimeoutSelectedWithBiometric(timeout),
              )
            : null,
      ),
    );

    if (isBiometricEnabled) {
      lockerBloc.add(
        const LockerEvent.biometricOperationStateChanged(
          biometricOperationState: BiometricOperationState.idle,
        ),
      );
    }

    if (context.mounted && result?.isBiometricSuccess == false && result.hasValidPassword) {
      settingsBloc.add(
        SettingsEvent.autoLockTimeoutSelected(
          timeout,
          result!.password!,
        ),
      );
    }
  }
}
