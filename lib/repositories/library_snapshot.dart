import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/book.dart';
import '../models/book_asset.dart';
import '../models/book_card.dart';

class ImportBookDraft {
  ImportBookDraft({
    required this.title,
    required this.createdAt,
    required this.fileHash,
    required this.contentFingerprint,
    required this.sourceFileName,
    required this.importedAt,
    required this.cardCount,
    required this.textCharCount,
    required this.assetRootKey,
    required this.cards,
    required this.assets,
  });

  final String title;
  final DateTime createdAt;
  final String fileHash;
  final String contentFingerprint;
  final String? sourceFileName;
  final DateTime importedAt;
  final int cardCount;
  final int textCharCount;
  final String? assetRootKey;
  final List<BookCardDraft> cards;
  final List<BookAssetDraft> assets;
}

class BookCardDraft {
  const BookCardDraft({
    required this.bookTitle,
    required this.cardIndex,
    required this.chapterIndex,
    required this.chapterCardIndex,
    required this.chapterTitle,
    required this.content,
    required this.blocksJson,
  });

  factory BookCardDraft.fromBookCard(BookCard card) {
    return BookCardDraft(
      bookTitle: card.bookTitle,
      cardIndex: card.cardIndex,
      chapterIndex: card.chapterIndex,
      chapterCardIndex: card.chapterCardIndex,
      chapterTitle: card.chapterTitle,
      content: card.content,
      blocksJson: card.blocksJson,
    );
  }

  final String bookTitle;
  final int cardIndex;
  final int chapterIndex;
  final int chapterCardIndex;
  final String? chapterTitle;
  final String content;
  final String? blocksJson;
}

class BookAssetDraft {
  const BookAssetDraft({
    required this.assetKey,
    required this.originalHref,
    required this.normalizedHref,
    required this.mimeType,
    required this.relativePath,
    required this.byteLength,
  });

  final String assetKey;
  final String? originalHref;
  final String? normalizedHref;
  final String? mimeType;
  final String relativePath;
  final int? byteLength;
}

class LibraryImportResult {
  const LibraryImportResult({
    required this.book,
    required this.insertedCards,
    required this.wasDuplicate,
    required this.matchedBy,
  });

  final Book book;
  final int insertedCards;
  final bool wasDuplicate;
  final String? matchedBy;
}

class LibraryBackupSnapshot {
  const LibraryBackupSnapshot({
    required this.books,
    required this.bookCards,
    required this.bookAssets,
    required this.bookRemarks,
  });

  final List<Book> books;
  final List<BookCard> bookCards;
  final List<BookAsset> bookAssets;
  final List<BookRemarkSnapshot> bookRemarks;
}

class BookRemarkSnapshot {
  const BookRemarkSnapshot({
    required this.bookId,
    required this.title,
    required this.updatedAt,
  });

  final int bookId;
  final String title;
  final DateTime updatedAt;
}

class LibraryContentIdentity {
  const LibraryContentIdentity._();

  static String contentFingerprintForCards(List<BookCard> cards) {
    final sorted = List<BookCard>.of(cards)
      ..sort((a, b) => a.cardIndex.compareTo(b.cardIndex));
    final buffer = StringBuffer()..writeln(sorted.length);

    for (final card in sorted) {
      final normalized = normalizeForFingerprint(card.content);
      buffer
        ..write(card.chapterIndex)
        ..write('|')
        ..write(card.chapterCardIndex)
        ..write('|')
        ..writeln(normalized.length)
        ..writeln(normalized)
        ..writeln(card.blocksJson ?? '');
    }

    return sha256.convert(utf8.encode(buffer.toString())).toString();
  }

  static String contentFingerprintForCardDrafts(List<BookCardDraft> cards) {
    final sorted = List<BookCardDraft>.of(cards)
      ..sort((a, b) => a.cardIndex.compareTo(b.cardIndex));
    final buffer = StringBuffer()..writeln(sorted.length);

    for (final card in sorted) {
      final normalized = normalizeForFingerprint(card.content);
      buffer
        ..write(card.chapterIndex)
        ..write('|')
        ..write(card.chapterCardIndex)
        ..write('|')
        ..writeln(normalized.length)
        ..writeln(normalized)
        ..writeln(card.blocksJson ?? '');
    }

    return sha256.convert(utf8.encode(buffer.toString())).toString();
  }

  static int textCharCountForCards(List<BookCard> cards) {
    return cards.fold<int>(
      0,
      (sum, card) => sum + normalizeForFingerprint(card.content).length,
    );
  }

  static String normalizeForFingerprint(String text) {
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
