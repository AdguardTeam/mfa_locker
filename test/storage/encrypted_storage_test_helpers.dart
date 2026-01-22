import 'dart:convert';
import 'dart:io';

import 'dart:typed_data';

import 'package:locker/erasable/erasable_byte_array.dart';
import 'package:locker/security/models/cipher_func.dart';
import 'package:locker/storage/models/data/key_wrap.dart';
import 'package:locker/storage/models/data/origin.dart';
import 'package:locker/storage/models/data/storage_data.dart';
import 'package:locker/storage/models/data/storage_entry.dart';
import 'package:locker/storage/models/data/wrapped_key.dart';
import 'package:locker/storage/models/domain/entry_id.dart';
import 'package:locker/storage/models/domain/entry_meta.dart';
import 'package:locker/storage/models/domain/entry_value.dart';
import 'package:locker/storage/models/exceptions/decrypt_failed_exception.dart';
import 'package:locker/utils/cryptography_utils.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import '../mocks/mock_bio_cipher_func.dart';
import '../mocks/mock_password_cipher_func.dart';

abstract class EncryptedStorageTestHelpers {
  static const lockTimeout = 123;

  static Future<StorageData> createStorageData({
    ErasableByteArray? masterKey,
    List<KeyWrap> wraps = const [],
    List<StorageEntry> entries = const [],
    List<int> salt = const [0],
    int lockTimeout = lockTimeout,
  }) async {
    masterKey ??= await CryptographyUtils.generateAESKey();
    final hmacKey = await CryptographyUtils.generateAESKey();

    final encryptedHmacKey = await CryptographyUtils.encrypt(key: masterKey, data: hmacKey);

    final storageData = StorageData(
      entries: entries,
      masterKey: WrappedKey(wraps: wraps),
      salt: Uint8List.fromList(salt),
      hmacKey: encryptedHmacKey,
      lockTimeout: lockTimeout,
    );

    final payload = jsonEncode(storageData.toJson());
    final hmacSignature = await CryptographyUtils.authenticateHmac(
      hmacKey: hmacKey,
      data: Uint8List.fromList(payload.codeUnits),
    );

    return storageData.copyWith(hmacSignature: hmacSignature);
  }

  static Future<StorageEntry> createEncryptedEntry({
    required ErasableByteArray masterKey,
    required String id,
    List<int> metaBytes = const [0],
    List<int> valueBytes = const [1],
  }) async {
    final meta = createEntryMeta(metaBytes);
    final value = createEntryValue(valueBytes);

    final encryptedMeta = await CryptographyUtils.encrypt(key: masterKey, data: meta);
    final encryptedValue = await CryptographyUtils.encrypt(key: masterKey, data: value);

    return StorageEntry(
      id: EntryId(id),
      encryptedMeta: encryptedMeta,
      encryptedValue: encryptedValue,
    );
  }

  static ErasableByteArray createErasable([List<int> bytes = const [0]]) =>
      ErasableByteArray(Uint8List.fromList(bytes));

  static EntryMeta createEntryMeta([List<int> bytes = const [0]]) =>
      EntryMeta.fromErasable(erasable: createErasable(bytes));

  static EntryValue createEntryValue([List<int> bytes = const [1]]) =>
      EntryValue.fromErasable(erasable: createErasable(bytes));

  static MockPasswordCipherFunc createMockPasswordCipherFunc({
    Uint8List? masterKeyBytes,
    Uint8List? passwordBytes,
    Uint8List? saltBytes,
  }) {
    final cipherFunc = MockPasswordCipherFunc();

    when(() => cipherFunc.origin).thenReturn(Origin.pwd);
    when(() => cipherFunc.password).thenReturn(createErasable(passwordBytes ?? [0]));
    when(() => cipherFunc.salt).thenReturn(saltBytes ?? Uint8List.fromList([0]));

    _mockCipherFuncFields(cipherFunc, masterKeyBytes);

    return cipherFunc;
  }

  static MockBioCipherFunc createMockBioCipherFunc({
    Uint8List? masterKeyBytes,
    String? keyTag,
  }) {
    final cipherFunc = MockBioCipherFunc();

    when(() => cipherFunc.origin).thenReturn(Origin.bio);
    when(() => cipherFunc.keyTag).thenReturn(keyTag ?? 'key-tag');

    _mockCipherFuncFields(cipherFunc, masterKeyBytes);

    return cipherFunc;
  }

  static void _mockCipherFuncFields(CipherFunc cipher, Uint8List? masterKeyBytes) {
    when(() => cipher.isErased).thenReturn(false);
    when(() => cipher.erase()).thenAnswer((_) {});

    // Mocked CipherFunc.encrypt returns the data unchanged.
    // The real encryption is tested separately in the utils/cryptography_utils_test.dart.
    when(() => cipher.encrypt(any())).thenAnswer((invocation) async {
      final erasable = invocation.positionalArguments.first as ErasableByteArray;

      return Uint8List.fromList(erasable.bytes);
    });

    if (masterKeyBytes != null) {
      when(() => cipher.decrypt(any())).thenAnswer((_) async => createErasable(masterKeyBytes));
    }
  }

  static MockPasswordCipherFunc createDecryptFailingPasswordCipherFunc() {
    final cipher = createMockPasswordCipherFunc();
    when(() => cipher.decrypt(any())).thenThrow(const DecryptFailedException());

    return cipher;
  }

  static Future<StorageData> readStorageData(File file) async {
    final fileContent = await file.readAsString();
    final decoded = jsonDecode(fileContent) as Map<String, Object?>;

    return StorageData.fromJson(decoded);
  }

  static Future<void> writeStorageData(File file, StorageData data) async {
    final encoded = jsonEncode(data.toJson());
    await file.writeAsString(encoded);
  }

  static Future<T> expectFileUnchanged<T>(File file, Future<T> Function() action) async {
    final before = await file.readAsBytes();
    final result = await action();
    final after = await file.readAsBytes();

    expect(after, orderedEquals(before));

    return result;
  }
}
