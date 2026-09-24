/// Errors of the locker layer: a session that ended while an operation was
/// pending, or a misuse of the locker/transaction API.
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

/// [locked] is thrown when the unlocked session ends mid-operation,
/// [notUnlocked] when it never started (e.g. `allMeta` while locked).
enum LockerExceptionType {
  locked,
  notUnlocked,
  insideTransaction,
  transactionClosed,
  invalidArgument,
}
