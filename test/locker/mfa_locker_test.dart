import 'dart:async';
import 'dart:typed_data';

import 'package:locker/erasable/erasable.dart';
import 'package:locker/locker/locker.dart';
import 'package:locker/locker/mfa_locker.dart';
import 'package:locker/security/models/cipher_func.dart';
import 'package:locker/storage/models/data/origin.dart';
import 'package:locker/storage/models/domain/entry_add_input.dart';
import 'package:locker/storage/models/domain/entry_id.dart';
import 'package:locker/storage/models/domain/entry_meta.dart';
import 'package:locker/storage/models/domain/entry_update_input.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../mocks/mock_bio_cipher_func.dart';
import '../mocks/mock_biometric_cipher_provider.dart';
import '../mocks/mock_encrypted_storage.dart';
import '../mocks/mock_file.dart';
import '../mocks/mock_password_cipher_func.dart';
import '../storage/encrypted_storage_test_helpers.dart';

part 'mfa_locker_test_helpers.dart';

void main() {
  setUpAll(() {
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
  });

  group('MFALocker', () {
    late MockEncryptedStorage storage;
    late MFALocker locker;

    setUp(() async {
      storage = MockEncryptedStorage();

      locker = MFALocker(
        file: MockFile(),
        storage: storage,
      );

      when(() => storage.isInitialized).thenAnswer((_) async => true);
      when(() => storage.lockTimeout).thenAnswer((_) async => _Helpers.lockTimeout.inMilliseconds);
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

      test('salt returns null from storage', () async {
        // Arrange
        when(() => storage.salt).thenAnswer((_) async => null);

        // Act
        final result = await locker.salt;

        // Assert
        expect(result, isNull);
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

      test('lockTimeout throws when not set in storage', () async {
        // Arrange
        when(() => storage.lockTimeout).thenAnswer((_) async => null);

        // Act & Assert
        await expectLater(
          locker.lockTimeout,
          throwsA(isA<StateError>()),
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
        final readAllMeta = _Helpers.stubReadAllMeta(storage, pwd);

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
        verify(() => storage.readAllMeta(cipherFunc: pwd)).called(1);

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
        final readAllMeta = _Helpers.stubReadAllMeta(storage, cipher);

        // Act
        await locker.loadAllMeta(cipher);

        // Assert
        verify(() => storage.readAllMeta(cipherFunc: cipher)).called(1);
        expect(locker.stateStream.value, LockerState.unlocked);
        expect(locker.allMeta, equals(readAllMeta));

        _Helpers.verifyErased(cipher);
      });
    });

    group('loadAllMetaIfLocked', () {
      test('unlocks, loads meta', () async {
        // Arrange
        final cipher = _Helpers.createMockPasswordCipherFunc();
        final readAllMeta = _Helpers.stubReadAllMeta(storage, cipher);

        // Act
        await locker.loadAllMetaIfLocked(cipher);

        // Assert
        verify(() => storage.readAllMeta(cipherFunc: cipher)).called(1);

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

        verifyNever(() => storage.readAllMeta(cipherFunc: any(named: 'cipherFunc')));
      });

      test('does nothing if already unlocked', () async {
        // Arrange
        final cipher = _Helpers.createMockPasswordCipherFunc();
        _Helpers.stubReadAllMeta(storage, cipher);
        await locker.loadAllMetaIfLocked(cipher);

        clearInteractions(storage);

        // Act
        await locker.loadAllMetaIfLocked(cipher);

        // Assert
        verifyNever(() => storage.readAllMeta(cipherFunc: any(named: 'cipherFunc')));
      });
    });

    group('lock', () {
      test('clears cache and locks the locker', () async {
        // Arrange
        const entryId = 'entryId';
        final cipher = _Helpers.createMockPasswordCipherFunc();
        _Helpers.stubReadAllMeta(storage, cipher, id: entryId);

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

    group('write', () {
      test('updates cache and call the storage.addEntry', () async {
        // Arrange
        final cipher = _Helpers.createMockPasswordCipherFunc();
        final metaToAdd = _StorageHelpers.createEntryMeta([1, 2]);
        final valueToAdd = _StorageHelpers.createEntryValue();
        final expectedId = EntryId('id');
        final input = EntryAddInput(meta: metaToAdd, value: valueToAdd);

        _Helpers.stubReadAllMeta(storage, cipher);
        await locker.loadAllMeta(cipher);

        when(
          () => storage.addEntry(
            input: input,
            cipherFunc: cipher,
          ),
        ).thenAnswer((_) async => expectedId);

        // Act
        final result = await locker.write(
          input: input,
          cipherFunc: cipher,
        );

        // Assert
        verify(
          () => storage.addEntry(
            input: input,
            cipherFunc: cipher,
          ),
        ).called(1);

        expect(result, equals(expectedId));
        expect(locker.allMeta[expectedId], same(metaToAdd));

        _Helpers.verifyErasedAll([cipher, valueToAdd]);
      });

      test('replaces existing meta and erases previous one when id matches', () async {
        // Arrange
        final cipher = _Helpers.createMockPasswordCipherFunc();
        final id = EntryId('entryId');

        _Helpers.stubReadAllMeta(storage, cipher, id: id.value, metaBytes: [1, 2]);
        await locker.loadAllMeta(cipher);

        final oldMeta = locker.allMeta[id]!;
        final newMeta = _StorageHelpers.createEntryMeta([3, 4]);
        final newValue = _StorageHelpers.createEntryValue();
        final input = EntryAddInput(meta: newMeta, value: newValue);

        when(
          () => storage.addEntry(
            input: input,
            cipherFunc: cipher,
          ),
        ).thenAnswer((_) async => id);

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

        _Helpers.stubReadAllMeta(storage, cipher);

        when(
          () => storage.addEntry(
            input: input,
            cipherFunc: cipher,
          ),
        ).thenThrow(Exception('test'));

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

        verifyNever(
          () => storage.addEntry(
            input: any(named: 'input'),
            cipherFunc: any(named: 'cipherFunc'),
          ),
        );

        _Helpers.verifyErasedAll([cipher, value, meta]);
      });

      test('passes explicit id to storage.addEntry', () async {
        // Arrange
        final cipher = _Helpers.createMockPasswordCipherFunc();
        final meta = _StorageHelpers.createEntryMeta([1, 2]);
        final value = _StorageHelpers.createEntryValue();
        final explicitId = EntryId('my-custom-id');
        final input = EntryAddInput(meta: meta, value: value, id: explicitId);

        _Helpers.stubReadAllMeta(storage, cipher);
        await locker.loadAllMeta(cipher);

        when(
          () => storage.addEntry(
            input: input,
            cipherFunc: cipher,
          ),
        ).thenAnswer((_) async => explicitId);

        // Act
        final result = await locker.write(
          input: input,
          cipherFunc: cipher,
        );

        // Assert
        verify(
          () => storage.addEntry(
            input: input,
            cipherFunc: cipher,
          ),
        ).called(1);

        expect(result, equals(explicitId));
        expect(locker.allMeta[explicitId], same(meta));

        _Helpers.verifyErasedAll([cipher, value]);
      });
    });

    group('readValue', () {
      test('returns value and call the storage.readValue', () async {
        // Arrange
        final cipher = _Helpers.createMockPasswordCipherFunc();
        final id = EntryId('id');
        final value = _StorageHelpers.createEntryValue([1, 2, 3]);

        _Helpers.stubReadAllMeta(storage, cipher, id: id.value);
        await locker.loadAllMeta(cipher);

        when(
          () => storage.readValue(
            id: id,
            cipherFunc: cipher,
          ),
        ).thenAnswer((_) async => value);

        // Act
        final result = await locker.readValue(id: id, cipherFunc: cipher);

        // Assert
        expect(result, same(value));
        verify(() => storage.readValue(id: id, cipherFunc: cipher)).called(1);

        _Helpers.verifyErased(cipher);
      });

      test('rethrows on storage error', () async {
        // Arrange
        final cipher = _Helpers.createMockPasswordCipherFunc();
        _Helpers.stubReadAllMeta(storage, cipher);

        when(
          () => storage.readValue(
            id: any(named: 'id'),
            cipherFunc: cipher,
          ),
        ).thenThrow(Exception('test'));

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

        verifyNever(
          () => storage.readValue(
            id: any(named: 'id'),
            cipherFunc: any(named: 'cipherFunc'),
          ),
        );

        _Helpers.verifyErased(cipher);
      });
    });

    group('delete', () {
      test('removes entry from cache and erases meta', () async {
        // Arrange
        const existingId = 'idToDelete';

        final cipher = _Helpers.createMockPasswordCipherFunc();
        final id = EntryId(existingId);

        _Helpers.stubReadAllMeta(storage, cipher, id: existingId);
        await locker.loadAllMeta(cipher);

        final deletedMetaRef = locker.allMeta[id]!;

        when(
          () => storage.deleteEntry(
            id: id,
            cipherFunc: cipher,
          ),
        ).thenAnswer((_) async => true);

        // Act
        await locker.delete(id: id, cipherFunc: cipher);

        // Assert
        verify(() => storage.deleteEntry(id: id, cipherFunc: cipher)).called(1);
        expect(locker.allMeta.containsKey(id), isFalse);

        _Helpers.verifyErasedAll([cipher, deletedMetaRef]);
      });

      test('leaves cache unchanged when deleting non-existing id', () async {
        // Arrange
        final missingId = EntryId('missing');
        final cipher = _Helpers.createMockPasswordCipherFunc();

        _Helpers.stubReadAllMeta(storage, cipher);
        await locker.loadAllMeta(cipher);

        final metaBefore = locker.allMeta;

        when(
          () => storage.deleteEntry(
            id: missingId,
            cipherFunc: cipher,
          ),
        ).thenAnswer((_) async => false);

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

        verifyNever(
          () => storage.deleteEntry(
            id: any(named: 'id'),
            cipherFunc: any(named: 'cipherFunc'),
          ),
        );
        _Helpers.verifyErased(cipher);
      });

      test('rethrows on storage error', () async {
        // Arrange
        final cipher = _Helpers.createMockPasswordCipherFunc();
        final id = EntryId('to-delete');

        _Helpers.stubReadAllMeta(storage, cipher, id: id.value);

        await locker.loadAllMeta(cipher);
        final before = Map.of(locker.allMeta);

        when(
          () => storage.deleteEntry(
            id: id,
            cipherFunc: cipher,
          ),
        ).thenThrow(Exception('test'));

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

      test('removes entry from cache when delete = false from storage', () async {
        // Arrange
        final cipher = _Helpers.createMockPasswordCipherFunc();
        final id = EntryId('x');
        _Helpers.stubReadAllMeta(storage, cipher, id: id.value);

        await locker.loadAllMeta(cipher);
        final deletedMetaRef = locker.allMeta[id]!;

        when(() => storage.deleteEntry(id: id, cipherFunc: cipher)).thenAnswer((_) async => false);

        // Act
        final result = await locker.delete(id: id, cipherFunc: cipher);

        // Assert
        expect(result, isFalse);
        expect(locker.allMeta.containsKey(id), isFalse);

        verify(() => storage.deleteEntry(id: id, cipherFunc: cipher)).called(1);
        _Helpers.verifyErasedAll([cipher, deletedMetaRef]);
      });
    });

    group('update', () {
      test('updates cache and calls storage.updateEntry with meta and value', () async {
        // Arrange
        final cipher = _Helpers.createMockPasswordCipherFunc();
        final id = EntryId('entryId');

        _Helpers.stubReadAllMeta(
          storage,
          cipher,
          id: id.value,
          metaBytes: [1, 2],
        );
        await locker.loadAllMeta(cipher);

        final oldMeta = locker.allMeta[id]!;
        final newMeta = _StorageHelpers.createEntryMeta([3, 4]);
        final newValue = _StorageHelpers.createEntryValue([5, 6]);
        final input = EntryUpdateInput(id: id, meta: newMeta, value: newValue);

        when(
          () => storage.updateEntry(
            input: input,
            cipherFunc: cipher,
          ),
        ).thenAnswer((_) async {});

        // Act
        await locker.update(
          input: input,
          cipherFunc: cipher,
        );

        // Assert
        verify(
          () => storage.updateEntry(
            input: input,
            cipherFunc: cipher,
          ),
        ).called(1);

        expect(locker.allMeta[id], same(newMeta));
        _Helpers.verifyErasedAll([cipher, newValue, oldMeta]);
      });

      test('updates only value without changing meta cache', () async {
        // Arrange
        final cipher = _Helpers.createMockPasswordCipherFunc();
        final id = EntryId('entryId');

        _Helpers.stubReadAllMeta(
          storage,
          cipher,
          id: id.value,
          metaBytes: [1, 2],
        );
        await locker.loadAllMeta(cipher);

        final existingMeta = locker.allMeta[id]!;
        final newValue = _StorageHelpers.createEntryValue([5, 6]);
        final input = EntryUpdateInput(id: id, value: newValue);

        when(
          () => storage.updateEntry(
            input: input,
            cipherFunc: cipher,
          ),
        ).thenAnswer((_) async {});

        // Act
        await locker.update(
          input: input,
          cipherFunc: cipher,
        );

        // Assert
        verify(
          () => storage.updateEntry(
            input: input,
            cipherFunc: cipher,
          ),
        ).called(1);

        expect(locker.allMeta[id], same(existingMeta));
        _Helpers.verifyErasedAll([cipher, newValue]);
      });

      test('updates only meta and updates cache', () async {
        // Arrange
        final cipher = _Helpers.createMockPasswordCipherFunc();
        final id = EntryId('entryId');

        _Helpers.stubReadAllMeta(storage, cipher, id: id.value, metaBytes: [1, 2]);
        await locker.loadAllMeta(cipher);

        final oldMeta = locker.allMeta[id]!;
        final newMeta = _StorageHelpers.createEntryMeta([3, 4]);
        final input = EntryUpdateInput(id: id, meta: newMeta);

        when(
          () => storage.updateEntry(
            input: input,
            cipherFunc: cipher,
          ),
        ).thenAnswer((_) async {});

        // Act
        await locker.update(
          input: input,
          cipherFunc: cipher,
        );

        // Assert
        verify(
          () => storage.updateEntry(
            input: input,
            cipherFunc: cipher,
          ),
        ).called(1);

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

        verifyNever(
          () => storage.updateEntry(
            input: any(named: 'input'),
            cipherFunc: any(named: 'cipherFunc'),
          ),
        );

        _Helpers.verifyErasedAll([cipher, value, meta]);
      });

      test('rethrows on storage error and erases meta on error', () async {
        // Arrange
        final cipher = _Helpers.createMockPasswordCipherFunc();
        final id = EntryId('entryId');
        final meta = _StorageHelpers.createEntryMeta([3, 4]);
        final value = _StorageHelpers.createEntryValue([5, 6]);
        final input = EntryUpdateInput(id: id, meta: meta, value: value);

        _Helpers.stubReadAllMeta(storage, cipher, id: id.value);
        await locker.loadAllMeta(cipher);

        final before = Map.of(locker.allMeta);

        when(
          () => storage.updateEntry(
            input: input,
            cipherFunc: cipher,
          ),
        ).thenThrow(Exception('test'));

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
      test('changePassword calls correct method from storage', () async {
        // Arrange
        final oldPwd = _Helpers.createMockPasswordCipherFunc();
        final newPwd = _Helpers.createMockPasswordCipherFunc(password: [2], salt: [2]);

        _Helpers.stubReadAllMeta(storage, oldPwd);
        await locker.loadAllMeta(oldPwd);

        when(
          () => storage.addOrReplaceWrap(
            newWrapFunc: newPwd,
            existingWrapFunc: oldPwd,
          ),
        ).thenAnswer((_) async {});

        // Act
        await locker.changePassword(
          newCipherFunc: newPwd,
          existingCipherFunc: oldPwd,
        );

        // Assert
        verify(
          () => storage.addOrReplaceWrap(
            newWrapFunc: newPwd,
            existingWrapFunc: oldPwd,
          ),
        ).called(1);

        _Helpers.verifyErasedAll([oldPwd, newPwd]);
      });

      test('enableBiometry calls correct method from storage', () async {
        // Arrange
        final pwd = _Helpers.createMockPasswordCipherFunc();
        final bio = _Helpers.createMockBioCipherFunc();

        _Helpers.stubReadAllMeta(storage, pwd);
        await locker.loadAllMeta(pwd);

        when(
          () => storage.addOrReplaceWrap(
            newWrapFunc: bio,
            existingWrapFunc: pwd,
          ),
        ).thenAnswer((_) async {});

        // Act
        await locker.enableBiometry(bioCipherFunc: bio, passwordCipherFunc: pwd);

        // Assert
        verify(
          () => storage.addOrReplaceWrap(
            newWrapFunc: bio,
            existingWrapFunc: pwd,
          ),
        ).called(1);

        _Helpers.verifyErasedAll([pwd, bio]);
      });

      test('disableBiometry calls correct method from storage', () async {
        // Arrange
        final originToDelete = Origin.bio;
        final pwd = _Helpers.createMockPasswordCipherFunc();
        final bio = _Helpers.createMockBioCipherFunc();

        _Helpers.stubReadAllMeta(storage, pwd);
        await locker.loadAllMeta(pwd);

        when(
          () => storage.deleteWrap(
            originToDelete: originToDelete,
            cipherFunc: pwd,
          ),
        ).thenAnswer((_) async => true);

        // Act
        await locker.disableBiometry(bioCipherFunc: bio, passwordCipherFunc: pwd);

        // Assert
        verify(
          () => storage.deleteWrap(
            originToDelete: originToDelete,
            cipherFunc: pwd,
          ),
        ).called(1);

        _Helpers.verifyErasedAll([pwd, bio]);
      });

      test('rethrows on changePassword error', () async {
        // Arrange
        final oldPwd = _Helpers.createMockPasswordCipherFunc();
        final newPwd = _Helpers.createMockPasswordCipherFunc(password: [2], salt: [2]);
        _Helpers.stubReadAllMeta(storage, oldPwd);
        await locker.loadAllMeta(oldPwd);

        when(
          () => storage.addOrReplaceWrap(
            newWrapFunc: newPwd,
            existingWrapFunc: oldPwd,
          ),
        ).thenThrow(Exception('test'));

        // Act & Assert
        await expectLater(
          () => locker.changePassword(newCipherFunc: newPwd, existingCipherFunc: oldPwd),
          throwsException,
        );

        _Helpers.verifyErasedAll([oldPwd, newPwd]);
      });

      test('rethrows on enableBiometry error', () async {
        // Arrange
        final pwd = _Helpers.createMockPasswordCipherFunc();
        final bio = _Helpers.createMockBioCipherFunc();
        _Helpers.stubReadAllMeta(storage, pwd);
        await locker.loadAllMeta(pwd);

        when(
          () => storage.addOrReplaceWrap(
            newWrapFunc: bio,
            existingWrapFunc: pwd,
          ),
        ).thenThrow(Exception('test'));

        // Act & Assert
        await expectLater(
          () => locker.enableBiometry(bioCipherFunc: bio, passwordCipherFunc: pwd),
          throwsException,
        );

        _Helpers.verifyErasedAll([pwd, bio]);
      });

      test('rethrows on disableBiometry error', () async {
        // Arrange
        final pwd = _Helpers.createMockPasswordCipherFunc();
        final bio = _Helpers.createMockBioCipherFunc();
        _Helpers.stubReadAllMeta(storage, pwd);
        await locker.loadAllMeta(pwd);

        when(
          () => storage.deleteWrap(
            originToDelete: Origin.bio,
            cipherFunc: pwd,
          ),
        ).thenThrow(Exception('test'));

        // Act & Assert
        await expectLater(
          () => locker.disableBiometry(bioCipherFunc: bio, passwordCipherFunc: pwd),
          throwsException,
        );

        _Helpers.verifyErasedAll([pwd, bio]);
      });
    });

    group('teardownBiometryPasswordOnly', () {
      const biometricKeyTag = 'test-bio-key-tag';

      late MockBiometricCipherProvider secureProvider;
      late MockEncryptedStorage tpStorage;
      late MFALocker tpLocker;

      setUp(() {
        secureProvider = MockBiometricCipherProvider();
        tpStorage = MockEncryptedStorage();

        tpLocker = MFALocker(
          file: MockFile(),
          storage: tpStorage,
          secureProvider: secureProvider,
        );

        when(() => tpStorage.isInitialized).thenAnswer((_) async => true);
        when(() => tpStorage.lockTimeout).thenAnswer((_) async => _Helpers.lockTimeout.inMilliseconds);
      });

      tearDown(() {
        tpLocker.dispose();
      });

      test('deletes bio wrap and biometric key on success', () async {
        // Arrange
        final pwd = _Helpers.createMockPasswordCipherFunc();
        _Helpers.stubReadAllMeta(tpStorage, pwd);

        when(
          () => tpStorage.deleteWrap(
            originToDelete: Origin.bio,
            cipherFunc: pwd,
          ),
        ).thenAnswer((_) async => true);

        when(() => secureProvider.deleteKey(tag: biometricKeyTag)).thenAnswer((_) async {});

        // Act
        await tpLocker.teardownBiometryPasswordOnly(
          passwordCipherFunc: pwd,
          biometricKeyTag: biometricKeyTag,
        );

        // Assert
        verify(
          () => tpStorage.deleteWrap(
            originToDelete: Origin.bio,
            cipherFunc: pwd,
          ),
        ).called(1);
        verify(() => secureProvider.deleteKey(tag: biometricKeyTag)).called(1);
      });

      test('completes normally when deleteKey throws', () async {
        // Arrange
        final pwd = _Helpers.createMockPasswordCipherFunc();
        _Helpers.stubReadAllMeta(tpStorage, pwd);

        when(
          () => tpStorage.deleteWrap(
            originToDelete: Origin.bio,
            cipherFunc: pwd,
          ),
        ).thenAnswer((_) async => true);

        when(() => secureProvider.deleteKey(tag: biometricKeyTag)).thenThrow(Exception('key gone'));

        // Act & Assert - should not throw
        await tpLocker.teardownBiometryPasswordOnly(
          passwordCipherFunc: pwd,
          biometricKeyTag: biometricKeyTag,
        );

        verify(
          () => tpStorage.deleteWrap(
            originToDelete: Origin.bio,
            cipherFunc: pwd,
          ),
        ).called(1);
        verify(() => secureProvider.deleteKey(tag: biometricKeyTag)).called(1);
      });

      test('unlocks before deleting wrap when locker is locked', () async {
        // Arrange
        final pwd = _Helpers.createMockPasswordCipherFunc();
        _Helpers.stubReadAllMeta(tpStorage, pwd);

        when(
          () => tpStorage.deleteWrap(
            originToDelete: Origin.bio,
            cipherFunc: pwd,
          ),
        ).thenAnswer((_) async => true);

        when(() => secureProvider.deleteKey(tag: biometricKeyTag)).thenAnswer((_) async {});

        expect(tpLocker.stateStream.value, LockerState.locked);

        // Act
        await tpLocker.teardownBiometryPasswordOnly(
          passwordCipherFunc: pwd,
          biometricKeyTag: biometricKeyTag,
        );

        // Assert
        verifyInOrder([
          () => tpStorage.readAllMeta(cipherFunc: pwd),
          () => tpStorage.deleteWrap(
                originToDelete: Origin.bio,
                cipherFunc: pwd,
              ),
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
        _Helpers.stubReadAllMeta(storage, cipher);

        when(() => storage.erase()).thenAnswer((_) async => true);
        await locker.loadAllMeta(cipher);

        // Act
        await locker.eraseStorage();

        // Assert
        verify(() => storage.erase()).called(1);
        expect(locker.stateStream.value, LockerState.locked);

        _Helpers.verifyErased(cipher);
      });

      test('throws when storage erase returns false', () async {
        // Arrange
        final cipher = _Helpers.createMockPasswordCipherFunc();
        final meta = _Helpers.stubReadAllMeta(storage, cipher);

        await locker.loadAllMeta(cipher);
        when(() => storage.erase()).thenAnswer((_) async => false);

        // Act & Assert
        await expectLater(
          () => locker.eraseStorage(),
          throwsA(isA<StateError>()),
        );
        verify(() => storage.erase()).called(1);
        expect(locker.stateStream.value, LockerState.unlocked);
        expect(locker.allMeta, equals(meta));

        _Helpers.verifyErased(cipher);
      });
    });

    group('race-condition safety', () {
      const delayDuration = Duration(milliseconds: 25);

      test('concurrent readValue calls serialize: sequential storage.readValue', () async {
        // Arrange
        final cipher = _Helpers.createMockPasswordCipherFunc();

        _Helpers.stubReadAllMeta(storage, cipher);
        await locker.loadAllMeta(cipher);

        final id1 = EntryId('id1');
        final id2 = EntryId('id2');

        final gate1 = Completer<void>();
        var calls = 0;

        when(
          () => storage.readValue(
            id: any(named: 'id'),
            cipherFunc: cipher,
          ),
        ).thenAnswer((invocation) async {
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
        expect(calls, 1, reason: 'First readValue should have entered storage.readValue and be waiting on the gate.');

        // Start second readValue; it must not enter storage yet
        final f2 = locker.readValue(id: id2, cipherFunc: cipher);
        await Future<void>.delayed(delayDuration);
        expect(calls, 1, reason: 'Second readValue must be queued and not call storage.readValue yet.');

        // Release the first call; second can now enter and complete.
        gate1.complete();
        final v1 = await f1;
        final v2 = await f2;

        // Assert
        expect(calls, 2);
        verify(() => storage.readValue(id: id1, cipherFunc: cipher)).called(1);
        verify(() => storage.readValue(id: id2, cipherFunc: cipher)).called(1);
        expect(v1, isNot(same(v2)));
      });

      test(
        'two concurrent write calls are serialized ',
        () async {
          // Arrange
          final cipher = _Helpers.createMockPasswordCipherFunc();
          _Helpers.stubReadAllMeta(storage, cipher);
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

          when(
            () => storage.addEntry(
              input: any(named: 'input'),
              cipherFunc: cipher,
            ),
          ).thenAnswer((invocation) async {
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
          expect(addCalls, 2, reason: 'Both storage.addEntry calls should have executed sequentially.');
          verify(
            () => storage.addEntry(input: input1, cipherFunc: cipher),
          ).called(1);
          verify(
            () => storage.addEntry(input: input2, cipherFunc: cipher),
          ).called(1);
          expect(id1.value, isNot(equals(id2.value)), reason: 'Both writes reached storage.');
        },
      );

      test('changePassword/readValue: serialized; old fails, new succeeds', () async {
        // Arrange
        final oldPwd = _Helpers.createMockPasswordCipherFunc();
        final newPwd = _Helpers.createMockPasswordCipherFunc(password: [2], salt: [2]);

        _Helpers.stubReadAllMeta(storage, oldPwd);
        await locker.loadAllMeta(oldPwd);

        final gate = Completer<void>();
        var wrapCalls = 0;

        when(() => storage.addOrReplaceWrap(newWrapFunc: newPwd, existingWrapFunc: oldPwd)).thenAnswer((_) async {
          wrapCalls++;
          if (wrapCalls == 1) {
            await gate.future;
          }
        });

        when(
          () => storage.readValue(
            id: any(named: 'id'),
            cipherFunc: oldPwd,
          ),
        ).thenThrow(Exception('decrypt failed with oldPwd'));

        final expected = _StorageHelpers.createEntryValue([4, 2]);
        when(
          () => storage.readValue(
            id: any(named: 'id'),
            cipherFunc: newPwd,
          ),
        ).thenAnswer((_) async => expected);

        // Act
        final fChange = locker.changePassword(newCipherFunc: newPwd, existingCipherFunc: oldPwd);
        await Future<void>.delayed(delayDuration);
        expect(wrapCalls, 1, reason: 'changePassword must have entered storage and be waiting on the gate');

        final fReadOld = locker.readValue(id: EntryId('id'), cipherFunc: oldPwd);
        await Future<void>.delayed(delayDuration);

        gate.complete();
        await fChange;

        await expectLater(
          () => fReadOld,
          throwsA(isA<Exception>()),
        );

        final vNew = await locker.readValue(id: EntryId('id'), cipherFunc: newPwd);
        expect(vNew, same(expected), reason: 'readValue(newPwd) must return the value provided by storage');

        // Assert
        _Helpers.verifyErasedAll([oldPwd, newPwd]);
        verify(() => storage.addOrReplaceWrap(newWrapFunc: newPwd, existingWrapFunc: oldPwd)).called(1);
        verify(
          () => storage.readValue(
            id: any(named: 'id'),
            cipherFunc: oldPwd,
          ),
        ).called(1);
        verify(
          () => storage.readValue(
            id: any(named: 'id'),
            cipherFunc: newPwd,
          ),
        ).called(1);
      });
    });
  });
}
