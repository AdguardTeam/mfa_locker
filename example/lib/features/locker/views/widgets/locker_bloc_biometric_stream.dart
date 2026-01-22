import 'package:mfa_demo/features/locker/bloc/locker_bloc.dart';
import 'package:mfa_demo/features/locker/views/widgets/biometric_auth_result.dart';

/// Extension to create a [BiometricAuthResult] stream from [LockerBloc].
extension LockerBlocBiometricStream on LockerBloc {
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
