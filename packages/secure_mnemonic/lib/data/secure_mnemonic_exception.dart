import 'package:secure_mnemonic/data/secure_mnemonic_exception_code.dart';

/// Exception thrown by the secure_mnemonic plugin when an error occurs.
class SecureMnemonicException implements Exception {
  /// The standardized error code identifying the type of error.
  final SecureMnemonicExceptionCode code;

  /// A human-readable message describing the error.
  final String message;

  /// Optional platform-specific details about the error.
  final Object? details;

  const SecureMnemonicException({
    required this.code,
    required this.message,
    this.details,
  });

  @override
  String toString() => 'SecureMnemonicException(code: $code, message: $message, details: $details)';
}
