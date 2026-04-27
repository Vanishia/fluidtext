import 'package:isar/isar.dart';

part 'book_remark.g.dart';

@collection
class BookRemark {
  Id id = Isar.autoIncrement;

  late String title;

  late DateTime updatedAt;
}
