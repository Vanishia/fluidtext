import 'dart:async';

import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import '../models/book.dart';
import '../models/book_card.dart';

class IsarDb {
  IsarDb._();

  static final IsarDb instance = IsarDb._();

  Isar? _isar;

  Future<Isar> get isar async {
    final existing = _isar;
    if (existing != null) return existing;

    final dir = await getApplicationDocumentsDirectory();
    final opened = await Isar.open(
      [BookSchema, BookCardSchema],
      directory: dir.path,
      inspector: true,
    );
    _isar = opened;
    return opened;
  }
}
