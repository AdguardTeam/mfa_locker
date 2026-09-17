import 'dart:async';

import 'package:locker/locker/utils/operation_lane.dart';
import 'package:test/test.dart';

void main() {
  group('OperationLane', () {
    late OperationLane lane;

    setUp(() {
      lane = OperationLane();
    });

    test('acquire completes immediately when the lane is free', () async {
      // Act
      await lane.acquire();

      // Assert
      expect(lane.isBusy, isTrue);
      expect(lane.pendingCount, 0);
    });

    test('waiters are released in FIFO order', () async {
      // Arrange
      final order = <int>[];

      await lane.acquire();

      // Act
      final first = lane.acquire().then((_) => order.add(1));
      final second = lane.acquire().then((_) => order.add(2));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(order, isEmpty);
      expect(lane.pendingCount, 2);

      lane.release();
      await first;
      expect(order, [1]);

      lane.release();
      await second;
      expect(order, [1, 2]);

      // Assert
      lane.release();
      expect(lane.isBusy, isFalse);
    });

    test('release without waiters frees the lane', () async {
      // Arrange
      await lane.acquire();

      // Act
      lane.release();

      // Assert
      expect(lane.isBusy, isFalse);
      expect(lane.pendingCount, 0);

      // The lane is reusable.
      await lane.acquire();
      expect(lane.isBusy, isTrue);
    });

    test('release is a no-op when the lane is not held', () async {
      // Act
      lane.release();

      // Assert
      expect(lane.isBusy, isFalse);
    });

    test('failPending fails all waiters without releasing the lane', () async {
      // Arrange
      await lane.acquire();
      final first = lane.acquire();
      final second = lane.acquire();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Act
      lane.failPending(StateError('locked'));

      // Assert
      await expectLater(first, throwsStateError);
      await expectLater(second, throwsStateError);
      expect(lane.pendingCount, 0);
      expect(lane.isBusy, isTrue, reason: 'the current holder still owns the lane');

      // The holder releases afterwards: the lane is free, nobody is resurrected.
      lane.release();
      expect(lane.isBusy, isFalse);
    });

    test('invalidate bumps the generation and fails pending waiters', () async {
      // Arrange
      final generation = lane.generation;
      await lane.acquire();
      final first = lane.acquire();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Act
      lane.invalidate(StateError('locked'));

      // Assert
      expect(lane.generation, greaterThan(generation));
      expect(lane.isCurrent(generation), isFalse);
      expect(lane.isCurrent(lane.generation), isTrue);
      await expectLater(first, throwsStateError);
      expect(lane.pendingCount, 0);
    });

    test('isCurrent reflects the generation captured before invalidate', () async {
      // Arrange
      final generation = lane.generation;

      // Act
      lane.invalidate(StateError('locked'));

      // Assert
      expect(lane.isCurrent(generation), isFalse);
      expect(lane.isCurrent(lane.generation), isTrue);
    });
  });
}
