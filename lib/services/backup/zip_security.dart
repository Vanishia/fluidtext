import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import '../../storage/storage_layout.dart';

/// ZIP 恢复限额。
///
/// 取值理由（配合计划 7.4「限额应由真实样本确定」的保守上界）：
/// - [maxArchiveBytes] 2GB：真实书库备份（含 EPUB 图片、背景、字体）远小于
///   该值；2GB 也低于 ZIP64 阈值，使恢复端可以明确拒绝 ZIP64 结构。
/// - [maxTotalUncompressedBytes] 4GB：解压后总大小上界，防止 ZIP bomb
///   写满磁盘；约为目标设备可用空间的保守下限。
/// - [maxFileUncompressedBytes] 512MB：单文件上界，封面图/字体/数据库
///   JSON 均远低于该值；同时把单条目的内存峰值限制在可接受范围。
/// - [maxEntryCount] 100000：EPUB 图片量级在千级，100k 留有充足余量。
/// - [maxCompressionRatio] 100：仅对解压大小超过
///   [compressionRatioMinBytes]（1MB）的条目生效，避免小 JSON（文本压缩比
///   天然偏高）被误伤；deflate 对重复内容的极限压缩比约 1032:1，100 足以
///   拦住 ZIP bomb 又不误伤真实图片（图片几乎不可再压缩）。
class ZipSecurityLimits {
  const ZipSecurityLimits({
    this.maxArchiveBytes = 2 * 1024 * 1024 * 1024,
    this.maxTotalUncompressedBytes = 4 * 1024 * 1024 * 1024,
    this.maxFileUncompressedBytes = 512 * 1024 * 1024,
    this.maxEntryCount = 100000,
    this.maxCompressionRatio = 100,
    this.compressionRatioMinBytes = 1024 * 1024,
  });

  /// The production limits documented above.
  static const standard = ZipSecurityLimits();

  final int maxArchiveBytes;
  final int maxTotalUncompressedBytes;
  final int maxFileUncompressedBytes;
  final int maxEntryCount;
  final int maxCompressionRatio;
  final int compressionRatioMinBytes;
}

/// A file extracted from a backup archive.
class ExtractedEntry {
  const ExtractedEntry({
    required this.relativePath,
    required this.bytes,
    required this.sha256,
  });

  /// Archive-relative POSIX path (forward slashes).
  final String relativePath;
  final int bytes;
  final String sha256;
}

class _CentralEntry {
  _CentralEntry({
    required this.nameBytes,
    required this.flags,
    required this.method,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.externalAttributes,
    required this.localHeaderOffset,
  });

  final List<int> nameBytes;
  final int flags;
  final int method;
  final int compressedSize;
  final int uncompressedSize;
  final int externalAttributes;
  final int localHeaderOffset;

  bool get isDirectory {
    final name = utf8.decode(nameBytes, allowMalformed: true);
    return name.endsWith('/') || name.endsWith(r'\');
  }
}

/// Self-contained ZIP structure validation and bounded streaming extraction.
///
/// The Central Directory is parsed with [RandomAccessFile] instead of
/// trusting the archive package's internal behaviour, so filename spoofing
/// (CDE vs Local File Header name mismatch), encrypted entries, symlink
/// entries and unsafe paths are rejected before any byte is decompressed.
class ZipSecurity {
  const ZipSecurity._();

  static const _cdeSignature = 0x02014B50; // PK\x01\x02
  static const _lfhSignature = 0x04034B50; // PK\x03\x04
  static const _eocdMinLength = 22;
  static const _maxCommentLength = 0xFFFF;
  static const _symlinkFileType = 0xA000;

  /// Validates [zipFile] structurally and extracts every regular file into
  /// [targetDir], enforcing all limits while streaming: at most one entry's
  /// bytes are held in memory at a time.
  ///
  /// Throws [FormatException] (Chinese message) on any structural,
  /// security or limit violation.
  ///
  /// [onBytes] reports extracted versus declared total uncompressed bytes
  /// after each entry, for progress display.
  static Future<List<ExtractedEntry>> extractToDisk(
    File zipFile,
    Directory targetDir, {
    ZipSecurityLimits limits = ZipSecurityLimits.standard,
    void Function(int extractedBytes, int totalBytes)? onBytes,
  }) async {
    final entries = await _validateStructure(zipFile, limits);
    final declaredTotalBytes = entries
        .where((entry) => !entry.isDirectory)
        .fold<int>(0, (sum, entry) => sum + entry.uncompressedSize);

    final input = InputFileStream(zipFile.path);
    final Archive archive;
    try {
      archive = ZipDecoder().decodeStream(input, verify: true);
    } catch (error) {
      await input.close();
      throw FormatException('ZIP 文件损坏或格式无法识别：$error');
    }

    final extracted = <ExtractedEntry>[];
    var totalBytes = 0;
    var fileCount = 0;
    try {
      for (final file in archive.files) {
        if (file.isDirectory) continue;
        if (file.isSymbolicLink) {
          throw FormatException('ZIP 包含符号链接条目：${file.name}');
        }
        if (++fileCount > limits.maxEntryCount) {
          throw const FormatException('ZIP 条目数量超出限制');
        }

        final normalizedName = file.name.replaceAll(r'\', '/');
        // Re-validate the decoded name: defence in depth on top of the
        // Central Directory checks.
        final safePath = _validateEntryPath(normalizedName);
        final relativePath = safePath.asPosixPath();

        final Uint8List content;
        try {
          content = file.content;
        } catch (error) {
          throw FormatException('ZIP 条目 $relativePath 解压失败：$error');
        }

        totalBytes += content.length;
        if (content.length > limits.maxFileUncompressedBytes) {
          throw FormatException('ZIP 条目 $relativePath 解压后大小超出限制');
        }
        if (totalBytes > limits.maxTotalUncompressedBytes) {
          throw const FormatException('ZIP 解压总大小超出限制');
        }

        final target = File(
          StorageLayout.joinPath([
            targetDir.path,
            safePath.asPlatformPath(separator: Platform.pathSeparator),
          ], separator: Platform.pathSeparator),
        );
        if (!StoragePathSafety.isLexicallyWithinDirectory(
          directoryPath: targetDir.absolute.path,
          filePath: target.absolute.path,
        )) {
          throw FormatException('ZIP 条目 $relativePath 逃逸出解压目录');
        }
        if (!await target.parent.exists()) {
          await target.parent.create(recursive: true);
        }
        await target.writeAsBytes(content, flush: true);

        extracted.add(
          ExtractedEntry(
            relativePath: relativePath,
            bytes: content.length,
            sha256: sha256.convert(content).toString(),
          ),
        );
        onBytes?.call(totalBytes, declaredTotalBytes);
      }
    } finally {
      await input.close();
    }

    // The decoder merges duplicate names; the structural pass already
    // rejected duplicates, so the counts must agree exactly.
    if (fileCount != entries.where((entry) => !entry.isDirectory).length) {
      throw const FormatException('ZIP 条目数量与中央目录声明不一致');
    }
    return extracted;
  }

  /// Parses EOCD + Central Directory + Local File Headers and enforces all
  /// structural rules and declared-size limits. Returns the central entries.
  static Future<List<_CentralEntry>> _validateStructure(
    File zipFile,
    ZipSecurityLimits limits,
  ) async {
    final length = await zipFile.length();
    if (length > limits.maxArchiveBytes) {
      throw const FormatException('备份文件超出 2GB 大小限制');
    }
    if (length < _eocdMinLength) {
      throw const FormatException('备份文件过小，不是有效的 ZIP');
    }

    final raf = await zipFile.open();
    try {
      final eocdOffset = await _findEocd(raf, length);
      await raf.setPosition(eocdOffset + 4);
      final diskNumber = await _readUint16(raf);
      final cdDisk = await _readUint16(raf);
      await _readUint16(raf); // entries on this disk
      final totalEntries = await _readUint16(raf);
      final cdSize = await _readUint32(raf);
      final cdOffset = await _readUint32(raf);

      if (diskNumber != 0 || cdDisk != 0) {
        throw const FormatException('不支持分卷 ZIP 备份');
      }
      if (totalEntries == 0xFFFF ||
          cdSize == 0xFFFFFFFF ||
          cdOffset == 0xFFFFFFFF) {
        throw const FormatException('不支持 ZIP64 格式的备份');
      }
      if (totalEntries > limits.maxEntryCount) {
        throw const FormatException('ZIP 条目数量超出限制');
      }
      if (cdOffset + cdSize > length || cdOffset + cdSize > eocdOffset) {
        throw const FormatException('ZIP 中央目录超出文件范围，文件可能已被截断');
      }

      final entries = <_CentralEntry>[];
      await raf.setPosition(cdOffset);
      final cdEnd = cdOffset + cdSize;
      for (var index = 0; index < totalEntries; index++) {
        if (await raf.position() + 46 > cdEnd) {
          throw const FormatException('ZIP 中央目录被截断');
        }
        entries.add(await _readCentralEntry(raf, length));
      }

      // Compare each Local File Header name with its Central Directory name
      // to reject filename spoofing.
      for (final entry in entries) {
        await _verifyLocalHeaderName(raf, entry, length);
      }

      _validateEntryNames(entries);
      _validateDeclaredLimits(entries, limits);
      return entries;
    } on FileSystemException catch (error) {
      throw FormatException('备份文件读取失败：$error');
    } on RangeError {
      throw const FormatException('ZIP 文件损坏或已被截断');
    } finally {
      await raf.close();
    }
  }

  static Future<int> _findEocd(RandomAccessFile raf, int length) async {
    final window = length < _eocdMinLength + _maxCommentLength
        ? length
        : _eocdMinLength + _maxCommentLength;
    await raf.setPosition(length - window);
    final tail = await raf.read(window);
    for (var offset = tail.length - _eocdMinLength; offset >= 0; offset--) {
      if (tail[offset] == 0x50 &&
          tail[offset + 1] == 0x4B &&
          tail[offset + 2] == 0x05 &&
          tail[offset + 3] == 0x06) {
        final commentLength = tail[offset + 20] | (tail[offset + 21] << 8);
        if (length - window + offset + _eocdMinLength + commentLength ==
            length) {
          return length - window + offset;
        }
      }
    }
    throw const FormatException('未找到 ZIP 结尾记录，文件可能已被截断');
  }

  static Future<_CentralEntry> _readCentralEntry(
    RandomAccessFile raf,
    int fileLength,
  ) async {
    final signature = await _readUint32(raf);
    if (signature != _cdeSignature) {
      throw const FormatException('ZIP 中央目录条目损坏');
    }
    await _readUint16(raf); // version made by
    await _readUint16(raf); // version needed
    final flags = await _readUint16(raf);
    final method = await _readUint16(raf);
    await _readUint32(raf); // mod time + date
    await _readUint32(raf); // crc32
    final compressedSize = await _readUint32(raf);
    final uncompressedSize = await _readUint32(raf);
    final nameLength = await _readUint16(raf);
    final extraLength = await _readUint16(raf);
    final commentLength = await _readUint16(raf);
    await _readUint16(raf); // disk number start
    await _readUint16(raf); // internal attributes
    final externalAttributes = await _readUint32(raf);
    final localHeaderOffset = await _readUint32(raf);

    if (compressedSize == 0xFFFFFFFF ||
        uncompressedSize == 0xFFFFFFFF ||
        localHeaderOffset == 0xFFFFFFFF) {
      throw const FormatException('不支持 ZIP64 格式的备份');
    }
    if (localHeaderOffset + 30 > fileLength) {
      throw const FormatException('ZIP 本地文件头超出文件范围，文件可能已被截断');
    }

    final nameBytes = await raf.read(nameLength);
    if (nameBytes.length != nameLength) {
      throw const FormatException('ZIP 中央目录被截断');
    }
    await raf.setPosition(await raf.position() + extraLength + commentLength);

    if (flags & 0x1 != 0) {
      final name = utf8.decode(nameBytes, allowMalformed: true);
      throw FormatException('ZIP 条目 $name 已加密，无法恢复加密备份');
    }
    if ((externalAttributes >> 16) & 0xF000 == _symlinkFileType) {
      final name = utf8.decode(nameBytes, allowMalformed: true);
      throw FormatException('ZIP 包含符号链接条目：$name');
    }
    if (method != 0 && method != 8) {
      final name = utf8.decode(nameBytes, allowMalformed: true);
      throw FormatException('ZIP 条目 $name 使用了不支持的压缩方式（$method）');
    }

    return _CentralEntry(
      nameBytes: nameBytes,
      flags: flags,
      method: method,
      compressedSize: compressedSize,
      uncompressedSize: uncompressedSize,
      externalAttributes: externalAttributes,
      localHeaderOffset: localHeaderOffset,
    );
  }

  static Future<void> _verifyLocalHeaderName(
    RandomAccessFile raf,
    _CentralEntry entry,
    int fileLength,
  ) async {
    await raf.setPosition(entry.localHeaderOffset);
    final signature = await _readUint32(raf);
    if (signature != _lfhSignature) {
      throw const FormatException('ZIP 本地文件头损坏，文件可能已被截断');
    }
    await raf.setPosition(entry.localHeaderOffset + 26);
    final nameLength = await _readUint16(raf);
    final extraLength = await _readUint16(raf);
    if (entry.localHeaderOffset + 30 + nameLength + extraLength > fileLength) {
      throw const FormatException('ZIP 本地文件头超出文件范围，文件可能已被截断');
    }
    final nameBytes = await raf.read(nameLength);
    if (nameBytes.length != nameLength) {
      throw const FormatException('ZIP 本地文件头被截断');
    }
    if (!_bytesEqual(nameBytes, entry.nameBytes)) {
      final central = utf8.decode(entry.nameBytes, allowMalformed: true);
      final local = utf8.decode(nameBytes, allowMalformed: true);
      throw FormatException('ZIP 条目文件名不一致（中央目录 "$central" / 本地头 "$local"），已拒绝');
    }
  }

  static void _validateEntryNames(List<_CentralEntry> entries) {
    final seenPaths = <String>{};
    final seenCaseFolded = <String>{};
    for (final entry in entries) {
      var name = utf8.decode(entry.nameBytes, allowMalformed: true);
      final isDirectory = name.endsWith('/') || name.endsWith(r'\');
      if (isDirectory) {
        name = name.substring(0, name.length - 1);
      }
      if (name.isEmpty) {
        throw const FormatException('ZIP 包含空文件名的条目');
      }
      final normalized = name.replaceAll(r'\', '/');
      // Full segment-level validation (absolute paths, drive letters, UNC,
      // `..`/`.`/empty segments and control characters are all rejected).
      StoragePathSafety.parseRelativePath(normalized, label: 'ZIP 条目路径');
      if (!seenPaths.add(normalized)) {
        throw FormatException('ZIP 包含重复条目路径：$normalized');
      }
      if (!seenCaseFolded.add(normalized.toLowerCase())) {
        throw FormatException('ZIP 包含仅大小写不同的重复条目路径：$normalized');
      }
    }
  }

  static void _validateDeclaredLimits(
    List<_CentralEntry> entries,
    ZipSecurityLimits limits,
  ) {
    var totalUncompressed = 0;
    for (final entry in entries) {
      if (entry.isDirectory) continue;
      if (entry.uncompressedSize > limits.maxFileUncompressedBytes) {
        final name = utf8.decode(entry.nameBytes, allowMalformed: true);
        throw FormatException('ZIP 条目 $name 解压后大小超出限制');
      }
      totalUncompressed += entry.uncompressedSize;
      if (totalUncompressed > limits.maxTotalUncompressedBytes) {
        throw const FormatException('ZIP 解压总大小超出限制');
      }
      if (entry.uncompressedSize > limits.compressionRatioMinBytes &&
          (entry.compressedSize == 0 ||
              entry.uncompressedSize / entry.compressedSize >
                  limits.maxCompressionRatio)) {
        final name = utf8.decode(entry.nameBytes, allowMalformed: true);
        throw FormatException('ZIP 条目 $name 压缩比异常，疑似 ZIP bomb');
      }
    }
  }

  static SafeRelativePath _validateEntryPath(String normalizedName) {
    return StoragePathSafety.parseRelativePath(
      normalizedName,
      label: 'ZIP 条目路径',
    );
  }

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static Future<int> _readUint16(RandomAccessFile raf) async {
    final bytes = await raf.read(2);
    if (bytes.length != 2) {
      throw const FormatException('ZIP 文件损坏或已被截断');
    }
    return bytes[0] | (bytes[1] << 8);
  }

  static Future<int> _readUint32(RandomAccessFile raf) async {
    final bytes = await raf.read(4);
    if (bytes.length != 4) {
      throw const FormatException('ZIP 文件损坏或已被截断');
    }
    return bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24);
  }
}
