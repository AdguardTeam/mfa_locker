import 'package:biometric_cipher/data/biometric_cipher_exception.dart';
import 'package:biometric_cipher/data/biometric_cipher_exception_code.dart';

/// A TPM-resident key entry returned by [BiometricCipher.listKeys].
///
/// Lists all keys stored by the platform crypto provider for the current
/// user. Entries include keys created by other applications and the OS
/// itself; they cannot be mapped back to tags used by this plugin.
class TpmKeyInfo {
  /// Constructs a TPM key info with a [name] and an [algorithm].
  const TpmKeyInfo({required this.name, required this.algorithm});

  /// The TPM key container name.
  final String name;

  /// The algorithm identifier of the key, e.g. `RSA` or `ECC`.
  final String algorithm;

  /// Creates a [TpmKeyInfo] from a method channel [map].
  ///
  /// Throws [BiometricCipherException] with
  /// [BiometricCipherExceptionCode.unknown] if the map is malformed.
  static TpmKeyInfo fromMap(Map<Object?, Object?> map) {
    final name = map['name'];
    final algorithm = map['algorithm'];

    if (name is! String || algorithm is! String) {
      throw const BiometricCipherException(
        code: BiometricCipherExceptionCode.unknown,
        message: 'Invalid TPM key entry',
      );
    }

    return TpmKeyInfo(name: name, algorithm: algorithm);
  }

  @override
  bool operator ==(Object other) => other is TpmKeyInfo && other.name == name && other.algorithm == algorithm;

  @override
  int get hashCode => Object.hash(name, algorithm);

  @override
  String toString() => 'TpmKeyInfo(name: $name, algorithm: $algorithm)';
}
