import 'dart:async';

import 'package:biometric_cipher/biometric_cipher.dart';

/// Service responsible for listening to device screen lock events.
abstract class ScreenLockService {
  /// Set the callback to be invoked when the device screen is locked.
  set onScreenLockedCallback(void Function() onLock);

  /// Start listening for screen lock events.
  void startListening();

  /// Stop listening for screen lock events.
  void stopListening();

  /// Dispose of resources.
  void dispose();
}

class ScreenLockServiceImpl implements ScreenLockService {
  final BiometricCipher _biometricCipher;

  ScreenLockServiceImpl({required BiometricCipher biometricCipher})
      : _biometricCipher = biometricCipher;

  StreamSubscription<bool>? _subscription;
  void Function()? _onScreenLocked;

  @override
  set onScreenLockedCallback(void Function() onLock) => _onScreenLocked = onLock;

  @override
  void startListening() {
    _subscription?.cancel();
    _subscription = _biometricCipher.screenLockStream.listen((_) {
      _onScreenLocked?.call();
    });
  }

  @override
  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
  }

  @override
  void dispose() {
    stopListening();
    _onScreenLocked = null;
  }
}
