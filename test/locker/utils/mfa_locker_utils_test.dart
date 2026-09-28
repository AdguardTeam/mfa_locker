import 'package:locker/erasable/erasable.dart';
import 'package:locker/locker/utils/mfa_locker_utils.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockErasable extends Mock implements Erasable {}

void main() {
  group('MFALockerUtils.eraseAfter', () {
    late MockErasable always;
    late MockErasable onError;

    setUp(() {
      always = MockErasable();
      onError = MockErasable();

      when(() => always.erase()).thenAnswer((_) {});
      when(() => onError.erase()).thenAnswer((_) {});
    });

    test('returns the callback result and erases only the always-erasables', () async {
      // Act
      final result = await MFALockerUtils.eraseAfter(
        erasables: [always],
        erasablesOnError: [onError],
        callback: () async => 42,
      );

      // Assert
      expect(result, 42);
      verify(() => always.erase()).called(1);
      verifyNever(() => onError.erase());
    });

    test('erases after the callback completes, not before', () async {
      // Act
      await MFALockerUtils.eraseAfter(
        erasables: [always],
        callback: () async {
          // Assert: the arguments are still alive while the callback runs.
          verifyNever(() => always.erase());
        },
      );

      // Assert
      verify(() => always.erase()).called(1);
    });

    test('erases both lists and rethrows the original error when the callback throws', () async {
      // Arrange
      final error = StateError('boom');

      // Act & Assert
      await expectLater(
        () => MFALockerUtils.eraseAfter(
          erasables: [always],
          erasablesOnError: [onError],
          callback: () async => throw error,
        ),
        throwsA(same(error)),
      );

      verify(() => always.erase()).called(1);
      verify(() => onError.erase()).called(1);
    });
  });
}
