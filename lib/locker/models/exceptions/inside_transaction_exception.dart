/// Thrown when a locker method is called from the body of a `withTransaction`:
/// the transaction owns the lane, so the call would deadlock. Use the
/// [LockerTransaction] methods instead.
class InsideTransactionException implements Exception {
  final String message;

  const InsideTransactionException([
    this.message = 'MFALocker methods cannot be used inside a transaction; use LockerTransaction instead',
  ]);

  @override
  String toString() => 'InsideTransactionException: $message';
}
