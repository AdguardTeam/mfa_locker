import 'dart:async';

import 'package:mfa_demo/features/locker/data/repositories/locker_repository.dart';

/// Service responsible for managing auto-lock timer logic.
abstract class TimerService {
  /// Current timeout duration
  Duration get timeout;

  /// Set the callback to be invoked when the timer expires
  set onLockCallback(void Function() onLock);

  /// Check if the app should be locked based on stored timestamp
  /// Returns true if current time exceeds the stored end timestamp
  bool get shouldLockOnResume;

  /// Initialize the service with stored preferences
  Future<void> startTimer();

  /// Refresh timeout from locker
  Future<void> updateLockTimeout();

  /// Stop the auto-lock timer
  void stopTimer();

  /// Called when user activity is detected - resets the timer
  void touch();

  /// Dispose of resources
  void dispose();
}

class TimerServiceImpl implements TimerService {
  final LockerRepository _lockerRepository;

  TimerServiceImpl({
    required LockerRepository lockerRepository,
  }) : _lockerRepository = lockerRepository;

  Duration _timeout = const Duration(minutes: 5);
  Timer? _lockTimer;
  void Function()? _onLock;

  int? _endTimestamp;

  @override
  Duration get timeout => _timeout;

  @override
  set onLockCallback(void Function() onLock) => _onLock = onLock;

  @override
  bool get shouldLockOnResume {
    final endTimestamp = _endTimestamp;
    if (endTimestamp == null) {
      return false;
    }

    final now = DateTime.now().millisecondsSinceEpoch;

    return now >= endTimestamp;
  }

  bool get _isRunning => _lockTimer?.isActive ?? false;

  @override
  Future<void> startTimer() async {
    _timeout = await _lockerRepository.autoLockTimeout;
    _scheduleTimer();
  }

  @override
  Future<void> updateLockTimeout() async {
    _timeout = await _lockerRepository.autoLockTimeout;

    if (_isRunning) {
      _scheduleTimer();
    }
  }

  @override
  void stopTimer() => _cancelTimer();

  @override
  void touch() {
    if (_isRunning) {
      _scheduleTimer();
    }
  }

  @override
  void dispose() => _cancelTimer();

  void _scheduleTimer() {
    _lockTimer?.cancel();

    _endTimestamp = DateTime.now().add(_timeout).millisecondsSinceEpoch;

    _lockTimer = Timer(_timeout, () {
      _onLock?.call();
    });
  }

  void _cancelTimer() {
    _lockTimer?.cancel();
    _lockTimer = null;
    _endTimestamp = null;
  }
}
