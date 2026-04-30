import 'package:locker/security/biometric_cipher_provider.dart';

/// Broadcast stream of device screen-lock events.
///
/// Adapts [BiometricCipherProvider.screenLockStream] into a [Stream] that emits
/// once per lock transition; unlock events are filtered out.
abstract class ScreenLockService {
  Stream<void> get onScreenLocked;
}

class ScreenLockServiceImpl implements ScreenLockService {
  final BiometricCipherProvider _biometricCipherProvider;

  ScreenLockServiceImpl({required BiometricCipherProvider biometricCipherProvider})
      : _biometricCipherProvider = biometricCipherProvider;

  @override
  late final Stream<void> onScreenLocked = _biometricCipherProvider.screenLockStream
      .where((isLocked) => isLocked)
      .map((_) {});
}
