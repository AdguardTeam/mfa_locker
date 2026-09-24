import 'package:locker/erasable/erasable.dart';

abstract final class MFALockerUtils {
  /// Runs [callback] and erases [erasables] afterwards, plus [erasablesOnError]
  /// when it throws; the single erase point of an API boundary.
  static Future<T> eraseAfter<T>({
    required List<Erasable> erasables,
    required Future<T> Function() callback,
    List<Erasable> erasablesOnError = const [],
  }) async {
    try {
      return await callback();
    } catch (_) {
      for (final erasable in erasablesOnError) {
        erasable.erase();
      }

      rethrow;
    } finally {
      for (final erasable in erasables) {
        erasable.erase();
      }
    }
  }
}
