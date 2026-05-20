import 'package:mfa_demo/core/services/timer_service.dart';
import 'package:mfa_demo/features/locker/bloc/locker_bloc.dart';
import 'package:mfa_demo/features/locker/data/repositories/locker_repository.dart';
import 'package:mfa_demo/features/settings/bloc/settings_bloc.dart';

/// Abstract factory for creating BLoC instances
abstract class BlocFactory {
  LockerBloc get lockerBloc;

  SettingsBloc get settingsBloc;
}

/// Implementation that creates BLoC instances with injected dependencies
class BlocFactoryImpl implements BlocFactory {
  final LockerRepository _lockerRepository;
  final TimerService _timerService;

  const BlocFactoryImpl({
    required LockerRepository lockerRepository,
    required TimerService timerService,
  }) : _lockerRepository = lockerRepository,
       _timerService = timerService;

  @override
  LockerBloc get lockerBloc => LockerBloc(
    lockerRepository: _lockerRepository,
    timerService: _timerService,
  );

  @override
  SettingsBloc get settingsBloc => SettingsBloc(
    timerService: _timerService,
    lockerRepository: _lockerRepository,
  );
}
