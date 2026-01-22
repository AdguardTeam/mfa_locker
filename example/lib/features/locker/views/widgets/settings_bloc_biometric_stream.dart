import 'package:mfa_demo/features/locker/views/widgets/biometric_auth_result.dart';
import 'package:mfa_demo/features/settings/bloc/settings_bloc.dart' hide BiometricNotAvailable;

/// Extension to create a [BiometricAuthResult] stream from [SettingsBloc].
extension SettingsBlocBiometricStream on SettingsBloc {
  Stream<BiometricAuthResult> get biometricResultStream => actions
      .map(
        (action) => action.mapOrNull(
          biometricAuthenticationSucceeded: (_) => const BiometricSuccess(),
          biometricAuthenticationCancelled: (_) => const BiometricCancelled(),
          biometricAuthenticationFailed: (a) => BiometricFailed(a.message),
          biometricNotAvailable: (_) => const BiometricNotAvailable(),
        ),
      )
      .where((result) => result != null)
      .cast<BiometricAuthResult>();
}
