/// Granular locker states surfaced by the repository.
///
/// This adds richer transitions than the underlying `locker.LockerState`,
/// covering initialization and recreation flows so that consumers can track
/// the repository lifecycle precisely.
enum RepositoryLockerState {
  /// Default state before the repository has created or inspected storage.
  unknown,

  /// Storage file is absent; user must initialize the vault.
  uninitialized,

  /// Storage exists but is locked and requires authentication.
  locked,

  /// Storage is unlocked and ready for CRUD operations.
  unlocked,
}
