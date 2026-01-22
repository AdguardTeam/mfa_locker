import 'package:freezed_annotation/freezed_annotation.dart';

part 'authentication_result.freezed.dart';

/// Result of authentication bottom sheet
@freezed
abstract class AuthenticationResult with _$AuthenticationResult {
  const factory AuthenticationResult({
    /// Password entered by user (null if cancelled or biometric used)
    String? password,

    /// True if biometric authentication was successful
    @Default(false) bool isBiometricSuccess,

    /// True if user cancelled the authentication
    @Default(false) bool cancelled,
  }) = _AuthenticationResult;
}

/// Extension methods for [AuthenticationResult] (works for both nullable and non-nullable).
extension AuthenticationResultExtensions on AuthenticationResult? {
  /// Returns true if the result is not null and contains a valid, non-empty password.
  bool get hasValidPassword => this != null && this!.password != null && this!.password!.isNotEmpty;
}
