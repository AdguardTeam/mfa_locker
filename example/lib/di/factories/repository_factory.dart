import 'package:locker/security/models/biometric_config.dart';
import 'package:mfa_demo/core/services/timer_service.dart';
import 'package:mfa_demo/features/locker/data/repositories/locker_repository.dart';

/// Abstract factory for creating repository and service instances
abstract class RepositoryFactory {
  LockerRepository get lockerRepository;

  TimerService get timerService;

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
  Future<void> init() async {
    _timerService = TimerServiceImpl(lockerRepository: lockerRepository);

    // Configure secure mnemonic provider once at app startup
    // This must be done before any biometric operations
    await lockerRepository.configureSecureMnemonic(
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
    await _lockerRepository?.dispose();
  }
}
