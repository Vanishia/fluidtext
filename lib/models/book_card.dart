import 'package:isar/isar.dart';

part 'book_card.g.dart';

@collection
class BookCard {
  Id id = Isar.autoIncrement;

  @Index()
  late int bookId;

  late String bookTitle;

  @Index()
  late int cardIndex;

  late String content;

  bool isRead = false;

  DateTime? readAt;

  bool isFavorite = false;
}

