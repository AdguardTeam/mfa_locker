class StorageException implements Exception {
  final StorageExceptionType type;
  final String message;

  const StorageException({
    required this.type,
    required this.message,
  });

  factory StorageException.notInitialized() => const StorageException(
        type: StorageExceptionType.notInitialized,
        message: 'Storage is not initialized',
      );

  factory StorageException.alreadyInitialized() => const StorageException(
        type: StorageExceptionType.alreadyInitialized,
        message: 'Storage is already initialized',
      );

  factory StorageException.invalidStorage({String? message}) => StorageException(
        type: StorageExceptionType.invalidStorage,
        message: message ?? 'Storage is invalid',
      );

  factory StorageException.entryNotFound({required String entryId}) => StorageException(
        type: StorageExceptionType.entryNotFound,
        message: 'Entry with id $entryId not found',
      );

  factory StorageException.other(String message) => StorageException(
        type: StorageExceptionType.other,
        message: message,
      );

  @override
  String toString() => 'StorageException: $message (type: $type)';
}

enum StorageExceptionType {
  notInitialized,
  alreadyInitialized,
  invalidStorage,
  entryNotFound,
  other,
}
