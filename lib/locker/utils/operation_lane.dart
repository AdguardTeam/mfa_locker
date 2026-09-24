import 'dart:async';
import 'dart:collection';

import 'package:meta/meta.dart';

/// FIFO queue with a single holder that serializes locker operations.
class OperationLane {
  final Queue<Completer<void>> _queue = Queue();

  bool _busy = false;

  /// Bumped by [invalidate]; [isCurrent] detects a lock that happened while an
  /// operation was waiting or running.
  int _generation = 0;

  bool get isBusy => _busy;

  int get generation => _generation;

  /// Completes when the lane becomes free, in FIFO order.
  Future<void> acquire() {
    if (!_busy) {
      _busy = true;

      return Future.value();
    }

    final ticket = Completer<void>();
    _queue.add(ticket);

    return ticket.future;
  }

  /// Releases the lane and hands it to the next waiter, if any.
  void release() {
    if (!_busy) {
      return;
    }

    if (_queue.isEmpty) {
      _busy = false;

      return;
    }

    _queue.removeFirst().complete();
  }

  /// Fails all pending waiters with [error] without releasing the lane.
  void failPending(Object error) {
    while (_queue.isNotEmpty) {
      _queue.removeFirst().completeError(error);
    }
  }

  /// Bumps the generation and fails pending waiters with [error].
  void invalidate(Object error) {
    _generation++;
    failPending(error);
  }

  /// Whether [generation] is still current, i.e. no [invalidate] since.
  bool isCurrent(int generation) => generation == _generation;

  @visibleForTesting
  int get pendingCount => _queue.length;
}
