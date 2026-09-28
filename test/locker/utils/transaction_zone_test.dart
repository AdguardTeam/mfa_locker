import 'dart:async';

import 'package:locker/locker/utils/transaction_zone.dart';
import 'package:test/test.dart';

void main() {
  group('TransactionZone', () {
    test('current is null outside a zone', () {
      expect(TransactionZone.current, isNull);
    });

    test('marks the body with the owner, including its async continuations', () async {
      // Arrange
      final owner = Object();
      Object? beforeAwait;
      Object? afterAwait;

      // Act
      await TransactionZone.run(owner, () async {
        beforeAwait = TransactionZone.current;
        await Future<void>.delayed(Duration.zero);
        afterAwait = TransactionZone.current;
      });

      // Assert
      expect(beforeAwait, same(owner));
      expect(afterAwait, same(owner), reason: 'the marker must survive awaits');
      expect(TransactionZone.current, isNull, reason: 'the zone must not leak outside the body');
    });

    test('a nested zone restores the outer owner when it finishes', () async {
      // Arrange
      final outer = Object();
      final inner = Object();
      Object? insideInner;
      Object? afterInner;

      // Act
      await TransactionZone.run(outer, () async {
        await TransactionZone.run(inner, () async {
          insideInner = TransactionZone.current;
        });
        afterInner = TransactionZone.current;
      });

      // Assert
      expect(insideInner, same(inner));
      expect(afterInner, same(outer));
    });

    test('returns the body result', () async {
      expect(await TransactionZone.run(Object(), () async => 7), 7);
    });
  });
}
