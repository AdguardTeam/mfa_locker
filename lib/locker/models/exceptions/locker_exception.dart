/// Typed errors of the locker layer: a session that was locked while an
/// operation was pending, or a misuse of the locker/transaction API.
class LockerException implements Exception {
  final LockerExceptionType type;
  final String message;

  const LockerException({
    required this.type,
    required this.message,
  });

  factory LockerException.locked() => const LockerException(
        type: LockerExceptionType.locked,
        message: 'Locker was locked while the operation was pending',
      );

  factory LockerException.notUnlocked() => const LockerException(
        type: LockerExceptionType.notUnlocked,
        message: 'Locker is not unlocked',
      );

  factory LockerException.insideTransaction() => const LockerException(
        type: LockerExceptionType.insideTransaction,
        message: 'MFALocker methods cannot be used inside a transaction; use LockerTransaction instead',
      );

  factory LockerException.transactionClosed() => const LockerException(
        type: LockerExceptionType.transactionClosed,
        message: 'Transaction is already closed',
      );

  factory LockerException.invalidArgument(String message) => LockerException(
        type: LockerExceptionType.invalidArgument,
        message: message,
      );

  @override
  String toString() => 'LockerException: $message (type: $type)';
}

enum LockerExceptionType {
  /// The locker was locked or disposed while the operation was pending.
  locked,

  /// The unlocked session has not started (e.g. `allMeta` while locked).
  notUnlocked,

  /// An `MFALocker` method was called from a `withTransaction` body.
  insideTransaction,

  /// A transaction method was called after the transaction was closed.
  transactionClosed,

  /// A locker method was called with an invalid argument value.
  invalidArgument,
}
