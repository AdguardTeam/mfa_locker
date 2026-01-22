import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:locker/storage/encrypted_storage_impl.dart';
import 'package:locker/storage/models/data/key_wrap.dart';
import 'package:locker/storage/models/data/origin.dart';
import 'package:locker/storage/models/domain/entry_id.dart';
import 'package:locker/storage/models/domain/entry_value.dart';
import 'package:locker/storage/models/exceptions/decrypt_failed_exception.dart';
import 'package:locker/storage/models/exceptions/storage_exception.dart';
import 'package:locker/utils/cryptography_utils.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../mocks/mock_file.dart';
import 'encrypted_storage_test_helpers.dart';

typedef _Helpers = EncryptedStorageTestHelpers;

void main() {
  late Directory tempDir;
  late File storageFile;
  late EncryptedStorageImpl storage;

  setUpAll(() async {
    registerFallbackValue(_Helpers.createErasable());
    registerFallbackValue(Uint8List(0));
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('locker_test_');
    storageFile = File(p.join(tempDir.path, 'storage.json'));
    storage = EncryptedStorageImpl(file: storageFile);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('EncryptedStorageImpl', () {
    group('isInitialized', () {
      test('returns true when storage valid', () async {
        // Arrange
        final data = await _Helpers.createStorageData();

        await _Helpers.writeStorageData(storageFile, data);

        // Act
        final result = await storage.isInitialized;

        // Assert
        expect(result, isTrue);
      });

      test('returns false when file missing', () async {
        // Arrange
        if (await storageFile.exists()) {
          await storageFile.delete();
        }

        // Act
        final result = await storage.isInitialized;

        // Assert
        expect(result, isFalse);
      });

      test('returns false and deletes empty file', () async {
        // Arrange
        await storageFile.writeAsString('');

        // Act
        final result = await storage.isInitialized;

        // Assert
        expect(result, isFalse);
        expect(await storageFile.exists(), isFalse);
      });

      test('returns false when content invalid', () async {
        // Arrange
        await storageFile.writeAsString('invalid-content');

        // Act
        final result = await storage.isInitialized;

        // Assert
        expect(result, isFalse);
      });
    });

    group('salt getter', () {
      test('returns salt from storage', () async {
        // Arrange
        const salt = [1, 2];
        final data = await _Helpers.createStorageData(salt: salt);

        await _Helpers.writeStorageData(storageFile, data);

        // Act
        final result = await storage.salt;

        // Assert
        expect(result, orderedEquals(salt));
      });

      test('returns null when loading fails', () async {
        // Arrange
        await storageFile.writeAsString('invalid');

        // Act
        final result = await storage.salt;

        // Assert
        expect(result, isNull);
      });

      test('returns null when file missing', () async {
        // Arrange
        if (await storageFile.exists()) {
          await storageFile.delete();
        }

        // Act
        final result = await storage.salt;

        // Assert
        expect(result, isNull);
      });
    });

    group('lockTimeout getter', () {
      test('returns lockTimeout from storage', () async {
        // Arrange
        final data = await _Helpers.createStorageData();

        await _Helpers.writeStorageData(storageFile, data);

        // Act
        final result = await storage.lockTimeout;

        // Assert
        expect(result, equals(_Helpers.lockTimeout));
      });

      test('returns null when loading fails', () async {
        // Arrange
        await storageFile.writeAsString('invalid');

        // Act
        final result = await storage.lockTimeout;

        // Assert
        expect(result, isNull);
      });

      test('returns null when file missing', () async {
        // Arrange
        if (await storageFile.exists()) {
          await storageFile.delete();
        }

        // Act
        final result = await storage.lockTimeout;

        // Assert
        expect(result, isNull);
      });
    });

    group('init', () {
      test('creates storage file on init', () async {
        // Arrange
        final cipherFunc = _Helpers.createMockPasswordCipherFunc();
        final entryMeta = _Helpers.createEntryMeta();
        final entryValue = _Helpers.createEntryValue();

        // Act
        await storage.init(
          passwordCipherFunc: cipherFunc,
          initialEntryMeta: entryMeta,
          initialEntryValue: entryValue,
          lockTimeout: _Helpers.lockTimeout,
        );

        // Assert
        final data = await _Helpers.readStorageData(storageFile);

        expect(data.entries, isNotEmpty);
        expect(data.masterKey.wraps, isNotEmpty);
        expect(data.hmacSignature, isNotEmpty);
        expect(data.hmacKey, isNotEmpty);
        expect(data.salt, orderedEquals(cipherFunc.salt));
        expect(data.lockTimeout, equals(_Helpers.lockTimeout));
      });

      test('throws when already initialized', () async {
        // Arrange
        final initialData = await _Helpers.createStorageData();
        final cipherFunc = _Helpers.createMockPasswordCipherFunc();
        final entryMeta = _Helpers.createEntryMeta();
        final entryValue = _Helpers.createEntryValue();

        await _Helpers.writeStorageData(storageFile, initialData);

        // Act & Assert
        await expectLater(
          () => storage.init(
            passwordCipherFunc: cipherFunc,
            initialEntryMeta: entryMeta,
            initialEntryValue: entryValue,
            lockTimeout: _Helpers.lockTimeout,
          ),
          throwsA(isA<StorageException>()),
        );
      });

      test('does not create file when encrypt fails', () async {
        // Arrange
        final failingCipher = _Helpers.createMockPasswordCipherFunc();
        when(() => failingCipher.encrypt(any())).thenThrow(StorageException.other('encrypt failed'));

        // Act & Assert
        await expectLater(
          () => storage.init(
            passwordCipherFunc: failingCipher,
            initialEntryMeta: _Helpers.createEntryMeta(),
            initialEntryValue: _Helpers.createEntryValue(),
            lockTimeout: _Helpers.lockTimeout,
          ),
          throwsA(isA<StorageException>()),
        );
        expect(await storageFile.exists(), isFalse);
      });

      test('throws when lockTimeout is zero', () async {
        // Arrange
        final cipherFunc = _Helpers.createMockPasswordCipherFunc();

        // Act & Assert
        await expectLater(
          () => storage.init(
            passwordCipherFunc: cipherFunc,
            initialEntryMeta: _Helpers.createEntryMeta(),
            initialEntryValue: _Helpers.createEntryValue(),
            lockTimeout: 0,
          ),
          throwsA(isA<StorageException>()),
        );
        expect(await storageFile.exists(), isFalse);
      });

      test('throws when lockTimeout is negative', () async {
        // Arrange
        final cipherFunc = _Helpers.createMockPasswordCipherFunc();

        // Act & Assert
        await expectLater(
          () => storage.init(
            passwordCipherFunc: cipherFunc,
            initialEntryMeta: _Helpers.createEntryMeta(),
            initialEntryValue: _Helpers.createEntryValue(),
            lockTimeout: -1,
          ),
          throwsA(isA<StorageException>()),
        );
        expect(await storageFile.exists(), isFalse);
      });
    });

    group('addOrReplaceWrap', () {
      test('adds new wrap, doesn`t change existing wrap', () async {
        // Arrange
        final masterKey = await CryptographyUtils.generateAESKey();
        final existingCipherFunc = _Helpers.createMockPasswordCipherFunc(masterKeyBytes: masterKey.bytes);
        final newCipherFunc = _Helpers.createMockBioCipherFunc(masterKeyBytes: masterKey.bytes);
        final existingWrap = KeyWrap(origin: Origin.pwd, encryptedKey: masterKey.bytes);
        final signedData = await _Helpers.createStorageData(
          wraps: [existingWrap],
          masterKey: masterKey,
        );

        await _Helpers.writeStorageData(storageFile, signedData);

        // Act
        await storage.addOrReplaceWrap(newWrapFunc: newCipherFunc, existingWrapFunc: existingCipherFunc);

        // Assert
        final updated = await _Helpers.readStorageData(storageFile);
        final wraps = updated.masterKey.wraps;
        final newWrapFromStorage = wraps.singleWhere((wrap) => wrap.origin == newCipherFunc.origin);
        final existingWrapFromStorage = wraps.singleWhere((wrap) => wrap.origin == existingCipherFunc.origin);
        final origins = wraps.map((wrap) => wrap.origin).toList();

        expect(wraps, hasLength(2));
        expect(origins, containsAll([existingCipherFunc.origin, newCipherFunc.origin]));
        expect(newWrapFromStorage.encryptedKey, orderedEquals(masterKey.bytes));
        expect(existingWrapFromStorage.encryptedKey, orderedEquals(existingWrap.encryptedKey));
      });

      test('replaces wrap when origin matches', () async {
        // Arrange
        final masterKey = await CryptographyUtils.generateAESKey();
        final existingSalt = Uint8List.fromList([0, 1]);
        final existingWrap = KeyWrap(origin: Origin.pwd, encryptedKey: masterKey.bytes);
        final signedData = await _Helpers.createStorageData(
          masterKey: masterKey,
          wraps: [existingWrap],
          salt: existingSalt,
        );
        final existingCipherFunc = _Helpers.createMockPasswordCipherFunc(
          masterKeyBytes: masterKey.bytes,
          saltBytes: existingSalt,
        );
        final newCipherFunc = _Helpers.createMockPasswordCipherFunc(
          masterKeyBytes: masterKey.bytes,
          saltBytes: Uint8List.fromList([9, 9, 9]),
        );

        await _Helpers.writeStorageData(storageFile, signedData);

        // Act
        await storage.addOrReplaceWrap(newWrapFunc: newCipherFunc, existingWrapFunc: existingCipherFunc);

        // Assert
        final updated = await _Helpers.readStorageData(storageFile);
        final wrap = updated.masterKey.wraps.single;

        expect(wrap.origin, equals(Origin.pwd));
        expect(wrap.encryptedKey, orderedEquals(masterKey.bytes));
        expect(updated.salt, orderedEquals(newCipherFunc.salt));
      });

      test('throws and keeps file unchanged when existing wrap decrypt fails', () async {
        // Arrange
        final masterKey = await CryptographyUtils.generateAESKey();
        final existingWrap = KeyWrap(origin: Origin.pwd, encryptedKey: masterKey.bytes);
        final signedData = await _Helpers.createStorageData(
          wraps: [existingWrap],
          masterKey: masterKey,
        );
        final failingExisting = _Helpers.createDecryptFailingPasswordCipherFunc();
        final newBio = _Helpers.createMockBioCipherFunc(masterKeyBytes: masterKey.bytes);

        await _Helpers.writeStorageData(storageFile, signedData);

        // Act & Assert
        await _Helpers.expectFileUnchanged(
          storageFile,
          () => expectLater(
            storage.addOrReplaceWrap(newWrapFunc: newBio, existingWrapFunc: failingExisting),
            throwsA(isA<DecryptFailedException>()),
          ),
        );
      });

      test('does not change salt when new wrap is non-password', () async {
        // Arrange
        final masterKey = await CryptographyUtils.generateAESKey();
        final salt = Uint8List.fromList([1, 2, 3]);
        final existingWrap = KeyWrap(origin: Origin.pwd, encryptedKey: masterKey.bytes);
        final signedData = await _Helpers.createStorageData(
          wraps: [existingWrap],
          masterKey: masterKey,
          salt: salt,
        );
        final existingCipher = _Helpers.createMockPasswordCipherFunc(masterKeyBytes: masterKey.bytes, saltBytes: salt);
        final newBio = _Helpers.createMockBioCipherFunc(masterKeyBytes: masterKey.bytes);

        await _Helpers.writeStorageData(storageFile, signedData);

        // Act
        await storage.addOrReplaceWrap(newWrapFunc: newBio, existingWrapFunc: existingCipher);

        // Assert
        final updated = await _Helpers.readStorageData(storageFile);
        expect(updated.salt, orderedEquals(salt));
      });
    });

    group('deleteWrap', () {
      test('removes wrap and returns true', () async {
        // Arrange
        final masterKey = await CryptographyUtils.generateAESKey();
        final cipherFunc = _Helpers.createMockPasswordCipherFunc(masterKeyBytes: masterKey.bytes);
        final wrapBio = KeyWrap(origin: Origin.bio, encryptedKey: masterKey.bytes);
        final wrapPwd = KeyWrap(origin: Origin.pwd, encryptedKey: masterKey.bytes);
        final signedData = await _Helpers.createStorageData(
          wraps: [wrapBio, wrapPwd],
          masterKey: masterKey,
        );

        await _Helpers.writeStorageData(storageFile, signedData);

        // Act
        final result = await storage.deleteWrap(originToDelete: Origin.bio, cipherFunc: cipherFunc);

        // Assert
        final updated = await _Helpers.readStorageData(storageFile);

        expect(result, isTrue);
        expect(updated.masterKey.wraps, hasLength(1));
        expect(updated.masterKey.wraps.single.origin, equals(Origin.pwd));
        expect(updated.hmacSignature, isNotNull);
      });

      test('returns false when storage invalid', () async {
        // Arrange
        await storageFile.writeAsString('invalid');

        final cipherFunc = _Helpers.createMockPasswordCipherFunc();

        // Act
        final result = await storage.deleteWrap(originToDelete: Origin.pwd, cipherFunc: cipherFunc);

        // Assert
        expect(result, isFalse);
      });

      test('returns false when wrap missing', () async {
        // Arrange
        final masterKey = await CryptographyUtils.generateAESKey();
        final cipherFunc = _Helpers.createMockPasswordCipherFunc(masterKeyBytes: masterKey.bytes);
        final wrapPwd = KeyWrap(origin: Origin.pwd, encryptedKey: masterKey.bytes);
        final signedData = await _Helpers.createStorageData(
          wraps: [wrapPwd],
          masterKey: masterKey,
        );

        await _Helpers.writeStorageData(storageFile, signedData);

        // Act
        final result = await storage.deleteWrap(originToDelete: Origin.bio, cipherFunc: cipherFunc);

        // Assert
        expect(result, isFalse);
      });

      test('returns false when deleting last wrap', () async {
        // Arrange
        final masterKey = await CryptographyUtils.generateAESKey();
        final cipherFunc = _Helpers.createMockPasswordCipherFunc(masterKeyBytes: masterKey.bytes);
        final wrapPwd = KeyWrap(origin: Origin.pwd, encryptedKey: masterKey.bytes);
        final data = await _Helpers.createStorageData(masterKey: masterKey, wraps: [wrapPwd]);

        await _Helpers.writeStorageData(storageFile, data);

        // Act
        final result = await _Helpers.expectFileUnchanged(
          storageFile,
          () => storage.deleteWrap(originToDelete: Origin.pwd, cipherFunc: cipherFunc),
        );

        // Assert
        expect(result, isFalse);
      });

      test('throws and keeps file unchanged when cipher decrypt fails', () async {
        // Arrange
        final masterKey = await CryptographyUtils.generateAESKey();
        final wrapPwd = KeyWrap(origin: Origin.pwd, encryptedKey: masterKey.bytes);
        final wrapBio = KeyWrap(origin: Origin.bio, encryptedKey: masterKey.bytes);
        final data = await _Helpers.createStorageData(masterKey: masterKey, wraps: [wrapPwd, wrapBio]);
        final failingCipher = _Helpers.createDecryptFailingPasswordCipherFunc();

        await _Helpers.writeStorageData(storageFile, data);

        // Act & Assert
        await _Helpers.expectFileUnchanged(
          storageFile,
          () => expectLater(
            storage.deleteWrap(originToDelete: Origin.bio, cipherFunc: failingCipher),
            throwsA(isA<DecryptFailedException>()),
          ),
        );
      });
    });

    group('deleteEntry', () {
      test('removes entry and returns true', () async {
        // Arrange
        const entryToDeleteId = 'target';
        const entryToKeepId = 'keep';

        final masterKey = await CryptographyUtils.generateAESKey();
        final cipherFunc = _Helpers.createMockPasswordCipherFunc(masterKeyBytes: masterKey.bytes);
        final wrapPwd = KeyWrap(origin: Origin.pwd, encryptedKey: masterKey.bytes);
        final entryToKeep = await _Helpers.createEncryptedEntry(
          masterKey: masterKey,
          id: entryToKeepId,
        );
        final entryToDelete = await _Helpers.createEncryptedEntry(
          masterKey: masterKey,
          id: entryToDeleteId,
        );
        final signedData = await _Helpers.createStorageData(
          wraps: [wrapPwd],
          entries: [entryToKeep, entryToDelete],
          masterKey: masterKey,
        );

        await _Helpers.writeStorageData(storageFile, signedData);

        // Act
        final result = await storage.deleteEntry(id: EntryId(entryToDeleteId), cipherFunc: cipherFunc);

        // Assert
        final data = await _Helpers.readStorageData(storageFile);
        final entryIds = data.entries.map((entry) => entry.id.value).toList();

        expect(result, isTrue);
        expect(entryIds, contains(entryToKeepId));
        expect(entryIds, isNot(contains(entryToDeleteId)));
      });

      test('changes HMAC signature when entry is deleted', () async {
        // Arrange
        const entryToDeleteId = 'target';
        const entryToKeepId = 'keep';

        final masterKey = await CryptographyUtils.generateAESKey();
        final cipherFunc = _Helpers.createMockPasswordCipherFunc(masterKeyBytes: masterKey.bytes);
        final wrapPwd = KeyWrap(origin: Origin.pwd, encryptedKey: masterKey.bytes);
        final entryToKeep = await _Helpers.createEncryptedEntry(
          masterKey: masterKey,
          id: entryToKeepId,
        );
        final entryToDelete = await _Helpers.createEncryptedEntry(
          masterKey: masterKey,
          id: entryToDeleteId,
        );
        final signedData = await _Helpers.createStorageData(
          wraps: [wrapPwd],
          entries: [entryToKeep, entryToDelete],
          masterKey: masterKey,
        );

        await _Helpers.writeStorageData(storageFile, signedData);
        final hmacBefore = (await _Helpers.readStorageData(storageFile)).hmacSignature!;

        // Act
        await storage.deleteEntry(id: EntryId(entryToDeleteId), cipherFunc: cipherFunc);

        // Assert
        final hmacAfter = (await _Helpers.readStorageData(storageFile)).hmacSignature!;
        expect(hmacAfter, isNot(orderedEquals(hmacBefore)));
      });

      test('returns false when entry absent', () async {
        // Arrange
        final masterKey = await CryptographyUtils.generateAESKey();
        final cipherFunc = _Helpers.createMockPasswordCipherFunc(masterKeyBytes: masterKey.bytes);
        final wrapPwd = KeyWrap(origin: Origin.pwd, encryptedKey: masterKey.bytes);
        final existingEntry = await _Helpers.createEncryptedEntry(
          masterKey: masterKey,
          id: 'existing',
        );
        final signedData = await _Helpers.createStorageData(
          masterKey: masterKey,
          wraps: [wrapPwd],
          entries: [existingEntry],
        );

        await _Helpers.writeStorageData(storageFile, signedData);

        // Act
        final result = await storage.deleteEntry(id: EntryId('missing'), cipherFunc: cipherFunc);

        // Assert
        expect(result, isFalse);
      });

      test('throws and keeps file unchanged when cipher decrypt fails', () async {
        // Arrange
        final masterKey = await CryptographyUtils.generateAESKey();
        final wrapPwd = KeyWrap(origin: Origin.pwd, encryptedKey: masterKey.bytes);
        final entry = await _Helpers.createEncryptedEntry(masterKey: masterKey, id: 'id');
        final data = await _Helpers.createStorageData(masterKey: masterKey, wraps: [wrapPwd], entries: [entry]);
        final failingCipher = _Helpers.createDecryptFailingPasswordCipherFunc();

        await _Helpers.writeStorageData(storageFile, data);

        // Act & Assert
        await _Helpers.expectFileUnchanged(
          storageFile,
          () => expectLater(
            storage.deleteEntry(id: EntryId('id'), cipherFunc: failingCipher),
            throwsA(isA<DecryptFailedException>()),
          ),
        );
      });
    });

    group('addEntry', () {
      test('stores new entry and returns id', () async {
        // Arrange
        final masterKey = await CryptographyUtils.generateAESKey();
        final cipherFunc = _Helpers.createMockPasswordCipherFunc(masterKeyBytes: masterKey.bytes);
        final wrapPwd = KeyWrap(origin: Origin.pwd, encryptedKey: masterKey.bytes);
        final initialEntry = await _Helpers.createEncryptedEntry(
          masterKey: masterKey,
          id: 'initial',
        );
        final signedData = await _Helpers.createStorageData(
          wraps: [wrapPwd],
          entries: [initialEntry],
          masterKey: masterKey,
        );

        await _Helpers.writeStorageData(storageFile, signedData);

        final entryMeta = _Helpers.createEntryMeta();
        final entryValue = _Helpers.createEntryValue();

        // Act
        final entryId = await storage.addEntry(
          entryMeta: entryMeta,
          entryValue: entryValue,
          cipherFunc: cipherFunc,
        );

        // Assert
        final updated = await _Helpers.readStorageData(storageFile);
        final entryIds = updated.entries.map((entry) => entry.id.value).toList();

        expect(updated.entries, hasLength(2));
        expect(entryIds, contains(initialEntry.id.value));
        expect(entryIds, contains(entryId.value));
      });

      test('changes HMAC signature when entry is added', () async {
        // Arrange
        final masterKey = await CryptographyUtils.generateAESKey();
        final cipherFunc = _Helpers.createMockPasswordCipherFunc(masterKeyBytes: masterKey.bytes);
        final wrapPwd = KeyWrap(origin: Origin.pwd, encryptedKey: masterKey.bytes);
        final existingEntry = await _Helpers.createEncryptedEntry(masterKey: masterKey, id: 'existing');
        final signedData = await _Helpers.createStorageData(
          wraps: [wrapPwd],
          entries: [existingEntry],
          masterKey: masterKey,
        );

        await _Helpers.writeStorageData(storageFile, signedData);
        final hmacBefore = (await _Helpers.readStorageData(storageFile)).hmacSignature!;

        final entryMeta = _Helpers.createEntryMeta();
        final entryValue = _Helpers.createEntryValue();

        // Act
        await storage.addEntry(
          entryMeta: entryMeta,
          entryValue: entryValue,
          cipherFunc: cipherFunc,
        );

        // Assert
        final hmacAfter = (await _Helpers.readStorageData(storageFile)).hmacSignature!;
        expect(hmacAfter, isNot(orderedEquals(hmacBefore)));
      });

      test('throws when file load fails', () async {
        // Arrange
        await storageFile.writeAsString('invalid');
        final cipherFunc = _Helpers.createMockPasswordCipherFunc();

        final entryMeta = _Helpers.createEntryMeta();
        final entryValue = _Helpers.createEntryValue();

        // Act & Assert
        await expectLater(
          () => storage.addEntry(
            entryMeta: entryMeta,
            entryValue: entryValue,
            cipherFunc: cipherFunc,
          ),
          throwsA(isA<StorageException>()),
        );
      });

      test('throws and keeps file unchanged when cipher decrypt fails', () async {
        // Arrange
        final masterKey = await CryptographyUtils.generateAESKey();
        final wrapPwd = KeyWrap(origin: Origin.pwd, encryptedKey: masterKey.bytes);
        final data = await _Helpers.createStorageData(masterKey: masterKey, wraps: [wrapPwd]);
        final failingCipher = _Helpers.createDecryptFailingPasswordCipherFunc();

        await _Helpers.writeStorageData(storageFile, data);

        // Act & Assert
        await _Helpers.expectFileUnchanged(
          storageFile,
          () => expectLater(
            storage.addEntry(
              entryMeta: _Helpers.createEntryMeta(),
              entryValue: _Helpers.createEntryValue(),
              cipherFunc: failingCipher,
            ),
            throwsA(isA<DecryptFailedException>()),
          ),
        );
      });
    });

    group('updateEntry', () {
      test('updates only meta when value omitted', () async {
        // Arrange
        const entryId = 'entry';

        final masterKey = await CryptographyUtils.generateAESKey();
        final cipherFunc = _Helpers.createMockPasswordCipherFunc(masterKeyBytes: masterKey.bytes);
        final wrapPwd = KeyWrap(origin: Origin.pwd, encryptedKey: masterKey.bytes);
        final entry = await _Helpers.createEncryptedEntry(
          masterKey: masterKey,
          id: entryId,
        );
        final signedData = await _Helpers.createStorageData(
          wraps: [wrapPwd],
          entries: [entry],
          masterKey: masterKey,
        );
        await _Helpers.writeStorageData(storageFile, signedData);

        final newMeta = _Helpers.createEntryMeta([5, 5]);

        // Act
        await storage.updateEntry(
          id: EntryId(entryId),
          cipherFunc: cipherFunc,
          entryMeta: newMeta,
        );

        // Assert
        final updated = await _Helpers.readStorageData(storageFile);
        final updatedEntry = updated.entries.singleWhere((element) => element.id.value == entryId);

        expect(updatedEntry.encryptedValue, orderedEquals(entry.encryptedValue));
        expect(updatedEntry.encryptedMeta, isNot(orderedEquals(entry.encryptedMeta)));
      });

      test('changes HMAC signature when entry meta is updated', () async {
        // Arrange
        const entryId = 'entry';
        final masterKey = await CryptographyUtils.generateAESKey();
        final cipherFunc = _Helpers.createMockPasswordCipherFunc(masterKeyBytes: masterKey.bytes);
        final wrapPwd = KeyWrap(origin: Origin.pwd, encryptedKey: masterKey.bytes);
        final entry = await _Helpers.createEncryptedEntry(masterKey: masterKey, id: entryId);
        final signedData = await _Helpers.createStorageData(
          wraps: [wrapPwd],
          entries: [entry],
          masterKey: masterKey,
        );
        await _Helpers.writeStorageData(storageFile, signedData);
        final hmacBefore = (await _Helpers.readStorageData(storageFile)).hmacSignature!;

        // Act
        await storage.updateEntry(
          id: EntryId(entryId),
          cipherFunc: cipherFunc,
          entryMeta: _Helpers.createEntryMeta([7]),
        );

        // Assert
        final hmacAfter = (await _Helpers.readStorageData(storageFile)).hmacSignature!;
        expect(hmacAfter, isNot(orderedEquals(hmacBefore)));
      });

      test('changes HMAC signature when entry value is updated', () async {
        // Arrange
        const entryId = 'entry';
        final masterKey = await CryptographyUtils.generateAESKey();
        final cipherFunc = _Helpers.createMockPasswordCipherFunc(masterKeyBytes: masterKey.bytes);
        final wrapPwd = KeyWrap(origin: Origin.pwd, encryptedKey: masterKey.bytes);
        final entry = await _Helpers.createEncryptedEntry(masterKey: masterKey, id: entryId);
        final signedData = await _Helpers.createStorageData(
          wraps: [wrapPwd],
          entries: [entry],
          masterKey: masterKey,
        );
        await _Helpers.writeStorageData(storageFile, signedData);
        final hmacBefore = (await _Helpers.readStorageData(storageFile)).hmacSignature!;

        // Act
        await storage.updateEntry(
          id: EntryId(entryId),
          cipherFunc: cipherFunc,
          entryValue: _Helpers.createEntryValue([7]),
        );

        // Assert
        final hmacAfter = (await _Helpers.readStorageData(storageFile)).hmacSignature!;
        expect(hmacAfter, isNot(orderedEquals(hmacBefore)));
      });

      test('updates only value when meta omitted', () async {
        // Arrange
        const entryId = 'entry';
        final masterKey = await CryptographyUtils.generateAESKey();
        final cipherFunc = _Helpers.createMockPasswordCipherFunc(masterKeyBytes: masterKey.bytes);
        final wrapPwd = KeyWrap(origin: Origin.pwd, encryptedKey: masterKey.bytes);
        final entry = await _Helpers.createEncryptedEntry(masterKey: masterKey, id: entryId);
        final signedData = await _Helpers.createStorageData(
          wraps: [wrapPwd],
          entries: [entry],
          masterKey: masterKey,
        );
        final newValue = _Helpers.createEntryValue([9, 9]);

        await _Helpers.writeStorageData(storageFile, signedData);

        // Act
        await storage.updateEntry(
          id: EntryId(entryId),
          cipherFunc: cipherFunc,
          entryValue: newValue,
        );

        // Assert
        final updated = await _Helpers.readStorageData(storageFile);
        final updatedEntry = updated.entries.singleWhere((e) => e.id.value == entryId);

        expect(updatedEntry.encryptedMeta, orderedEquals(entry.encryptedMeta));
        expect(updatedEntry.encryptedValue, isNot(orderedEquals(entry.encryptedValue)));
      });

      test('updates both meta and value', () async {
        // Arrange
        const entryId = 'entry';
        final masterKey = await CryptographyUtils.generateAESKey();
        final cipherFunc = _Helpers.createMockPasswordCipherFunc(masterKeyBytes: masterKey.bytes);
        final wrapPwd = KeyWrap(origin: Origin.pwd, encryptedKey: masterKey.bytes);
        final entry = await _Helpers.createEncryptedEntry(masterKey: masterKey, id: entryId);
        final signedData = await _Helpers.createStorageData(
          wraps: [wrapPwd],
          entries: [entry],
          masterKey: masterKey,
        );

        await _Helpers.writeStorageData(storageFile, signedData);

        // Act
        await storage.updateEntry(
          id: EntryId(entryId),
          cipherFunc: cipherFunc,
          entryMeta: _Helpers.createEntryMeta([3]),
          entryValue: _Helpers.createEntryValue([4]),
        );

        // Assert
        final updated = await _Helpers.readStorageData(storageFile);
        final updatedEntry = updated.entries.singleWhere((e) => e.id.value == entryId);

        expect(updatedEntry.encryptedMeta, isNot(orderedEquals(entry.encryptedMeta)));
        expect(updatedEntry.encryptedValue, isNot(orderedEquals(entry.encryptedValue)));
      });

      test('throws when neither meta nor value provided', () async {
        // Arrange
        final cipherFunc = _Helpers.createMockPasswordCipherFunc();

        // Act & Assert
        await expectLater(
          storage.updateEntry(
            id: EntryId('id'),
            cipherFunc: cipherFunc,
          ),
          throwsA(isA<StorageException>()),
        );
      });

      test('throws when entry missing', () async {
        // Arrange
        final masterKey = await CryptographyUtils.generateAESKey();
        final signedData = await _Helpers.createStorageData(masterKey: masterKey);
        final cipher = _Helpers.createMockPasswordCipherFunc(masterKeyBytes: masterKey.bytes);

        await _Helpers.writeStorageData(storageFile, signedData);

        // Act & Assert
        await expectLater(
          () => storage.updateEntry(
            id: EntryId('missing'),
            cipherFunc: cipher,
            entryMeta: _Helpers.createEntryMeta(),
          ),
          throwsA(isA<StorageException>()),
        );
      });

      test('throws and keeps file unchanged when cipher decrypt fails', () async {
        // Arrange
        final masterKey = await CryptographyUtils.generateAESKey();
        final wrapPwd = KeyWrap(origin: Origin.pwd, encryptedKey: masterKey.bytes);
        final entry = await _Helpers.createEncryptedEntry(masterKey: masterKey, id: 'id');
        final data = await _Helpers.createStorageData(masterKey: masterKey, wraps: [wrapPwd], entries: [entry]);
        final failingCipher = _Helpers.createDecryptFailingPasswordCipherFunc();

        await _Helpers.writeStorageData(storageFile, data);

        // Act & Assert
        await _Helpers.expectFileUnchanged(
          storageFile,
          () => expectLater(
            storage.updateEntry(
              id: EntryId('id'),
              cipherFunc: failingCipher,
              entryMeta: _Helpers.createEntryMeta([8]),
            ),
            throwsA(isA<DecryptFailedException>()),
          ),
        );
      });
    });

    group('readAllMeta', () {
      test('returns correct meta for multiple entries', () async {
        // Arrange
        const entryId1 = 'id1';
        const entryId2 = 'id2';
        const metaBytes1 = [1, 2, 3];
        const metaBytes2 = [3, 4, 5];

        final masterKey = await CryptographyUtils.generateAESKey();
        final cipherFunc = _Helpers.createMockPasswordCipherFunc(masterKeyBytes: masterKey.bytes);
        final wrapPwd = KeyWrap(origin: Origin.pwd, encryptedKey: masterKey.bytes);
        final entry1 = await _Helpers.createEncryptedEntry(
          masterKey: masterKey,
          id: entryId1,
          metaBytes: metaBytes1,
        );
        final entry2 = await _Helpers.createEncryptedEntry(
          masterKey: masterKey,
          id: entryId2,
          metaBytes: metaBytes2,
        );
        final data = await _Helpers.createStorageData(
          wraps: [wrapPwd],
          entries: [entry1, entry2],
          masterKey: masterKey,
        );

        await _Helpers.writeStorageData(storageFile, data);

        // Act
        final result = await storage.readAllMeta(cipherFunc: cipherFunc);

        // Assert
        expect(result.length, equals(2));
        expect(result[EntryId(entryId1)]!.bytes, orderedEquals(metaBytes1));
        expect(result[EntryId(entryId2)]!.bytes, orderedEquals(metaBytes2));
      });

      test('throws when file load fails', () async {
        // Arrange
        await storageFile.writeAsString('invalid');
        final cipher = _Helpers.createMockPasswordCipherFunc();

        // Act & Assert
        await expectLater(
          () => storage.readAllMeta(cipherFunc: cipher),
          throwsA(isA<StorageException>()),
        );
      });

      test('throws and keeps file unchanged when cipher decrypt fails', () async {
        // Arrange
        final masterKey = await CryptographyUtils.generateAESKey();
        final wrapPwd = KeyWrap(origin: Origin.pwd, encryptedKey: masterKey.bytes);
        final entry = await _Helpers.createEncryptedEntry(masterKey: masterKey, id: 'id');
        final data = await _Helpers.createStorageData(
          masterKey: masterKey,
          wraps: [wrapPwd],
          entries: [entry],
        );
        final failingCipher = _Helpers.createDecryptFailingPasswordCipherFunc();

        await _Helpers.writeStorageData(storageFile, data);

        // Act & Assert
        await _Helpers.expectFileUnchanged(
          storageFile,
          () => expectLater(
            storage.readAllMeta(cipherFunc: failingCipher),
            throwsA(isA<DecryptFailedException>()),
          ),
        );
      });
    });

    group('readValue', () {
      test('returns decrypted value for id', () async {
        // Arrange
        const entryId = 'entryId';
        const valueBytes = [7, 8, 9];

        final masterKey = await CryptographyUtils.generateAESKey();
        final cipher = _Helpers.createMockPasswordCipherFunc(masterKeyBytes: masterKey.bytes);
        final wrapPwd = KeyWrap(origin: Origin.pwd, encryptedKey: masterKey.bytes);
        final entry = await _Helpers.createEncryptedEntry(
          masterKey: masterKey,
          id: entryId,
          valueBytes: valueBytes,
        );
        final signedData = await _Helpers.createStorageData(
          wraps: [wrapPwd],
          entries: [entry],
          masterKey: masterKey,
        );
        await _Helpers.writeStorageData(storageFile, signedData);

        // Act
        final value = await storage.readValue(id: EntryId(entryId), cipherFunc: cipher);

        // Assert
        expect(value.bytes, orderedEquals(valueBytes));
      });

      test('throws when entry missing', () async {
        // Arrange
        final masterKey = await CryptographyUtils.generateAESKey();
        final cipher = _Helpers.createMockPasswordCipherFunc(masterKeyBytes: masterKey.bytes);
        final wrapPwd = KeyWrap(origin: Origin.pwd, encryptedKey: masterKey.bytes);
        final signedData = await _Helpers.createStorageData(
          wraps: [wrapPwd],
          masterKey: masterKey,
        );
        await _Helpers.writeStorageData(storageFile, signedData);

        // Act & Assert
        await expectLater(
          () => storage.readValue(id: EntryId('missing'), cipherFunc: cipher),
          throwsA(isA<StorageException>()),
        );
      });

      test('throws and keeps file unchanged when cipher decrypt fails', () async {
        // Arrange
        final masterKey = await CryptographyUtils.generateAESKey();
        final wrapPwd = KeyWrap(origin: Origin.pwd, encryptedKey: masterKey.bytes);
        final entry = await _Helpers.createEncryptedEntry(masterKey: masterKey, id: 'id');
        final data = await _Helpers.createStorageData(
          masterKey: masterKey,
          wraps: [wrapPwd],
          entries: [entry],
        );
        final failingCipher = _Helpers.createDecryptFailingPasswordCipherFunc();

        await _Helpers.writeStorageData(storageFile, data);

        // Act & Assert
        await _Helpers.expectFileUnchanged(
          storageFile,
          () => expectLater(
            () => storage.readValue(id: EntryId('id'), cipherFunc: failingCipher),
            throwsA(isA<DecryptFailedException>()),
          ),
        );
      });
    });

    group('updateLockTimeout', () {
      test('updates lockTimeout and re-signs HMAC', () async {
        // Arrange
        const newLockTimeout = 123;
        final masterKey = await CryptographyUtils.generateAESKey();
        final cipher = _Helpers.createMockPasswordCipherFunc(masterKeyBytes: masterKey.bytes);
        final wrapPwd = KeyWrap(origin: Origin.pwd, encryptedKey: masterKey.bytes);
        final signed = await _Helpers.createStorageData(
          wraps: [wrapPwd],
          masterKey: masterKey,
        );
        await _Helpers.writeStorageData(storageFile, signed);
        final hmacBefore = (await _Helpers.readStorageData(storageFile)).hmacSignature!;

        // Act
        await storage.updateLockTimeout(lockTimeout: newLockTimeout, cipherFunc: cipher);

        // Assert
        final updated = await _Helpers.readStorageData(storageFile);
        expect(updated.lockTimeout, equals(newLockTimeout));
        expect(updated.hmacSignature, isNotNull);
        final hmacAfter = updated.hmacSignature!;
        expect(hmacAfter, isNot(orderedEquals(hmacBefore)));
      });

      test('throws when file storage invalid', () async {
        // Arrange
        await storageFile.writeAsString('invalid');
        final cipher = _Helpers.createMockPasswordCipherFunc();

        // Act & Assert
        await expectLater(
          () => storage.updateLockTimeout(lockTimeout: 123, cipherFunc: cipher),
          throwsA(isA<StorageException>()),
        );
      });

      test('throws and keeps file unchanged when cipher decrypt fails', () async {
        // Arrange
        final masterKey = await CryptographyUtils.generateAESKey();
        final wrapPwd = KeyWrap(origin: Origin.pwd, encryptedKey: masterKey.bytes);
        final signed = await _Helpers.createStorageData(
          masterKey: masterKey,
          wraps: [wrapPwd],
        );
        await _Helpers.writeStorageData(storageFile, signed);
        final failingCipher = _Helpers.createDecryptFailingPasswordCipherFunc();

        // Act & Assert
        await _Helpers.expectFileUnchanged(
          storageFile,
          () => expectLater(
            storage.updateLockTimeout(lockTimeout: 123, cipherFunc: failingCipher),
            throwsA(isA<DecryptFailedException>()),
          ),
        );
      });

      test('throws and keeps file unchanged when lockTimeout is zero', () async {
        // Arrange
        final signed = await _Helpers.createStorageData();
        await _Helpers.writeStorageData(storageFile, signed);
        final cipher = _Helpers.createMockPasswordCipherFunc();

        // Act & Assert
        await _Helpers.expectFileUnchanged(
          storageFile,
          () => expectLater(
            storage.updateLockTimeout(lockTimeout: 0, cipherFunc: cipher),
            throwsA(isA<StorageException>()),
          ),
        );
      });

      test('throws and keeps file unchanged when lockTimeout is negative', () async {
        // Arrange
        final signed = await _Helpers.createStorageData();
        await _Helpers.writeStorageData(storageFile, signed);
        final cipher = _Helpers.createMockPasswordCipherFunc();

        // Act & Assert
        await _Helpers.expectFileUnchanged(
          storageFile,
          () => expectLater(
            storage.updateLockTimeout(lockTimeout: -1, cipherFunc: cipher),
            throwsA(isA<StorageException>()),
          ),
        );
      });
    });

    group('erase', () {
      test('returns true when file absent', () async {
        // Arrange
        if (await storageFile.exists()) {
          await storageFile.delete();
        }

        // Act
        final result = await storage.erase();

        // Assert
        expect(result, isTrue);
      });

      test('deletes existing file and returns true', () async {
        // Arrange
        final data = await _Helpers.createStorageData();
        await _Helpers.writeStorageData(storageFile, data);

        // Act
        final result = await storage.erase();

        // Assert
        expect(result, isTrue);
        expect(await storageFile.exists(), isFalse);
      });

      test('returns false when deletion fails', () async {
        // Arrange

        final mockFile = MockFile();
        when(() => mockFile.path).thenReturn(storageFile.path);
        when(() => mockFile.exists()).thenAnswer((_) async => true);
        when(() => mockFile.delete()).thenThrow(const FileSystemException('delete failed'));

        final failingStorage = EncryptedStorageImpl(
          file: mockFile,
        );

        // Act
        final result = await failingStorage.erase();

        // Assert
        expect(result, isFalse);
      });
    });

    group('race-condition safety', () {
      const delayDuration = Duration(milliseconds: 25);

      late MockFile gateFile;
      late EncryptedStorageImpl storage;

      setUp(() {
        gateFile = MockFile();
        storage = EncryptedStorageImpl(file: gateFile);
        when(() => gateFile.path).thenReturn(storageFile.path);
        when(() => gateFile.parent).thenReturn(storageFile.parent);
        when(() => gateFile.exists()).thenAnswer((_) => storageFile.exists());
        when(() => gateFile.length()).thenAnswer((_) => storageFile.length());
        when(() => gateFile.stat()).thenAnswer((_) => storageFile.stat());
        when(() => gateFile.writeAsString(any(), flush: any(named: 'flush'))).thenAnswer((inv) {
          final s = inv.positionalArguments[0] as String;
          final flush = inv.namedArguments[#flush] as bool? ?? false;
          return storageFile.writeAsString(s, flush: flush);
        });
        when(
          () => gateFile.rename(any()),
        ).thenAnswer((inv) => storageFile.rename(inv.positionalArguments[0] as String));
        when(() => gateFile.delete()).thenAnswer((_) => storageFile.delete());
      });

      tearDown(() async {
        if (await gateFile.exists()) {
          await gateFile.delete();
        }
      });

      test('two concurrent addEntry calls are serialized', () async {
        // Arrange
        final masterKey = await CryptographyUtils.generateAESKey();
        final cipher = _Helpers.createMockPasswordCipherFunc(masterKeyBytes: masterKey.bytes);
        final wrapPwd = KeyWrap(origin: Origin.pwd, encryptedKey: masterKey.bytes);
        final initial = await _Helpers.createEncryptedEntry(masterKey: masterKey, id: 'initial');
        final signed = await _Helpers.createStorageData(
          wraps: [wrapPwd],
          entries: [initial],
          masterKey: masterKey,
        );
        await _Helpers.writeStorageData(storageFile, signed);

        final gate = Completer<void>();
        var readCalls = 0;

        when(() => gateFile.readAsString()).thenAnswer((_) async {
          readCalls++;
          if (readCalls == 1 && !gate.isCompleted) {
            await gate.future;
          }
          return storageFile.readAsString();
        });

        final m1 = _Helpers.createEntryMeta([1]);
        final v1 = _Helpers.createEntryValue([1]);
        final m2 = _Helpers.createEntryMeta([2]);
        final v2 = _Helpers.createEntryValue([2]);

        // Act:
        final f1 = storage.addEntry(entryMeta: m1, entryValue: v1, cipherFunc: cipher);
        await Future<void>.delayed(delayDuration);
        expect(readCalls, 1, reason: 'the first operation entered and is waiting at the gate');

        final f2 = storage.addEntry(entryMeta: m2, entryValue: v2, cipherFunc: cipher);
        await Future<void>.delayed(delayDuration);
        expect(readCalls, 1, reason: 'the second operation must not enter until the lock is released');

        gate.complete();
        final ids = await Future.wait([f1, f2]);

        // Assert
        final updated = await _Helpers.readStorageData(storageFile);
        final entryIds = updated.entries.map((e) => e.id.value).toList();
        expect(entryIds, containsAll(ids.map((e) => e.value)));
        expect(updated.entries.length, 3, reason: 'initial + 2 new entries');
        expect(ids[0] != ids[1], isTrue, reason: 'EntryIds must be different');
        expect(readCalls, greaterThanOrEqualTo(2), reason: 'after releasing the lock, a second read cycle occurred');
      });

      test('concurrent addEntry and deleteEntry are serialized', () async {
        // Arrange
        const id1 = 'id1';
        const deleteId = 'deleteId';
        final masterKey = await CryptographyUtils.generateAESKey();
        final cipher = _Helpers.createMockPasswordCipherFunc(masterKeyBytes: masterKey.bytes);
        final wrapPwd = KeyWrap(origin: Origin.pwd, encryptedKey: masterKey.bytes);
        final entry1 = await _Helpers.createEncryptedEntry(masterKey: masterKey, id: id1);
        final entryDelete = await _Helpers.createEncryptedEntry(masterKey: masterKey, id: deleteId);
        final signed = await _Helpers.createStorageData(
          wraps: [wrapPwd],
          entries: [entry1, entryDelete],
          masterKey: masterKey,
        );
        await _Helpers.writeStorageData(storageFile, signed);

        final gate = Completer<void>();
        var readCalls = 0;

        when(() => gateFile.readAsString()).thenAnswer((_) async {
          readCalls++;
          if (readCalls == 1 && !gate.isCompleted) {
            await gate.future;
          }
          return storageFile.readAsString();
        });

        // Act
        final addIdFuture = storage.addEntry(
          entryMeta: _Helpers.createEntryMeta([3]),
          entryValue: _Helpers.createEntryValue([3]),
          cipherFunc: cipher,
        );
        await Future<void>.delayed(delayDuration);
        expect(readCalls, 1);

        final delFuture = storage.deleteEntry(id: EntryId(deleteId), cipherFunc: cipher);
        await Future<void>.delayed(delayDuration);
        expect(readCalls, 1, reason: 'delete must await');

        gate.complete();
        final results = await Future.wait([addIdFuture, delFuture]);

        // Assert
        final newId = (results.first as EntryId).value;
        final deleteOk = results.last as bool;
        expect(deleteOk, isTrue);

        final data = await _Helpers.readStorageData(storageFile);
        final ids = data.entries.map((e) => e.id.value).toList();
        expect(ids, contains(id1));
        expect(ids, contains(newId));
        expect(ids, isNot(contains(deleteId)));
        expect(readCalls, greaterThanOrEqualTo(2));
      });

      test('concurrent updateEntry and readValue are serialized: read sees updated value', () async {
        // Arrange
        const entryId = 'entryId';
        final masterKey = await CryptographyUtils.generateAESKey();
        final cipher = _Helpers.createMockPasswordCipherFunc(masterKeyBytes: masterKey.bytes);
        final wrapPwd = KeyWrap(origin: Origin.pwd, encryptedKey: masterKey.bytes);
        final entry = await _Helpers.createEncryptedEntry(
          masterKey: masterKey,
          id: entryId,
          valueBytes: [1],
        );
        final signed = await _Helpers.createStorageData(
          wraps: [wrapPwd],
          entries: [entry],
          masterKey: masterKey,
        );
        await _Helpers.writeStorageData(storageFile, signed);

        final gate = Completer<void>();
        var readCalls = 0;

        when(() => gateFile.readAsString()).thenAnswer((_) async {
          readCalls++;
          if (readCalls == 1 && !gate.isCompleted) {
            await gate.future;
          }
          return storageFile.readAsString();
        });

        final newVal = _Helpers.createEntryValue(const [2]);

        // Act:
        final update = storage.updateEntry(id: EntryId(entryId), cipherFunc: cipher, entryValue: newVal);
        await Future<void>.delayed(delayDuration);
        expect(readCalls, 1);

        final read = storage.readValue(id: EntryId(entryId), cipherFunc: cipher);
        await Future<void>.delayed(delayDuration);
        expect(readCalls, 1);

        gate.complete();
        await update;
        final readValue = await read;

        // Assert
        expect(readValue.bytes, orderedEquals(const [2]));

        final persisted = await storage.readValue(id: EntryId(entryId), cipherFunc: cipher);
        expect(persisted.bytes, orderedEquals(const [2]));
      });

      test('concurrent addOrReplaceWrap and readValue are serialized', () async {
        // Arrange
        const entryId = 'entryId';
        const valueBytes = [2];
        final masterKey = await CryptographyUtils.generateAESKey();
        final pwd = _Helpers.createMockPasswordCipherFunc(masterKeyBytes: masterKey.bytes);
        final bio = _Helpers.createMockBioCipherFunc(masterKeyBytes: masterKey.bytes);
        final wrapPwd = KeyWrap(origin: Origin.pwd, encryptedKey: masterKey.bytes);
        final entry = await _Helpers.createEncryptedEntry(
          masterKey: masterKey,
          id: entryId,
          valueBytes: valueBytes,
        );
        final signed = await _Helpers.createStorageData(
          wraps: [wrapPwd],
          entries: [entry],
          masterKey: masterKey,
        );
        await _Helpers.writeStorageData(storageFile, signed);

        final gate = Completer<void>();
        var readCalls = 0;

        when(() => gateFile.readAsString()).thenAnswer((_) async {
          readCalls++;
          if (readCalls == 1 && !gate.isCompleted) {
            await gate.future;
          }
          return storageFile.readAsString();
        });

        // Act:
        final addWrapF = storage.addOrReplaceWrap(newWrapFunc: bio, existingWrapFunc: pwd);
        await Future<void>.delayed(delayDuration);
        expect(readCalls, 1);

        final readPwdF = storage.readValue(id: EntryId(entryId), cipherFunc: pwd);
        await Future<void>.delayed(delayDuration);
        expect(readCalls, 1, reason: 'read must await addOrReplaceWrap');

        gate.complete();
        final results = await Future.wait([addWrapF, readPwdF]);

        // Assert
        final value = results[1] as EntryValue;
        expect(value.bytes, orderedEquals(valueBytes));

        final after = await _Helpers.readStorageData(storageFile);
        final origins = after.masterKey.wraps.map((w) => w.origin).toList();
        expect(origins, containsAll([Origin.pwd, Origin.bio]));

        final v2 = await storage.readValue(id: EntryId(entryId), cipherFunc: bio);
        expect(v2.bytes, orderedEquals(valueBytes));
      });

      test('concurrent erase and addEntry are serialized: erase runs after addEntry finishes', () async {
        // Arrange
        const entryId = 'entryId';
        final masterKey = await CryptographyUtils.generateAESKey();
        final cipher = _Helpers.createMockPasswordCipherFunc(masterKeyBytes: masterKey.bytes);
        final wrapPwd = KeyWrap(origin: Origin.pwd, encryptedKey: masterKey.bytes);
        final entry = await _Helpers.createEncryptedEntry(masterKey: masterKey, id: entryId);

        final signed = await _Helpers.createStorageData(
          wraps: [wrapPwd],
          entries: [entry],
          masterKey: masterKey,
        );
        await _Helpers.writeStorageData(storageFile, signed);

        final gate = Completer<void>();
        var readCalls = 0;
        var deleteCalls = 0;

        when(() => gateFile.delete()).thenAnswer((_) {
          deleteCalls++;
          return storageFile.delete();
        });
        when(() => gateFile.readAsString()).thenAnswer((_) async {
          readCalls++;
          if (readCalls == 1 && !gate.isCompleted) {
            await gate.future;
          }
          return storageFile.readAsString();
        });

        // Act: addEntry enters and blocks; erase is queued.
        final addF = storage.addEntry(
          entryMeta: _Helpers.createEntryMeta([1]),
          entryValue: _Helpers.createEntryValue([1]),
          cipherFunc: cipher,
        );
        await Future<void>.delayed(delayDuration);
        expect(readCalls, 1, reason: 'addEntry must enter and block at the gate');

        final eraseF = storage.erase();
        await Future<void>.delayed(delayDuration);
        expect(readCalls, 1, reason: 'erase must wait for addEntry to finish');
        expect(deleteCalls, 0, reason: 'there must be no deletions before addEntry finishes');

        // Unblock addEntry — then erase will run.
        gate.complete();
        await addF;
        final erased = await eraseF;

        // Assert
        expect(erased, isTrue);
        expect(deleteCalls, greaterThanOrEqualTo(1), reason: 'there must be at least one deletion');
        expect(await storageFile.exists(), isFalse, reason: 'file must not exist after erase');
        expect(readCalls, 1, reason: 'erase does not trigger a read; the only read was from addEntry');
      });
    });
  });
}
