import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/models/book.dart';
import 'package:fluidtext/models/book_asset.dart';
import 'package:fluidtext/models/book_card.dart';
import 'package:fluidtext/repositories/library_snapshot.dart';
import 'package:fluidtext/services/backup/backup_format.dart';

Map<String, dynamic> _v2Payload() {
  return <String, dynamic>{
    'format': 'fluidtext.backup',
    'version': 2,
    'exportedAt': '2026-08-01T10:00:00.000Z',
    'books': [
      <String, dynamic>{
        'id': 1,
        'title': '第一本书',
        'createdAt': '2026-01-01T00:00:00.000Z',
        'fileHash': 'hash',
        'contentFingerprint': 'fingerprint',
        'sourceFileName': 'book.epub',
        'importedAt': '2026-01-02T00:00:00.000Z',
        'cardCount': 2,
        'textCharCount': 100,
        'assetRootKey': 'asset_1',
      },
    ],
    'bookCards': [
      <String, dynamic>{
        'id': 10,
        'bookId': 1,
        'bookTitle': '第一本书',
        'cardIndex': 0,
        'chapterIndex': 0,
        'chapterCardIndex': 0,
        'chapterTitle': null,
        'content': '内容',
        'blocksJson': null,
        'isRead': true,
        'readAt': '2026-02-01T00:00:00.000Z',
        'isFavorite': false,
        'favoritedAt': null,
      },
    ],
    'bookAssets': [
      <String, dynamic>{
        'id': 20,
        'bookId': 1,
        'assetKey': 'img1',
        'originalHref': 'images/1.png',
        'normalizedHref': 'images/1.png',
        'mimeType': 'image/png',
        'relativePath': 'book_assets/asset_1/images/img1.png',
        'byteLength': 12,
        'createdAt': '2026-01-01T00:00:00.000Z',
      },
    ],
    'bookRemarks': [
      <String, dynamic>{
        'id': 1,
        'title': '备注',
        'updatedAt': '2026-03-01T00:00:00.000Z',
      },
    ],
    'readerSession': <String, dynamic>{
      'lastOpenedBookIds': [1],
      'savedAt': '2026-08-01T00:00:00.000Z',
    },
  };
}

void main() {
  group('parseV2Payload', () {
    test('parses a complete v2 payload', () {
      final data = parseV2Payload(_v2Payload());
      expect(data.books, hasLength(1));
      expect(data.bookCards, hasLength(1));
      expect(data.bookAssets, hasLength(1));
      expect(data.bookRemarks, hasLength(1));
      expect(data.books.single['title'], '第一本书');
      expect(data.bookCards.single['isRead'], isTrue);
      expect(data.readerSession, isNotNull);
    });

    test('converts num to int and defaults missing fields to null', () {
      final payload = _v2Payload();
      final book = (payload['books'] as List).single as Map<String, dynamic>;
      book['id'] = 1.0; // double is accepted and converted
      book.remove('fileHash');
      book.remove('importedAt');
      final card =
          (payload['bookCards'] as List).single as Map<String, dynamic>;
      card.remove('isRead');
      card.remove('isFavorite');

      final data = parseV2Payload(payload);
      expect(data.books.single['id'], 1);
      expect(data.books.single['fileHash'], isNull);
      expect(data.bookCards.single['isRead'], isFalse);
    });

    test('rejects non-FluidText payloads', () {
      final payload = _v2Payload()..['format'] = 'other.format';
      expect(() => parseV2Payload(payload), throwsFormatException);
    });

    test('rejects missing version', () {
      final payload = _v2Payload()..remove('version');
      expect(() => parseV2Payload(payload), throwsFormatException);
    });

    test('rejects too-new versions with a clear message', () {
      final payload = _v2Payload()..['version'] = 4;
      expect(
        () => parseV2Payload(payload),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('版本过新'),
          ),
        ),
      );
    });

    test('rejects unsupported old versions', () {
      final payload = _v2Payload()..['version'] = 1;
      expect(() => parseV2Payload(payload), throwsFormatException);
    });

    test('rejects non-boolean flags', () {
      final payload = _v2Payload();
      (payload['bookCards'] as List).cast<Map<String, dynamic>>().single[
              'isRead'] =
          1;
      expect(() => parseV2Payload(payload), throwsFormatException);
    });

    test('rejects records with bad field types', () {
      final payload = _v2Payload();
      (payload['books'] as List).cast<Map<String, dynamic>>().single[
              'title'] =
          42;
      expect(() => parseV2Payload(payload), throwsFormatException);
    });

    test('rejects unparseable timestamps', () {
      final payload = _v2Payload();
      (payload['books'] as List).cast<Map<String, dynamic>>().single[
              'createdAt'] =
          'not-a-date';
      expect(() => parseV2Payload(payload), throwsFormatException);
    });

    test('rejects a non-map readerSession', () {
      final payload = _v2Payload()..['readerSession'] = 'oops';
      expect(() => parseV2Payload(payload), throwsFormatException);
    });
  });

  group('serializer', () {
    test('toLibraryJson round-trips through parseLibraryJson', () {
      final original = parseV2Payload(_v2Payload());
      final encoded = original.toLibraryJson();
      expect(encoded.containsKey('format'), isFalse);
      expect(encoded.containsKey('version'), isFalse);

      final reparsed = parseLibraryJson(encoded);
      expect(reparsed.books, original.books);
      expect(reparsed.bookCards, original.bookCards);
      expect(reparsed.bookAssets, original.bookAssets);
      expect(reparsed.bookRemarks, original.bookRemarks);
      expect(reparsed.readerSession, original.readerSession);
    });

    test('fromSnapshot uses the v2 field names', () {
      final snapshot = LibraryBackupSnapshot(
        books: [
          Book()
            ..id = 7
            ..title = '快照书'
            ..createdAt = DateTime.utc(2026)
            ..fileHash = 'hash'
            ..assetRootKey = 'asset_7',
        ],
        bookCards: [
          BookCard()
            ..id = 70
            ..bookId = 7
            ..bookTitle = '快照书'
            ..cardIndex = 0
            ..chapterIndex = 0
            ..chapterCardIndex = 0
            ..content = '正文'
            ..isRead = false
            ..isFavorite = true
            ..favoritedAt = DateTime.utc(2026, 2),
        ],
        bookAssets: [
          BookAsset()
            ..id = 90
            ..bookId = 7
            ..assetKey = 'img'
            ..relativePath = 'book_assets/asset_7/images/img.png'
            ..createdAt = DateTime.utc(2026),
        ],
        bookRemarks: [
          BookRemarkSnapshot(
            bookId: 7,
            title: '想法',
            updatedAt: DateTime.utc(2026, 3),
          ),
        ],
      );

      final data = BackupLibraryData.fromSnapshot(snapshot);
      final book = data.books.single;
      expect(book.keys, containsAll(<String>[
        'id',
        'title',
        'createdAt',
        'fileHash',
        'contentFingerprint',
        'sourceFileName',
        'importedAt',
        'cardCount',
        'textCharCount',
        'assetRootKey',
      ]));
      expect(book['createdAt'], '2026-01-01T00:00:00.000Z');
      final card = data.bookCards.single;
      expect(card['isFavorite'], isTrue);
      expect(card['favoritedAt'], '2026-02-01T00:00:00.000Z');
      expect(data.bookAssets.single['relativePath'], contains('book_assets/'));
      expect(data.bookRemarks.single['title'], '想法');
    });
  });

  group('BackupManifest', () {
    BackupManifest buildManifest() {
      return BackupManifest(
        sqliteSchemaVersion: 1,
        appVersion: '1.0.0+1',
        platform: 'windows',
        exportedAt: DateTime.utc(2026, 8, 1),
        counts: const BackupManifestCounts(
          books: 1,
          bookCards: 2,
          bookAssets: 3,
          bookRemarks: 4,
        ),
        files: const [
          BackupManifestFile(
            path: 'data/library.json',
            bytes: 100,
            sha256:
                'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          ),
        ],
      );
    }

    test('round-trips through JSON', () {
      final manifest = buildManifest();
      final parsed = BackupManifest.fromJson(manifest.toJson());
      expect(parsed.sqliteSchemaVersion, 1);
      expect(parsed.appVersion, '1.0.0+1');
      expect(parsed.platform, 'windows');
      expect(parsed.exportedAt, DateTime.utc(2026, 8, 1));
      expect(parsed.counts.books, 1);
      expect(parsed.counts.bookRemarks, 4);
      expect(parsed.files.single.path, 'data/library.json');
      expect(parsed.files.single.bytes, 100);
    });

    test('toJson carries the v3 header', () {
      final json = buildManifest().toJson();
      expect(json['format'], 'fluidtext.backup');
      expect(json['version'], 3);
    });

    test('rejects too-new versions', () {
      final json = buildManifest().toJson()..['version'] = 9;
      expect(
        () => BackupManifest.fromJson(json),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('版本过新'),
          ),
        ),
      );
    });

    test('rejects missing required fields', () {
      final json = buildManifest().toJson()..remove('counts');
      expect(() => BackupManifest.fromJson(json), throwsFormatException);

      final noFiles = buildManifest().toJson()..remove('files');
      expect(() => BackupManifest.fromJson(noFiles), throwsFormatException);
    });

    test('rejects malformed file entries', () {
      final json = buildManifest().toJson();
      (json['files'] as List).cast<Map<String, dynamic>>().single['sha256'] =
          'short';
      expect(() => BackupManifest.fromJson(json), throwsFormatException);
    });
  });
}
