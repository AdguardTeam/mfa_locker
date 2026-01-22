import 'dart:typed_data';

import 'package:locker/erasable/erasable.dart';
import 'package:locker/erasable/erasable_byte_array.dart';
import 'package:locker/storage/models/data/origin.dart';

/// Abstract base class for cipher functions that handle encryption and decryption.
///
/// A cipher function encapsulates a cryptographic key and provides methods for
/// encrypting and decrypting data. Each cipher function has an associated origin
/// indicating how the key was derived (e.g., from password or biometric authentication).
abstract class CipherFunc implements Erasable {
  /// The origin indicating how this cipher function's key was derived.
  final Origin origin;

  /// Creates a new cipher function with the given [origin].
  CipherFunc({
    required this.origin,
  });

  /// Decrypts the given [data] and returns the result in an [ErasableByteArray].
  Future<ErasableByteArray> decrypt(Uint8List data);

  /// Encrypts the given [data] and returns the encrypted bytes.
  Future<Uint8List> encrypt(ErasableByteArray data);
}
