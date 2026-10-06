import 'package:locker/locker/models/exceptions/locker_exception.dart';
import 'package:test/test.dart';

void main() {
  group('LockerException', () {
    test('factories expose their type and a non-empty message', () {
      expect(LockerException.locked().type, LockerExceptionType.locked);
      expect(LockerException.locked().message, isNotEmpty);

      expect(LockerException.notUnlocked().type, LockerExceptionType.notUnlocked);
      expect(LockerException.notUnlocked().message, isNotEmpty);

      expect(LockerException.insideTransaction().type, LockerExceptionType.insideTransaction);
      expect(LockerException.insideTransaction().message, isNotEmpty);

      expect(LockerException.transactionClosed().type, LockerExceptionType.transactionClosed);
      expect(LockerException.transactionClosed().message, isNotEmpty);
    });

    test('invalidArgument keeps the caller-provided message', () {
      // Act
      final error = LockerException.invalidArgument('Lock timeout must be greater than 0');

      // Assert
      expect(error.type, LockerExceptionType.invalidArgument);
      expect(error.message, 'Lock timeout must be greater than 0');
    });

    test('toString includes the type and the message', () {
      // Arrange
      final error = LockerException.invalidArgument('bad argument');

      // Act & Assert
      expect(error.toString(), 'LockerException(type: LockerExceptionType.invalidArgument, message: bad argument)');
    });
  });
}
