import 'dart:io';
import 'dart:typed_data';

import 'package:locker/erasable/erasable_byte_array.dart';
import 'package:locker/locker/mfa_locker.dart';
import 'package:locker/security/models/cipher_func.dart';
import 'package:locker/storage/encrypted_storage.dart';
import 'package:locker/storage/encrypted_storage_impl.dart';
import 'package:locker/storage/models/data/key_wrap.dart';
import 'package:locker/storage/models/data/origin.dart';
import 'package:locker/storage/models/domain/entry_id.dart';
import 'package:locker/storage/models/domain/entry_update_input.dart';
import 'package:locker/storage/models/domain/entry_value.dart';
import 'package:locker/storage/models/exceptions/storage_exception.dart';
import 'package:locker/utils/cryptography_utils.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../mocks/mock_bio_cipher_func.dart';
import '../storage/encrypted_storage_test_helpers.dart';

part 'mfa_locker_transaction_test_helpers.dart';

typedef _Helpers = EncryptedStorageTestHelpers;

void main() {
  late Directory tempDir;
  late File storageFile;
  late EncryptedStorageImpl storage;
  late ErasableByteArray masterKey;

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('locker_txn_test_');
    storageFile = File(p.join(tempDir.path, 'storage.json'));
    storage = EncryptedStorageImpl(file: storageFile);

    masterKey = await CryptographyUtils.generateAESKey();
    final entry = await _Helpers.createEncryptedEntry(
      masterKey: masterKey,
      id: 'a',
      valueBytes: [2, 3],
    );
    final data = await _Helpers.createStorageData(
      masterKey: masterKey,
      wraps: [KeyWrap(origin: Origin.bio, encryptedKey: masterKey.bytes)],
      entries: [entry],
    );
    await _Helpers.writeStorageData(storageFile, data);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  MockBioCipherFunc createCountingCipher(void Function() onDecrypt) {
    final cipher = MockBioCipherFunc();

    when(() => cipher.origin).thenReturn(Origin.bio);
    when(() => cipher.isErased).thenReturn(false);
    when(() => cipher.erase()).thenAnswer((_) {});
    when(() => cipher.decrypt(any())).thenAnswer((invocation) {
      onDecrypt();

      return Future.value(
        ErasableByteArray(Uint8List.fromList(masterKey.bytes)),
      );
    });

    return cipher;
  }

  test('one transaction performs multiple operations with a single unwrap', () async {
    // Arrange
    var decryptCalls = 0;
    final cipher = createCountingCipher(() => decryptCalls++);
    EntryValue? before;
    EntryValue? after;

    final locker = MFALocker(file: storageFile, storage: storage);

    // Act
    await locker.withTransaction(cipher, (txn) async {
      before = await txn.readValue(EntryId('a'));
      await txn.update(
        EntryUpdateInput(id: EntryId('a'), value: _Helpers.createEntryValue([42])),
      );
      after = await txn.readValue(EntryId('a'));
    });

    // Assert
    expect(before?.bytes, orderedEquals([2, 3]));
    expect(after?.bytes, orderedEquals([42]));
    expect(decryptCalls, 1, reason: 'read + update must reuse a single unwrap (one biometric prompt)');
  });

  test('changes are buffered and only persisted after the body returns', () async {
    // Arrange
    final cipher = createCountingCipher(() {});
    final locker = MFALocker(file: storageFile, storage: storage);

    // Act & Assert
    await locker.withTransaction(cipher, (txn) async {
      await txn.update(
        EntryUpdateInput(id: EntryId('a'), value: _Helpers.createEntryValue([42])),
      );

      // The buffered update is visible inside the body...
      expect((await txn.readValue(EntryId('a'))).bytes, orderedEquals([42]));

      // ...but the file on disk is still the original one.
      final onDisk = await _TransactionHelpers.readValueFromFile(storage, cipher, EntryId('a'));
      expect(onDisk.bytes, orderedEquals([2, 3]));
    });

    // After the body returns the transaction is committed.
    final committed = await _TransactionHelpers.readValueFromFile(storage, cipher, EntryId('a'));
    expect(committed.bytes, orderedEquals([42]));
  });

  test('a throwing body discards all buffered changes', () async {
    // Arrange
    final cipher = createCountingCipher(() {});
    final locker = MFALocker(file: storageFile, storage: storage);

    // Act & Assert
    await expectLater(
      locker.withTransaction(cipher, (txn) async {
        await txn.update(
          EntryUpdateInput(id: EntryId('a'), value: _Helpers.createEntryValue([42])),
        );

        throw StorageException.other('boom');
      }),
      throwsA(isA<StorageException>()),
    );

    // Nothing was persisted.
    final onDisk = await _TransactionHelpers.readValueFromFile(storage, cipher, EntryId('a'));
    expect(onDisk.bytes, orderedEquals([2, 3]));
  });

  test('baseline: two standalone operations unwrap twice', () async {
    // Arrange
    var decryptCalls = 0;
    final cipher = createCountingCipher(() => decryptCalls++);

    // Act: each operation performs its own unwrap, as a public one-shot call does.
    await _TransactionHelpers.updateValueInFile(storage, cipher, EntryId('a'), [42]);
    await _TransactionHelpers.readValueFromFile(storage, cipher, EntryId('a'));

    // Assert
    expect(decryptCalls, 2, reason: 'without a transaction every operation unwraps again');
  });

  test('the lane is released when the body returns', () async {
    // Arrange
    final cipher = createCountingCipher(() {});
    final locker = MFALocker(file: storageFile, storage: storage);

    // Act: a second transaction body starts only after the first one finished.
    await locker.withTransaction(cipher, (txn) async {
      await txn.update(
        EntryUpdateInput(id: EntryId('a'), value: _Helpers.createEntryValue([42])),
      );
    });

    final value = await locker.withTransaction(cipher, (txn) => txn.readValue(EntryId('a')));

    // Assert
    expect(value.bytes, orderedEquals([42]));
  });
}
