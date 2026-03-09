import 'dart:typed_data';

import 'package:epub_plus/epub_plus.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:isar/isar.dart';

import '../models/book.dart';
import '../models/book_card.dart';
import 'text_splitter.dart';

class BookImportResult {
  BookImportResult({
    required this.bookId,
    required this.bookTitle,
    required this.insertedCards,
  });

  final int bookId;
  final String bookTitle;
  final int insertedCards;
}

class BookImportService {
  const BookImportService();

  Future<BookImportResult> importEpubBytes({
    required Isar isar,
    required Uint8List bytes,
    int targetCharsPerCard = 300,
  }) async {
    final epub = await EpubReader.readBook(bytes);
    final rawTitle = (epub.title ?? '').trim();
    final title = rawTitle.isEmpty ? 'Untitled' : rawTitle;

    final bookId = await isar.writeTxn(() async {
      final book = Book()
        ..title = title
        ..createdAt = DateTime.now();
      return await isar.books.put(book);
    });

    var cardIndex = 0;
    var insertedCards = 0;

    for (final chapterText in _chapterTexts(epub.chapters)) {
      final cardsToInsert = <BookCard>[];
      final splitter = TextSplitter(targetChars: targetCharsPerCard);

      for (final piece in splitter.split(chapterText)) {
        final trimmed = piece.trim();
        if (trimmed.isEmpty) continue;

        cardsToInsert.add(
          BookCard()
            ..bookId = bookId
            ..bookTitle = title
            ..cardIndex = cardIndex
            ..content = trimmed,
        );
        cardIndex++;
      }

      if (cardsToInsert.isEmpty) continue;

      await isar.writeTxn(() async {
        await isar.bookCards.putAll(cardsToInsert);
      });
      insertedCards += cardsToInsert.length;
    }

    return BookImportResult(
      bookId: bookId,
      bookTitle: title,
      insertedCards: insertedCards,
    );
  }

  Iterable<String> _chapterTexts(List<EpubChapter> chapters) sync* {
    for (final chapter in chapters) {
      final html = chapter.htmlContent;
      if (html != null && html.trim().isNotEmpty) {
        final document = html_parser.parse(html);
        final text = document.body?.text ?? document.documentElement?.text ?? '';
        if (text.trim().isNotEmpty) yield text;
      }
      if (chapter.subChapters.isNotEmpty) {
        yield* _chapterTexts(chapter.subChapters);
      }
    }
  }
}
