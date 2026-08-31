import 'package:locker/erasable/erasable.dart';
import 'package:locker/erasable/erasable_byte_array.dart';

/// The unwrapped master key of an open vault transaction.
///
/// Returned by [EncryptedStorage.unlockKeys] and held by a single open
/// [LockerTransaction]. Erasing zeroes the underlying key material so it can
/// never be reused after the owning transaction is closed.
class UnlockedKeys implements Erasable {
  /// The unwrapped master key used to encrypt and decrypt entry payloads.
  final ErasableByteArray masterKey;

  UnlockedKeys({required this.masterKey});

  @override
  bool get isErased => masterKey.isErased;

  @override
  void erase() => masterKey.erase();
}
