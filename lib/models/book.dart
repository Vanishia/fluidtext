import 'package:isar/isar.dart';

part 'book.g.dart';

@collection
class Book {
  Id id = Isar.autoIncrement;

  @Index()
  late String title;

  late DateTime createdAt;

  @Index()
  String? fileHash;

  @Index()
  String? contentFingerprint;

  String? sourceFileName;

  DateTime? importedAt;

  int? cardCount;

  int? textCharCount;
}
