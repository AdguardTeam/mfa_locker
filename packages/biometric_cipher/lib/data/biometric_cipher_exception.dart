import 'package:biometric_cipher/data/biometric_cipher_exception_code.dart';

/// Exception thrown by the biometric_cipher plugin when an error occurs.
class BiometricCipherException implements Exception {
  /// The standardized error code identifying the type of error.
  final BiometricCipherExceptionCode code;

  /// A human-readable message describing the error.
  final String message;

  /// Optional platform-specific details about the error.
  final Object? details;

  const BiometricCipherException({
    required this.code,
    required this.message,
    this.details,
  });

  @override
  String toString() => 'BiometricCipherException(code: $code, message: $message, details: $details)';
}
