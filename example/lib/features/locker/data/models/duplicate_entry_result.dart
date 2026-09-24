/// Result of the "duplicate entry" dialog.
class DuplicateEntryResult {
  final String newName;

  /// Whether to run the duplication inside a single biometric transaction.
  final bool useTransaction;

  const DuplicateEntryResult({
    required this.newName,
    required this.useTransaction,
  });
}
