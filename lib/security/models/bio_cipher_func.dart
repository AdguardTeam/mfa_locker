import 'dart:async';
import 'dart:typed_data';

import 'package:adguard_logger/adguard_logger.dart';
import 'package:locker/erasable/erasable_byte_array.dart';
import 'package:locker/security/models/cipher_func.dart';
import 'package:locker/security/secure_mnemonic_provider.dart';
import 'package:locker/storage/models/data/origin.dart';

class BioCipherFunc extends CipherFunc {
  final String keyTag;
  final SecureMnemonicProvider _secureProvider;

  BioCipherFunc({
    required this.keyTag,
  })  : assert(keyTag != '', 'keyTag cannot be empty'),
        _secureProvider = SecureMnemonicProviderImpl.instance,
        super(origin: Origin.bio);

  @override
  Future<Uint8List> encrypt(ErasableByteArray data) async {
    if (data.isErased || data.bytes.isEmpty) {
      throw ArgumentError.value(
        data.bytes,
        'data',
        'Data must not be empty or erased',
      );
    }

    try {
      return await _secureProvider.encrypt(tag: keyTag, data: data.bytes);
    } catch (error, stackTrace) {
      logger.logError(
        'BioCipherFunc: Failed to encrypt data with biometrics',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  @override
  Future<ErasableByteArray> decrypt(Uint8List data) async {
    if (data.isEmpty) {
      throw ArgumentError.value(
        data,
        'data',
        'Encrypted data must not be empty',
      );
    }

    try {
      final decrypted = await _secureProvider.decrypt(tag: keyTag, data: data);

      return ErasableByteArray(decrypted);
    } catch (error, stackTrace) {
      logger.logError(
        'BioCipherFunc: Failed to decrypt data with biometrics',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  @override
  bool get isErased => false;

  @override
  void erase() {}
}
