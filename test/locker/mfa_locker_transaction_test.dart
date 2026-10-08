import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:locker/erasable/erasable_byte_array.dart';
import 'package:locker/locker/mfa_locker.dart';
import 'package:locker/locker/mfa_locker_transaction.dart';
import 'package:locker/locker/models/exceptions/locker_exception.dart';
import 'package:locker/security/models/cipher_func.dart';
import 'package:locker/storage/encrypted_storage.dart';
import 'package:locker/storage/encrypted_storage_impl.dart';
import 'package:locker/storage/models/data/key_wrap.dart';
import 'package:locker/storage/models/data/origin.dart';
import 'package:locker/storage/models/domain/entry_add_input.dart';
import 'package:locker/storage/models/domain/entry_id.dart';
import 'package:locker/storage/models/domain/entry_update_input.dart';
import 'package:locker/storage/models/domain/entry_value.dart';
import 'package:locker/storage/models/exceptions/storage_exception.dart';
import 'package:locker/utils/cryptography_utils.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../mocks/mock_bio_cipher_func.dart';
import '../mocks/mock_encrypted_storage.dart';
import '../mocks/mock_storage_transaction.dart';
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

  test('a conflicting external write fails the commit and keeps the locker usable', () async {
    // Arrange
    final cipher = createCountingCipher(() {});
    final locker = MFALocker(file: storageFile, storage: storage);

    // Act: while the body runs, a concurrent writer changes the file.
    final future = locker.withTransaction(cipher, (txn) async {
      await txn.update(
        EntryUpdateInput(id: EntryId('a'), value: _Helpers.createEntryValue([42])),
      );
      await _TransactionHelpers.updateValueInFile(storage, cipher, EntryId('a'), [7]);
    });

    // Assert: the commit detects the race, the buffered update is not persisted.
    await expectLater(
      future,
      throwsA(isA<StorageException>().having((e) => e.type, 'type', StorageExceptionType.conflict)),
    );

    final onDisk = await _TransactionHelpers.readValueFromFile(storage, cipher, EntryId('a'));
    expect(onDisk.bytes, orderedEquals([7]), reason: 'the concurrent write wins, the buffered one is discarded');

    // The lane was released: the locker still serves requests.
    final value = await locker.withTransaction(cipher, (txn) => txn.readValue(EntryId('a')));
    expect(value.bytes, orderedEquals([7]));
  });

  group('MfaLockerTransaction lifecycle', () {
    final isClosedTransactionError = isA<LockerException>().having(
      (e) => e.type,
      'type',
      LockerExceptionType.transactionClosed,
    );

    final isConflictError = isA<StorageException>().having(
      (e) => e.type,
      'type',
      StorageExceptionType.conflict,
    );

    Future<MfaLockerTransaction> openTransaction(CipherFunc cipher) => MfaLockerTransaction.open(
          storage: storage,
          cipherFunc: cipher,
          initialize: (_) async {},
        );

    test('abort is idempotent and closes the transaction', () async {
      // Arrange
      final txn = await openTransaction(createCountingCipher(() {}));

      // Act
      txn.abort();

      // Assert
      expect(txn.isClosed, isTrue);
      expect(txn.isCommitting, isFalse);
      expect(txn.abort, returnsNormally);
    });

    test('operations after abort throw a closed-transaction error', () async {
      // Arrange
      final txn = await openTransaction(createCountingCipher(() {}));
      txn.abort();

      // Act & Assert
      await expectLater(txn.readValue(EntryId('a')), throwsA(isClosedTransactionError));
      await expectLater(txn.updateLockTimeout(const Duration(seconds: 1)), throwsA(isClosedTransactionError));
    });

    test('commit after abort throws a closed-transaction error', () async {
      // Arrange
      final txn = await openTransaction(createCountingCipher(() {}));
      txn.abort();

      // Act & Assert
      await expectLater(txn.commit(), throwsA(isClosedTransactionError));
    });

    test('a second commit throws a closed-transaction error', () async {
      // Arrange
      final txn = await openTransaction(createCountingCipher(() {}));
      await txn.commit();

      // Act & Assert
      await expectLater(txn.commit(), throwsA(isClosedTransactionError));
      expect(txn.isClosed, isTrue);
      expect(txn.isCommitting, isFalse);
    });

    group('commit failure', () {
      late MockEncryptedStorage mockStorage;
      late MockStorageTransaction storageTransaction;
      late MockBioCipherFunc cipher;

      setUp(() {
        mockStorage = MockEncryptedStorage();
        storageTransaction = MockStorageTransaction();
        cipher = createCountingCipher(() {});

        when(() => mockStorage.openTransaction(cipherFunc: cipher)).thenAnswer((_) async => storageTransaction);
        when(() => storageTransaction.erase()).thenAnswer((_) {});
      });

      Future<MfaLockerTransaction> open() => MfaLockerTransaction.open(
            storage: mockStorage,
            cipherFunc: cipher,
            initialize: (_) async {},
          );

      test('a failed commit erases the buffer, closes the transaction and rethrows', () async {
        // Arrange
        when(() => mockStorage.closeTransaction(storageTransaction)).thenThrow(StorageException.conflict());
        final txn = await open();

        // Act & Assert
        await expectLater(txn.commit(), throwsA(isConflictError));

        expect(txn.isClosed, isTrue, reason: 'a failed commit must close the transaction');
        expect(txn.isCommitting, isFalse);
        verify(() => storageTransaction.erase()).called(1);

        // The failed transaction cannot be reused.
        await expectLater(txn.commit(), throwsA(isClosedTransactionError));
      });

      test('a failed commit erases the pending metadata', () async {
        // Arrange
        final meta = _Helpers.createEntryMeta([5]);
        final input = EntryAddInput(meta: meta, value: _Helpers.createEntryValue([1]));
        when(() => mockStorage.closeTransaction(storageTransaction)).thenThrow(StorageException.conflict());
        when(() => storageTransaction.addEntry(input)).thenAnswer((_) async => EntryId('new'));

        final txn = await open();
        await txn.write(input);
        expect(meta.isErased, isFalse);

        // Act & Assert
        await expectLater(txn.commit(), throwsA(isConflictError));

        expect(meta.isErased, isTrue, reason: 'the uncommitted metadata must not outlive the failed commit');
      });

      test('abort during an in-flight commit is a no-op and the commit erases the buffer once', () async {
        // Arrange
        final commitGate = Completer<void>();
        when(() => mockStorage.closeTransaction(storageTransaction)).thenAnswer((_) => commitGate.future);
        final txn = await open();

        // Act: the commit is in flight when the transaction is aborted.
        final commitFuture = txn.commit();
        expect(txn.isCommitting, isTrue);
        txn.abort();

        // Assert: the buffer survives while the commit is writing it.
        expect(txn.isClosed, isFalse);
        verifyNever(() => storageTransaction.erase());

        commitGate.complete();
        await commitFuture;

        expect(txn.isClosed, isTrue);
        expect(txn.isCommitting, isFalse);
        verify(() => storageTransaction.erase()).called(1);
      });
    });
  });
}
