import 'package:locker/locker/models/biometric_state.dart';
import 'package:test/test.dart';

void main() {
  group('BiometricState', () {
    group('keyInvalidated', () {
      test('isKeyInvalidated is true', () {
        expect(BiometricState.keyInvalidated.isKeyInvalidated, isTrue);
      });

      test('isEnabled is false', () {
        expect(BiometricState.keyInvalidated.isEnabled, isFalse);
      });

      test('isAvailable is false', () {
        expect(BiometricState.keyInvalidated.isAvailable, isFalse);
      });
    });

    group('other values', () {
      test('enabled.isKeyInvalidated is false', () {
        expect(BiometricState.enabled.isKeyInvalidated, isFalse);
      });

      test('availableButDisabled.isKeyInvalidated is false', () {
        expect(BiometricState.availableButDisabled.isKeyInvalidated, isFalse);
      });
    });
  });
}
