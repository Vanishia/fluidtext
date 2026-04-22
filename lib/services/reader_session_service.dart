import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class ReaderSessionService {
  ReaderSessionService._();

  static final instance = ReaderSessionService._();
  static const _fileName = 'reader_session.json';

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
    await file.writeAsString(jsonEncode(payload), flush: true);
  }

  Future<File> _sessionFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }
}
