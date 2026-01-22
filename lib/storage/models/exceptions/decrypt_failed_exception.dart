class DecryptFailedException implements Exception {
  final String? message;
  final StackTrace? stackTrace;

  const DecryptFailedException({
    this.message,
    this.stackTrace,
  });

  @override
  String toString() => 'DecryptFailedException(message: $message, stackTrace: $stackTrace)';
}
