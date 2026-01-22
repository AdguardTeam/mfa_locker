import 'package:synchronized/synchronized.dart';

/// Callable helper that runs async blocks exclusively via a Lock.
/// Use a single shared instance per resource so all callers serialize on the same lock.
class Sync {
  final Lock _lock = Lock(reentrant: true);

  Future<T> call<T>(Future<T> Function() body) => _lock.synchronized<T>(body);
}
