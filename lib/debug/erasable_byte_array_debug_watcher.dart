import 'dart:async';
import 'dart:typed_data';

import 'package:adguard_logger/adguard_logger.dart';
import 'package:locker/erasable/erasable_byte_array.dart';

// TODO(m.semenov): use it in package for debug purposes
class ErasableByteArrayDebugWatcher {
  // When we call ErasableByteArray.erase(), we don't remove it from ErasableByteArrayDebugWatcher pools
  // So we must call ErasableByteArrayDebugWatcher.dispose() to clean up the pools
  final Map<Uint8List, ErasableByteArray> _pool = {};
  final Map<ErasableByteArray, DateTime> _creationTimestamps = {};
  final Map<ErasableByteArray, StackTrace> _creationTraces = {};

  final Duration? _eraseWarningThreshold;
  final Duration? _checkInterval;

  Timer? _checkTimer;

  ErasableByteArrayDebugWatcher({
    Duration? eraseWarningThreshold,
    Duration? checkInterval,
  })  : assert(
          (eraseWarningThreshold == null) == (checkInterval == null),
          'Both eraseWarningThreshold and checkInterval must be provided or none of them',
        ),
        _checkInterval = checkInterval,
        _eraseWarningThreshold = eraseWarningThreshold {
    _initCheckTimer();
  }

  bool get _debugMode => _checkInterval != null && _eraseWarningThreshold != null;

  int get size => _pool.length;

  Iterable<ErasableByteArray> get values => _pool.values;

  void add(ErasableByteArray byteArray) {
    final bytes = byteArray.bytes;

    // Use identity comparison by using the list itself as the key.
    if (_pool.containsKey(bytes)) {
      return;
    }

    _pool[bytes] = byteArray;
    _creationTimestamps[byteArray] = DateTime.now();

    if (_debugMode) {
      _creationTraces[byteArray] = StackTrace.current;
    }
  }

  StackTrace? getTraceFor(ErasableByteArray object) => _creationTraces[object];

  void shutdownCheckTimer() => _checkTimer?.cancel();

  void _initCheckTimer() {
    if (!_debugMode) {
      return;
    }

    _checkTimer = Timer.periodic(
      _checkInterval!,
      (_) => _logLongLivedObjects(),
    );
  }

  /// Logs a warning if any [ErasableByteArray] instance remains un-erased
  /// for longer than [_eraseWarningThreshold].
  ///
  /// This method is being called periodically by [_checkTimer] every [_checkInterval].
  void _logLongLivedObjects() {
    final currentTime = DateTime.now();

    for (final entry in _creationTimestamps.entries) {
      final array = entry.key;
      final timestamp = entry.value;

      if (array.isErased) continue;

      final elapsed = currentTime.difference(timestamp);

      if (elapsed > _eraseWarningThreshold!) {
        final trace = _creationTraces[array];
        final message = 'Warning: ErasableByteArray instance not erased for ${elapsed.inMilliseconds} ms';

        logger.logWarning(trace != null ? '$message. Trace: $trace' : message);
      }
    }
  }

  void dispose() {
    _checkTimer?.cancel();
    _checkTimer = null;

    _pool.clear();
    _creationTimestamps.clear();
    _creationTraces.clear();
  }
}
