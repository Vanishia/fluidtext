import 'dart:developer' as developer;
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
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
    required this.wasDuplicate,
    this.matchedBy,
  });

  final int bookId;
  final String bookTitle;
  final int insertedCards;
  final bool wasDuplicate;
  final String? matchedBy;
}

class BookImportService {
  const BookImportService();

  Future<BookImportResult> importEpubBytes({
    required Isar isar,
    required Uint8List bytes,
    String? sourceFileName,
    int targetCharsPerCard = 300,
  }) async {
    developer.log(
      'Starting EPUB import: bytes=${bytes.length}, targetCharsPerCard=$targetCharsPerCard',
      name: 'BookImportService',
    );

    final fileHash = sha256.convert(bytes).toString();
    final epub = await EpubReader.readBook(bytes);
    final rawTitle = (epub.title ?? '').trim();
    final title = rawTitle.isEmpty ? 'Untitled' : rawTitle;
    final contentTextFiles = epub.content?.html.length ?? 0;
    final contentAllFiles = epub.content?.allFiles.length ?? 0;
    developer.log(
      'Parsed EPUB metadata: title="$title", topLevelChapters=${epub.chapters.length}, htmlFiles=$contentTextFiles, allFiles=$contentAllFiles',
      name: 'BookImportService',
    );

    final draft = _buildImportDraft(
      title: title,
      chapters: _chapterContents(epub.chapters).toList(growable: false),
      targetCharsPerCard: targetCharsPerCard,
    );
    if (draft.cards.isEmpty) {
      throw const BookImportException('没有从 EPUB 中解析出可导入的文本');
    }

    final existingByFileHash = await _findBestCompleteBookByFileHash(
      isar: isar,
      fileHash: fileHash,
      contentFingerprint: draft.contentFingerprint,
      cardCount: draft.cards.length,
    );
    if (existingByFileHash != null) {
      developer.log(
        'Duplicate EPUB import matched by fileHash: bookId=${existingByFileHash.id}',
        name: 'BookImportService',
      );
      return BookImportResult(
        bookId: existingByFileHash.id,
        bookTitle: existingByFileHash.title,
        insertedCards: 0,
        wasDuplicate: true,
        matchedBy: 'fileHash',
      );
    }

    final existingByFingerprint =
        await _findBookByContentFingerprintWithLegacyBackfill(
          isar: isar,
          contentFingerprint: draft.contentFingerprint,
          fileHash: fileHash,
          sourceFileName: sourceFileName,
          cardCount: draft.cards.length,
          textCharCount: draft.textCharCount,
        );
    if (existingByFingerprint != null) {
      developer.log(
        'Duplicate EPUB import matched by contentFingerprint: bookId=${existingByFingerprint.id}',
        name: 'BookImportService',
      );
      return BookImportResult(
        bookId: existingByFingerprint.id,
        bookTitle: existingByFingerprint.title,
        insertedCards: 0,
        wasDuplicate: true,
        matchedBy: 'contentFingerprint',
      );
    }

    final now = DateTime.now();
    final book = Book()
      ..title = title
      ..createdAt = now
      ..fileHash = fileHash
      ..contentFingerprint = draft.contentFingerprint
      ..sourceFileName = sourceFileName
      ..importedAt = now
      ..cardCount = draft.cards.length
      ..textCharCount = draft.textCharCount;

    final bookId = await isar.writeTxn(() async {
      final newBookId = await isar.books.put(book);
      for (final card in draft.cards) {
        card.bookId = newBookId;
      }
      await isar.bookCards.putAll(draft.cards);
      return newBookId;
    });

    developer.log(
      'Finished EPUB import: bookId=$bookId, insertedCards=${draft.cards.length}',
      name: 'BookImportService',
    );

    return BookImportResult(
      bookId: bookId,
      bookTitle: title,
      insertedCards: draft.cards.length,
      wasDuplicate: false,
    );
  }

  _ImportDraft _buildImportDraft({
    required String title,
    required List<_ChapterContent> chapters,
    required int targetCharsPerCard,
  }) {
    final cards = <BookCard>[];
    var cardIndex = 0;
    var chapterIndex = 0;
    var textCharCount = 0;

    for (final chapter in chapters) {
      developer.log(
        'Processing chapter[$chapterIndex]: textLength=${chapter.text.length}',
        name: 'BookImportService',
      );
      final splitter = TextSplitter(targetChars: targetCharsPerCard);
      var pieceCount = 0;
      var chapterCardIndex = 0;
      var chapterCards = 0;

      textCharCount += _normalizeForFingerprint(chapter.text).length;

      for (final piece in splitter.split(chapter.text)) {
        pieceCount++;
        final trimmed = piece.trim();
        if (trimmed.isEmpty) continue;

        cards.add(
          BookCard()
            ..bookId = 0
            ..bookTitle = title
            ..cardIndex = cardIndex
            ..chapterIndex = chapterIndex
            ..chapterCardIndex = chapterCardIndex
            ..chapterTitle = chapter.title
            ..content = trimmed,
        );
        cardIndex++;
        chapterCardIndex++;
        chapterCards++;
      }

      developer.log(
        'Split chapter[$chapterIndex] into $pieceCount pieces, $chapterCards non-empty cards',
        name: 'BookImportService',
      );

      if (chapterCards > 0) {
        chapterIndex++;
      }
    }

    return _ImportDraft(
      cards: cards,
      contentFingerprint: _contentFingerprintForCards(cards),
      textCharCount: textCharCount,
    );
  }

  Future<Book?> _findBestCompleteBookByFileHash({
    required Isar isar,
    required String fileHash,
    required String contentFingerprint,
    required int cardCount,
  }) async {
    final matches = await isar.books
        .filter()
        .fileHashEqualTo(fileHash)
        .findAll();
    if (matches.isEmpty) return null;

    final completeMatches = <Book>[];
    for (final book in matches) {
      final actualCardCount = await isar.bookCards
          .filter()
          .bookIdEqualTo(book.id)
          .count();
      if (actualCardCount != cardCount) {
        developer.log(
          'Skipping incomplete fileHash duplicate: bookId=${book.id}, actualCards=$actualCardCount, expectedCards=$cardCount',
          name: 'BookImportService',
        );
        continue;
      }

      if (book.contentFingerprint == contentFingerprint) {
        completeMatches.add(book);
        continue;
      }

      if (book.contentFingerprint == null) {
        final cards = await isar.bookCards
            .filter()
            .bookIdEqualTo(book.id)
            .sortByCardIndex()
            .findAll();
        if (_contentFingerprintForCards(cards) == contentFingerprint) {
          completeMatches.add(book);
        }
      }
    }

    if (completeMatches.isEmpty) return null;
    return _bestDuplicateMatch(isar, completeMatches);
  }

  Future<Book?> _findBookByContentFingerprintWithLegacyBackfill({
    required Isar isar,
    required String contentFingerprint,
    required String fileHash,
    required String? sourceFileName,
    required int cardCount,
    required int textCharCount,
  }) async {
    final matches = await isar.books
        .filter()
        .contentFingerprintEqualTo(contentFingerprint)
        .findAll();
    final completeMatches = <Book>[];
    for (final book in matches) {
      final actualCardCount = await isar.bookCards
          .filter()
          .bookIdEqualTo(book.id)
          .count();
      if (actualCardCount == cardCount) {
        completeMatches.add(book);
      } else {
        developer.log(
          'Skipping incomplete contentFingerprint duplicate: bookId=${book.id}, actualCards=$actualCardCount, expectedCards=$cardCount',
          name: 'BookImportService',
        );
      }
    }

    final legacyBooks = await isar.books
        .filter()
        .contentFingerprintIsNull()
        .findAll();
    for (final legacyBook in legacyBooks) {
      final legacyCards = await isar.bookCards
          .filter()
          .bookIdEqualTo(legacyBook.id)
          .sortByCardIndex()
          .findAll();
      if (legacyCards.isEmpty) continue;

      final legacyFingerprint = _contentFingerprintForCards(legacyCards);
      final legacyTextCharCount = _textCharCountForCards(legacyCards);
      final isMatch = legacyFingerprint == contentFingerprint;
      await _fillMissingIdentity(
        isar: isar,
        book: legacyBook,
        contentFingerprint: legacyFingerprint,
        fileHash: null,
        sourceFileName: null,
        cardCount: legacyCards.length,
        textCharCount: legacyTextCharCount,
      );

      if (isMatch && legacyCards.length == cardCount) {
        completeMatches.add(legacyBook);
      } else if (isMatch) {
        developer.log(
          'Skipping incomplete legacy duplicate: bookId=${legacyBook.id}, actualCards=${legacyCards.length}, expectedCards=$cardCount',
          name: 'BookImportService',
        );
      }
    }

    if (completeMatches.isEmpty) return null;
    final best = await _bestDuplicateMatch(isar, completeMatches);
    await _fillMissingIdentity(
      isar: isar,
      book: best,
      contentFingerprint: contentFingerprint,
      fileHash: fileHash,
      sourceFileName: sourceFileName,
      cardCount: cardCount,
      textCharCount: textCharCount,
    );
    return best;
  }

  Future<Book> _bestDuplicateMatch(Isar isar, List<Book> matches) async {
    if (matches.length == 1) return matches.single;

    Book? best;
    var bestScore = -1;
    for (final book in matches) {
      final readCount = await isar.bookCards
          .filter()
          .bookIdEqualTo(book.id)
          .and()
          .isReadEqualTo(true)
          .count();
      final favoriteCount = await isar.bookCards
          .filter()
          .bookIdEqualTo(book.id)
          .and()
          .isFavoriteEqualTo(true)
          .count();
      final score = favoriteCount * 1000000 + readCount;
      if (score > bestScore) {
        best = book;
        bestScore = score;
      }
    }

    return best ?? matches.first;
  }

  Future<void> _fillMissingIdentity({
    required Isar isar,
    required Book book,
    required String contentFingerprint,
    String? fileHash,
    required String? sourceFileName,
    required int cardCount,
    required int textCharCount,
  }) async {
    final needsUpdate =
        book.contentFingerprint == null ||
        (fileHash != null && book.fileHash == null) ||
        (sourceFileName != null && book.sourceFileName == null) ||
        book.cardCount == null ||
        book.textCharCount == null ||
        book.importedAt == null;
    if (!needsUpdate) {
      return;
    }

    await isar.writeTxn(() async {
      book.contentFingerprint ??= contentFingerprint;
      if (fileHash != null) book.fileHash ??= fileHash;
      if (sourceFileName != null) book.sourceFileName ??= sourceFileName;
      book.importedAt ??= book.createdAt;
      book.cardCount ??= cardCount;
      book.textCharCount ??= textCharCount;
      await isar.books.put(book);
    });
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
        final text =
            document.body?.text ?? document.documentElement?.text ?? '';
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

  String _normalizeForFingerprint(String text) {
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _contentFingerprintForCards(List<BookCard> cards) {
    final sorted = List<BookCard>.of(cards)
      ..sort((a, b) => a.cardIndex.compareTo(b.cardIndex));
    final buffer = StringBuffer()..writeln(sorted.length);

    for (final card in sorted) {
      final normalized = _normalizeForFingerprint(card.content);
      buffer
        ..write(card.chapterIndex)
        ..write('|')
        ..write(card.chapterCardIndex)
        ..write('|')
        ..writeln(normalized.length)
        ..writeln(normalized);
    }

    return sha256.convert(utf8.encode(buffer.toString())).toString();
  }

  int _textCharCountForCards(List<BookCard> cards) {
    return cards.fold<int>(
      0,
      (sum, card) => sum + _normalizeForFingerprint(card.content).length,
    );
  }
}

class BookImportException implements Exception {
  const BookImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _ImportDraft {
  const _ImportDraft({
    required this.cards,
    required this.contentFingerprint,
    required this.textCharCount,
  });

  final List<BookCard> cards;
  final String contentFingerprint;
  final int textCharCount;
}

class _ChapterContent {
  const _ChapterContent({required this.text, required this.title});

  final String text;
  final String? title;
}
