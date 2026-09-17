/// Thrown when the locker was locked (or disposed) while an operation was
/// waiting in the queue or running, so its result must not be applied.
class LockerLockedException implements Exception {
  final String message;

  const LockerLockedException([
    this.message = 'Locker was locked while the operation was waiting',
  ]);

  @override
  String toString() => 'LockerLockedException: $message';
}
