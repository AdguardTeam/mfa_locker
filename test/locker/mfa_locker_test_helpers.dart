part of 'mfa_locker_test.dart';

typedef _StorageHelpers = EncryptedStorageTestHelpers;

abstract class _Helpers {
  static const lockTimeout = Duration(milliseconds: 200);

  static MockPasswordCipherFunc createMockPasswordCipherFunc({
    List<int> salt = const [0],
    List<int> password = const [0],
  }) {
    final cipher = MockPasswordCipherFunc();

    when(() => cipher.origin).thenReturn(Origin.pwd);
    when(() => cipher.salt).thenReturn(Uint8List.fromList(salt));
    when(() => cipher.password).thenReturn(_StorageHelpers.createErasable(password));
    when(() => cipher.erase()).thenAnswer((_) {});

    return cipher;
  }

  static MockBioCipherFunc createMockBioCipherFunc() {
    final cipher = MockBioCipherFunc();

    when(() => cipher.origin).thenReturn(Origin.bio);
    when(() => cipher.erase()).thenAnswer((_) {});

    return cipher;
  }

  static Map<EntryId, EntryMeta> stubReadAllMeta(
    MockEncryptedStorage storage,
    CipherFunc cipher, {
    String id = 'a',
    List<int> metaBytes = const [1],
  }) {
    final result = {
      EntryId(id): _StorageHelpers.createEntryMeta(metaBytes),
    };

    when(() => storage.readAllMeta(cipherFunc: cipher)).thenAnswer(
      (_) async => result,
    );

    return result;
  }

  static void verifyErased(Erasable erasable) {
    if (erasable is Mock) {
      verify(() => erasable.erase()).called(greaterThan(0));
    } else {
      expect(erasable.isErased, isTrue);
    }
  }

  static void verifyErasedAll(List<Erasable> erasables) {
    for (final erasable in erasables) {
      verifyErased(erasable);
    }
  }
}
