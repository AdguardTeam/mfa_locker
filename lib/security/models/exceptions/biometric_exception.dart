class BiometricException implements Exception {
  final BiometricExceptionType type;
  final Object? originalError;

  const BiometricException(
    this.type, {
    this.originalError,
  });

  @override
  String toString() => 'BiometricException(type: $type)';
}

enum BiometricExceptionType {
  cancel,
  failure,
  keyNotFound,
  keyAlreadyExists,
  notAvailable,
  notConfigured,
}
