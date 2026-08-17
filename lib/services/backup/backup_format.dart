import '../../models/book.dart';
import '../../models/book_asset.dart';
import '../../models/book_card.dart';
import '../../repositories/library_snapshot.dart';

/// Backup payload DTO shared by backup format v2 (import only) and v3
/// (export and import). All records are plain JSON maps using the exact key
/// names of the v2 export so old backups parse without field renames.
class BackupLibraryData {
  const BackupLibraryData({
    required this.books,
    required this.bookCards,
    required this.bookAssets,
    required this.bookRemarks,
    this.readerSession,
  });

  factory BackupLibraryData.fromSnapshot(
    LibraryBackupSnapshot snapshot, {
    Map<String, dynamic>? readerSession,
  }) {
    return BackupLibraryData(
      books: snapshot.books.map(_bookToJson).toList(growable: false),
      bookCards: snapshot.bookCards
          .map(_bookCardToJson)
          .toList(growable: false),
      bookAssets: snapshot.bookAssets
          .map(_bookAssetToJson)
          .toList(growable: false),
      bookRemarks: snapshot.bookRemarks
          .map(_bookRemarkToJson)
          .toList(growable: false),
      readerSession: readerSession,
    );
  }

  static const format = 'fluidtext.backup';

  /// Highest backup format version this build understands.
  static const maxSupportedVersion = 3;

  final List<Map<String, dynamic>> books;
  final List<Map<String, dynamic>> bookCards;
  final List<Map<String, dynamic>> bookAssets;
  final List<Map<String, dynamic>> bookRemarks;
  final Map<String, dynamic>? readerSession;

  /// Serializes to the `data/library.json` payload of a v3 archive. Keys are
  /// identical to the v2 backup JSON, minus the format/version/exportedAt
  /// header (which lives in the v3 manifest instead).
  Map<String, dynamic> toLibraryJson() {
    return <String, dynamic>{
      'books': books,
      'bookCards': bookCards,
      'bookAssets': bookAssets,
      'bookRemarks': bookRemarks,
      'readerSession': readerSession,
    };
  }
}

/// Parses and validates a v2 backup payload (`format`/`version` header plus
/// the library collections).
BackupLibraryData parseV2Payload(Map<String, dynamic> json) {
  if (json['format'] != BackupLibraryData.format) {
    throw const FormatException('不是 FluidText 备份文件（format 不匹配）');
  }
  final version = json['version'];
  if (version is! num) {
    throw const FormatException('备份文件缺少版本号');
  }
  if (version > BackupLibraryData.maxSupportedVersion) {
    throw const FormatException('备份由更新版本的 FluidText 导出，请升级应用后再恢复');
  }
  if (version != 2) {
    throw const FormatException('不支持的备份版本，请使用 1.0.0 或当前版本导出的备份文件');
  }
  return _parseLibraryRecords(json, source: '备份文件');
}

/// Parses the `data/library.json` payload inside a v3 archive: same record
/// shape as v2 but without the format/version header.
BackupLibraryData parseLibraryJson(Map<String, dynamic> json) {
  return _parseLibraryRecords(json, source: '备份文件');
}

BackupLibraryData _parseLibraryRecords(
  Map<String, dynamic> json, {
  required String source,
}) {
  final readerSession = json['readerSession'];
  if (readerSession != null && readerSession is! Map<String, dynamic>) {
    throw FormatException('$source 的 readerSession 字段类型非法');
  }
  return BackupLibraryData(
    books: _recordList(json, 'books', source).map(_parseBook).toList(),
    bookCards: _recordList(json, 'bookCards', source).map(_parseCard).toList(),
    bookAssets: _recordList(
      json,
      'bookAssets',
      source,
    ).map(_parseAsset).toList(),
    bookRemarks: _recordList(
      json,
      'bookRemarks',
      source,
    ).map(_parseRemark).toList(),
    readerSession: readerSession as Map<String, dynamic>?,
  );
}

List<Map<String, dynamic>> _recordList(
  Map<String, dynamic> json,
  String key,
  String source,
) {
  final value = json[key];
  if (value == null) return const <Map<String, dynamic>>[];
  if (value is! List) {
    throw FormatException('$source 的 $key 字段必须是数组');
  }
  return [
    for (final entry in value)
      if (entry is Map<String, dynamic>)
        entry
      else
        throw FormatException('$source 的 $key 包含非法记录'),
  ];
}

int _requiredInt(Map<String, dynamic> record, String key, String label) {
  final value = record[key];
  if (value is! num) {
    throw FormatException('$label 缺少必需的数值字段 $key');
  }
  return value.toInt();
}

int? _optionalInt(Map<String, dynamic> record, String key, String label) {
  final value = record[key];
  if (value == null) return null;
  if (value is! num) {
    throw FormatException('$label 的字段 $key 类型非法');
  }
  return value.toInt();
}

String _requiredString(Map<String, dynamic> record, String key, String label) {
  final value = record[key];
  if (value is! String) {
    throw FormatException('$label 缺少必需的文本字段 $key');
  }
  return value;
}

String? _optionalString(Map<String, dynamic> record, String key, String label) {
  final value = record[key];
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('$label 的字段 $key 类型非法');
  }
  return value;
}

bool _optionalBool(Map<String, dynamic> record, String key, String label) {
  final value = record[key];
  if (value == null) return false;
  if (value is! bool) {
    throw FormatException('$label 的字段 $key 必须是布尔值');
  }
  return value;
}

String? _optionalTimestamp(
  Map<String, dynamic> record,
  String key,
  String label,
) {
  final value = _optionalString(record, key, label);
  if (value == null) return null;
  if (DateTime.tryParse(value) == null) {
    throw FormatException('$label 的时间字段 $key 无法解析');
  }
  return value;
}

Map<String, dynamic> _parseBook(Map<String, dynamic> record) {
  const label = '书籍记录';
  return <String, dynamic>{
    'id': _requiredInt(record, 'id', label),
    'title': _requiredString(record, 'title', label),
    'createdAt': _optionalTimestamp(record, 'createdAt', label),
    'fileHash': _optionalString(record, 'fileHash', label),
    'contentFingerprint': _optionalString(record, 'contentFingerprint', label),
    'sourceFileName': _optionalString(record, 'sourceFileName', label),
    'importedAt': _optionalTimestamp(record, 'importedAt', label),
    'cardCount': _optionalInt(record, 'cardCount', label),
    'textCharCount': _optionalInt(record, 'textCharCount', label),
    'assetRootKey': _optionalString(record, 'assetRootKey', label),
  };
}

Map<String, dynamic> _parseCard(Map<String, dynamic> record) {
  const label = '卡片记录';
  return <String, dynamic>{
    'id': _requiredInt(record, 'id', label),
    'bookId': _requiredInt(record, 'bookId', label),
    'bookTitle': _requiredString(record, 'bookTitle', label),
    'cardIndex': _requiredInt(record, 'cardIndex', label),
    'chapterIndex': _requiredInt(record, 'chapterIndex', label),
    'chapterCardIndex': _requiredInt(record, 'chapterCardIndex', label),
    'chapterTitle': _optionalString(record, 'chapterTitle', label),
    'content': _requiredString(record, 'content', label),
    'blocksJson': _optionalString(record, 'blocksJson', label),
    'isRead': _optionalBool(record, 'isRead', label),
    'readAt': _optionalTimestamp(record, 'readAt', label),
    'isFavorite': _optionalBool(record, 'isFavorite', label),
    'favoritedAt': _optionalTimestamp(record, 'favoritedAt', label),
  };
}

Map<String, dynamic> _parseAsset(Map<String, dynamic> record) {
  const label = '资源记录';
  return <String, dynamic>{
    'id': _requiredInt(record, 'id', label),
    'bookId': _requiredInt(record, 'bookId', label),
    'assetKey': _requiredString(record, 'assetKey', label),
    'originalHref': _optionalString(record, 'originalHref', label),
    'normalizedHref': _optionalString(record, 'normalizedHref', label),
    'mimeType': _optionalString(record, 'mimeType', label),
    'relativePath': _requiredString(record, 'relativePath', label),
    'byteLength': _optionalInt(record, 'byteLength', label),
    'createdAt': _optionalTimestamp(record, 'createdAt', label),
  };
}

Map<String, dynamic> _parseRemark(Map<String, dynamic> record) {
  const label = '备注记录';
  return <String, dynamic>{
    'id': _requiredInt(record, 'id', label),
    'title': _requiredString(record, 'title', label),
    'updatedAt': _optionalTimestamp(record, 'updatedAt', label),
  };
}

/// A single file entry of the v3 manifest: archive-relative path, byte
/// length and SHA-256 (hex) of the uncompressed content.
class BackupManifestFile {
  const BackupManifestFile({
    required this.path,
    required this.bytes,
    required this.sha256,
  });

  final String path;
  final int bytes;
  final String sha256;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'path': path,
    'bytes': bytes,
    'sha256': sha256,
  };

  factory BackupManifestFile.fromJson(Map<String, dynamic> json) {
    final path = json['path'];
    final bytes = json['bytes'];
    final sha256 = json['sha256'];
    if (path is! String || path.isEmpty) {
      throw const FormatException('备份清单包含缺少路径的文件条目');
    }
    if (bytes is! num || bytes < 0) {
      throw FormatException('备份清单条目 $path 的字节数非法');
    }
    if (sha256 is! String || sha256.length != 64) {
      throw FormatException('备份清单条目 $path 的 SHA-256 非法');
    }
    return BackupManifestFile(path: path, bytes: bytes.toInt(), sha256: sha256);
  }
}

class BackupManifestCounts {
  const BackupManifestCounts({
    required this.books,
    required this.bookCards,
    required this.bookAssets,
    required this.bookRemarks,
  });

  final int books;
  final int bookCards;
  final int bookAssets;
  final int bookRemarks;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'books': books,
    'bookCards': bookCards,
    'bookAssets': bookAssets,
    'bookRemarks': bookRemarks,
  };

  factory BackupManifestCounts.fromJson(Map<String, dynamic> json) {
    int countOf(String key) {
      final value = json[key];
      if (value is! num || value < 0) {
        throw FormatException('备份清单缺少数量字段 $key');
      }
      return value.toInt();
    }

    return BackupManifestCounts(
      books: countOf('books'),
      bookCards: countOf('bookCards'),
      bookAssets: countOf('bookAssets'),
      bookRemarks: countOf('bookRemarks'),
    );
  }
}

/// v3 archive manifest (`manifest.json`).
class BackupManifest {
  const BackupManifest({
    required this.sqliteSchemaVersion,
    required this.appVersion,
    required this.platform,
    required this.exportedAt,
    required this.counts,
    required this.files,
  });

  static const version = 3;

  final int sqliteSchemaVersion;
  final String appVersion;
  final String platform;
  final DateTime exportedAt;
  final BackupManifestCounts counts;
  final List<BackupManifestFile> files;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'format': BackupLibraryData.format,
    'version': version,
    'sqliteSchemaVersion': sqliteSchemaVersion,
    'appVersion': appVersion,
    'platform': platform,
    'exportedAt': exportedAt.toIso8601String(),
    'counts': counts.toJson(),
    'files': files.map((file) => file.toJson()).toList(growable: false),
  };

  factory BackupManifest.fromJson(Map<String, dynamic> json) {
    if (json['format'] != BackupLibraryData.format) {
      throw const FormatException('备份清单 format 不匹配');
    }
    final version = json['version'];
    if (version is! num) {
      throw const FormatException('备份清单缺少版本号');
    }
    if (version > BackupLibraryData.maxSupportedVersion) {
      throw const FormatException('备份由更新版本的 FluidText 导出，请升级应用后再恢复');
    }
    if (version != BackupManifest.version) {
      throw const FormatException('不支持的备份文件格式，请使用当前版本导出的 ZIP 备份');
    }

    final schemaVersion = json['sqliteSchemaVersion'];
    if (schemaVersion is! num) {
      throw const FormatException('备份清单缺少 sqliteSchemaVersion');
    }
    final appVersion = json['appVersion'];
    if (appVersion is! String) {
      throw const FormatException('备份清单缺少 appVersion');
    }
    final platform = json['platform'];
    if (platform is! String) {
      throw const FormatException('备份清单缺少 platform');
    }
    final exportedAtRaw = json['exportedAt'];
    final exportedAt = exportedAtRaw is String
        ? DateTime.tryParse(exportedAtRaw)
        : null;
    if (exportedAt == null) {
      throw const FormatException('备份清单的 exportedAt 无法解析');
    }
    final counts = json['counts'];
    if (counts is! Map<String, dynamic>) {
      throw const FormatException('备份清单缺少 counts');
    }
    final files = json['files'];
    if (files is! List) {
      throw const FormatException('备份清单缺少 files');
    }

    return BackupManifest(
      sqliteSchemaVersion: schemaVersion.toInt(),
      appVersion: appVersion,
      platform: platform,
      exportedAt: exportedAt,
      counts: BackupManifestCounts.fromJson(counts),
      files: [
        for (final entry in files)
          if (entry is Map<String, dynamic>)
            BackupManifestFile.fromJson(entry)
          else
            throw const FormatException('备份清单包含非法文件条目'),
      ],
    );
  }
}

Map<String, dynamic> _bookToJson(Book book) {
  return <String, dynamic>{
    'id': book.id,
    'assetRootKey': book.assetRootKey,
    'cardCount': book.cardCount,
    'contentFingerprint': book.contentFingerprint,
    'createdAt': book.createdAt.toIso8601String(),
    'fileHash': book.fileHash,
    'importedAt': book.importedAt?.toIso8601String(),
    'sourceFileName': book.sourceFileName,
    'textCharCount': book.textCharCount,
    'title': book.title,
  };
}

Map<String, dynamic> _bookCardToJson(BookCard card) {
  return <String, dynamic>{
    'id': card.id,
    'blocksJson': card.blocksJson,
    'bookId': card.bookId,
    'bookTitle': card.bookTitle,
    'cardIndex': card.cardIndex,
    'chapterCardIndex': card.chapterCardIndex,
    'chapterIndex': card.chapterIndex,
    'chapterTitle': card.chapterTitle,
    'content': card.content,
    'favoritedAt': card.favoritedAt?.toIso8601String(),
    'isFavorite': card.isFavorite,
    'isRead': card.isRead,
    'readAt': card.readAt?.toIso8601String(),
  };
}

Map<String, dynamic> _bookAssetToJson(BookAsset asset) {
  return <String, dynamic>{
    'id': asset.id,
    'bookId': asset.bookId,
    'assetKey': asset.assetKey,
    'originalHref': asset.originalHref,
    'normalizedHref': asset.normalizedHref,
    'mimeType': asset.mimeType,
    'relativePath': asset.relativePath,
    'byteLength': asset.byteLength,
    'createdAt': asset.createdAt.toIso8601String(),
  };
}

Map<String, dynamic> _bookRemarkToJson(BookRemarkSnapshot remark) {
  return <String, dynamic>{
    'id': remark.bookId,
    'title': remark.title,
    'updatedAt': remark.updatedAt.toIso8601String(),
  };
}
