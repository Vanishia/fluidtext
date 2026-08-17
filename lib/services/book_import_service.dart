import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:epub_plus/epub_plus.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;

import '../models/book_card.dart';
import '../repositories/library_repository.dart';
import '../repositories/library_snapshot.dart';
import 'app_logger.dart';
import 'book_asset_store.dart';
import 'epub_html_decoder.dart';
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

enum BookImportStage { parsing, readingChapters, buildingCards, writing }

class BookImportProgress {
  const BookImportProgress({
    required this.stage,
    this.completedUnits = 0,
    this.totalUnits = 0,
    this.producedCards = 0,
  });

  final BookImportStage stage;

  /// Chapters processed in the current stage; meaningful only for
  /// [BookImportStage.readingChapters] and [BookImportStage.buildingCards].
  final int completedUnits;
  final int totalUnits;
  final int producedCards;

  /// Determinate progress (0..1), or null when the total is unknown.
  double? get fraction {
    if (totalUnits <= 0) return null;
    return (completedUnits / totalUnits).clamp(0.0, 1.0);
  }
}

/// Mutable per-import progress tracker; forwards snapshots to the callback
/// supplied to [BookImportService.importEpubBytes].
class _ImportProgressReporter {
  _ImportProgressReporter(this._emit);

  final void Function(BookImportProgress progress)? _emit;

  var _totalChapters = 0;
  var _readChapters = 0;
  var _packedChapters = 0;

  void parsing() {
    _emit?.call(const BookImportProgress(stage: BookImportStage.parsing));
  }

  void expectChapters(int total) {
    _totalChapters = total;
  }

  void chapterRead() {
    _readChapters += 1;
    _emit?.call(
      BookImportProgress(
        stage: BookImportStage.readingChapters,
        completedUnits: _readChapters,
        totalUnits: _totalChapters,
      ),
    );
  }

  void chapterPacked(int producedCards) {
    _packedChapters += 1;
    _emit?.call(
      BookImportProgress(
        stage: BookImportStage.buildingCards,
        completedUnits: _packedChapters,
        totalUnits: _totalChapters,
        producedCards: producedCards,
      ),
    );
  }

  void writing() {
    _emit?.call(const BookImportProgress(stage: BookImportStage.writing));
  }
}

class BookImportService {
  BookImportService({BookAssetStore? assetStore})
    : _assetStore = assetStore ?? BookAssetStore.instance;

  static const maxSingleImageBytes = 64 * 1024 * 1024;
  static const maxTotalImageBytes = 512 * 1024 * 1024;

  final BookAssetStore _assetStore;

  static const _ignoredHtmlTags = {
    'script',
    'style',
    'head',
    'metadata',
    'svg',
  };

  static const _blockHtmlTags = {
    'address',
    'article',
    'aside',
    'blockquote',
    'body',
    'dd',
    'div',
    'dl',
    'dt',
    'figcaption',
    'figure',
    'footer',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'header',
    'hr',
    'li',
    'main',
    'nav',
    'ol',
    'p',
    'pre',
    'section',
    'table',
    'tbody',
    'td',
    'tfoot',
    'th',
    'thead',
    'tr',
    'ul',
  };

  static const _maxSkippedChapterRatio = 0.35;
  static const _minChaptersBeforeRatioFailure = 4;

  Future<BookImportResult> importEpubBytes({
    required LibraryImportRepository repository,
    required Uint8List bytes,
    String? sourceFileName,
    int targetCharsPerCard = 300,
    void Function(BookImportProgress progress)? onProgress,
  }) async {
    final progressReporter = _ImportProgressReporter(onProgress)..parsing();
    _logImport(
      'Starting EPUB import: bytes=${bytes.length}, targetCharsPerCard=$targetCharsPerCard',
      name: 'BookImportService',
    );

    final fileHash = sha256.convert(bytes).toString();
    late final EpubBookRef epub;
    try {
      epub = await EpubReader.openBook(bytes);
    } catch (error, stackTrace) {
      _logImport(
        'Failed to parse EPUB package',
        name: 'BookImportService',
        error: error,
        stackTrace: stackTrace,
      );
      throw BookImportException(
        '无法打开 EPUB 基础结构，文件可能损坏或格式不兼容；${_ImportToleranceReport.shortError(error)}',
      );
    }
    final stagedAssetRootKey = _assetStore.createAssetRootKey(fileHash);
    var retainStagedAssets = false;
    try {
      final report = _ImportToleranceReport();
      final rawTitle = (epub.title ?? '').trim();
      final title = rawTitle.isEmpty ? 'Untitled' : rawTitle;
      final imageIndex = await _stageAvailableImages(
        epub,
        assetRootKey: stagedAssetRootKey,
        report: report,
      );
      final chapters = await _readAvailableChapters(
        epub,
        report: report,
        progress: progressReporter,
      );
      _throwIfTooManyChaptersSkipped(report);
      final contentTextFiles = epub.content?.html.length ?? 0;
      final contentImageFiles = imageIndex.assetCount;
      final contentAllFiles = epub.content?.allFiles.length ?? 0;
      _logImport(
        'Parsed EPUB metadata: title="$title", topLevelChapters=${chapters.length}, htmlFiles=$contentTextFiles, imageFiles=$contentImageFiles, allFiles=$contentAllFiles',
        name: 'BookImportService',
      );

      _ImportDraft? structuredDraft = _buildImportDraft(
        title: title,
        chapters: _chapterContents(
          chapters,
          imageIndex: imageIndex,
          report: report,
        ),
        targetCharsPerCard: targetCharsPerCard,
        progress: progressReporter,
      );
      _throwIfTooManyChaptersSkipped(report);
      late final _ImportDraft draft;
      if (structuredDraft.assets.isNotEmpty) {
        draft = structuredDraft;
      } else {
        structuredDraft = null;
        draft = _buildLegacyImportDraft(
          title: title,
          chapters: _legacyChapterContents(chapters, report: report),
          targetCharsPerCard: targetCharsPerCard,
          progress: progressReporter,
        );
      }
      if (draft.cards.isEmpty) {
        final detail = report.summary;
        throw BookImportException(
          detail == null
              ? '没有从 EPUB 中解析出可导入的正文'
              : '没有从 EPUB 中解析出可导入的正文；$detail',
        );
      }

      final now = DateTime.now();
      final assetRootKey = draft.assets.isEmpty ? null : stagedAssetRootKey;

      if (assetRootKey != null) {
        await _assetStore.pruneAssetRoot(
          assetRootKey: assetRootKey,
          retainedRelativePaths: draft.assets.values
              .map((asset) => asset.relativePath)
              .toSet(),
        );
      }

      progressReporter.writing();
      final imported = await repository.importBookDraft(
        ImportBookDraft(
          title: title,
          createdAt: now,
          fileHash: fileHash,
          contentFingerprint: draft.contentFingerprint,
          sourceFileName: sourceFileName,
          importedAt: now,
          cardCount: draft.cards.length,
          textCharCount: draft.textCharCount,
          assetRootKey: assetRootKey,
          cards: draft.cards
              .map(BookCardDraft.fromBookCard)
              .toList(growable: false),
          assets: draft.assets.values
              .map(
                (asset) => BookAssetDraft(
                  assetKey: asset.assetKey,
                  originalHref: asset.originalHref,
                  normalizedHref: asset.normalizedHref,
                  mimeType: asset.mimeType,
                  relativePath: asset.relativePath,
                  byteLength: asset.byteLength,
                ),
              )
              .toList(growable: false),
        ),
      );
      retainStagedAssets = assetRootKey != null && !imported.wasDuplicate;

      _logImport(
        'Finished EPUB import: bookId=${imported.book.id}, insertedCards=${imported.insertedCards}, duplicate=${imported.wasDuplicate}',
        name: 'BookImportService',
      );

      return BookImportResult(
        bookId: imported.book.id,
        bookTitle: imported.book.title,
        insertedCards: imported.insertedCards,
        wasDuplicate: imported.wasDuplicate,
        matchedBy: imported.matchedBy,
      );
    } finally {
      if (!retainStagedAssets) {
        await _assetStore.deleteAssetRoot(stagedAssetRootKey);
      }
    }
  }

  Future<_EpubImageIndex> _stageAvailableImages(
    EpubBookRef epub, {
    required String assetRootKey,
    required _ImportToleranceReport report,
  }) async {
    final imageRefs = epub.content?.images ?? const {};
    final imageIndex = _EpubImageIndex();
    final stagedByArchivePath = <String, _ImageAssetDraft>{};
    var totalImageBytes = 0;

    for (final entry in imageRefs.entries) {
      final imageRef = entry.value;
      try {
        final archiveEntry = imageRef.getContentFileEntry();
        final existingAsset = stagedByArchivePath[archiveEntry.name];
        if (existingAsset != null) {
          imageIndex.add(
            entryKey: entry.key,
            fileName: imageRef.fileName,
            asset: existingAsset,
          );
          continue;
        }
        final declaredBytes = archiveEntry.size;
        if (declaredBytes > maxSingleImageBytes) {
          throw BookImportException(
            '图片 ${imageRef.fileName ?? entry.key} 解压后超过 64 MB，已停止导入',
          );
        }
        if (totalImageBytes + declaredBytes > maxTotalImageBytes) {
          throw const BookImportException('图片资源总量超过 512 MB，已停止导入');
        }

        final file = await EpubReader.readByteContentFile(imageRef);
        final bytes = file.content;
        if (bytes == null || bytes.isEmpty) continue;
        if (bytes.length > maxSingleImageBytes) {
          throw BookImportException(
            '图片 ${file.fileName ?? entry.key} 超过 64 MB，已停止导入',
          );
        }
        totalImageBytes += bytes.length;
        if (totalImageBytes > maxTotalImageBytes) {
          throw const BookImportException('图片资源总量超过 512 MB，已停止导入');
        }

        final normalizedHref =
            _EpubImageIndex._normalizeEpubPath(file.fileName ?? entry.key) ??
            entry.key;
        final assetKey = sha256.convert(bytes).toString();
        final extension = _EpubImageIndex._extensionForAsset(
          href: normalizedHref,
          mimeType: file.contentMimeType,
        );
        final relativePath = await _assetStore.writeAssetFile(
          assetRootKey: assetRootKey,
          assetKey: assetKey,
          extension: extension,
          bytes: bytes,
        );
        final asset = _ImageAssetDraft(
          assetKey: assetKey,
          originalHref: file.fileName ?? entry.key,
          normalizedHref: normalizedHref,
          mimeType: file.contentMimeType,
          relativePath: relativePath,
          byteLength: bytes.length,
        );
        stagedByArchivePath[archiveEntry.name] = asset;
        imageIndex.add(
          entryKey: entry.key,
          fileName: file.fileName,
          asset: asset,
        );
      } on BookImportException {
        rethrow;
      } catch (error, stackTrace) {
        report.rememberImageError(imageRef.fileName ?? entry.key, error);
        _logImport(
          'Skipping EPUB image that cannot be read: href="${imageRef.fileName ?? entry.key}"',
          name: 'BookImportService',
          error: error,
          stackTrace: stackTrace,
        );
      } finally {
        try {
          imageRef.getContentFileEntry().closeSync();
        } catch (_) {
          // A missing/corrupt entry was already reported while reading it.
        }
      }
    }

    return imageIndex;
  }

  Future<List<EpubChapter>> _readAvailableChapters(
    EpubBookRef epub, {
    required _ImportToleranceReport report,
    required _ImportProgressReporter progress,
  }) async {
    late final List<EpubChapterRef> chapterRefs;
    try {
      chapterRefs = epub.getChapters();
    } catch (error, stackTrace) {
      _logImport(
        'Failed to read EPUB chapter navigation',
        name: 'BookImportService',
        error: error,
        stackTrace: stackTrace,
      );
      throw BookImportException(
        '无法读取 EPUB 章节目录；${_ImportToleranceReport.shortError(error)}',
      );
    }

    progress.expectChapters(_countChapterRefs(chapterRefs));
    return _readAvailableChapterRefs(
      chapterRefs,
      report: report,
      progress: progress,
    );
  }

  int _countChapterRefs(List<EpubChapterRef> refs) {
    var count = 0;
    for (final ref in refs) {
      count += 1 + _countChapterRefs(ref.subChapters);
    }
    return count;
  }

  Future<List<EpubChapter>> _readAvailableChapterRefs(
    List<EpubChapterRef> refs, {
    required _ImportToleranceReport report,
    required _ImportProgressReporter progress,
  }) async {
    final chapters = <EpubChapter>[];

    for (final ref in refs) {
      report.seenChapters += 1;
      try {
        final htmlContent = await _readChapterHtml(ref);
        final subChapters = await _readAvailableChapterRefs(
          ref.subChapters,
          report: report,
          progress: progress,
        );
        final chapter = EpubChapter(
          title: ref.title,
          contentFileName: ref.contentFileName,
          anchor: ref.anchor,
          htmlContent: htmlContent,
          subChapters: subChapters,
        );
        chapters.add(chapter);
      } catch (error, stackTrace) {
        report.skippedChapters += 1;
        report.rememberChapterError(ref.title ?? '', error);
        _logImport(
          'Skipping EPUB chapter that cannot be read: title="${(ref.title ?? '').trim().isEmpty ? '(untitled)' : ref.title}"',
          name: 'BookImportService',
          error: error,
          stackTrace: stackTrace,
        );

        if (ref.subChapters.isNotEmpty) {
          chapters.addAll(
            await _readAvailableChapterRefs(
              ref.subChapters,
              report: report,
              progress: progress,
            ),
          );
        }
      } finally {
        progress.chapterRead();
      }
    }

    return chapters;
  }

  /// Reads a chapter as strict UTF-8 (epub_plus behaviour); files that fail
  /// UTF-8 decoding are retried with legacy-charset fallbacks so GBK EPUBs
  /// do not lose whole chapters.
  Future<String> _readChapterHtml(EpubChapterRef ref) async {
    try {
      return await ref.readHtmlContent();
    } on FormatException {
      final bytes = await ref.epubTextContentFileRef?.readContentAsBytes();
      if (bytes == null) rethrow;
      _logImport(
        'Recovering non-UTF8 EPUB chapter via encoding fallback: title="${(ref.title ?? '').trim().isEmpty ? '(untitled)' : ref.title}"',
        name: 'BookImportService',
      );
      return decodeHtmlBytesLossy(bytes);
    }
  }

  _ImportDraft _buildImportDraft({
    required String title,
    required Iterable<_ChapterContent> chapters,
    required int targetCharsPerCard,
    required _ImportProgressReporter progress,
  }) {
    final cards = <BookCard>[];
    final assets = <String, _ImageAssetDraft>{};
    var cardIndex = 0;
    var chapterIndex = 0;
    var textCharCount = 0;

    for (final chapter in chapters) {
      _logImport(
        'Processing chapter[$chapterIndex]: textLength=${chapter.textCharCount}, images=${chapter.imageCount}',
        name: 'BookImportService',
      );
      final packer = _CardBlockPacker(targetChars: targetCharsPerCard);
      final chapterDraftCards = packer.pack(chapter.items);
      var chapterCardIndex = 0;
      var chapterCards = 0;

      textCharCount += chapter.textCharCount;
      assets.addAll(chapter.assets);

      for (final draftCard in chapterDraftCards) {
        cards.add(
          BookCard()
            ..bookId = 0
            ..bookTitle = title
            ..cardIndex = cardIndex
            ..chapterIndex = chapterIndex
            ..chapterCardIndex = chapterCardIndex
            ..chapterTitle = chapter.title
            ..content = draftCard.content
            ..blocksJson = draftCard.blocksJson,
        );
        cardIndex++;
        chapterCardIndex++;
        chapterCards++;
      }

      _logImport(
        'Packed chapter[$chapterIndex] into $chapterCards cards',
        name: 'BookImportService',
      );
      progress.chapterPacked(cards.length);

      if (chapterCards > 0) {
        chapterIndex++;
      }
    }

    return _ImportDraft(
      cards: cards,
      assets: assets,
      contentFingerprint: _contentFingerprintForCards(cards),
      textCharCount: textCharCount,
    );
  }

  _ImportDraft _buildLegacyImportDraft({
    required String title,
    required Iterable<_LegacyChapterContent> chapters,
    required int targetCharsPerCard,
    required _ImportProgressReporter progress,
  }) {
    final cards = <BookCard>[];
    var cardIndex = 0;
    var chapterIndex = 0;
    var textCharCount = 0;

    for (final chapter in chapters) {
      _logImport(
        'Processing legacy chapter[$chapterIndex]: textLength=${chapter.text.length}',
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

      _logImport(
        'Split legacy chapter[$chapterIndex] into $pieceCount pieces, $chapterCards non-empty cards',
        name: 'BookImportService',
      );
      progress.chapterPacked(cards.length);

      if (chapterCards > 0) {
        chapterIndex++;
      }
    }

    return _ImportDraft(
      cards: cards,
      assets: const <String, _ImageAssetDraft>{},
      contentFingerprint: _contentFingerprintForCards(cards),
      textCharCount: textCharCount,
    );
  }

  Iterable<_ChapterContent> _chapterContents(
    List<EpubChapter> chapters, {
    required _EpubImageIndex imageIndex,
    required _ImportToleranceReport report,
  }) sync* {
    for (var index = 0; index < chapters.length; index++) {
      final chapter = chapters[index];
      final html = chapter.htmlContent;
      final contentFileName = chapter.contentFileName;
      final chapterTitle = (chapter.title ?? '').trim();
      _logImport(
        'Inspecting chapter node[$index]: title="${chapterTitle.isEmpty ? '(untitled)' : chapterTitle}", htmlLength=${html?.length ?? 0}, subChapters=${chapter.subChapters.length}',
        name: 'BookImportService',
      );

      if (html != null && html.trim().isNotEmpty) {
        late final List<_ContentItem> items;
        try {
          final document = html_parser.parse(html);
          items = _extractContentItems(
            document,
            contentFileName: contentFileName,
            imageIndex: imageIndex,
            report: report,
          );
        } catch (error, stackTrace) {
          report.skippedChapters += 1;
          report.rememberChapterError(chapterTitle, error);
          _logImport(
            'Skipping EPUB chapter after parse failure: title="${chapterTitle.isEmpty ? '(untitled)' : chapterTitle}"',
            name: 'BookImportService',
            error: error,
            stackTrace: stackTrace,
          );
          if (chapter.subChapters.isNotEmpty) {
            yield* _chapterContents(
              chapter.subChapters,
              imageIndex: imageIndex,
              report: report,
            );
          }
          continue;
        }
        final textCharCount = items.whereType<_TextContentItem>().fold<int>(
          0,
          (sum, item) => sum + _normalizeForFingerprint(item.text).length,
        );
        final imageAssets = <String, _ImageAssetDraft>{
          for (final item in items.whereType<_ImageContentItem>())
            item.asset.assetKey: item.asset,
        };

        if (textCharCount > 0 || imageAssets.isNotEmpty) {
          _logImport(
            'Yielding chapter node[$index] textLength=$textCharCount, images=${imageAssets.length}',
            name: 'BookImportService',
          );
          yield _ChapterContent(
            title: chapterTitle.isEmpty ? null : chapterTitle,
            items: items,
            assets: imageAssets,
            textCharCount: textCharCount,
            imageCount: imageAssets.length,
          );
        } else {
          _logImport(
            'Chapter node[$index] produced empty content after HTML parsing',
            name: 'BookImportService',
          );
        }
      } else {
        _logImport(
          'Chapter node[$index] has empty htmlContent',
          name: 'BookImportService',
        );
      }

      if (chapter.subChapters.isNotEmpty) {
        yield* _chapterContents(
          chapter.subChapters,
          imageIndex: imageIndex,
          report: report,
        );
      }
    }
  }

  Iterable<_LegacyChapterContent> _legacyChapterContents(
    List<EpubChapter> chapters, {
    required _ImportToleranceReport report,
  }) sync* {
    for (var index = 0; index < chapters.length; index++) {
      final chapter = chapters[index];
      final html = chapter.htmlContent;
      final chapterTitle = (chapter.title ?? '').trim();

      if (html != null && html.trim().isNotEmpty) {
        late final String text;
        try {
          final document = html_parser.parse(html);
          text = document.body?.text ?? document.documentElement?.text ?? '';
        } catch (error, stackTrace) {
          report.rememberChapterError(chapterTitle, error);
          _logImport(
            'Skipping legacy EPUB chapter after parse failure: title="${chapterTitle.isEmpty ? '(untitled)' : chapterTitle}"',
            name: 'BookImportService',
            error: error,
            stackTrace: stackTrace,
          );
          if (chapter.subChapters.isNotEmpty) {
            yield* _legacyChapterContents(chapter.subChapters, report: report);
          }
          continue;
        }
        final trimmedText = text.trim();
        if (trimmedText.isNotEmpty) {
          yield _LegacyChapterContent(
            title: chapterTitle.isEmpty ? null : chapterTitle,
            text: trimmedText,
          );
        }
      }

      if (chapter.subChapters.isNotEmpty) {
        yield* _legacyChapterContents(chapter.subChapters, report: report);
      }
    }
  }

  List<_ContentItem> _extractContentItems(
    html_dom.Document document, {
    required String? contentFileName,
    required _EpubImageIndex imageIndex,
    required _ImportToleranceReport report,
  }) {
    final root = document.body ?? document.documentElement;
    if (root == null) return const <_ContentItem>[];

    final items = <_ContentItem>[];
    final textBuffer = StringBuffer();

    void flushText() {
      final text = _collapseInlineWhitespace(textBuffer.toString());
      textBuffer.clear();
      if (text.trim().isEmpty) return;
      items.add(_TextContentItem(text));
    }

    void addBreak() {
      flushText();
      if (items.isEmpty || items.last is _BreakContentItem) return;
      items.add(const _BreakContentItem());
    }

    void visit(html_dom.Node node) {
      if (node is html_dom.Text) {
        textBuffer.write(node.text);
        return;
      }

      if (node is! html_dom.Element) {
        for (final child in node.nodes) {
          visit(child);
        }
        return;
      }

      final tag = node.localName?.toLowerCase() ?? '';
      if (_ignoredHtmlTags.contains(tag)) return;

      if (tag == 'br') {
        addBreak();
        return;
      }

      if (tag == 'img' || tag == 'image') {
        flushText();
        final href = _imageHrefForElement(node);
        if (href != null) {
          final asset = imageIndex.resolve(
            contentFileName: contentFileName,
            href: href,
            report: report,
          );
          if (asset != null) {
            items.add(
              _ImageContentItem(
                asset: asset,
                alt: (node.attributes['alt'] ?? '').trim(),
              ),
            );
          }
        }
        return;
      }

      final isBlock = _blockHtmlTags.contains(tag);
      if (isBlock) flushText();
      for (final child in node.nodes) {
        visit(child);
      }
      if (isBlock) addBreak();
    }

    visit(root);
    flushText();
    while (items.isNotEmpty && items.last is _BreakContentItem) {
      items.removeLast();
    }
    return items;
  }

  void _throwIfTooManyChaptersSkipped(_ImportToleranceReport report) {
    if (report.seenChapters < _minChaptersBeforeRatioFailure) return;
    if (report.skippedChapters == 0) return;

    final ratio = report.skippedChapters / report.seenChapters;
    if (ratio <= _maxSkippedChapterRatio) return;

    final detail = report.summary;
    throw BookImportException(
      detail == null ? 'EPUB 章节解析失败过多，已停止导入' : 'EPUB 章节解析失败过多，已停止导入；$detail',
    );
  }

  String? _imageHrefForElement(html_dom.Element element) {
    return (element.attributes['src'] ??
            element.attributes['href'] ??
            element.attributes['xlink:href'])
        ?.trim();
  }

  String _collapseInlineWhitespace(String text) {
    return text.replaceAll(RegExp(r'[\t\r\n ]+'), ' ');
  }

  String _normalizeForFingerprint(String text) {
    return LibraryContentIdentity.normalizeForFingerprint(text);
  }

  String _contentFingerprintForCards(List<BookCard> cards) {
    return LibraryContentIdentity.contentFingerprintForCards(cards);
  }
}

class BookImportException implements Exception {
  const BookImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Maps an import failure to a user-facing message. [BookImportException]
/// messages are already written for users; anything else gets a generic hint
/// while the technical detail stays in the log file / copied report.
String describeBookImportError(Object error) {
  if (error is BookImportException) return error.message;
  if (error is FileSystemException) {
    return '无法读取文件或写入应用存储，请检查存储空间是否充足后重试';
  }
  return '文件可能已损坏，或使用了暂不支持的格式。请确认这是有效的 EPUB 文件后重试';
}

/// Import diagnostics go through [AppLogger] so they land in the log file.
/// Call sites carrying an [error] are warnings (tolerated and skipped);
/// fatal failures surface as the thrown [BookImportException].
void _logImport(
  String message, {
  String? name,
  Object? error,
  StackTrace? stackTrace,
}) {
  final logger = AppLogger.instance;
  final tag = name ?? 'BookImportService';
  if (error != null) {
    logger.warning(tag, message, error: error, stackTrace: stackTrace);
  } else {
    logger.info(tag, message);
  }
}

class _ImportToleranceReport {
  int seenChapters = 0;
  int skippedChapters = 0;
  int skippedImages = 0;
  String? firstChapterError;
  String? firstImageError;
  final Set<String> _seenImageFailures = <String>{};

  void rememberChapterError(String title, Object error) {
    firstChapterError ??=
        '${title.trim().isEmpty ? '未命名章节' : title.trim()}：${shortError(error)}';
  }

  void rememberImageError(String href, Object error) {
    if (!_seenImageFailures.add(href)) return;
    skippedImages += 1;
    firstImageError ??= '$href：${shortError(error)}';
  }

  void rememberMissingImage(String href) {
    if (!_seenImageFailures.add(href)) return;
    skippedImages += 1;
    firstImageError ??= href;
  }

  String? get summary {
    final parts = <String>[];
    if (skippedChapters > 0) {
      parts.add(
        '已跳过 $skippedChapters/$seenChapters 个异常章节'
        '${firstChapterError == null ? '' : '（$firstChapterError）'}',
      );
    }
    if (skippedImages > 0) {
      parts.add(
        '已跳过 $skippedImages 张异常图片'
        '${firstImageError == null ? '' : '（$firstImageError）'}',
      );
    }
    return parts.isEmpty ? null : parts.join('，');
  }

  static String shortError(Object error) {
    final text = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length <= 80) return text;
    return '${text.substring(0, 80)}...';
  }
}

class _ImportDraft {
  const _ImportDraft({
    required this.cards,
    required this.assets,
    required this.contentFingerprint,
    required this.textCharCount,
  });

  final List<BookCard> cards;
  final Map<String, _ImageAssetDraft> assets;
  final String contentFingerprint;
  final int textCharCount;
}

class _ChapterContent {
  const _ChapterContent({
    required this.items,
    required this.assets,
    required this.textCharCount,
    required this.imageCount,
    required this.title,
  });

  final List<_ContentItem> items;
  final Map<String, _ImageAssetDraft> assets;
  final int textCharCount;
  final int imageCount;
  final String? title;
}

class _LegacyChapterContent {
  const _LegacyChapterContent({required this.text, required this.title});

  final String text;
  final String? title;
}

sealed class _ContentItem {
  const _ContentItem();
}

class _TextContentItem extends _ContentItem {
  const _TextContentItem(this.text);

  final String text;
}

class _ImageContentItem extends _ContentItem {
  const _ImageContentItem({required this.asset, required this.alt});

  final _ImageAssetDraft asset;
  final String alt;
}

class _BreakContentItem extends _ContentItem {
  const _BreakContentItem();
}

class _CardDraft {
  const _CardDraft({required this.content, required this.blocksJson});

  final String content;
  final String? blocksJson;
}

class _CardBlockPacker {
  _CardBlockPacker({required this.targetChars})
    : minTextBeforeImageBreak = (targetChars * 2 / 3).round(),
      _lengthPolicy = CardLengthPolicy(targetChars: targetChars);

  final int targetChars;
  final int minTextBeforeImageBreak;
  final CardLengthPolicy _lengthPolicy;
  static const maxImagesPerCard = 2;

  final List<_CardBlockDraft> _blocks = <_CardBlockDraft>[];
  final StringBuffer _textBuffer = StringBuffer();
  var _textChars = 0;
  var _imageCount = 0;

  List<_CardDraft> pack(List<_ContentItem> items) {
    final cards = <_CardDraft>[];

    for (final item in items) {
      switch (item) {
        case _TextContentItem():
          _appendText(item.text, cards);
        case _ImageContentItem():
          _appendImage(item, cards);
        case _BreakContentItem():
          _appendBreak(cards);
      }
    }

    _flushCard(cards);
    return cards;
  }

  void _appendText(String text, List<_CardDraft> cards) {
    for (var index = 0; index < text.length; index += 1) {
      final character = text[index];
      _textBuffer.write(character);
      _textChars += 1;

      if (_lengthPolicy.shouldBreak(_textChars, character)) {
        _flushCard(cards);
      }
    }
  }

  void _appendBreak(List<_CardDraft> cards) {
    if (_textBuffer.isNotEmpty) {
      final current = _textBuffer.toString();
      if (!current.endsWith('\n')) {
        _textBuffer.write('\n');
        _textChars += 1;
      }
      if (_textChars >= targetChars) {
        _flushCard(cards);
      }
    }
  }

  void _appendImage(_ImageContentItem item, List<_CardDraft> cards) {
    _flushTextBuffer();
    if (_hasCurrentContent && _textChars >= minTextBeforeImageBreak) {
      _flushCard(cards);
    }
    if (_hasCurrentContent && _imageCount >= maxImagesPerCard) {
      _flushCard(cards);
    }

    _blocks.add(
      _CardBlockDraft.image(assetKey: item.asset.assetKey, alt: item.alt),
    );
    _imageCount += 1;
  }

  void _flushCard(List<_CardDraft> cards) {
    _flushTextBuffer();
    if (_blocks.isEmpty) return;

    final blocks = List<_CardBlockDraft>.of(_blocks);
    cards.add(
      _CardDraft(
        content: _plainContentForBlocks(blocks),
        blocksJson: _blocksJsonForBlocks(blocks),
      ),
    );
    _blocks.clear();
    _textBuffer.clear();
    _textChars = 0;
    _imageCount = 0;
  }

  void _flushTextBuffer() {
    final text = _tidyCardText(_textBuffer.toString());
    _textBuffer.clear();
    if (text.isEmpty) return;

    if (_blocks.isNotEmpty && _blocks.last.type == 'text') {
      final previous = _blocks.removeLast();
      _blocks.add(_CardBlockDraft.text('${previous.text}$text'));
      return;
    }
    _blocks.add(_CardBlockDraft.text(text));
  }

  bool get _hasCurrentContent =>
      _blocks.isNotEmpty || _textBuffer.toString().trim().isNotEmpty;

  String _tidyCardText(String text) {
    return text
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n[ \t]+'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  String _plainContentForBlocks(List<_CardBlockDraft> blocks) {
    final text = blocks
        .where((block) => block.type == 'text')
        .map((block) => block.text)
        .join('\n')
        .trim();
    if (text.isNotEmpty) return text;

    final altText = blocks
        .where((block) => block.type == 'image')
        .map((block) => block.alt.trim())
        .where((alt) => alt.isNotEmpty)
        .join('\n')
        .trim();
    return altText.isEmpty ? '图片' : altText;
  }

  String? _blocksJsonForBlocks(List<_CardBlockDraft> blocks) {
    if (!blocks.any((block) => block.type == 'image')) return null;

    return jsonEncode({
      'version': 1,
      'blocks': blocks.map((block) => block.toJson()).toList(growable: false),
    });
  }
}

class _CardBlockDraft {
  const _CardBlockDraft.text(this.text)
    : type = 'text',
      assetKey = '',
      alt = '';

  const _CardBlockDraft.image({required this.assetKey, required this.alt})
    : type = 'image',
      text = '';

  final String type;
  final String text;
  final String assetKey;
  final String alt;

  Map<String, Object?> toJson() {
    return switch (type) {
      'text' => {'type': type, 'text': text},
      'image' => {'type': type, 'assetKey': assetKey, 'alt': alt},
      _ => {'type': type},
    };
  }
}

class _ImageAssetDraft {
  const _ImageAssetDraft({
    required this.assetKey,
    required this.originalHref,
    required this.normalizedHref,
    required this.mimeType,
    required this.relativePath,
    required this.byteLength,
  });

  final String assetKey;
  final String originalHref;
  final String normalizedHref;
  final String? mimeType;
  final String relativePath;
  final int byteLength;
}

class _EpubImageIndex {
  final Map<String, _ImageAssetDraft> _byHref = <String, _ImageAssetDraft>{};
  final Set<String> _assetKeys = <String>{};

  int get assetCount => _assetKeys.length;

  void add({
    required String entryKey,
    required String? fileName,
    required _ImageAssetDraft asset,
  }) {
    _assetKeys.add(asset.assetKey);
    _addCandidate(entryKey, asset);
    _addCandidate(fileName, asset);
    _addCandidate(asset.normalizedHref, asset);
  }

  _ImageAssetDraft? resolve({
    required String? contentFileName,
    required String href,
    required _ImportToleranceReport report,
  }) {
    final normalized = _resolveEpubHref(
      baseFileName: contentFileName,
      href: href,
      report: report,
    );
    if (normalized == null) return null;
    final asset =
        _byHref[normalized] ??
        _byHref[normalized.toLowerCase()] ??
        _resolveBySuffix(normalized);
    if (asset == null) {
      report.rememberMissingImage(href);
      _logImport(
        'Skipping unresolved EPUB image: href="$href", normalized="$normalized"',
        name: 'BookImportService',
      );
    }
    return asset;
  }

  void _addCandidate(String? href, _ImageAssetDraft asset) {
    final normalized = _normalizeEpubPath(href);
    if (normalized == null || normalized.isEmpty) return;
    _byHref.putIfAbsent(normalized, () => asset);
    _byHref.putIfAbsent(normalized.toLowerCase(), () => asset);
  }

  _ImageAssetDraft? _resolveBySuffix(String normalizedHref) {
    final normalized = normalizedHref.toLowerCase();
    for (final entry in _byHref.entries) {
      final key = entry.key.toLowerCase();
      if (normalized.endsWith('/$key') || key.endsWith('/$normalized')) {
        return entry.value;
      }
    }
    return null;
  }

  static String? _resolveEpubHref({
    required String? baseFileName,
    required String href,
    required _ImportToleranceReport report,
  }) {
    final cleanedHref = _stripHrefNoise(href);
    if (cleanedHref == null) return null;

    final uri = Uri.tryParse(cleanedHref);
    if (uri != null && uri.hasScheme && uri.scheme.toLowerCase() != 'file') {
      return null;
    }

    final decoded = _safeDecodeHref(
      cleanedHref,
      report: report,
    ).replaceAll(r'\', '/');
    if (decoded.startsWith('/')) {
      return _normalizeEpubPath(decoded.substring(1));
    }

    final base = _normalizeEpubPath(baseFileName);
    final baseDir = _directoryName(base);
    return _normalizeEpubPath(
      baseDir == null || baseDir.isEmpty ? decoded : '$baseDir/$decoded',
    );
  }

  static String? _normalizeEpubPath(String? path) {
    final stripped = _stripHrefNoise(path);
    if (stripped == null) return null;
    final decoded = _decodeHrefLossy(stripped).replaceAll(r'\', '/');
    final segments = <String>[];
    for (final rawSegment in decoded.split('/')) {
      final segment = rawSegment.trim();
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') {
        if (segments.isNotEmpty) segments.removeLast();
        continue;
      }
      segments.add(segment);
    }
    return segments.join('/');
  }

  static String? _stripHrefNoise(String? href) {
    final trimmed = href?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    if (trimmed.startsWith('data:')) return null;
    final queryIndex = trimmed.indexOf('?');
    final fragmentIndex = trimmed.indexOf('#');
    final cutPoints = <int>[
      if (queryIndex >= 0) queryIndex,
      if (fragmentIndex >= 0) fragmentIndex,
    ];
    if (cutPoints.isEmpty) return trimmed;
    cutPoints.sort();
    return trimmed.substring(0, cutPoints.first);
  }

  static String? _directoryName(String? path) {
    if (path == null || path.isEmpty) return null;
    final slash = path.lastIndexOf('/');
    if (slash <= 0) return null;
    return path.substring(0, slash);
  }

  static String _safeDecodeHref(
    String href, {
    required _ImportToleranceReport report,
  }) {
    try {
      return Uri.decodeFull(href);
    } catch (error) {
      report.rememberImageError(href, error);
      _logImport(
        'Using undecoded EPUB image href after decode failure: href="$href"',
        name: 'BookImportService',
        error: error,
      );
      return href;
    }
  }

  static String _decodeHrefLossy(String href) {
    try {
      return Uri.decodeFull(href);
    } catch (_) {
      return href;
    }
  }

  static String _extensionForAsset({
    required String href,
    required String? mimeType,
  }) {
    final lowerMime = mimeType?.toLowerCase() ?? '';
    if (lowerMime.contains('jpeg') || lowerMime.contains('jpg')) return '.jpg';
    if (lowerMime.contains('png')) return '.png';
    if (lowerMime.contains('gif')) return '.gif';
    if (lowerMime.contains('webp')) return '.webp';
    if (lowerMime.contains('bmp')) return '.bmp';
    if (lowerMime.contains('svg')) return '.svg';

    final lowerHref = href.toLowerCase();
    for (final extension in const [
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.webp',
      '.bmp',
      '.svg',
    ]) {
      if (lowerHref.endsWith(extension)) {
        return extension == '.jpeg' ? '.jpg' : extension;
      }
    }
    return '.bin';
  }
}
