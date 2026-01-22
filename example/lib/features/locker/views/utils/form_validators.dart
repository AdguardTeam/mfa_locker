/// Form validation utilities for locker feature
class FormValidators {
  /// Validates that a field is not empty
  static String? required(String? value, {String? fieldName}) {
    if (value == null || value.isEmpty) {
      return 'Please enter ${fieldName ?? 'a value'}';
    }

    return null;
  }

  /// Validates password with minimum length requirement
  static String? password(String? value, {int minLength = 6}) {
    if (value == null || value.isEmpty) {
      return 'Please enter a password';
    }
    if (value.length < minLength) {
      return 'Password must be at least $minLength characters';
    }

    return null;
  }

  /// Validates that a confirmation field matches another value
  static String? confirmation(String? value, String? originalValue, {String? fieldName}) {
    if (value == null || value.isEmpty) {
      return 'Please confirm your ${fieldName ?? 'value'}';
    }
    if (value != originalValue) {
      return '${fieldName ?? 'Values'} do not match';
    }

    return null;
  }

  FormValidators._();
}
