import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:biometric_cipher/data/biometric_status.dart';
import 'package:biometric_cipher/data/tpm_status.dart';
import 'package:locker/erasable/erasable.dart';
import 'package:locker/locker/locker.dart';
import 'package:locker/locker/mfa_locker.dart';
import 'package:locker/locker/models/biometric_state.dart';
import 'package:locker/security/models/exceptions/biometric_exception.dart';
import 'package:locker/storage/models/data/origin.dart';
import 'package:locker/storage/models/domain/entry_add_input.dart';
import 'package:locker/storage/models/domain/entry_id.dart';
import 'package:locker/storage/models/domain/entry_meta.dart';
import 'package:locker/storage/models/domain/entry_update_input.dart';
import 'package:locker/storage/models/exceptions/decrypt_failed_exception.dart';
import 'package:locker/storage/models/exceptions/storage_exception.dart';
import 'package:locker/storage/storage_change_set.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../mocks/mock_bio_cipher_func.dart';
import '../mocks/mock_biometric_cipher_provider.dart';
import '../mocks/mock_encrypted_storage.dart';
import '../mocks/mock_file.dart';
import '../mocks/mock_password_cipher_func.dart';
import '../mocks/mock_storage_change_set.dart';
import '../storage/encrypted_storage_test_helpers.dart';

part 'mfa_locker_test_helpers.dart';

void main() {
  setUpAll(() async {
    registerFallbackValue(EntryId('fallback'));
    registerFallbackValue(_StorageHelpers.createEntryMeta());
    registerFallbackValue(_StorageHelpers.createEntryValue([1]));
    registerFallbackValue(<EntryAddInput>[]);
    registerFallbackValue(
      EntryAddInput(
        meta: _StorageHelpers.createEntryMeta(),
        value: _StorageHelpers.createEntryValue([1]),
      ),
    );
    registerFallbackValue(EntryUpdateInput(id: EntryId('fallback')));
    registerFallbackValue(MockBioCipherFunc());
    registerFallbackValue(MockPasswordCipherFunc());
    registerFallbackValue(_StorageHelpers.createErasable());
    registerFallbackValue(
      StorageChangeSet(
        data: await _StorageHelpers.createStorageData(),
        masterKey: _StorageHelpers.createErasable(),
      ),
    );
  });

  group('MFALocker', () {
    late MockEncryptedStorage storage;
    late MockStorageChangeSet changeSet;
    late MFALocker locker;

    setUp(() async {
      storage = MockEncryptedStorage();
      changeSet = MockStorageChangeSet();

      locker = MFALocker(
        file: MockFile(),
        storage: storage,
      );

      when(() => storage.isInitialized).thenAnswer((_) async => true);
      when(() => storage.lockTimeout).thenAnswer((_) async => _Helpers.lockTimeout.inMilliseconds);
      when(() => storage.openChangeSet(cipherFunc: any(named: 'cipherFunc'))).thenAnswer((_) async => changeSet);
      when(() => storage.commitChangeSet(any())).thenAnswer((_) async {});
      when(() => changeSet.readAllMeta()).thenAnswer((_) async => <EntryId, EntryMeta>{});
      when(() => changeSet.erase()).thenAnswer((_) {});
    });

    tearDown(() async {
      locker.dispose();
    });

    group('getters', () {
      test('stateStream starts with "locked"', () async {
        // Arrange

        // Act

        // Assert
        expect(locker.stateStream.value, LockerState.locked);
      });

      test('isStorageInitialized returns data from storage', () async {
        // Arrange

        // Act
        final result = await locker.isStorageInitialized;

        // Assert
        expect(result, isTrue);
        verify(() => storage.isInitialized).called(1);
      });

      test('salt returns data from storage', () async {
        // Arrange
        final salt = Uint8List.fromList([9, 9]);
        when(() => storage.salt).thenAnswer((_) async => salt);

        // Act
        final result = await locker.salt;

        // Assert
        expect(result, same(salt));
        verify(() => storage.salt).called(1);
      });

      test('lockTimeout returns value from storage', () async {
        // Arrange

        // Act
        final first = await locker.lockTimeout;
        clearInteractions(storage);
        final second = await locker.lockTimeout;

        // Assert
        expect(first, equals(_Helpers.lockTimeout));
        expect(second, equals(_Helpers.lockTimeout));
        verify(() => storage.lockTimeout).called(1);
      });

      test('lockTimeout propagates StorageException from storage', () async {
        // Arrange
        when(() => storage.lockTimeout).thenThrow(StorageException.notInitialized());

        // Act & Assert
        await expectLater(
          locker.lockTimeout,
          throwsA(isA<StorageException>()),
        );
      });

      test('allMeta throws when locked', () async {
        // Arrange

        // Act

        // Assert
        expect(
          () => locker.allMeta,
          throwsA(isA<StateError>()),
        );
      });
    });

    group('init', () {
      test('loads meta, unlocks locker', () async {
        // Arrange
        final pwd = _Helpers.createMockPasswordCipherFunc();
        final meta = _StorageHelpers.createEntryMeta();
        final value = _StorageHelpers.createEntryValue();
        final entry = EntryAddInput(meta: meta, value: value);
        final readAllMeta = _Helpers.stubReadAllMeta(changeSet);

        when(() => storage.isInitialized).thenAnswer((_) async => false);
        when(
          () => storage.init(
            passwordCipherFunc: pwd,
            initialEntries: [entry],
            lockTimeout: _Helpers.lockTimeout.inMilliseconds,
          ),
        ).thenAnswer((_) async {
          // After initialization completes, storage becomes initialized
          when(() => storage.isInitialized).thenAnswer((_) async => true);
        });

        // Act
        await locker.init(
          passwordCipherFunc: pwd,
          initialEntries: [entry],
          lockTimeout: _Helpers.lockTimeout,
        );

        // Assert
        verify(
          () => storage.init(
            passwordCipherFunc: pwd,
            initialEntries: [entry],
            lockTimeout: _Helpers.lockTimeout.inMilliseconds,
          ),
        ).called(1);
        verify(() => changeSet.readAllMeta()).called(1);

        expect(locker.stateStream.value, LockerState.unlocked);
        expect(locker.allMeta, equals(readAllMeta));

        _Helpers.verifyErasedAll([pwd, meta, value]);
      });

      test('throws when storage already initialized', () async {
        // Arrange
        final pwd = _Helpers.createMockPasswordCipherFunc();
        final meta = _StorageHelpers.createEntryMeta();
        final value = _StorageHelpers.createEntryValue();
        final entry = EntryAddInput(meta: meta, value: value);

        // Act & Assert
        await expectLater(
          () => locker.init(
            passwordCipherFunc: pwd,
            initialEntries: [entry],
            lockTimeout: _Helpers.lockTimeout,
          ),
          throwsA(isA<StateError>()),
        );

        verifyNever(
          () => storage.init(
            passwordCipherFunc: any(named: 'passwordCipherFunc'),
            initialEntries: any(named: 'initialEntries'),
            lockTimeout: any(named: 'lockTimeout'),
          ),
        );

        _Helpers.verifyErasedAll([pwd, meta, value]);
      });

      test('rethrows on storage error', () async {
        // Arrange
        final pwd = _Helpers.createMockPasswordCipherFunc();
        final meta = _StorageHelpers.createEntryMeta();
        final value = _StorageHelpers.createEntryValue();
        final entry = EntryAddInput(meta: meta, value: value);

        when(() => storage.isInitialized).thenAnswer((_) async => false);
        when(
          () => storage.init(
            passwordCipherFunc: pwd,
            initialEntries: [entry],
            lockTimeout: _Helpers.lockTimeout.inMilliseconds,
          ),
        ).thenThrow(Exception('test'));

        // Act & Assert
        await expectLater(
          () => locker.init(
            passwordCipherFunc: pwd,
            initialEntries: [entry],
            lockTimeout: _Helpers.lockTimeout,
          ),
          throwsException,
        );

        expect(locker.stateStream.value, LockerState.locked);
        _Helpers.verifyErasedAll([pwd, meta, value]);
      });
    });

    group('loadAllMeta', () {
      test('loads meta', () async {
        // Arrange
        final cipher = _Helpers.createMockPasswordCipherFunc();
        final readAllMeta = _Helpers.stubReadAllMeta(changeSet);

        // Act
        await locker.loadAllMeta(cipher);

        // Assert
        verify(() => storage.openChangeSet(cipherFunc: cipher)).called(1);
        expect(locker.stateStream.value, LockerState.unlocked);
        expect(locker.allMeta, equals(readAllMeta));

        _Helpers.verifyErased(cipher);
      });
    });

    group('loadAllMetaIfLocked', () {
      test('unlocks, loads meta', () async {
        // Arrange
        final cipher = _Helpers.createMockPasswordCipherFunc();
        final readAllMeta = _Helpers.stubReadAllMeta(changeSet);

        // Act
        await locker.loadAllMetaIfLocked(cipher);

        // Assert
        verify(() => changeSet.readAllMeta()).called(1);

        expect(locker.stateStream.value, LockerState.unlocked);
        expect(locker.allMeta, equals(readAllMeta));
      });

      test('throws when storage not initialized', () async {
        // Arrange
        when(() => storage.isInitialized).thenAnswer((_) async => false);
        final cipher = _Helpers.createMockPasswordCipherFunc();

        // Act & Assert
        await expectLater(
          () => locker.loadAllMetaIfLocked(cipher),
          throwsA(isA<StateError>()),
        );

        verifyNever(() => storage.openChangeSet(cipherFunc: any(named: 'cipherFunc')));
      });

      test('does nothing if already unlocked', () async {
        // Arrange
        final cipher = _Helpers.createMockPasswordCipherFunc();
        _Helpers.stubReadAllMeta(changeSet);
        await locker.loadAllMetaIfLocked(cipher);

        clearInteractions(changeSet);

        // Act
        await locker.loadAllMetaIfLocked(cipher);

        // Assert
        verifyNever(() => changeSet.readAllMeta());
      });
    });

    group('lock', () {
      test('clears cache and locks the locker', () async {
        // Arrange
        const entryId = 'entryId';
        final cipher = _Helpers.createMockPasswordCipherFunc();
        _Helpers.stubReadAllMeta(changeSet, id: entryId);

        await locker.loadAllMeta(cipher);
        final metaRef = locker.allMeta[EntryId(entryId)]!;

        // Act
        locker.lock();

        // Assert
        expect(locker.stateStream.value, LockerState.locked);
        expect(() => locker.allMeta, throwsA(isA<StateError>()));
        _Helpers.verifyErased(metaRef);
      });

      test('lock does nothing when locked', () async {
        // Act
        locker.lock();

        // Assert
        expect(locker.stateStream.value, LockerState.locked);
      });
    });

    group('transaction', () {
      late MockBioCipherFunc cipher;
      late Map<EntryId, EntryMeta> metas;

      setUp(() {
        cipher = _Helpers.createMockBioCipherFunc();
        metas = {
          EntryId('a'): _StorageHelpers.createEntryMeta([1]),
        };

        when(() => changeSet.readAllMeta()).thenAnswer((_) async => metas);
      });

      test('beginTransaction unlocks once, loads meta and returns an open transaction', () async {
        // Arrange

        // Act
        final txn = await locker.beginTransaction(cipher);

        // Assert
        expect(txn.isClosed, isFalse);
        expect(locker.stateStream.value, LockerState.unlocked);
        verify(() => storage.openChangeSet(cipherFunc: cipher)).called(1);
        verify(() => changeSet.readAllMeta()).called(1);
        await txn.abort();
      });

      test('the second beginTransaction waits for the first one to finish', () async {
        // Arrange
        var openCalls = 0;
        when(() => storage.openChangeSet(cipherFunc: any(named: 'cipherFunc'))).thenAnswer((_) async {
          openCalls++;

          return changeSet;
        });

        final txn = await locker.beginTransaction(cipher);
        var secondCompleted = false;

        // Act: the second transaction queues up behind the first one.
        final secondFuture = locker.beginTransaction(cipher);
        unawaited(
          secondFuture.then<void>(
            (_) => secondCompleted = true,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 25));

        // Assert: it is still waiting and did not open a second change set.
        expect(secondCompleted, isFalse);
        expect(openCalls, 1);

        await txn.commit();

        final second = await secondFuture;
        expect(second.isClosed, isFalse);
        expect(openCalls, 2);

        await second.abort();
      });

      test('beginTransaction throws when storage is not initialized', () async {
        // Arrange
        when(() => storage.isInitialized).thenAnswer((_) async => false);

        // Act & Assert
        await expectLater(locker.beginTransaction(cipher), throwsStateError);
        verifyNever(() => storage.openChangeSet(cipherFunc: any(named: 'cipherFunc')));
      });

      test('operations run on the change set without a second unlock', () async {
        // Arrange
        when(() => changeSet.readValue(any())).thenAnswer((_) async => _StorageHelpers.createEntryValue([9]));
        when(() => changeSet.updateEntry(any())).thenAnswer((_) async {});

        final txn = await locker.beginTransaction(cipher);

        // Act
        await txn.readValue(EntryId('a'));
        await txn.update(EntryUpdateInput(id: EntryId('a'), value: _StorageHelpers.createEntryValue([2])));
        await txn.abort();

        // Assert
        verify(() => storage.openChangeSet(cipherFunc: cipher)).called(1);
        verify(() => changeSet.readValue(EntryId('a'))).called(1);
        verify(() => changeSet.updateEntry(any())).called(1);
      });

      test('write exposes meta inside the transaction and erases it on abort', () async {
        // Arrange
        final expectedId = EntryId('new');
        final metaToAdd = _StorageHelpers.createEntryMeta([5]);
        when(() => changeSet.addEntry(any())).thenAnswer((_) async => expectedId);

        final txn = await locker.beginTransaction(cipher);

        // Act
        final id = await txn.write(
          EntryAddInput(meta: metaToAdd, value: _StorageHelpers.createEntryValue([1])),
        );

        // Assert: visible inside the transaction, invisible outside of it.
        expect(id, expectedId);
        expect(txn.allMeta[expectedId], same(metaToAdd));
        expect(locker.allMeta, isNot(contains(expectedId)));

        await txn.abort();

        expect(locker.allMeta, isNot(contains(expectedId)));
        expect(metaToAdd.isErased, isTrue);
        verify(() => changeSet.addEntry(any())).called(1);
      });

      test('write applies meta to the cache on commit', () async {
        // Arrange
        final expectedId = EntryId('new');
        final metaToAdd = _StorageHelpers.createEntryMeta([5]);
        when(() => changeSet.addEntry(any())).thenAnswer((_) async => expectedId);

        final txn = await locker.beginTransaction(cipher);

        // Act
        await txn.write(
          EntryAddInput(meta: metaToAdd, value: _StorageHelpers.createEntryValue([1])),
        );
        await txn.commit();

        // Assert
        expect(locker.allMeta[expectedId], same(metaToAdd));
        expect(metaToAdd.isErased, isFalse);
      });

      test('write erases the value and hands the meta over to the transaction', () async {
        // Arrange
        final meta = _StorageHelpers.createEntryMeta([5]);
        final value = _StorageHelpers.createEntryValue([1]);
        when(() => changeSet.addEntry(any())).thenAnswer((_) async => EntryId('new'));

        final txn = await locker.beginTransaction(cipher);

        // Act
        await txn.write(EntryAddInput(meta: meta, value: value));

        // Assert: the value is consumed immediately, the meta is owned by the
        // transaction until it is committed or aborted.
        expect(value.isErased, isTrue);
        expect(meta.isErased, isFalse);

        await txn.abort();
      });

      test('write erases both value and meta when the operation fails', () async {
        // Arrange
        final meta = _StorageHelpers.createEntryMeta([5]);
        final value = _StorageHelpers.createEntryValue([1]);
        when(() => changeSet.addEntry(any())).thenThrow(StorageException.other('boom'));

        final txn = await locker.beginTransaction(cipher);

        // Act & Assert
        await expectLater(txn.write(EntryAddInput(meta: meta, value: value)), throwsA(isA<StorageException>()));
        expect(value.isErased, isTrue);
        expect(meta.isErased, isTrue);
        await txn.abort();
      });

      test('update erases the value and hands the meta over to the transaction', () async {
        // Arrange
        final meta = _StorageHelpers.createEntryMeta([5]);
        final value = _StorageHelpers.createEntryValue([1]);
        when(() => changeSet.updateEntry(any())).thenAnswer((_) async {});

        final txn = await locker.beginTransaction(cipher);

        // Act
        await txn.update(EntryUpdateInput(id: EntryId('a'), meta: meta, value: value));

        // Assert: the value is consumed immediately, the meta is owned by the
        // transaction until it is committed or aborted.
        expect(value.isErased, isTrue);
        expect(meta.isErased, isFalse);
        expect(txn.allMeta[EntryId('a')], same(meta));

        await txn.abort();
      });

      test('update erases both value and meta when the operation fails', () async {
        // Arrange
        final meta = _StorageHelpers.createEntryMeta([5]);
        final value = _StorageHelpers.createEntryValue([1]);
        when(() => changeSet.updateEntry(any())).thenThrow(StorageException.other('boom'));

        final txn = await locker.beginTransaction(cipher);

        // Act & Assert
        await expectLater(
          txn.update(EntryUpdateInput(id: EntryId('a'), meta: meta, value: value)),
          throwsA(isA<StorageException>()),
        );
        expect(value.isErased, isTrue);
        expect(meta.isErased, isTrue);
        await txn.abort();
      });

      test('delete hides the entry inside the transaction and removes it on commit', () async {
        // Arrange
        when(() => changeSet.deleteEntry(any())).thenAnswer((_) async {});

        final txn = await locker.beginTransaction(cipher);
        final committedMeta = locker.allMeta[EntryId('a')];

        // Act
        await txn.delete(EntryId('a'));

        // Assert: hidden inside the transaction, still visible outside.
        expect(txn.allMeta, isNot(contains(EntryId('a'))));
        expect(locker.allMeta, contains(EntryId('a')));
        expect(committedMeta?.isErased, isFalse);

        await txn.commit();

        expect(locker.allMeta, isNot(contains(EntryId('a'))));
        expect(committedMeta?.isErased, isTrue);
        verify(() => changeSet.deleteEntry(EntryId('a'))).called(1);
      });

      test('delete keeps the committed meta when the transaction is aborted', () async {
        // Arrange
        when(() => changeSet.deleteEntry(any())).thenAnswer((_) async {});

        final txn = await locker.beginTransaction(cipher);
        final committedMeta = locker.allMeta[EntryId('a')];

        // Act
        await txn.delete(EntryId('a'));
        await txn.abort();

        // Assert
        expect(locker.allMeta, contains(EntryId('a')));
        expect(committedMeta?.isErased, isFalse);
      });

      test('update applies the new meta on commit and erases the replaced one', () async {
        // Arrange
        final newMeta = _StorageHelpers.createEntryMeta([5]);
        when(() => changeSet.updateEntry(any())).thenAnswer((_) async {});

        final txn = await locker.beginTransaction(cipher);
        final replacedMeta = locker.allMeta[EntryId('a')];

        // Act
        await txn.update(EntryUpdateInput(id: EntryId('a'), meta: newMeta));

        expect(locker.allMeta[EntryId('a')], same(replacedMeta));

        await txn.commit();

        // Assert
        expect(locker.allMeta[EntryId('a')], same(newMeta));
        expect(replacedMeta?.isErased, isTrue);
        expect(newMeta.isErased, isFalse);
      });

      test('update erases the new meta when the transaction is aborted', () async {
        // Arrange
        final newMeta = _StorageHelpers.createEntryMeta([5]);
        when(() => changeSet.updateEntry(any())).thenAnswer((_) async {});

        final txn = await locker.beginTransaction(cipher);
        final committedMeta = locker.allMeta[EntryId('a')];

        // Act
        await txn.update(EntryUpdateInput(id: EntryId('a'), meta: newMeta));
        await txn.abort();

        // Assert
        expect(locker.allMeta[EntryId('a')], same(committedMeta));
        expect(committedMeta?.isErased, isFalse);
        expect(newMeta.isErased, isTrue);
      });

      test('delete ignores a not-found entry', () async {
        // Arrange
        when(() => changeSet.deleteEntry(any())).thenThrow(StorageException.entryNotFound());

        final txn = await locker.beginTransaction(cipher);

        // Act & Assert
        await expectLater(txn.delete(EntryId('a')), completes);
        await txn.abort();
      });

      test('commit persists the change set and erases keys', () async {
        // Arrange
        final txn = await locker.beginTransaction(cipher);

        // Act
        await txn.commit();

        // Assert
        expect(txn.isClosed, isTrue);
        verify(() => storage.commitChangeSet(changeSet)).called(1);
        verify(() => changeSet.erase()).called(1);

        // A new transaction is possible afterwards.
        final changeSet2 = MockStorageChangeSet();
        when(() => storage.openChangeSet(cipherFunc: any(named: 'cipherFunc'))).thenAnswer((_) async => changeSet2);
        when(() => changeSet2.erase()).thenAnswer((_) {});
        await expectLater(locker.beginTransaction(cipher), completes);
      });

      test('abort discards the change set without committing', () async {
        // Arrange
        final txn = await locker.beginTransaction(cipher);

        // Act
        await txn.abort();

        // Assert
        expect(txn.isClosed, isTrue);
        verifyNever(() => storage.commitChangeSet(any()));
        verify(() => changeSet.erase()).called(1);
      });

      test('operations after close throw StateError', () async {
        // Arrange
        final txn = await locker.beginTransaction(cipher);
        await txn.abort();

        // Act & Assert
        await expectLater(txn.readValue(EntryId('a')), throwsStateError);
      });

      test('lock closes the active transaction', () async {
        // Arrange
        final txn = await locker.beginTransaction(cipher);

        // Act
        locker.lock();

        // Assert
        expect(txn.isClosed, isTrue);
        verify(() => changeSet.erase()).called(1);
      });

      test('a queued operation fails and does not run when the locker is locked', () async {
        // Arrange
        var storageRead = false;
        when(() => changeSet.readValue(any())).thenAnswer((_) async {
          storageRead = true;

          return _StorageHelpers.createEntryValue([1]);
        });

        final txn = await locker.beginTransaction(cipher);

        // Act: the one-shot queues behind the transaction, then the user locks.
        final readFuture = locker.readValue(id: EntryId('a'), cipherFunc: cipher);
        await Future<void>.delayed(const Duration(milliseconds: 25));
        locker.lock();

        // Assert: the queued operation fails instead of resurrecting the locker.
        await expectLater(readFuture, throwsStateError);
        expect(storageRead, isFalse, reason: 'a queued operation must not reach storage after lock()');
        expect(locker.stateStream.value, LockerState.locked);
        expect(txn.isClosed, isTrue);
      });

      test('a queued transaction fails and does not run when the locker is disposed', () async {
        // Arrange
        final txn = await locker.beginTransaction(cipher);

        // Act
        final secondFuture = locker.beginTransaction(cipher);
        await Future<void>.delayed(const Duration(milliseconds: 25));
        locker.dispose();

        // Assert
        await expectLater(secondFuture, throwsStateError);
        verify(() => storage.openChangeSet(cipherFunc: cipher)).called(1);
        expect(txn.isClosed, isTrue);
      });

      test('standalone operations are executed in FIFO order with a transaction', () async {
        // Arrange
        final order = <String>[];
        when(() => changeSet.readValue(EntryId('b'))).thenAnswer((_) async {
          order.add('second');

          return _StorageHelpers.createEntryValue([1]);
        });
        when(() => changeSet.addEntry(any())).thenAnswer((_) async {
          order.add('third');

          return EntryId('new');
        });
        when(() => changeSet.readValue(EntryId('a'))).thenAnswer((_) async {
          order.add('first');

          return _StorageHelpers.createEntryValue([2]);
        });

        final txn = await locker.beginTransaction(cipher);

        // Act: enqueue a one-shot read and a write behind the open transaction.
        final readFuture = locker.readValue(id: EntryId('b'), cipherFunc: cipher);
        final writeFuture = locker.write(
          input: EntryAddInput(
            meta: _StorageHelpers.createEntryMeta([1]),
            value: _StorageHelpers.createEntryValue([1]),
          ),
          cipherFunc: cipher,
        );
        await Future<void>.delayed(const Duration(milliseconds: 25));

        await txn.readValue(EntryId('a'));
        await txn.abort();
        await readFuture;
        await writeFuture;

        // Assert
        expect(order, ['first', 'second', 'third']);
      });

      test('beginTransaction skips metadata reload when already unlocked', () async {
        // Arrange
        final first = await locker.beginTransaction(cipher);
        await first.abort();

        // Re-arm the mock so the second begin starts from a clean slate.
        final changeSet2 = MockStorageChangeSet();
        reset(storage);
        when(() => storage.isInitialized).thenAnswer((_) async => true);
        when(() => storage.openChangeSet(cipherFunc: any(named: 'cipherFunc'))).thenAnswer((_) async => changeSet2);
        when(() => changeSet2.readAllMeta()).thenAnswer((_) async => metas);

        // Act
        final second = await locker.beginTransaction(cipher);

        // Assert
        expect(second.isClosed, isFalse);
        verifyNever(() => changeSet2.readAllMeta());
        await second.abort();
      });

      test('withTransaction runs the body and commits the transaction', () async {
        // Arrange
        when(() => changeSet.readValue(any())).thenAnswer((_) async => _StorageHelpers.createEntryValue([9]));

        // Act
        final result = await locker.withTransaction(cipher, (txn) async {
          await txn.readValue(EntryId('a'));

          return 'done';
        });

        // Assert
        expect(result, 'done');
        verify(() => storage.openChangeSet(cipherFunc: cipher)).called(1);
        verify(() => storage.commitChangeSet(changeSet)).called(1);
        verify(() => changeSet.erase()).called(1);
      });

      test('withTransaction aborts when the body throws', () async {
        // Arrange
        when(() => changeSet.readValue(any())).thenThrow(StorageException.other('boom'));

        // Act & Assert
        await expectLater(
          locker.withTransaction(cipher, (txn) async => txn.readValue(EntryId('a'))),
          throwsA(isA<StorageException>()),
        );
        verifyNever(() => storage.commitChangeSet(any()));
        verify(() => changeSet.erase()).called(1);
      });

      test('allMeta inside the withTransaction body exposes uncommitted changes', () async {
        // Arrange
        final expectedId = EntryId('new');
        final metaToAdd = _StorageHelpers.createEntryMeta([5]);
        when(() => changeSet.addEntry(any())).thenAnswer((_) async => expectedId);
        when(() => changeSet.deleteEntry(any())).thenAnswer((_) async {});

        Map<EntryId, EntryMeta>? insideMeta;

        // Act
        await locker.withTransaction(cipher, (txn) async {
          await txn.write(
            EntryAddInput(meta: metaToAdd, value: _StorageHelpers.createEntryValue([1])),
          );
          await txn.delete(EntryId('a'));
          insideMeta = locker.allMeta;
        });

        // Assert: inside the body the zone-aware view exposes the overlay...
        expect(insideMeta?[expectedId], same(metaToAdd));
        expect(insideMeta, isNot(contains(EntryId('a'))));

        // ...after the commit the same merged state is the committed one.
        expect(locker.allMeta[expectedId], same(metaToAdd));
        expect(locker.allMeta, isNot(contains(EntryId('a'))));
      });

      test('allMeta inside an aborted withTransaction body is discarded', () async {
        // Arrange
        final expectedId = EntryId('new');
        final metaToAdd = _StorageHelpers.createEntryMeta([5]);
        when(() => changeSet.addEntry(any())).thenAnswer((_) async => expectedId);
        when(() => changeSet.readValue(any())).thenThrow(StorageException.other('boom'));

        // Act & Assert
        await expectLater(
          locker.withTransaction(cipher, (txn) async {
            await txn.write(
              EntryAddInput(meta: metaToAdd, value: _StorageHelpers.createEntryValue([1])),
            );
            expect(locker.allMeta[expectedId], same(metaToAdd));

            throw StorageException.other('boom');
          }),
          throwsA(isA<StorageException>()),
        );

        expect(locker.allMeta, isNot(contains(expectedId)));
        expect(metaToAdd.isErased, isTrue);
      });

      test('a locker method called from a transaction body fails instead of deadlocking', () async {
        // Arrange
        final cipher = _Helpers.createMockBioCipherFunc();
        var storageRead = false;
        when(() => changeSet.readValue(any())).thenAnswer((_) async {
          storageRead = true;

          return _StorageHelpers.createEntryValue([1]);
        });

        // Act & Assert
        await expectLater(
          locker.withTransaction(
            cipher,
            (txn) => locker.readValue(id: EntryId('a'), cipherFunc: cipher),
          ),
          throwsA(
            isA<StateError>().having((e) => e.message, 'message', contains('inside a transaction')),
          ),
        ).timeout(const Duration(seconds: 1));

        expect(storageRead, isFalse);

        // The transaction was aborted, so a new operation can run.
        final value = await locker.readValue(id: EntryId('a'), cipherFunc: cipher);
        expect(value.bytes, orderedEquals([1]));
      });

      test('one-shot operations wait while a transaction is open', () async {
        // Arrange
        var storageRead = false;
        when(() => changeSet.readValue(any())).thenAnswer((_) async {
          storageRead = true;

          return _StorageHelpers.createEntryValue([1]);
        });

        final txn = await locker.beginTransaction(cipher);

        // Act: a one-shot read starts while the transaction is open — it must
        // not reach storage until the transaction is finished.
        final readFuture = locker.readValue(id: EntryId('a'), cipherFunc: cipher);
        await Future<void>.delayed(const Duration(milliseconds: 25));
        expect(storageRead, isFalse, reason: 'one-shot read must wait for the transaction to finish');

        await txn.commit();
        await readFuture;

        // Assert
        expect(storageRead, isTrue, reason: 'after the transaction finishes the one-shot read proceeds');
      });
    });

    group('write', () {
      test('updates cache and calls changeSet.addEntry', () async {
        // Arrange
        final cipher = _Helpers.createMockPasswordCipherFunc();
        final metaToAdd = _StorageHelpers.createEntryMeta([1, 2]);
        final valueToAdd = _StorageHelpers.createEntryValue();
        final expectedId = EntryId('id');
        final input = EntryAddInput(meta: metaToAdd, value: valueToAdd);

        _Helpers.stubReadAllMeta(changeSet);
        await locker.loadAllMeta(cipher);

        when(() => changeSet.addEntry(any())).thenAnswer((_) async => expectedId);

        // Act
        final result = await locker.write(
          input: input,
          cipherFunc: cipher,
        );

        // Assert
        verify(() => changeSet.addEntry(input)).called(1);

        expect(result, equals(expectedId));
        expect(locker.allMeta[expectedId], same(metaToAdd));

        _Helpers.verifyErasedAll([cipher, valueToAdd]);
      });

      test('replaces existing meta and erases previous one when id matches', () async {
        // Arrange
        final cipher = _Helpers.createMockPasswordCipherFunc();
        final id = EntryId('entryId');

        _Helpers.stubReadAllMeta(changeSet, id: id.value, metaBytes: [1, 2]);
        await locker.loadAllMeta(cipher);

        final oldMeta = locker.allMeta[id]!;
        final newMeta = _StorageHelpers.createEntryMeta([3, 4]);
        final newValue = _StorageHelpers.createEntryValue();
        final input = EntryAddInput(meta: newMeta, value: newValue);

        when(() => changeSet.addEntry(any())).thenAnswer((_) async => id);

        // Act
        await locker.write(
          input: input,
          cipherFunc: cipher,
        );

        // Assert
        expect(locker.allMeta[id]!, same(newMeta));

        _Helpers.verifyErasedAll([cipher, newValue, oldMeta]);
      });

      test('rethrows on storage error', () async {
        // Arrange
        final cipher = _Helpers.createMockPasswordCipherFunc();
        final meta = _StorageHelpers.createEntryMeta();
        final value = _StorageHelpers.createEntryValue();
        final input = EntryAddInput(meta: meta, value: value);

        _Helpers.stubReadAllMeta(changeSet);

        when(() => changeSet.addEntry(any())).thenThrow(Exception('test'));

        // Act & Assert
        await expectLater(
          () => locker.write(
            input: input,
            cipherFunc: cipher,
          ),
          throwsException,
        );

        _Helpers.verifyErasedAll([cipher, value, meta]);
      });

      test('throws when storage not initialized', () async {
        // Arrange
        when(() => storage.isInitialized).thenAnswer((_) async => false);
        final cipher = _Helpers.createMockPasswordCipherFunc();
        final meta = _StorageHelpers.createEntryMeta();
        final value = _StorageHelpers.createEntryValue();
        final input = EntryAddInput(meta: meta, value: value);

        // Act & Assert
        await expectLater(
          () => locker.write(
            input: input,
            cipherFunc: cipher,
          ),
          throwsA(isA<StateError>()),
        );

        verifyNever(() => changeSet.addEntry(any()));

        _Helpers.verifyErasedAll([cipher, value, meta]);
      });

      test('passes explicit id to changeSet.addEntry', () async {
        // Arrange
        final cipher = _Helpers.createMockPasswordCipherFunc();
        final meta = _StorageHelpers.createEntryMeta([1, 2]);
        final value = _StorageHelpers.createEntryValue();
        final explicitId = EntryId('my-custom-id');
        final input = EntryAddInput(meta: meta, value: value, id: explicitId);

        _Helpers.stubReadAllMeta(changeSet);
        await locker.loadAllMeta(cipher);

        when(() => changeSet.addEntry(any())).thenAnswer((_) async => explicitId);

        // Act
        final result = await locker.write(
          input: input,
          cipherFunc: cipher,
        );

        // Assert
        verify(() => changeSet.addEntry(input)).called(1);

        expect(result, equals(explicitId));
        expect(locker.allMeta[explicitId], same(meta));

        _Helpers.verifyErasedAll([cipher, value]);
      });
    });

    group('readValue', () {
      test('returns value and calls changeSet.readValue', () async {
        // Arrange
        final cipher = _Helpers.createMockPasswordCipherFunc();
        final id = EntryId('id');
        final value = _StorageHelpers.createEntryValue([1, 2, 3]);

        _Helpers.stubReadAllMeta(changeSet, id: id.value);
        await locker.loadAllMeta(cipher);

        when(() => changeSet.readValue(id)).thenAnswer((_) async => value);

        // Act
        final result = await locker.readValue(id: id, cipherFunc: cipher);

        // Assert
        expect(result, same(value));
        verify(() => changeSet.readValue(id)).called(1);

        _Helpers.verifyErased(cipher);
      });

      test('rethrows on storage error', () async {
        // Arrange
        final cipher = _Helpers.createMockPasswordCipherFunc();
        _Helpers.stubReadAllMeta(changeSet);

        when(() => changeSet.readValue(any())).thenThrow(Exception('test'));

        // Act & Assert
        await expectLater(
          () => locker.readValue(
            id: EntryId('entry-id'),
            cipherFunc: cipher,
          ),
          throwsException,
        );

        _Helpers.verifyErased(cipher);
      });

      test('throws when storage not initialized', () async {
        // Arrange
        when(() => storage.isInitialized).thenAnswer((_) async => false);
        final cipher = _Helpers.createMockPasswordCipherFunc();

        // Act & Assert
        await expectLater(
          () => locker.readValue(
            id: EntryId('entry-id'),
            cipherFunc: cipher,
          ),
          throwsA(isA<StateError>()),
        );

        verifyNever(() => changeSet.readValue(any()));

        _Helpers.verifyErased(cipher);
      });
    });

    group('delete', () {
      test('removes entry from cache and erases meta', () async {
        // Arrange
        const existingId = 'idToDelete';

        final cipher = _Helpers.createMockPasswordCipherFunc();
        final id = EntryId(existingId);

        _Helpers.stubReadAllMeta(changeSet, id: existingId);
        await locker.loadAllMeta(cipher);

        final deletedMetaRef = locker.allMeta[id]!;

        when(() => changeSet.deleteEntry(id)).thenAnswer((_) async {});

        // Act
        await locker.delete(id: id, cipherFunc: cipher);

        // Assert
        verify(() => changeSet.deleteEntry(id)).called(1);
        expect(locker.allMeta.containsKey(id), isFalse);

        _Helpers.verifyErasedAll([cipher, deletedMetaRef]);
      });

      test('leaves cache unchanged when deleting non-existing id', () async {
        // Arrange
        final missingId = EntryId('missing');
        final cipher = _Helpers.createMockPasswordCipherFunc();

        _Helpers.stubReadAllMeta(changeSet);
        await locker.loadAllMeta(cipher);

        final metaBefore = locker.allMeta;

        when(() => changeSet.deleteEntry(missingId)).thenThrow(StorageException.entryNotFound());

        // Act
        await locker.delete(id: missingId, cipherFunc: cipher);

        // Assert
        expect(locker.allMeta.containsKey(missingId), isFalse);
        expect(metaBefore, equals(locker.allMeta));

        _Helpers.verifyErased(cipher);
      });

      test('throws when storage not initialized', () async {
        // Arrange
        when(() => storage.isInitialized).thenAnswer((_) async => false);
        final cipher = _Helpers.createMockPasswordCipherFunc();

        // Act & Assert
        await expectLater(
          () => locker.delete(id: EntryId('to-delete'), cipherFunc: cipher),
          throwsA(isA<StateError>()),
        );

        verifyNever(() => changeSet.deleteEntry(any()));
        _Helpers.verifyErased(cipher);
      });

      test('rethrows on storage error', () async {
        // Arrange
        final cipher = _Helpers.createMockPasswordCipherFunc();
        final id = EntryId('to-delete');

        _Helpers.stubReadAllMeta(changeSet, id: id.value);

        await locker.loadAllMeta(cipher);
        final before = Map.of(locker.allMeta);

        when(() => changeSet.deleteEntry(id)).thenThrow(Exception('test'));

        // Act & Assert
        await expectLater(
          () => locker.delete(
            id: id,
            cipherFunc: cipher,
          ),
          throwsException,
        );

        expect(locker.allMeta, equals(before));
        _Helpers.verifyErased(cipher);
      });

      test('removes entry from cache when entry not found in storage', () async {
        // Arrange
        final cipher = _Helpers.createMockPasswordCipherFunc();
        final id = EntryId('x');
        _Helpers.stubReadAllMeta(changeSet, id: id.value);

        await locker.loadAllMeta(cipher);
        final deletedMetaRef = locker.allMeta[id]!;

        when(() => changeSet.deleteEntry(id)).thenThrow(StorageException.entryNotFound());

        // Act
        await locker.delete(id: id, cipherFunc: cipher);

        // Assert
        expect(locker.allMeta.containsKey(id), isFalse);

        verify(() => changeSet.deleteEntry(id)).called(1);
        _Helpers.verifyErasedAll([cipher, deletedMetaRef]);
      });
    });

    group('update', () {
      test('updates cache and calls storage.updateEntry with meta and value', () async {
        // Arrange
        final cipher = _Helpers.createMockPasswordCipherFunc();
        final id = EntryId('entryId');

        _Helpers.stubReadAllMeta(
          changeSet,
          id: id.value,
          metaBytes: [1, 2],
        );
        await locker.loadAllMeta(cipher);

        final oldMeta = locker.allMeta[id]!;
        final newMeta = _StorageHelpers.createEntryMeta([3, 4]);
        final newValue = _StorageHelpers.createEntryValue([5, 6]);
        final input = EntryUpdateInput(id: id, meta: newMeta, value: newValue);

        when(() => changeSet.updateEntry(any())).thenAnswer((_) async {});

        // Act
        await locker.update(
          input: input,
          cipherFunc: cipher,
        );

        // Assert
        verify(() => changeSet.updateEntry(input)).called(1);

        expect(locker.allMeta[id], same(newMeta));
        _Helpers.verifyErasedAll([cipher, newValue, oldMeta]);
      });

      test('updates only value without changing meta cache', () async {
        // Arrange
        final cipher = _Helpers.createMockPasswordCipherFunc();
        final id = EntryId('entryId');

        _Helpers.stubReadAllMeta(
          changeSet,
          id: id.value,
          metaBytes: [1, 2],
        );
        await locker.loadAllMeta(cipher);

        final existingMeta = locker.allMeta[id]!;
        final newValue = _StorageHelpers.createEntryValue([5, 6]);
        final input = EntryUpdateInput(id: id, value: newValue);

        when(() => changeSet.updateEntry(any())).thenAnswer((_) async {});

        // Act
        await locker.update(
          input: input,
          cipherFunc: cipher,
        );

        // Assert
        verify(() => changeSet.updateEntry(input)).called(1);

        expect(locker.allMeta[id], same(existingMeta));
        _Helpers.verifyErasedAll([cipher, newValue]);
      });

      test('updates only meta and updates cache', () async {
        // Arrange
        final cipher = _Helpers.createMockPasswordCipherFunc();
        final id = EntryId('entryId');

        _Helpers.stubReadAllMeta(changeSet, id: id.value, metaBytes: [1, 2]);
        await locker.loadAllMeta(cipher);

        final oldMeta = locker.allMeta[id]!;
        final newMeta = _StorageHelpers.createEntryMeta([3, 4]);
        final input = EntryUpdateInput(id: id, meta: newMeta);

        when(() => changeSet.updateEntry(any())).thenAnswer((_) async {});

        // Act
        await locker.update(
          input: input,
          cipherFunc: cipher,
        );

        // Assert
        verify(() => changeSet.updateEntry(input)).called(1);

        expect(locker.allMeta[id], same(newMeta));
        _Helpers.verifyErasedAll([cipher, oldMeta]);
      });

      test('throws when storage not initialized', () async {
        // Arrange
        when(() => storage.isInitialized).thenAnswer((_) async => false);
        final cipher = _Helpers.createMockPasswordCipherFunc();
        final meta = _StorageHelpers.createEntryMeta();
        final value = _StorageHelpers.createEntryValue();
        final input = EntryUpdateInput(id: EntryId('entry-id'), meta: meta, value: value);

        // Act & Assert
        await expectLater(
          () => locker.update(
            input: input,
            cipherFunc: cipher,
          ),
          throwsA(isA<StateError>()),
        );

        verifyNever(() => changeSet.updateEntry(any()));

        _Helpers.verifyErasedAll([cipher, value, meta]);
      });

      test('rethrows on storage error and erases meta on error', () async {
        // Arrange
        final cipher = _Helpers.createMockPasswordCipherFunc();
        final id = EntryId('entryId');
        final meta = _StorageHelpers.createEntryMeta([3, 4]);
        final value = _StorageHelpers.createEntryValue([5, 6]);
        final input = EntryUpdateInput(id: id, meta: meta, value: value);

        _Helpers.stubReadAllMeta(changeSet, id: id.value);
        await locker.loadAllMeta(cipher);

        final before = Map.of(locker.allMeta);

        when(() => changeSet.updateEntry(any())).thenThrow(Exception('test'));

        // Act & Assert
        await expectLater(
          () => locker.update(
            input: input,
            cipherFunc: cipher,
          ),
          throwsException,
        );

        expect(locker.allMeta, equals(before));
        _Helpers.verifyErasedAll([cipher, value, meta]);
      });
    });

    group('wrap management', () {
      test('changePassword calls addOrReplaceWrap on the change set', () async {
        // Arrange
        final oldPwd = _Helpers.createMockPasswordCipherFunc();
        final newPwd = _Helpers.createMockPasswordCipherFunc(password: [2], salt: [2]);

        _Helpers.stubReadAllMeta(changeSet);
        await locker.loadAllMeta(oldPwd);

        when(() => changeSet.addOrReplaceWrap(newWrapFunc: any(named: 'newWrapFunc'))).thenAnswer((_) async {});

        // Act
        await locker.changePassword(
          newCipherFunc: newPwd,
          existingCipherFunc: oldPwd,
        );

        // Assert
        verify(() => changeSet.addOrReplaceWrap(newWrapFunc: newPwd)).called(1);

        _Helpers.verifyErasedAll([oldPwd, newPwd]);
      });

      test('rethrows on changePassword error', () async {
        // Arrange
        final oldPwd = _Helpers.createMockPasswordCipherFunc();
        final newPwd = _Helpers.createMockPasswordCipherFunc(password: [2], salt: [2]);
        _Helpers.stubReadAllMeta(changeSet);
        await locker.loadAllMeta(oldPwd);

        when(() => changeSet.addOrReplaceWrap(newWrapFunc: any(named: 'newWrapFunc'))).thenThrow(Exception('test'));

        // Act & Assert
        await expectLater(
          () => locker.changePassword(newCipherFunc: newPwd, existingCipherFunc: oldPwd),
          throwsException,
        );

        _Helpers.verifyErasedAll([oldPwd, newPwd]);
      });
    });

    group('setupBiometry', () {
      const biometricKeyTag = 'test-bio-key-tag';

      late MockBiometricCipherProvider secureProvider;
      late MockEncryptedStorage tpStorage;
      late MockStorageChangeSet tpChangeSet;
      late MFALocker tpLocker;

      setUp(() {
        secureProvider = MockBiometricCipherProvider();
        tpStorage = MockEncryptedStorage();
        tpChangeSet = MockStorageChangeSet();

        tpLocker = MFALocker(
          file: MockFile(),
          storage: tpStorage,
          secureProvider: secureProvider,
        );

        when(() => tpStorage.isInitialized).thenAnswer((_) async => true);
        when(() => tpStorage.lockTimeout).thenAnswer((_) async => _Helpers.lockTimeout.inMilliseconds);
        when(() => tpStorage.openChangeSet(cipherFunc: any(named: 'cipherFunc'))).thenAnswer((_) async => tpChangeSet);
        when(() => tpStorage.commitChangeSet(any())).thenAnswer((_) async {});
        when(() => tpChangeSet.readAllMeta()).thenAnswer((_) async => <EntryId, EntryMeta>{});
        when(() => tpChangeSet.erase()).thenAnswer((_) {});
      });

      tearDown(() {
        tpLocker.dispose();
      });

      test('throws BiometricException when TPM is not supported', () async {
        // Arrange
        final bio = _Helpers.createMockBioCipherFunc();
        final pwd = _Helpers.createMockPasswordCipherFunc();
        when(() => secureProvider.getTPMStatus()).thenAnswer((_) async => TPMStatus.unsupported);

        // Act & Assert
        await expectLater(
          () => tpLocker.setupBiometry(bioCipherFunc: bio, passwordCipherFunc: pwd),
          throwsA(
            predicate(
              (e) => e is BiometricException && e.type == BiometricExceptionType.notAvailable,
            ),
          ),
        );
        verifyNever(() => secureProvider.generateKey(tag: any(named: 'tag')));
        verifyNever(() => secureProvider.deleteKey(tag: any(named: 'tag')));
      });

      test('throws BiometricException when biometry is not available', () async {
        // Arrange
        final bio = _Helpers.createMockBioCipherFunc();
        final pwd = _Helpers.createMockPasswordCipherFunc();
        when(() => secureProvider.getTPMStatus()).thenAnswer((_) async => TPMStatus.supported);
        when(() => secureProvider.getBiometryStatus()).thenAnswer((_) async => BiometricStatus.unsupported);

        // Act & Assert
        await expectLater(
          () => tpLocker.setupBiometry(bioCipherFunc: bio, passwordCipherFunc: pwd),
          throwsA(
            predicate(
              (e) => e is BiometricException && e.type == BiometricExceptionType.notAvailable,
            ),
          ),
        );
        verifyNever(() => secureProvider.generateKey(tag: any(named: 'tag')));
        verifyNever(() => secureProvider.deleteKey(tag: any(named: 'tag')));
      });

      test('deletes key defensively, generates key, and enables biometry on success', () async {
        // Arrange
        final bio = _Helpers.createMockBioCipherFunc();
        when(() => bio.keyTag).thenReturn(biometricKeyTag);
        final pwd = _Helpers.createMockPasswordCipherFunc();
        when(() => secureProvider.getTPMStatus()).thenAnswer((_) async => TPMStatus.supported);
        when(() => secureProvider.getBiometryStatus()).thenAnswer((_) async => BiometricStatus.supported);
        when(() => secureProvider.deleteKey(tag: biometricKeyTag)).thenAnswer((_) async {});
        when(() => secureProvider.generateKey(tag: biometricKeyTag)).thenAnswer((_) async {});
        _Helpers.stubReadAllMeta(tpChangeSet);
        when(() => tpChangeSet.addOrReplaceWrap(newWrapFunc: any(named: 'newWrapFunc'))).thenAnswer((_) async {});

        // Act
        await tpLocker.setupBiometry(bioCipherFunc: bio, passwordCipherFunc: pwd);

        // Assert
        verify(() => secureProvider.deleteKey(tag: biometricKeyTag)).called(1);
        verify(() => secureProvider.generateKey(tag: biometricKeyTag)).called(1);
        verify(() => tpChangeSet.addOrReplaceWrap(newWrapFunc: bio)).called(1);
      });

      test('deletes generated key on failure and rethrows', () async {
        // Arrange
        final bio = _Helpers.createMockBioCipherFunc();
        when(() => bio.keyTag).thenReturn(biometricKeyTag);
        final pwd = _Helpers.createMockPasswordCipherFunc();
        when(() => secureProvider.getTPMStatus()).thenAnswer((_) async => TPMStatus.supported);
        when(() => secureProvider.getBiometryStatus()).thenAnswer((_) async => BiometricStatus.supported);
        when(() => secureProvider.deleteKey(tag: biometricKeyTag)).thenAnswer((_) async {});
        when(() => secureProvider.generateKey(tag: biometricKeyTag)).thenAnswer((_) async {});
        _Helpers.stubReadAllMeta(tpChangeSet);
        when(() => tpChangeSet.addOrReplaceWrap(newWrapFunc: any(named: 'newWrapFunc'))).thenThrow(
          Exception('storage error'),
        );

        // Act & Assert
        await expectLater(
          () => tpLocker.setupBiometry(bioCipherFunc: bio, passwordCipherFunc: pwd),
          throwsException,
        );
        // deleteKey called twice: once defensive before generate, once for cleanup on failure
        verify(() => secureProvider.deleteKey(tag: biometricKeyTag)).called(2);
      });
    });

    group('teardownBiometry', () {
      const biometricKeyTag = 'test-bio-key-tag';

      late MockBiometricCipherProvider secureProvider;
      late MockEncryptedStorage tpStorage;
      late MockStorageChangeSet tpChangeSet;
      late MFALocker tpLocker;

      setUp(() {
        secureProvider = MockBiometricCipherProvider();
        tpStorage = MockEncryptedStorage();
        tpChangeSet = MockStorageChangeSet();

        tpLocker = MFALocker(
          file: MockFile(),
          storage: tpStorage,
          secureProvider: secureProvider,
        );

        when(() => tpStorage.isInitialized).thenAnswer((_) async => true);
        when(() => tpStorage.lockTimeout).thenAnswer((_) async => _Helpers.lockTimeout.inMilliseconds);
        when(() => tpStorage.openChangeSet(cipherFunc: any(named: 'cipherFunc'))).thenAnswer((_) async => tpChangeSet);
        when(() => tpStorage.commitChangeSet(any())).thenAnswer((_) async {});
        when(() => tpChangeSet.readAllMeta()).thenAnswer((_) async => <EntryId, EntryMeta>{});
        when(() => tpChangeSet.erase()).thenAnswer((_) {});
      });

      tearDown(() {
        tpLocker.dispose();
      });

      test('deletes bio wrap and biometric key on success', () async {
        // Arrange
        final pwd = _Helpers.createMockPasswordCipherFunc();
        _Helpers.stubReadAllMeta(tpChangeSet);

        when(() => tpChangeSet.deleteWrap(originToDelete: Origin.bio)).thenAnswer((_) async {});
        when(() => secureProvider.deleteKey(tag: biometricKeyTag)).thenAnswer((_) async {});

        // Act
        await tpLocker.teardownBiometry(
          passwordCipherFunc: pwd,
          biometricKeyTag: biometricKeyTag,
        );

        // Assert
        verify(() => tpChangeSet.deleteWrap(originToDelete: Origin.bio)).called(1);
        verify(() => secureProvider.deleteKey(tag: biometricKeyTag)).called(1);
      });

      test('completes normally when deleteKey throws', () async {
        // Arrange
        final pwd = _Helpers.createMockPasswordCipherFunc();
        _Helpers.stubReadAllMeta(tpChangeSet);

        when(() => tpChangeSet.deleteWrap(originToDelete: Origin.bio)).thenAnswer((_) async {});
        when(() => secureProvider.deleteKey(tag: biometricKeyTag)).thenThrow(Exception('key gone'));

        // Act & Assert - should not throw
        await tpLocker.teardownBiometry(
          passwordCipherFunc: pwd,
          biometricKeyTag: biometricKeyTag,
        );

        verify(() => tpChangeSet.deleteWrap(originToDelete: Origin.bio)).called(1);
        verify(() => secureProvider.deleteKey(tag: biometricKeyTag)).called(1);
      });

      test('skips key deletion when biometricKeyTag is null', () async {
        // Arrange
        final pwd = _Helpers.createMockPasswordCipherFunc();
        _Helpers.stubReadAllMeta(tpChangeSet);

        when(() => tpChangeSet.deleteWrap(originToDelete: Origin.bio)).thenAnswer((_) async {});

        // Act
        await tpLocker.teardownBiometry(
          passwordCipherFunc: pwd,
        );

        // Assert
        verify(() => tpChangeSet.deleteWrap(originToDelete: Origin.bio)).called(1);
        verifyNever(() => secureProvider.deleteKey(tag: any(named: 'tag')));
      });

      test('unlocks before deleting wrap when locker is locked', () async {
        // Arrange
        final pwd = _Helpers.createMockPasswordCipherFunc();
        _Helpers.stubReadAllMeta(tpChangeSet);

        when(() => tpChangeSet.deleteWrap(originToDelete: Origin.bio)).thenAnswer((_) async {});
        when(() => secureProvider.deleteKey(tag: biometricKeyTag)).thenAnswer((_) async {});

        expect(tpLocker.stateStream.value, LockerState.locked);

        // Act
        await tpLocker.teardownBiometry(
          passwordCipherFunc: pwd,
          biometricKeyTag: biometricKeyTag,
        );

        // Assert
        verifyInOrder([
          () => tpChangeSet.readAllMeta(),
          () => tpChangeSet.deleteWrap(originToDelete: Origin.bio),
        ]);
      });
    });

    group('eraseStorage', () {
      test('erases storage when locked', () async {
        // Arrange
        when(() => storage.erase()).thenAnswer((_) async => true);

        // Act
        await locker.eraseStorage();

        // Assert
        verify(() => storage.erase()).called(1);
        expect(locker.stateStream.value, LockerState.locked);
      });

      test('erases storage, locks the locker', () async {
        // Arrange
        final cipher = _Helpers.createMockPasswordCipherFunc();
        _Helpers.stubReadAllMeta(changeSet);

        when(() => storage.erase()).thenAnswer((_) async => true);
        await locker.loadAllMeta(cipher);

        // Act
        await locker.eraseStorage();

        // Assert
        verify(() => storage.erase()).called(1);
        expect(locker.stateStream.value, LockerState.locked);

        _Helpers.verifyErased(cipher);
      });

      test('propagates exception when storage erase throws', () async {
        // Arrange
        final cipher = _Helpers.createMockPasswordCipherFunc();
        final meta = _Helpers.stubReadAllMeta(changeSet);

        await locker.loadAllMeta(cipher);
        when(() => storage.erase()).thenThrow(const FileSystemException('delete failed'));

        // Act & Assert
        await expectLater(
          () => locker.eraseStorage(),
          throwsA(isA<FileSystemException>()),
        );
        verify(() => storage.erase()).called(1);
        expect(locker.stateStream.value, LockerState.unlocked);
        expect(locker.allMeta, equals(meta));

        _Helpers.verifyErased(cipher);
      });
    });

    group('race-condition safety', () {
      const delayDuration = Duration(milliseconds: 25);

      test('concurrent readValue calls serialize: sequential changeSet.readValue', () async {
        // Arrange
        final cipher = _Helpers.createMockPasswordCipherFunc();

        _Helpers.stubReadAllMeta(changeSet);
        await locker.loadAllMeta(cipher);

        final id1 = EntryId('id1');
        final id2 = EntryId('id2');

        final gate1 = Completer<void>();
        var calls = 0;

        when(() => changeSet.readValue(any())).thenAnswer((invocation) async {
          calls++;
          if (calls == 1) {
            await gate1.future;
          }

          final n = calls;
          return _StorageHelpers.createEntryValue([n]);
        });

        // Act: start first readValue; it should enter storage and block on gate1
        final f1 = locker.readValue(id: id1, cipherFunc: cipher);
        await Future<void>.delayed(delayDuration);
        expect(calls, 1, reason: 'First readValue should have entered changeSet.readValue and be waiting on the gate.');

        // Start second readValue; it must not enter storage yet
        final f2 = locker.readValue(id: id2, cipherFunc: cipher);
        await Future<void>.delayed(delayDuration);
        expect(calls, 1, reason: 'Second readValue must be queued and not call changeSet.readValue yet.');

        // Release the first call; second can now enter and complete.
        gate1.complete();
        final v1 = await f1;
        final v2 = await f2;

        // Assert
        expect(calls, 2);
        verify(() => changeSet.readValue(id1)).called(1);
        verify(() => changeSet.readValue(id2)).called(1);
        expect(v1, isNot(same(v2)));
      });

      test(
        'two concurrent write calls are serialized ',
        () async {
          // Arrange
          final cipher = _Helpers.createMockPasswordCipherFunc();
          _Helpers.stubReadAllMeta(changeSet);
          await locker.loadAllMeta(cipher);
          expect(locker.stateStream.value, LockerState.unlocked);

          final meta1 = _StorageHelpers.createEntryMeta([1]);
          final val1 = _StorageHelpers.createEntryValue([1]);
          final meta2 = _StorageHelpers.createEntryMeta([2]);
          final val2 = _StorageHelpers.createEntryValue([2]);
          final input1 = EntryAddInput(meta: meta1, value: val1);
          final input2 = EntryAddInput(meta: meta2, value: val2);

          final gate1 = Completer<void>();
          var addCalls = 0;

          when(() => changeSet.addEntry(any())).thenAnswer((invocation) async {
            addCalls++;
            if (addCalls == 1) {
              await gate1.future;
            }

            return EntryId('id$addCalls');
          });

          // Act: start two concurrent writes
          final f1 = locker.write(input: input1, cipherFunc: cipher);
          await Future<void>.delayed(delayDuration);
          expect(addCalls, 1, reason: 'First write must have entered storage.addEntry and be blocked.');

          final f2 = locker.write(input: input2, cipherFunc: cipher);
          await Future<void>.delayed(delayDuration);
          expect(addCalls, 1, reason: 'Second write must be queued and not enter addEntry yet.');

          gate1.complete();
          final id1 = await f1;
          final id2 = await f2;

          // Assert
          expect(addCalls, 2, reason: 'Both changeSet.addEntry calls should have executed sequentially.');
          verify(() => changeSet.addEntry(input1)).called(1);
          verify(() => changeSet.addEntry(input2)).called(1);
          expect(id1.value, isNot(equals(id2.value)), reason: 'Both writes reached storage.');
        },
      );

      test('changePassword/readValue: serialized; old fails, new succeeds', () async {
        // Arrange
        final oldPwd = _Helpers.createMockPasswordCipherFunc();
        final newPwd = _Helpers.createMockPasswordCipherFunc(password: [2], salt: [2]);

        _Helpers.stubReadAllMeta(changeSet);
        await locker.loadAllMeta(oldPwd);

        final gate = Completer<void>();
        var wrapCalls = 0;
        var wrapStored = false;

        when(() => changeSet.addOrReplaceWrap(newWrapFunc: any(named: 'newWrapFunc'))).thenAnswer((_) async {
          wrapCalls++;
          if (wrapCalls == 1) {
            await gate.future;
          }

          wrapStored = true;
        });

        // Once the new wrap is stored, the old password can no longer open the
        // storage: unwrapping fails before any entry is read.
        when(() => storage.openChangeSet(cipherFunc: oldPwd)).thenAnswer((_) async {
          if (wrapStored) {
            throw const DecryptFailedException();
          }

          return changeSet;
        });
        when(() => storage.openChangeSet(cipherFunc: newPwd)).thenAnswer((_) async => changeSet);

        final expected = _StorageHelpers.createEntryValue([4, 2]);
        when(() => changeSet.readValue(any())).thenAnswer((_) async => expected);

        // Act
        final fChange = locker.changePassword(newCipherFunc: newPwd, existingCipherFunc: oldPwd);
        await Future<void>.delayed(delayDuration);
        expect(wrapCalls, 1, reason: 'changePassword must have entered the change set and be waiting on the gate');

        final fReadOld = locker.readValue(id: EntryId('id'), cipherFunc: oldPwd);
        await Future<void>.delayed(delayDuration);

        gate.complete();
        await fChange;

        await expectLater(
          () => fReadOld,
          throwsA(isA<DecryptFailedException>()),
        );

        final vNew = await locker.readValue(id: EntryId('id'), cipherFunc: newPwd);
        expect(vNew, same(expected), reason: 'readValue(newPwd) must return the value provided by the change set');

        // Assert
        _Helpers.verifyErasedAll([oldPwd, newPwd]);
        verify(() => changeSet.addOrReplaceWrap(newWrapFunc: newPwd)).called(1);
        verify(() => storage.openChangeSet(cipherFunc: oldPwd)).called(3);
        verify(() => storage.openChangeSet(cipherFunc: newPwd)).called(1);
      });
    });

    group('determineBiometricState', () {
      const biometricKeyTag = 'test-bio-key-tag';

      late MockBiometricCipherProvider secureProvider;
      late MockEncryptedStorage dsStorage;
      late MFALocker dsLocker;

      setUp(() {
        secureProvider = MockBiometricCipherProvider();
        dsStorage = MockEncryptedStorage();

        dsLocker = MFALocker(
          file: MockFile(),
          storage: dsStorage,
          secureProvider: secureProvider,
        );

        when(() => dsStorage.isInitialized).thenAnswer((_) async => true);
        when(() => dsStorage.lockTimeout).thenAnswer((_) async => _Helpers.lockTimeout.inMilliseconds);

        when(() => secureProvider.getTPMStatus()).thenAnswer((_) async => TPMStatus.supported);
        when(() => secureProvider.getBiometryStatus()).thenAnswer((_) async => BiometricStatus.supported);
        when(() => dsStorage.isBiometricEnabled).thenAnswer((_) async => true);
      });

      tearDown(() async {
        dsLocker.dispose();
      });

      test('returns keyInvalidated when isKeyValid returns false', () async {
        when(() => secureProvider.isKeyValid(tag: biometricKeyTag)).thenAnswer((_) async => false);

        final result = await dsLocker.determineBiometricState(
          biometricKeyTag: biometricKeyTag,
        );

        expect(result, BiometricState.keyInvalidated);
        verify(() => secureProvider.isKeyValid(tag: biometricKeyTag)).called(1);
      });

      test('returns enabled when isKeyValid returns true', () async {
        when(() => secureProvider.isKeyValid(tag: biometricKeyTag)).thenAnswer((_) async => true);

        final result = await dsLocker.determineBiometricState(
          biometricKeyTag: biometricKeyTag,
        );

        expect(result, BiometricState.enabled);
      });

      test('returns enabled without key check when biometricKeyTag is null', () async {
        final result = await dsLocker.determineBiometricState();

        expect(result, BiometricState.enabled);
        verifyNever(() => secureProvider.isKeyValid(tag: any(named: 'tag')));
      });

      test('returns tpmUnsupported when TPM is unsupported', () async {
        when(() => secureProvider.getTPMStatus()).thenAnswer((_) async => TPMStatus.unsupported);

        final result = await dsLocker.determineBiometricState();

        expect(result, BiometricState.tpmUnsupported);
      });

      test('returns tpmVersionIncompatible when TPM version is unsupported', () async {
        when(() => secureProvider.getTPMStatus()).thenAnswer((_) async => TPMStatus.tpmVersionUnsupported);

        final result = await dsLocker.determineBiometricState();

        expect(result, BiometricState.tpmVersionIncompatible);
      });

      test('returns hardwareUnavailable when biometric status is unsupported', () async {
        when(() => secureProvider.getBiometryStatus()).thenAnswer((_) async => BiometricStatus.unsupported);

        final result = await dsLocker.determineBiometricState();

        expect(result, BiometricState.hardwareUnavailable);
      });

      test('returns hardwareUnavailable when biometric status is deviceNotPresent', () async {
        when(() => secureProvider.getBiometryStatus()).thenAnswer((_) async => BiometricStatus.deviceNotPresent);

        final result = await dsLocker.determineBiometricState();

        expect(result, BiometricState.hardwareUnavailable);
      });

      test('returns hardwareUnavailable when biometric status is deviceBusy', () async {
        when(() => secureProvider.getBiometryStatus()).thenAnswer((_) async => BiometricStatus.deviceBusy);

        final result = await dsLocker.determineBiometricState();

        expect(result, BiometricState.hardwareUnavailable);
      });

      test('returns notEnrolled when user has not configured biometric', () async {
        when(() => secureProvider.getBiometryStatus()).thenAnswer((_) async => BiometricStatus.notConfiguredForUser);

        final result = await dsLocker.determineBiometricState();

        expect(result, BiometricState.notEnrolled);
      });

      test('returns disabledByPolicy when biometric is disabled by policy', () async {
        when(() => secureProvider.getBiometryStatus()).thenAnswer((_) async => BiometricStatus.disabledByPolicy);

        final result = await dsLocker.determineBiometricState();

        expect(result, BiometricState.disabledByPolicy);
      });

      test('returns securityUpdateRequired when Android security update is required', () async {
        when(
          () => secureProvider.getBiometryStatus(),
        ).thenAnswer((_) async => BiometricStatus.androidBiometricErrorSecurityUpdateRequired);

        final result = await dsLocker.determineBiometricState();

        expect(result, BiometricState.securityUpdateRequired);
      });

      test('returns availableButDisabled when biometric is not enabled in app settings', () async {
        when(() => dsStorage.isBiometricEnabled).thenAnswer((_) async => false);

        final result = await dsLocker.determineBiometricState();

        expect(result, BiometricState.availableButDisabled);
        verifyNever(() => secureProvider.isKeyValid(tag: any(named: 'tag')));
      });
    });
  });
}
