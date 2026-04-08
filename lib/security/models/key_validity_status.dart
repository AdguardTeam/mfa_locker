/// Result of a biometric key validity check.
///
/// Used to distinguish between a confirmed-invalid key (enrollment changed)
/// and an indeterminate result (check itself failed).
enum KeyValidityStatus {
  valid,
  invalid,
  unknown,
}
