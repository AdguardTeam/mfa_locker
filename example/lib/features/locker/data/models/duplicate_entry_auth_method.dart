/// How the user authenticates a duplicated entry.
enum DuplicateEntryAuthMethod {
  /// Hardware-backed biometric authentication.
  biometric,

  /// Password authentication, available on every platform.
  password,
}
