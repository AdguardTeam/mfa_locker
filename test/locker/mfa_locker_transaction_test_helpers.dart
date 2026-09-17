part of 'mfa_locker_transaction_test.dart';

abstract class _TransactionHelpers {
  static Future<EntryValue> readValueFromFile(
    EncryptedStorage storage,
    CipherFunc cipher,
    EntryId id,
  ) async {
    final transaction = await storage.openTransaction(cipherFunc: cipher);
    try {
      return await transaction.readValue(id);
    } finally {
      transaction.erase();
    }
  }

  static Future<void> updateValueInFile(
    EncryptedStorage storage,
    CipherFunc cipher,
    EntryId id,
    List<int> bytes,
  ) async {
    final transaction = await storage.openTransaction(cipherFunc: cipher);
    try {
      await transaction.updateEntry(EntryUpdateInput(id: id, value: _Helpers.createEntryValue(bytes)));
      await storage.closeTransaction(transaction);
    } finally {
      transaction.erase();
    }
  }
}
