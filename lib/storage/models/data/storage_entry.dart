import 'dart:convert';

import 'dart:typed_data';

import 'package:locker/storage/models/domain/entry_id.dart';

const _idFieldName = 'id';
const _metaFieldName = 'meta';
const _valueFieldName = 'value';

class StorageEntry {
  final EntryId id;
  final Uint8List encryptedMeta;
  final Uint8List encryptedValue;

  const StorageEntry({
    required this.id,
    required this.encryptedMeta,
    required this.encryptedValue,
  });

  StorageEntry copyWith({
    Uint8List? encryptedMeta,
    Uint8List? encryptedValue,
  }) =>
      StorageEntry(
        id: id,
        encryptedMeta: encryptedMeta ?? this.encryptedMeta,
        encryptedValue: encryptedValue ?? this.encryptedValue,
      );

  factory StorageEntry.fromJson(Map<String, Object?> json) {
    final idStr = json[_idFieldName] as String;
    final metaStr = json[_metaFieldName] as String;
    final valueStr = json[_valueFieldName] as String;

    return StorageEntry(
      id: EntryId(utf8.decode(base64.decode(idStr))),
      encryptedMeta: base64.decode(metaStr),
      encryptedValue: base64.decode(valueStr),
    );
  }

  Map<String, Object?> toJson() => {
        _idFieldName: base64.encode(utf8.encode(id.value)),
        _metaFieldName: base64.encode(encryptedMeta),
        _valueFieldName: base64.encode(encryptedValue),
      };
}
