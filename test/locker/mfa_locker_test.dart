import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:biometric_cipher/data/biometric_status.dart';
import 'package:biometric_cipher/data/tpm_status.dart';
import 'package:locker/erasable/erasable.dart';
import 'package:locker/locker/locker.dart';
import 'package:locker/locker/locker_transaction.dart';
import 'package:locker/locker/mfa_locker.dart';
import 'package:locker/locker/models/biometric_state.dart';
import 'package:locker/locker/models/exceptions/locker_exception.dart';
import 'package:locker/security/models/biometric_config.dart';
import 'package:locker/security/models/exceptions/biometric_exception.dart';
import 'package:locker/storage/models/data/origin.dart';
import 'package:locker/storage/models/domain/entry_add_input.dart';
import 'package:locker/storage/models/domain/entry_id.dart';
import 'package:locker/storage/models/domain/entry_meta.dart';
import 'package:locker/storage/models/domain/entry_update_input.dart';
import 'package:locker/storage/models/exceptions/decrypt_failed_exception.dart';
import 'package:locker/storage/models/exceptions/storage_exception.dart';
import 'package:locker/storage/storage_transaction.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../mocks/mock_bio_cipher_func.dart';
import '../mocks/mock_biometric_cipher_provider.dart';
import '../mocks/mock_encrypted_storage.dart';
import '../mocks/mock_file.dart';
import '../mocks/mock_password_cipher_func.dart';
import '../mocks/mock_storage_transaction.dart';
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
      StorageTransaction(
        data: await _StorageHelpers.createStorageData(),
        masterKey: _StorageHelpers.createErasable(),
      ),
    );
  });

  group('MFALocker', () {
    late MockEncryptedStorage storage;
    late MockStorageTransaction changeSet;
    late MFALocker locker;

    setUp(() async {
      storage = MockEncryptedStorage();
      changeSet = MockStorageTransaction();

      locker = MFALocker(
        file: MockFile(),
        storage: storage,
      );

      when(() => storage.isInitialized).thenAnswer((_) async => true);
      when(() => storage.lockTimeout).thenAnswer((_) async => _Helpers.lockTimeout.inMilliseconds);
      when(() => storage.openTransaction(cipherFunc: any(named: 'cipherFunc'))).thenAnswer((_) async => changeSet);
      when(() => storage.closeTransaction(any())).thenAnswer((_) async {});
      when(() => changeSet.readAllMeta()).thenAnswer((_) async => <EntryId, EntryMeta>{});
      when(() => changeSet.erase()).thenAnswer((_) {});
    });

    tearDown(() async {
      locker.dispose();
    });

    group('getters', () {
      test('stateStream starts with "locked"', () async {
        expect(locker.stateStream.value, LockerState.locked);
      });

      test('isStorageInitialized returns data from storage', () async {
        // Act
        final result = await locker.isStorageInitialized;

        // Assert
        expect(result, isTrue);
        verify(() => storage.isInitialized).called(1);
      });

      test('isBiometricEnabled returns data from storage', () async {
        // Arrange
        when(() => storage.isBiometricEnabled).thenAnswer((_) async => true);

        // Act
        final result = await locker.isBiometricEnabled;

        // Assert
        expect(result, isTrue);
        verify(() => storage.isBiometricEnabled).called(1);
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
        expect(
          () => locker.allMeta,
          throwsA(isLockerError(LockerExceptionType.notUnlocked)),
        );
      });

      test('allMeta is unmodifiable', () async {
        // Arrange
        _Helpers.stubReadAllMeta(changeSet);
        await locker.loadAllMeta(_Helpers.createMockPasswordCipherFunc());

        // Act & Assert: the cache is shared with the locker, so mutating it must fail.
        expect(
          () => locker.allMeta[EntryId('new')] = _StorageHelpers.createEntryMeta(),
          throwsUnsupportedError,
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
        verifyNever(() => storage.closeTransaction(any()));

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
          throwsA(isStorageError(StorageExceptionType.alreadyInitialized)),
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

      test('rejects a non-positive timeout before touching the storage', () async {
        // Arrange
        final pwd = _Helpers.createMockPasswordCipherFunc();
        final meta = _StorageHelpers.createEntryMeta();
        final value = _StorageHelpers.createEntryValue();
        final entry = EntryAddInput(meta: meta, value: value);

        // Act & Assert: the same error type as in updateLockTimeout, before any storage call.
        await expectLater(
          () => locker.init(
            passwordCipherFunc: pwd,
            initialEntries: [entry],
            lockTimeout: Duration.zero,
          ),
          throwsA(isLockerError(LockerExceptionType.invalidArgument)),
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

      test('erases the inputs when the locker is locked while init is queued', () async {
        // Arrange: a transaction occupies the lane, init queues behind it.
        final laneCipher = _Helpers.createMockBioCipherFunc();
        final laneGate = Completer<void>();
        final txnFuture = locker.withTransaction(laneCipher, (txn) => laneGate.future);

        final pwd = _Helpers.createMockPasswordCipherFunc();
        final meta = _StorageHelpers.createEntryMeta();
        final value = _StorageHelpers.createEntryValue();

        final initFuture = locker.init(
          passwordCipherFunc: pwd,
          initialEntries: [EntryAddInput(meta: meta, value: value)],
          lockTimeout: _Helpers.lockTimeout,
        );
        await Future<void>.delayed(const Duration(milliseconds: 25));

        // Act
        locker.lock();
        laneGate.complete();

        // Assert: the queued init fails and its inputs are erased.
        await expectLater(initFuture, throwsA(isLockerError(LockerExceptionType.locked)));
        await expectLater(txnFuture, throwsA(isLockerError(LockerExceptionType.locked)));
        _Helpers.verifyErasedAll([pwd, meta, value]);
      });

      test('does not unlock the locker locked while the storage is being written', () async {
        // Arrange
        final pwd = _Helpers.createMockPasswordCipherFunc();
        final meta = _StorageHelpers.createEntryMeta();
        final value = _StorageHelpers.createEntryValue();
        final entry = EntryAddInput(meta: meta, value: value);
        final writeCompleter = Completer<void>();

        when(() => storage.isInitialized).thenAnswer((_) async => false);
        when(
          () => storage.init(
            passwordCipherFunc: pwd,
            initialEntries: [entry],
            lockTimeout: _Helpers.lockTimeout.inMilliseconds,
          ),
        ).thenAnswer((_) {
          // The write is in flight and the file is already there, so the
          // continuation would load metadata if it were not cancelled.
          when(() => storage.isInitialized).thenAnswer((_) async => true);

          return writeCompleter.future;
        });

        final initFuture = locker.init(
          passwordCipherFunc: pwd,
          initialEntries: [entry],
          lockTimeout: _Helpers.lockTimeout,
        );
        await Future<void>.delayed(const Duration(milliseconds: 25));

        // Act: the user locks the locker while the storage write is in flight.
        locker.lock();
        writeCompleter.complete();

        // Assert: lock() wins, the locker is never unlocked and the inputs are erased.
        await expectLater(initFuture, throwsA(isLockerError(LockerExceptionType.locked)));
        expect(locker.stateStream.value, LockerState.locked);
        verifyNever(() => storage.openTransaction(cipherFunc: any(named: 'cipherFunc')));
        _Helpers.verifyErasedAll([pwd, meta, value]);
      });

      test('does not cache metadata when the locker is disposed while the storage is being written', () async {
        // Arrange
        final pwd = _Helpers.createMockPasswordCipherFunc();
        final meta = _StorageHelpers.createEntryMeta();
        final value = _StorageHelpers.createEntryValue();
        final entry = EntryAddInput(meta: meta, value: value);
        final writeCompleter = Completer<void>();

        when(() => storage.isInitialized).thenAnswer((_) async => false);
        when(
          () => storage.init(
            passwordCipherFunc: pwd,
            initialEntries: [entry],
            lockTimeout: _Helpers.lockTimeout.inMilliseconds,
          ),
        ).thenAnswer((_) {
          // The write is in flight and the file is already there, so the
          // continuation would load metadata if it were not cancelled.
          when(() => storage.isInitialized).thenAnswer((_) async => true);

          return writeCompleter.future;
        });

        final initFuture = locker.init(
          passwordCipherFunc: pwd,
          initialEntries: [entry],
          lockTimeout: _Helpers.lockTimeout,
        );
        await Future<void>.delayed(const Duration(milliseconds: 25));

        // Act: the locker is disposed while the storage write is in flight.
        locker.dispose();
        writeCompleter.complete();

        // Assert: no metadata is loaded into the disposed locker and nothing leaks.
        await expectLater(initFuture, throwsA(isLockerError(LockerExceptionType.locked)));
        verifyNever(() => storage.openTransaction(cipherFunc: any(named: 'cipherFunc')));
        _Helpers.verifyErasedAll([pwd, meta, value]);
      });
    });

    group('loadAllMeta', () {
      test('unlocks, loads meta and persists nothing', () async {
        // Arrange
        final cipher = _Helpers.createMockPasswordCipherFunc();
        final readAllMeta = _Helpers.stubReadAllMeta(changeSet);

        // Act
        await locker.loadAllMeta(cipher);

        // Assert
        verify(() => storage.openTransaction(cipherFunc: cipher)).called(1);
        verify(() => changeSet.readAllMeta()).called(1);
        verify(() => changeSet.erase()).called(1);
        verifyNever(() => storage.closeTransaction(any()));

        expect(locker.stateStream.value, LockerState.unlocked);
        expect(locker.allMeta, equals(readAllMeta));

        _Helpers.verifyErased(cipher);
      });

      test('throws when storage not initialized', () async {
        // Arrange
        when(() => storage.isInitialized).thenAnswer((_) async => false);
        final cipher = _Helpers.createMockPasswordCipherFunc();

        // Act & Assert
        await expectLater(
          () => locker.loadAllMeta(cipher),
          throwsA(isStorageError(StorageExceptionType.notInitialized)),
        );

        verifyNever(() => storage.openTransaction(cipherFunc: any(named: 'cipherFunc')));
        _Helpers.verifyErased(cipher);
      });

      test('erases the working copy and stays locked when the metadata read fails', () async {
        // Arrange
        final cipher = _Helpers.createMockPasswordCipherFunc();
        when(() => changeSet.readAllMeta()).thenThrow(StorageException.invalidStorage());

        // Act & Assert
        await expectLater(
          () => locker.loadAllMeta(cipher),
          throwsA(isStorageError(StorageExceptionType.invalidStorage)),
        );

        verify(() => changeSet.erase()).called(1);
        expect(locker.stateStream.value, LockerState.locked);
        _Helpers.verifyErased(cipher);
      });

      test('lock during the metadata read erases the loaded meta and stays locked', () async {
        // Arrange
        final cipher = _Helpers.createMockPasswordCipherFunc();
        final meta = _StorageHelpers.createEntryMeta([1]);
        final readGate = Completer<Map<EntryId, EntryMeta>>();
        when(() => changeSet.readAllMeta()).thenAnswer((_) => readGate.future);

        // Act: the metadata read is in flight when the user locks.
        final future = locker.loadAllMeta(cipher);
        await Future<void>.delayed(const Duration(milliseconds: 25));
        locker.lock();
        readGate.complete({EntryId('a'): meta});

        // Assert: the loaded meta is erased and the locker is not unlocked.
        await expectLater(future, throwsA(isLockerError(LockerExceptionType.locked)));
        expect(meta.isErased, isTrue);
        verify(() => changeSet.erase()).called(1);
        expect(locker.stateStream.value, LockerState.locked);
        expect(() => locker.allMeta, throwsA(isLockerError(LockerExceptionType.notUnlocked)));
      });

      test('does nothing if already unlocked', () async {
        // Arrange
        final cipher = _Helpers.createMockPasswordCipherFunc();
        _Helpers.stubReadAllMeta(changeSet);
        await locker.loadAllMeta(cipher);

        clearInteractions(storage);
        clearInteractions(changeSet);

        // Act
        await locker.loadAllMeta(cipher);

        // Assert
        verifyNever(() => changeSet.readAllMeta());
        verifyNever(() => storage.openTransaction(cipherFunc: any(named: 'cipherFunc')));
        expect(locker.stateStream.value, LockerState.unlocked);
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
        expect(() => locker.allMeta, throwsA(isLockerError(LockerExceptionType.notUnlocked)));
        _Helpers.verifyErased(metaRef);
      });

      test('lock does nothing when locked', () async {
        // Act
        locker.lock();

        // Assert
        expect(locker.stateStream.value, LockerState.locked);
      });

      test('lock after dispose is a no-op', () async {
        // Arrange
        locker.dispose();

        // Act & Assert: the state stream is closed, so lock() must not emit.
        expect(locker.lock, returnsNormally);
        expect(locker.stateStream.value, LockerState.locked);
      });
    });

    group('dispose', () {
      test('erases the cached metadata', () async {
        // Arrange
        const entryId = 'entryId';
        _Helpers.stubReadAllMeta(changeSet, id: entryId);
        await locker.loadAllMeta(_Helpers.createMockPasswordCipherFunc());
        final metaRef = locker.allMeta[EntryId(entryId)]!;

        // Act
        locker.dispose();

        // Assert
        expect(metaRef.isErased, isTrue);
      });

      test('an operation after dispose fails with a locked error', () async {
        // Arrange
        _Helpers.stubReadAllMeta(changeSet);
        await locker.loadAllMeta(_Helpers.createMockPasswordCipherFunc());
        locker.dispose();
        clearInteractions(storage);

        // Act & Assert: dispose is terminal, so the storage is not touched.
        await expectLater(
          locker.readValue(id: EntryId('a'), cipherFunc: _Helpers.createMockPasswordCipherFunc()),
          throwsA(isLockerError(LockerExceptionType.locked)),
        );
        await expectLater(
          locker.loadAllMeta(_Helpers.createMockPasswordCipherFunc()),
          throwsA(isLockerError(LockerExceptionType.locked)),
        );
        verifyNever(() => storage.openTransaction(cipherFunc: any(named: 'cipherFunc')));
      });

      test('allMeta throws after dispose even when it was unlocked', () async {
        // Arrange
        _Helpers.stubReadAllMeta(changeSet);
        await locker.loadAllMeta(_Helpers.createMockPasswordCipherFunc());

        // Act
        locker.dispose();

        // Assert
        expect(() => locker.allMeta, throwsA(isLockerError(LockerExceptionType.notUnlocked)));
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

      test('withTransaction unlocks once, loads meta and runs the body', () async {
        // Arrange
        var bodyRan = false;

        // Act
        await locker.withTransaction(cipher, (txn) async {
          bodyRan = true;
        });

        // Assert
        expect(bodyRan, isTrue);
        expect(locker.stateStream.value, LockerState.unlocked);
        verify(() => storage.openTransaction(cipherFunc: cipher)).called(1);
        verify(() => changeSet.readAllMeta()).called(1);
      });

      test('the second withTransaction waits for the first one to finish', () async {
        // Arrange
        var openCalls = 0;
        when(() => storage.openTransaction(cipherFunc: any(named: 'cipherFunc'))).thenAnswer((_) async {
          openCalls++;

          return changeSet;
        });

        final firstGate = Completer<void>();
        var secondRan = false;

        // Act: the second body queues up behind the first one.
        final firstFuture = locker.withTransaction(cipher, (txn) => firstGate.future);
        final secondFuture = locker.withTransaction(cipher, (txn) async {
          secondRan = true;
        });
        await Future<void>.delayed(const Duration(milliseconds: 25));

        // Assert: it is still waiting and did not open a second change set.
        expect(secondRan, isFalse);
        expect(openCalls, 1);

        firstGate.complete();
        await firstFuture;
        await secondFuture;

        expect(secondRan, isTrue);
        expect(openCalls, 2);
      });

      test('withTransaction throws when storage is not initialized', () async {
        // Arrange
        when(() => storage.isInitialized).thenAnswer((_) async => false);

        // Act & Assert
        await expectLater(
          locker.withTransaction(cipher, (_) async {}),
          throwsA(isStorageError(StorageExceptionType.notInitialized)),
        );
        verifyNever(() => storage.openTransaction(cipherFunc: any(named: 'cipherFunc')));
      });

      test('operations run on the change set without a second unlock', () async {
        // Arrange
        when(() => changeSet.readValue(any())).thenAnswer((_) async => _StorageHelpers.createEntryValue([9]));
        when(() => changeSet.updateEntry(any())).thenAnswer((_) async {});

        // Act
        await locker.withTransaction(cipher, (txn) async {
          await txn.readValue(EntryId('a'));
          await txn.update(EntryUpdateInput(id: EntryId('a'), value: _StorageHelpers.createEntryValue([2])));
        });

        // Assert
        verify(() => storage.openTransaction(cipherFunc: cipher)).called(1);
        verify(() => changeSet.readValue(EntryId('a'))).called(1);
        verify(() => changeSet.updateEntry(any())).called(1);
      });

      test('write erases the meta when the body throws', () async {
        // Arrange
        final expectedId = EntryId('new');
        final metaToAdd = _StorageHelpers.createEntryMeta([5]);
        when(() => changeSet.addEntry(any())).thenAnswer((_) async => expectedId);

        // Act & Assert
        await expectLater(
          locker.withTransaction(cipher, (txn) async {
            final id = await txn.write(
              EntryAddInput(meta: metaToAdd, value: _StorageHelpers.createEntryValue([1])),
            );

            expect(id, expectedId);
            verify(() => changeSet.addEntry(any())).called(1);

            throw StorageException.other('boom');
          }),
          throwsA(isA<StorageException>()),
        );

        expect(locker.allMeta, isNot(contains(expectedId)));
        expect(metaToAdd.isErased, isTrue);
      });

      test('write applies meta to the cache on commit', () async {
        // Arrange
        final expectedId = EntryId('new');
        final metaToAdd = _StorageHelpers.createEntryMeta([5]);
        when(() => changeSet.addEntry(any())).thenAnswer((_) async => expectedId);

        // Act
        await locker.withTransaction(cipher, (txn) async {
          await txn.write(
            EntryAddInput(meta: metaToAdd, value: _StorageHelpers.createEntryValue([1])),
          );
        });

        // Assert
        expect(locker.allMeta[expectedId], same(metaToAdd));
        expect(metaToAdd.isErased, isFalse);
      });

      test('write erases the value and hands the meta over to the transaction', () async {
        // Arrange
        final meta = _StorageHelpers.createEntryMeta([5]);
        final value = _StorageHelpers.createEntryValue([1]);
        when(() => changeSet.addEntry(any())).thenAnswer((_) async => EntryId('new'));

        // Act
        await locker.withTransaction(cipher, (txn) async {
          await txn.write(EntryAddInput(meta: meta, value: value));

          // The value is consumed immediately, the meta is owned by the
          // transaction until the body finishes.
          expect(value.isErased, isTrue);
          expect(meta.isErased, isFalse);
        });

        // Assert: the committed meta is not erased.
        expect(meta.isErased, isFalse);
      });

      test('write erases both value and meta when the operation fails', () async {
        // Arrange
        final meta = _StorageHelpers.createEntryMeta([5]);
        final value = _StorageHelpers.createEntryValue([1]);
        when(() => changeSet.addEntry(any())).thenThrow(StorageException.other('boom'));

        // Act & Assert
        await expectLater(
          locker.withTransaction(cipher, (txn) => txn.write(EntryAddInput(meta: meta, value: value))),
          throwsA(isA<StorageException>()),
        );
        expect(value.isErased, isTrue);
        expect(meta.isErased, isTrue);
      });

      test('update erases the value and keeps the meta until commit', () async {
        // Arrange
        final meta = _StorageHelpers.createEntryMeta([5]);
        final value = _StorageHelpers.createEntryValue([1]);
        when(() => changeSet.updateEntry(any())).thenAnswer((_) async {});

        // Act
        await locker.withTransaction(cipher, (txn) async {
          await txn.update(EntryUpdateInput(id: EntryId('a'), meta: meta, value: value));

          expect(value.isErased, isTrue);
          expect(meta.isErased, isFalse);
        });

        // Assert: the committed meta is not erased.
        expect(meta.isErased, isFalse);
      });

      test('update erases both value and meta when the operation fails', () async {
        // Arrange
        final meta = _StorageHelpers.createEntryMeta([5]);
        final value = _StorageHelpers.createEntryValue([1]);
        when(() => changeSet.updateEntry(any())).thenThrow(StorageException.other('boom'));

        // Act & Assert
        await expectLater(
          locker.withTransaction(
            cipher,
            (txn) => txn.update(EntryUpdateInput(id: EntryId('a'), meta: meta, value: value)),
          ),
          throwsA(isA<StorageException>()),
        );
        expect(value.isErased, isTrue);
        expect(meta.isErased, isTrue);
      });

      test('delete removes the entry from the cache on commit', () async {
        // Arrange
        when(() => changeSet.deleteEntry(any())).thenAnswer((_) async {});
        EntryMeta? committedMeta;

        // Act
        await locker.withTransaction(cipher, (txn) async {
          committedMeta = locker.allMeta[EntryId('a')];

          await txn.delete(EntryId('a'));
        });

        // Assert
        expect(locker.allMeta, isNot(contains(EntryId('a'))));
        expect(committedMeta?.isErased, isTrue);
        verify(() => changeSet.deleteEntry(EntryId('a'))).called(1);
      });

      test('delete keeps the committed meta when the body throws', () async {
        // Arrange
        when(() => changeSet.deleteEntry(any())).thenAnswer((_) async {});
        EntryMeta? committedMeta;

        // Act & Assert
        await expectLater(
          locker.withTransaction(cipher, (txn) async {
            committedMeta = locker.allMeta[EntryId('a')];
            await txn.delete(EntryId('a'));

            throw StorageException.other('boom');
          }),
          throwsA(isA<StorageException>()),
        );

        expect(locker.allMeta, contains(EntryId('a')));
        expect(committedMeta?.isErased, isFalse);
      });

      test('update applies the new meta on commit and erases the replaced one', () async {
        // Arrange
        final newMeta = _StorageHelpers.createEntryMeta([5]);
        when(() => changeSet.updateEntry(any())).thenAnswer((_) async {});
        EntryMeta? replacedMeta;

        // Act
        await locker.withTransaction(cipher, (txn) async {
          replacedMeta = locker.allMeta[EntryId('a')];

          await txn.update(EntryUpdateInput(id: EntryId('a'), meta: newMeta));
        });

        // Assert
        expect(locker.allMeta[EntryId('a')], same(newMeta));
        expect(replacedMeta?.isErased, isTrue);
        expect(newMeta.isErased, isFalse);
      });

      test('update erases the new meta when the body throws', () async {
        // Arrange
        final newMeta = _StorageHelpers.createEntryMeta([5]);
        when(() => changeSet.updateEntry(any())).thenAnswer((_) async {});
        EntryMeta? committedMeta;

        // Act & Assert
        await expectLater(
          locker.withTransaction(cipher, (txn) async {
            committedMeta = locker.allMeta[EntryId('a')];
            await txn.update(EntryUpdateInput(id: EntryId('a'), meta: newMeta));

            throw StorageException.other('boom');
          }),
          throwsA(isA<StorageException>()),
        );

        expect(locker.allMeta[EntryId('a')], same(committedMeta));
        expect(committedMeta?.isErased, isFalse);
        expect(newMeta.isErased, isTrue);
      });

      test('delete ignores a not-found entry', () async {
        // Arrange
        when(() => changeSet.deleteEntry(any())).thenThrow(StorageException.entryNotFound());

        // Act & Assert
        await expectLater(
          locker.withTransaction(cipher, (txn) => txn.delete(EntryId('a'))),
          completes,
        );
      });

      test('commit persists the change set and erases keys', () async {
        // Act
        await locker.withTransaction(cipher, (_) async {});

        // Assert
        verify(() => storage.closeTransaction(changeSet)).called(1);
        verify(() => changeSet.erase()).called(1);

        // A new transaction is possible afterwards.
        final changeSet2 = MockStorageTransaction();
        when(() => storage.openTransaction(cipherFunc: any(named: 'cipherFunc'))).thenAnswer((_) async => changeSet2);
        when(() => changeSet2.erase()).thenAnswer((_) {});
        await expectLater(locker.withTransaction(cipher, (_) async {}), completes);
      });

      test('abort discards the change set without committing', () async {
        // Act & Assert
        await expectLater(
          locker.withTransaction(cipher, (txn) async {
            throw StorageException.other('boom');
          }),
          throwsA(isA<StorageException>()),
        );
        verifyNever(() => storage.closeTransaction(any()));
        verify(() => changeSet.erase()).called(1);
      });

      test('operations after the body throw a closed-transaction error', () async {
        // Arrange
        late LockerTransaction captured;
        await locker.withTransaction(cipher, (txn) async {
          captured = txn;
        });

        // Act & Assert
        await expectLater(
          captured.readValue(EntryId('a')),
          throwsA(isLockerError(LockerExceptionType.transactionClosed)),
        );
      });

      test('lock aborts the active transaction', () async {
        // Arrange
        final gate = Completer<void>();
        final bodyStarted = Completer<void>();
        final future = locker.withTransaction(cipher, (txn) {
          bodyStarted.complete();

          return gate.future;
        });
        await bodyStarted.future;

        // Act
        locker.lock();
        gate.complete();

        // Assert
        await expectLater(future, throwsA(isLockerError(LockerExceptionType.locked)));
        verify(() => changeSet.erase()).called(1);
      });

      test('lock during an in-flight commit lets the commit finish and discards it', () async {
        // Arrange: unlock first, then hold the next commit open.
        await locker.loadAllMeta(cipher);
        clearInteractions(changeSet);
        final meta = _StorageHelpers.createEntryMeta([5]);
        final commitGate = Completer<void>();
        when(() => storage.closeTransaction(any())).thenAnswer((_) => commitGate.future);
        when(() => changeSet.addEntry(any())).thenAnswer((_) async => EntryId('new'));

        // Act: the write reaches its commit, then the user locks.
        final writeFuture = locker.write(
          input: EntryAddInput(meta: meta, value: _StorageHelpers.createEntryValue([1])),
          cipherFunc: cipher,
        );
        await Future<void>.delayed(const Duration(milliseconds: 25));
        locker.lock();
        commitGate.complete();

        // Assert: the lock is reported and the working copy is erased once —
        // after the commit, never under it (which would corrupt the write).
        await expectLater(writeFuture, throwsA(isLockerError(LockerExceptionType.locked)));
        verify(() => changeSet.erase()).called(1);
        expect(locker.stateStream.value, LockerState.locked);
      });

      test('dispose while the storage is opening does not unlock the disposed locker', () async {
        // Arrange: unlock first, then hold the next open.
        await locker.loadAllMeta(cipher);
        final openGate = Completer<StorageTransaction>();
        when(() => storage.openTransaction(cipherFunc: any(named: 'cipherFunc'))).thenAnswer((_) => openGate.future);

        // Act: the write starts opening the storage, then the locker is disposed.
        final writeFuture = locker.write(
          input: EntryAddInput(
            meta: _StorageHelpers.createEntryMeta([5]),
            value: _StorageHelpers.createEntryValue([1]),
          ),
          cipherFunc: cipher,
        );
        await Future<void>.delayed(const Duration(milliseconds: 25));
        locker.dispose();
        openGate.complete(changeSet);

        // Assert: the body never runs and the disposed locker is not unlocked.
        await expectLater(writeFuture, throwsA(isLockerError(LockerExceptionType.locked)));
        verifyNever(() => changeSet.addEntry(any()));
      });

      test('a queued operation fails and does not run when the locker is locked', () async {
        // Arrange
        var storageRead = false;
        when(() => changeSet.readValue(any())).thenAnswer((_) async {
          storageRead = true;

          return _StorageHelpers.createEntryValue([1]);
        });

        final gate = Completer<void>();
        final txnFuture = locker.withTransaction(cipher, (txn) => gate.future);

        // Act: the one-shot queues behind the transaction, then the user locks.
        final readFuture = locker.readValue(id: EntryId('a'), cipherFunc: cipher);
        await Future<void>.delayed(const Duration(milliseconds: 25));
        locker.lock();
        gate.complete();

        // Assert: the queued operation fails instead of resurrecting the locker.
        await expectLater(readFuture, throwsA(isLockerError(LockerExceptionType.locked)));
        await expectLater(txnFuture, throwsA(isLockerError(LockerExceptionType.locked)));
        expect(storageRead, isFalse, reason: 'a queued operation must not reach storage after lock()');
        expect(locker.stateStream.value, LockerState.locked);
      });

      test('a queued transaction fails and does not run when the locker is disposed', () async {
        // Arrange
        final gate = Completer<void>();
        final firstFuture = locker.withTransaction(cipher, (txn) => gate.future);

        // Act
        final secondFuture = locker.withTransaction(cipher, (_) async {});
        await Future<void>.delayed(const Duration(milliseconds: 25));
        locker.dispose();
        gate.complete();

        // Assert
        await expectLater(secondFuture, throwsA(isLockerError(LockerExceptionType.locked)));
        await expectLater(firstFuture, throwsA(isLockerError(LockerExceptionType.locked)));
        verify(() => storage.openTransaction(cipherFunc: cipher)).called(1);
      });

      test('standalone operations are executed in FIFO order with a transaction', () async {
        // Arrange
        final order = <String>[];
        final gate = Completer<void>();
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

        final txnFuture = locker.withTransaction(cipher, (txn) async {
          await txn.readValue(EntryId('a'));
          await gate.future;
        });

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

        gate.complete();
        await txnFuture;
        await readFuture;
        await writeFuture;

        // Assert
        expect(order, ['first', 'second', 'third']);
      });

      test('withTransaction skips metadata reload when already unlocked', () async {
        // Arrange
        await locker.withTransaction(cipher, (_) async {});

        // Re-arm the mock so the second transaction starts from a clean slate.
        final changeSet2 = MockStorageTransaction();
        reset(storage);
        when(() => storage.isInitialized).thenAnswer((_) async => true);
        when(() => storage.openTransaction(cipherFunc: any(named: 'cipherFunc'))).thenAnswer((_) async => changeSet2);
        when(() => storage.closeTransaction(any())).thenAnswer((_) async {});
        when(() => changeSet2.readAllMeta()).thenAnswer((_) async => metas);
        when(() => changeSet2.erase()).thenAnswer((_) {});

        // Act
        await locker.withTransaction(cipher, (_) async {});

        // Assert
        verifyNever(() => changeSet2.readAllMeta());
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
        verify(() => storage.openTransaction(cipherFunc: cipher)).called(1);
        verify(() => storage.closeTransaction(changeSet)).called(1);
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
        verifyNever(() => storage.closeTransaction(any()));
        verify(() => changeSet.erase()).called(1);
      });

      test('locker.allMeta stays committed-only inside the body', () async {
        // Arrange
        final expectedId = EntryId('new');
        final metaToAdd = _StorageHelpers.createEntryMeta([5]);
        when(() => changeSet.addEntry(any())).thenAnswer((_) async => expectedId);
        when(() => changeSet.deleteEntry(any())).thenAnswer((_) async {});

        bool? lockerSawNewInside;

        // Act
        await locker.withTransaction(cipher, (txn) async {
          await txn.write(
            EntryAddInput(meta: metaToAdd, value: _StorageHelpers.createEntryValue([1])),
          );
          await txn.delete(EntryId('a'));
          lockerSawNewInside = locker.allMeta.containsKey(expectedId);
        });

        // Assert: the uncommitted overlay is invisible until the commit.
        expect(lockerSawNewInside, isFalse);

        // ...after the commit the overlay becomes the committed state.
        expect(locker.allMeta[expectedId], same(metaToAdd));
        expect(locker.allMeta, isNot(contains(EntryId('a'))));
      });

      test('uncommitted writes are discarded when the body throws', () async {
        // Arrange
        final expectedId = EntryId('new');
        final metaToAdd = _StorageHelpers.createEntryMeta([5]);
        when(() => changeSet.addEntry(any())).thenAnswer((_) async => expectedId);

        // Act & Assert
        await expectLater(
          locker.withTransaction(cipher, (txn) async {
            await txn.write(
              EntryAddInput(meta: metaToAdd, value: _StorageHelpers.createEntryValue([1])),
            );

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
          throwsA(isLockerError(LockerExceptionType.insideTransaction)),
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

        final gate = Completer<void>();
        final txnFuture = locker.withTransaction(cipher, (txn) => gate.future);

        // Act: a one-shot read starts while the transaction is open — it must
        // not reach storage until the transaction is finished.
        final readFuture = locker.readValue(id: EntryId('a'), cipherFunc: cipher);
        await Future<void>.delayed(const Duration(milliseconds: 25));
        expect(storageRead, isFalse, reason: 'one-shot read must wait for the transaction to finish');

        gate.complete();
        await txnFuture;
        await readFuture;

        // Assert
        expect(storageRead, isTrue, reason: 'after the transaction finishes the one-shot read proceeds');
      });

      test('a queued transaction erases its cipher when the locker is locked', () async {
        // Arrange
        final queuedCipher = _Helpers.createMockBioCipherFunc();
        final gate = Completer<void>();
        final firstFuture = locker.withTransaction(cipher, (txn) => gate.future);

        // Act: the second transaction queues behind the first one, then the locker is locked.
        final secondFuture = locker.withTransaction(queuedCipher, (_) async {});
        await Future<void>.delayed(const Duration(milliseconds: 25));
        locker.lock();
        gate.complete();

        // Assert: the queued transaction fails and its cipher is erased.
        await expectLater(secondFuture, throwsA(isLockerError(LockerExceptionType.locked)));
        await expectLater(firstFuture, throwsA(isLockerError(LockerExceptionType.locked)));
        _Helpers.verifyErased(queuedCipher);
      });

      test('withTransaction does not mask the body error when the locker is locked meanwhile', () async {
        // Act & Assert: lock() aborts the transaction, but the original body
        // error must still be the reported one.
        await expectLater(
          locker.withTransaction(cipher, (txn) async {
            locker.lock();

            throw StorageException.other('boom');
          }),
          throwsA(isA<StorageException>().having((e) => e.message, 'message', 'boom')),
        );
      });

      test('withTransaction reports the lock when the body completes but the locker was locked', () async {
        // Act & Assert
        await expectLater(
          locker.withTransaction(cipher, (txn) async {
            locker.lock();

            return 'done';
          }),
          throwsA(isLockerError(LockerExceptionType.locked)),
        );
      });

      test('a method of another locker can be called from a transaction body', () async {
        // Arrange: the second locker owns its own lane, so the zone of the
        // first locker's transaction must not block it.
        final otherStorage = MockEncryptedStorage();
        final otherChangeSet = MockStorageTransaction();
        final otherLocker = MFALocker(file: MockFile(), storage: otherStorage);

        when(() => otherStorage.isInitialized).thenAnswer((_) async => true);
        when(() => otherStorage.openTransaction(cipherFunc: any(named: 'cipherFunc')))
            .thenAnswer((_) async => otherChangeSet);
        when(() => otherStorage.closeTransaction(any())).thenAnswer((_) async {});
        when(() => otherChangeSet.readAllMeta()).thenAnswer((_) async => <EntryId, EntryMeta>{});
        when(() => otherChangeSet.readValue(any())).thenAnswer((_) async => _StorageHelpers.createEntryValue([7]));
        when(() => otherChangeSet.erase()).thenAnswer((_) {});
        addTearDown(otherLocker.dispose);

        when(() => changeSet.readValue(any())).thenAnswer((_) async => _StorageHelpers.createEntryValue([1]));

        // Act
        final value = await locker.withTransaction(cipher, (txn) async {
          await txn.readValue(EntryId('a'));

          return otherLocker.readValue(id: EntryId('b'), cipherFunc: _Helpers.createMockBioCipherFunc());
        });

        // Assert
        expect(value.bytes, orderedEquals([7]));
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
        await locker.loadAllMeta(_Helpers.createMockPasswordCipherFunc());

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
        await locker.loadAllMeta(_Helpers.createMockPasswordCipherFunc());

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
          throwsA(isStorageError(StorageExceptionType.notInitialized)),
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
        await locker.loadAllMeta(_Helpers.createMockPasswordCipherFunc());

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
        await locker.loadAllMeta(_Helpers.createMockPasswordCipherFunc());

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
          throwsA(isStorageError(StorageExceptionType.notInitialized)),
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
        await locker.loadAllMeta(_Helpers.createMockPasswordCipherFunc());

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
        await locker.loadAllMeta(_Helpers.createMockPasswordCipherFunc());

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
          throwsA(isStorageError(StorageExceptionType.notInitialized)),
        );

        verifyNever(() => changeSet.deleteEntry(any()));
        _Helpers.verifyErased(cipher);
      });

      test('rethrows on storage error', () async {
        // Arrange
        final cipher = _Helpers.createMockPasswordCipherFunc();
        final id = EntryId('to-delete');

        _Helpers.stubReadAllMeta(changeSet, id: id.value);

        await locker.loadAllMeta(_Helpers.createMockPasswordCipherFunc());
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

        await locker.loadAllMeta(_Helpers.createMockPasswordCipherFunc());
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
        await locker.loadAllMeta(_Helpers.createMockPasswordCipherFunc());

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
        await locker.loadAllMeta(_Helpers.createMockPasswordCipherFunc());

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
        await locker.loadAllMeta(_Helpers.createMockPasswordCipherFunc());

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
          throwsA(isStorageError(StorageExceptionType.notInitialized)),
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
        await locker.loadAllMeta(_Helpers.createMockPasswordCipherFunc());

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
        await locker.loadAllMeta(_Helpers.createMockPasswordCipherFunc());

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
        await locker.loadAllMeta(_Helpers.createMockPasswordCipherFunc());

        when(() => changeSet.addOrReplaceWrap(newWrapFunc: any(named: 'newWrapFunc'))).thenThrow(Exception('test'));

        // Act & Assert
        await expectLater(
          () => locker.changePassword(newCipherFunc: newPwd, existingCipherFunc: oldPwd),
          throwsException,
        );

        _Helpers.verifyErasedAll([oldPwd, newPwd]);
      });
    });

    group('updateLockTimeout', () {
      test('passes the timeout to the storage transaction and commits', () async {
        // Arrange
        final cipher = _Helpers.createMockPasswordCipherFunc();
        _Helpers.stubReadAllMeta(changeSet);
        await locker.loadAllMeta(_Helpers.createMockPasswordCipherFunc());
        when(() => changeSet.updateLockTimeout(any())).thenAnswer((_) async {});

        // Act
        await locker.updateLockTimeout(lockTimeout: _Helpers.lockTimeout, cipherFunc: cipher);

        // Assert
        verify(() => changeSet.updateLockTimeout(_Helpers.lockTimeout.inMilliseconds)).called(1);
        verify(() => storage.closeTransaction(changeSet)).called(1);
        _Helpers.verifyErased(cipher);
      });

      test('rejects a zero timeout before unwrapping', () async {
        // Arrange
        final cipher = _Helpers.createMockPasswordCipherFunc();

        // Act & Assert: an invalid value must not open a change set (no prompt).
        await expectLater(
          locker.updateLockTimeout(lockTimeout: Duration.zero, cipherFunc: cipher),
          throwsA(isLockerError(LockerExceptionType.invalidArgument)),
        );
        verifyNever(() => storage.openTransaction(cipherFunc: any(named: 'cipherFunc')));
        _Helpers.verifyErased(cipher);
      });

      test('rejects a sub-millisecond timeout before unwrapping', () async {
        // Arrange
        final cipher = _Helpers.createMockPasswordCipherFunc();

        // Act & Assert
        await expectLater(
          locker.updateLockTimeout(lockTimeout: const Duration(microseconds: 999), cipherFunc: cipher),
          throwsA(isLockerError(LockerExceptionType.invalidArgument)),
        );
        verifyNever(() => storage.openTransaction(cipherFunc: any(named: 'cipherFunc')));
        _Helpers.verifyErased(cipher);
      });
    });

    group('setupBiometry', () {
      const biometricKeyTag = 'test-bio-key-tag';

      late MockBiometricCipherProvider secureProvider;
      late MockEncryptedStorage tpStorage;
      late MockStorageTransaction tpChangeSet;
      late MFALocker tpLocker;

      setUp(() {
        secureProvider = MockBiometricCipherProvider();
        tpStorage = MockEncryptedStorage();
        tpChangeSet = MockStorageTransaction();

        tpLocker = MFALocker(
          file: MockFile(),
          storage: tpStorage,
          secureProvider: secureProvider,
        );

        when(() => tpStorage.isInitialized).thenAnswer((_) async => true);
        when(() => tpStorage.lockTimeout).thenAnswer((_) async => _Helpers.lockTimeout.inMilliseconds);
        when(() => tpStorage.openTransaction(cipherFunc: any(named: 'cipherFunc')))
            .thenAnswer((_) async => tpChangeSet);
        when(() => tpStorage.closeTransaction(any())).thenAnswer((_) async {});
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
      late MockStorageTransaction tpChangeSet;
      late MFALocker tpLocker;

      setUp(() {
        secureProvider = MockBiometricCipherProvider();
        tpStorage = MockEncryptedStorage();
        tpChangeSet = MockStorageTransaction();

        tpLocker = MFALocker(
          file: MockFile(),
          storage: tpStorage,
          secureProvider: secureProvider,
        );

        when(() => tpStorage.isInitialized).thenAnswer((_) async => true);
        when(() => tpStorage.lockTimeout).thenAnswer((_) async => _Helpers.lockTimeout.inMilliseconds);
        when(() => tpStorage.openTransaction(cipherFunc: any(named: 'cipherFunc')))
            .thenAnswer((_) async => tpChangeSet);
        when(() => tpStorage.closeTransaction(any())).thenAnswer((_) async {});
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

      test('completes when the locker is locked while the erase is in flight', () async {
        // Arrange
        final eraseCompleter = Completer<void>();
        when(() => storage.erase()).thenAnswer((_) => eraseCompleter.future);

        // Act
        final eraseFuture = locker.eraseStorage();
        await Future<void>.delayed(const Duration(milliseconds: 25));
        locker.lock();
        eraseCompleter.complete();

        // Assert: the erase completed, a concurrent lock is not reported as a failure.
        await expectLater(eraseFuture, completes);
        expect(locker.stateStream.value, LockerState.locked);
      });

      test('completes when the locker is disposed while the erase is in flight', () async {
        // Arrange
        final eraseCompleter = Completer<void>();
        when(() => storage.erase()).thenAnswer((_) => eraseCompleter.future);

        // Act
        final eraseFuture = locker.eraseStorage();
        await Future<void>.delayed(const Duration(milliseconds: 25));
        locker.dispose();
        eraseCompleter.complete();

        // Assert
        await expectLater(eraseFuture, completes);
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
        when(() => storage.openTransaction(cipherFunc: oldPwd)).thenAnswer((_) async {
          if (wrapStored) {
            throw const DecryptFailedException();
          }

          return changeSet;
        });
        when(() => storage.openTransaction(cipherFunc: newPwd)).thenAnswer((_) async => changeSet);

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

        // Assert: every API boundary erases its own cipher exactly once.
        verify(() => oldPwd.erase()).called(3);
        verify(() => newPwd.erase()).called(2);
        verify(() => changeSet.addOrReplaceWrap(newWrapFunc: newPwd)).called(1);
        verify(() => storage.openTransaction(cipherFunc: oldPwd)).called(3);
        verify(() => storage.openTransaction(cipherFunc: newPwd)).called(1);
      });
    });

    group('configureBiometricCipher', () {
      test('passes the config to the secure provider', () async {
        // Arrange
        final provider = MockBiometricCipherProvider();
        final config = const BiometricConfig(
          promptTitle: 'title',
          promptSubtitle: 'subtitle',
          androidCancelButtonText: 'cancel',
          androidPromptDescription: 'description',
        );
        final lockerWithProvider = MFALocker(file: MockFile(), storage: storage, secureProvider: provider);
        addTearDown(lockerWithProvider.dispose);
        when(() => provider.configure(config)).thenAnswer((_) async {});

        // Act
        await lockerWithProvider.configureBiometricCipher(config);

        // Assert
        verify(() => provider.configure(config)).called(1);
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
