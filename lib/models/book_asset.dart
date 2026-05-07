import 'package:isar/isar.dart';

part 'book_asset.g.dart';

@collection
class BookAsset {
  Id id = Isar.autoIncrement;

  @Index()
  late int bookId;

  @Index()
  late String assetKey;

  String? originalHref;

  @Index()
  String? normalizedHref;

  String? mimeType;

  late String relativePath;

  int? byteLength;

  late DateTime createdAt;
}
