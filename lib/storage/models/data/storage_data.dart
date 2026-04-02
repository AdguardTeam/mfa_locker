import 'dart:convert';

import 'dart:typed_data';

import 'package:locker/storage/models/data/storage_entry.dart';
import 'package:locker/storage/models/data/wrapped_key.dart';

const _entriesFieldName = 'entries';
const _masterKeyFieldName = 'masterKey';
const _hmacKeyFieldName = 'hmacKey';
const _hmacSignatureFieldName = 'hmacSignature';
const _saltFieldName = 'salt';
const _lockTimeoutFieldName = 'lockTimeout';

class StorageData {
  final List<StorageEntry> entries;
  final WrappedKey masterKey;
  final Uint8List salt;
  final Uint8List? hmacKey;
  final Uint8List? hmacSignature;

  /// The auto-lock timeout in milliseconds
  final int lockTimeout;

  const StorageData({
    required this.entries,
    required this.masterKey,
    required this.salt,
    required this.lockTimeout,
    this.hmacKey,
    this.hmacSignature,
  });

  StorageData copyWith({
    List<StorageEntry>? entries,
    WrappedKey? masterKey,
    Uint8List? hmacKey,
    Uint8List? hmacSignature,
    Uint8List? salt,
    int? lockTimeout,
  }) =>
      StorageData(
        entries: entries ?? this.entries,
        masterKey: masterKey ?? this.masterKey,
        hmacKey: hmacKey ?? this.hmacKey,
        hmacSignature: hmacSignature ?? this.hmacSignature,
        salt: salt ?? this.salt,
        lockTimeout: lockTimeout ?? this.lockTimeout,
      );

  /// Returns a copy with hmacSignature set to null
  StorageData withoutHmacSignature() => StorageData(
        entries: entries,
        masterKey: masterKey,
        hmacKey: hmacKey,
        salt: salt,
        lockTimeout: lockTimeout,
      );

  factory StorageData.fromJson(Map<String, Object?> json) {
    final entriesList =
        (json[_entriesFieldName] as List).map((e) => StorageEntry.fromJson(e as Map<String, Object?>)).toList();
    final masterKey = WrappedKey.fromJson(json[_masterKeyFieldName] as Map<String, Object?>);
    final hmacKeyStr = json[_hmacKeyFieldName] as String?;
    final hmacSignatureStr = json[_hmacSignatureFieldName] as String?;
    final saltStr = json[_saltFieldName] as String;
    final lockTimeout = json[_lockTimeoutFieldName] as int;

    return StorageData(
      entries: entriesList,
      masterKey: masterKey,
      salt: base64.decode(saltStr),
      hmacKey: hmacKeyStr == null ? null : base64.decode(hmacKeyStr),
      hmacSignature: hmacSignatureStr == null ? null : base64.decode(hmacSignatureStr),
      lockTimeout: lockTimeout,
    );
  }

  Map<String, Object?> toJson() => {
        _entriesFieldName: entries.map((e) => e.toJson()).toList(),
        _masterKeyFieldName: masterKey.toJson(),
        _saltFieldName: base64.encode(salt),
        if (hmacKey != null) _hmacKeyFieldName: base64.encode(hmacKey!),
        if (hmacSignature != null) _hmacSignatureFieldName: base64.encode(hmacSignature!),
        _lockTimeoutFieldName: lockTimeout,
      };
}
