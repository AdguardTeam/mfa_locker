import 'package:mfa_demo/features/locker/data/models/duplicate_entry_auth_method.dart';

/// Result of the "duplicate entry" dialog.
class DuplicateEntryResult {
  final String newName;

  /// Whether to run the duplication inside a single transaction.
  final bool useTransaction;

  /// How the user chose to authenticate.
  final DuplicateEntryAuthMethod authMethod;

  /// The password, set only when [authMethod] is
  /// [DuplicateEntryAuthMethod.password].
  final String? password;

  const DuplicateEntryResult({
    required this.newName,
    required this.useTransaction,
    required this.authMethod,
    this.password,
  });
}
