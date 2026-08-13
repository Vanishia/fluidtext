import 'dart:convert';
import 'dart:io';

import '../storage/json_file_store.dart';
import '../storage/storage_layout.dart';

class ReaderSessionService {
  ReaderSessionService({StorageLayoutProvider? storageLayout})
    : _storageLayout = storageLayout ?? AppStorageResolver.activeRuntimeLayout;

  static final instance = ReaderSessionService();

  final StorageLayoutProvider _storageLayout;

  Future<List<int>> loadLastOpenedBookIds() async {
    try {
      final file = await _sessionFile();
      if (!await file.exists()) return const <int>[];

      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final ids = json['lastOpenedBookIds'];
      if (ids is! List) return const <int>[];

      return ids.whereType<num>().map((value) => value.toInt()).toList();
    } catch (_) {
      return const <int>[];
    }
  }

  Future<void> saveLastOpenedBookIds(List<int> bookIds) async {
    final file = await _sessionFile();
    final payload = <String, Object?>{
      'lastOpenedBookIds': bookIds,
      'savedAt': DateTime.now().toIso8601String(),
    };
    await JsonFileStore.writeAtomic(file, payload);
  }

  Future<Map<String, dynamic>?> exportJson() async {
    try {
      final file = await _sessionFile();
      if (!await file.exists()) return null;
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return json;
    } catch (_) {
      return null;
    }
  }

  Future<File> _sessionFile() async {
    return (await _storageLayout()).readerSessionFile;
  }
}
