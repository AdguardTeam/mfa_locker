import 'package:locker/erasable/erasable.dart';

/// Runs [callback] and erases sensitive arguments afterwards: [erasables] always
/// (in `finally`) and [erasablesOnError] only when [callback] throws.
///
/// Marks the single API boundary that owns the caller's raw input, so erase
/// happens exactly once per operation.
Future<T> eraseAfter<T>({
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
