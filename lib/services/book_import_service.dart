import 'dart:developer' as developer;
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
    developer.log(
      'Starting EPUB import: bytes=${bytes.length}, targetCharsPerCard=$targetCharsPerCard',
      name: 'BookImportService',
    );

    final epub = await EpubReader.readBook(bytes);
    final rawTitle = (epub.title ?? '').trim();
    final title = rawTitle.isEmpty ? 'Untitled' : rawTitle;
    developer.log(
      'Parsed EPUB metadata: title="$title", topLevelChapters=${epub.chapters.length}',
      name: 'BookImportService',
    );

    final bookId = await isar.writeTxn(() async {
      final book = Book()
        ..title = title
        ..createdAt = DateTime.now();
      return await isar.books.put(book);
    });

    var cardIndex = 0;
    var insertedCards = 0;
    var chapterIndex = 0;

    for (final chapter in _chapterContents(epub.chapters)) {
      developer.log(
        'Processing chapter[$chapterIndex]: textLength=${chapter.text.length}',
        name: 'BookImportService',
      );
      final cardsToInsert = <BookCard>[];
      final splitter = TextSplitter(targetChars: targetCharsPerCard);
      var pieceCount = 0;
      var chapterCardIndex = 0;

      for (final piece in splitter.split(chapter.text)) {
        pieceCount++;
        final trimmed = piece.trim();
        if (trimmed.isEmpty) continue;

        cardsToInsert.add(
          BookCard()
            ..bookId = bookId
            ..bookTitle = title
            ..cardIndex = cardIndex
            ..chapterIndex = chapterIndex
            ..chapterCardIndex = chapterCardIndex
            ..chapterTitle = chapter.title
            ..content = trimmed,
        );
        cardIndex++;
        chapterCardIndex++;
      }

      developer.log(
        'Split chapter[$chapterIndex] into $pieceCount pieces, ${cardsToInsert.length} non-empty cards',
        name: 'BookImportService',
      );

      if (cardsToInsert.isEmpty) continue;

      await isar.writeTxn(() async {
        await isar.bookCards.putAll(cardsToInsert);
      });
      insertedCards += cardsToInsert.length;
      chapterIndex++;
    }

    developer.log(
      'Finished EPUB import: bookId=$bookId, insertedCards=$insertedCards',
      name: 'BookImportService',
    );

    return BookImportResult(
      bookId: bookId,
      bookTitle: title,
      insertedCards: insertedCards,
    );
  }

  Iterable<_ChapterContent> _chapterContents(List<EpubChapter> chapters) sync* {
    for (var index = 0; index < chapters.length; index++) {
      final chapter = chapters[index];
      final html = chapter.htmlContent;
      final chapterTitle = (chapter.title ?? '').trim();
      developer.log(
        'Inspecting chapter node[$index]: title="${chapterTitle.isEmpty ? '(untitled)' : chapterTitle}", htmlLength=${html?.length ?? 0}, subChapters=${chapter.subChapters.length}',
        name: 'BookImportService',
      );

      if (html != null && html.trim().isNotEmpty) {
        final document = html_parser.parse(html);
        final text = document.body?.text ?? document.documentElement?.text ?? '';
        final trimmedText = text.trim();
        if (trimmedText.isNotEmpty) {
          developer.log(
            'Yielding chapter node[$index] textLength=${trimmedText.length}',
            name: 'BookImportService',
          );
          yield _ChapterContent(
            title: chapterTitle.isEmpty ? null : chapterTitle,
            text: trimmedText,
          );
        } else {
          developer.log(
            'Chapter node[$index] produced empty text after HTML parsing',
            name: 'BookImportService',
          );
        }
      } else {
        developer.log(
          'Chapter node[$index] has empty htmlContent',
          name: 'BookImportService',
        );
      }

      if (chapter.subChapters.isNotEmpty) {
        yield* _chapterContents(chapter.subChapters);
      }
    }
  }
}

class _ChapterContent {
  const _ChapterContent({
    required this.text,
    required this.title,
  });

  final String text;
  final String? title;
}
