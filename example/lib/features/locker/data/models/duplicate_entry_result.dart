/// Result of the "duplicate entry" dialog.
class DuplicateEntryResult {
  /// The name for the new (duplicated) entry.
  final String newName;

  /// Whether to run the duplication inside a single biometric transaction.
  final bool useTransaction;

  const DuplicateEntryResult({
    required this.newName,
    required this.useTransaction,
  });
}
