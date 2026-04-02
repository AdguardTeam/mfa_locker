import 'package:biometric_cipher/biometric_cipher.dart';
import 'package:locker/security/models/biometric_config.dart';
import 'package:mfa_demo/core/services/screen_lock_service.dart';
import 'package:mfa_demo/core/services/timer_service.dart';
import 'package:mfa_demo/features/locker/data/repositories/locker_repository.dart';

/// Abstract factory for creating repository and service instances
abstract class RepositoryFactory {
  LockerRepository get lockerRepository;

  TimerService get timerService;

  ScreenLockService get screenLockService;

  Future<void> init();

  Future<void> dispose();
}

/// Implementation that provides singleton repository and service instances
class RepositoryFactoryImpl implements RepositoryFactory {
  final String _storageFilePath;

  RepositoryFactoryImpl({
    required String storageFilePath,
  }) : _storageFilePath = storageFilePath;

  LockerRepository? _lockerRepository;
  TimerService? _timerService;
  late final BiometricCipher _biometricCipher;
  late final ScreenLockService _screenLockService;

  @override
  LockerRepository get lockerRepository =>
      _lockerRepository ??= LockerRepositoryImpl(storageFilePath: _storageFilePath);

  @override
  TimerService get timerService {
    if (_timerService == null) {
      throw StateError('TimerService not initialized. Call init() first.');
    }

    return _timerService!;
  }

  @override
  ScreenLockService get screenLockService => _screenLockService;

  @override
  Future<void> init() async {
    _timerService = TimerServiceImpl(lockerRepository: lockerRepository);
    _biometricCipher = BiometricCipher();
    _screenLockService = ScreenLockServiceImpl(biometricCipher: _biometricCipher);

    // Configure biometric cipher provider once at app startup
    // This must be done before any biometric operations
    await lockerRepository.configureBiometricCipher(
      const BiometricConfig(
        promptTitle: 'Authenticate',
        promptSubtitle: 'Use biometric to unlock',
        androidCancelButtonText: 'Cancel',
        androidPromptDescription: 'Confirm your identity to access your locker',
      ),
    );
  }

  @override
  Future<void> dispose() async {
    _timerService?.dispose();
    _screenLockService.dispose();
    await _lockerRepository?.dispose();
  }
}
