import 'package:locker/locker.dart';
import 'package:mfa_demo/core/constants/app_constants.dart';
import 'package:mfa_demo/features/locker/views/widgets/biometric_auth_result.dart';

/// Maps a biometric [BiometricState] to the failure the UI already knows about.
extension BiometricStateKnownFailure on BiometricState {
  /// The failure this state implies before any attempt is made, or `null` when it implies none.
  ///
  /// An invalidated key never starts an attempt, so this is how its reason reaches the sheet.
  BiometricAuthResult? get knownAuthFailure =>
      isKeyInvalidated ? const BiometricKeyInvalidated(AppConstants.biometricKeyInvalidatedMessage) : null;
}
