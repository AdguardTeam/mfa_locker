import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locker/locker.dart';
import 'package:mfa_demo/core/services/timer_service.dart';
import 'package:mfa_demo/features/locker/bloc/locker_bloc.dart';
import 'package:mfa_demo/features/locker/data/models/authentication_result.dart';
import 'package:mfa_demo/features/locker/data/models/repository_locker_state.dart';
import 'package:mfa_demo/features/locker/data/repositories/locker_repository.dart';
import 'package:mfa_demo/features/locker/views/widgets/authentication_bottom_sheet.dart';
import 'package:mfa_demo/features/locker/views/widgets/locker_bloc_biometric_stream.dart';
import 'package:rxdart/rxdart.dart';

void main() {
  group('showAuthenticationBottomSheet', () {
    testWidgets('bypasses the password sheet when biometrics succeed', (tester) async {
      final harness = _AuthenticationHarness();
      addTearDown(harness.dispose);

      await harness.pump(tester);
      await tester.tap(find.text(_AuthenticationHarness.triggerLabel));
      await tester.pumpAndSettle();

      expect(find.byType(AuthenticationBottomSheet), findsNothing);
      expect(harness.result?.isBiometricSuccess, isTrue);
    });

    testWidgets('opens the password fallback when the biometric operation fails to decrypt', (tester) async {
      final harness = _AuthenticationHarness(biometricError: const DecryptFailedException(message: 'damaged key'));
      addTearDown(harness.dispose);

      await harness.pump(tester);
      await tester.tap(find.text(_AuthenticationHarness.triggerLabel));
      await tester.pumpAndSettle();

      expect(find.byType(AuthenticationBottomSheet), findsOneWidget);
    });

    for (final type in <BiometricExceptionType>[
      BiometricExceptionType.cancel,
      BiometricExceptionType.failure,
      BiometricExceptionType.keyInvalidated,
      BiometricExceptionType.notAvailable,
    ]) {
      testWidgets('opens the password fallback on a $type biometric outcome', (tester) async {
        final harness = _AuthenticationHarness(biometricError: BiometricException(type));
        addTearDown(harness.dispose);

        await harness.pump(tester);
        await tester.tap(find.text(_AuthenticationHarness.triggerLabel));
        await tester.pumpAndSettle();

        expect(find.byType(AuthenticationBottomSheet), findsOneWidget);
        if (type == BiometricExceptionType.keyInvalidated) {
          expect(find.byIcon(Icons.fingerprint), findsNothing);
        }
      });
    }
  });

  group('LockerBloc pre-sheet biometric operations', () {
    test('every operation terminates with a biometric failure on a decrypt failure', () async {
      final events = <LockerEvent>[
        const LockerEvent.unlockWithBiometricRequested(),
        const LockerEvent.addEntryWithBiometricRequested(name: 'name', value: 'value'),
        LockerEvent.deleteEntryWithBiometricRequested(id: EntryId.generate()),
      ];

      for (final event in events) {
        final repository = _StubLockerRepository(biometricError: const DecryptFailedException(message: 'damaged key'));
        final bloc = LockerBloc(lockerRepository: repository, timerService: _StubTimerService());
        final actions = <LockerAction>[];
        final subscription = bloc.actions.listen(actions.add);

        bloc.add(event);
        await pumpEventQueue();

        await subscription.cancel();
        await bloc.close();
        await repository.dispose();

        expect(
          actions.whereType<BiometricAuthenticationFailedAction>(),
          isNotEmpty,
          reason: '${event.runtimeType} left the pre-sheet await without a terminal result',
        );
      }
    });
  });
}

/// Drives [showAuthenticationBottomSheet] with the BLoC's real biometric result stream.
class _AuthenticationHarness {
  _AuthenticationHarness({Object? biometricError}) {
    _repository = _StubLockerRepository(biometricError: biometricError);
    _bloc = LockerBloc(lockerRepository: _repository, timerService: _StubTimerService());
  }

  static const triggerLabel = 'Authenticate';

  late final LockerBloc _bloc;
  late final _StubLockerRepository _repository;
  AuthenticationResult? result;

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => _authenticate(context),
            child: const Text(triggerLabel),
          ),
        ),
      ),
    ),
  );

  Future<void> dispose() async {
    await _bloc.close();
    await _repository.dispose();
  }

  Future<void> _authenticate(BuildContext context) async {
    result = await showAuthenticationBottomSheet(
      context,
      title: 'Unlock Storage',
      showBiometricButton: true,
      onBiometricPressed: () => _bloc.add(const LockerEvent.unlockWithBiometricRequested()),
      biometricResultStream: _bloc.biometricResultStream,
    );
  }
}

/// Repository whose biometric operations produce [biometricError], or succeed when it is null.
class _StubLockerRepository implements LockerRepository {
  _StubLockerRepository({this.biometricError});

  final Object? biometricError;
  final BehaviorSubject<RepositoryLockerState> _stateController = BehaviorSubject.seeded(
    RepositoryLockerState.locked,
  );

  @override
  ValueStream<RepositoryLockerState> get lockerStateStream => _stateController;

  @override
  Future<BiometricState> determineBiometricState() async => BiometricState.availableButDisabled;

  @override
  Future<void> unlockWithBiometric() async {
    _failIfConfigured();
  }

  @override
  Future<void> addEntryWithBiometric({required String name, required String value}) async {
    _failIfConfigured();
  }

  @override
  Future<void> deleteEntryWithBiometric({required EntryId id}) async {
    _failIfConfigured();
  }

  @override
  Future<void> dispose() => _stateController.close();

  void _failIfConfigured() {
    final error = biometricError;
    if (error != null) {
      throw error;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubTimerService implements TimerService {
  @override
  Duration get timeout => const Duration(minutes: 5);

  @override
  set onLockCallback(void Function() onLock) {}

  @override
  bool get shouldLockOnResume => false;

  @override
  Future<void> startTimer() async {}

  @override
  Future<void> updateLockTimeout() async {}

  @override
  void stopTimer() {}

  @override
  void touch() {}

  @override
  void dispose() {}
}
