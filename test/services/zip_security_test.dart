import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/services/backup/zip_security.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('fluidtext-zip-test-');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Uint8List encodeZip(Map<String, List<int>> files) {
    final archive = Archive();
    files.forEach((name, bytes) {
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    });
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  Future<void> expectRejected(
    String name,
    Uint8List zip, {
    String? messagePart,
    ZipSecurityLimits limits = ZipSecurityLimits.standard,
  }) async {
    final file = File('${tempDir.path}/$name.zip');
    await file.writeAsBytes(zip, flush: true);
    final target = await Directory(
      '${tempDir.path}/$name',
    ).create(recursive: true);
    final matcher = messagePart == null
        ? throwsFormatException
        : throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains(messagePart),
            ),
          );
    await expectLater(
      () => ZipSecurity.extractToDisk(file, target, limits: limits),
      matcher,
    );
  }

  // --- byte-level helpers over the ZIP structures -------------------------

  int uint16At(Uint8List bytes, int offset) =>
      bytes[offset] | (bytes[offset + 1] << 8);

  int uint32At(Uint8List bytes, int offset) =>
      bytes[offset] |
      bytes[offset + 1] << 8 |
      bytes[offset + 2] << 16 |
      bytes[offset + 3] << 24;

  void writeUint32At(Uint8List bytes, int offset, int value) {
    bytes[offset] = value & 0xFF;
    bytes[offset + 1] = (value >> 8) & 0xFF;
    bytes[offset + 2] = (value >> 16) & 0xFF;
    bytes[offset + 3] = (value >> 24) & 0xFF;
  }

  int eocdOffset(Uint8List bytes) {
    for (var i = bytes.length - 22; i >= 0; i--) {
      if (bytes[i] == 0x50 &&
          bytes[i + 1] == 0x4B &&
          bytes[i + 2] == 0x05 &&
          bytes[i + 3] == 0x06) {
        return i;
      }
    }
    throw StateError('no EOCD');
  }

  /// Offsets of every Central Directory Entry.
  List<int> cdeOffsets(Uint8List bytes) {
    final eocd = eocdOffset(bytes);
    final count = uint16At(bytes, eocd + 10);
    var offset = uint32At(bytes, eocd + 16);
    final offsets = <int>[];
    for (var i = 0; i < count; i++) {
      expect(uint32At(bytes, offset), 0x02014B50);
      offsets.add(offset);
      final nameLength = uint16At(bytes, offset + 28);
      final extraLength = uint16At(bytes, offset + 30);
      final commentLength = uint16At(bytes, offset + 32);
      offset += 46 + nameLength + extraLength + commentLength;
    }
    return offsets;
  }

  int lfhOffsetOf(Uint8List bytes, int cdeOffset) =>
      uint32At(bytes, cdeOffset + 42);

  // --- tests ---------------------------------------------------------------

  test('extracts a normal zip and reports correct sha256', () async {
    final contentA = utf8.encode('你好，FluidText');
    final contentB = List<int>.generate(256, (index) => index);
    final zip = encodeZip(<String, List<int>>{
      'a.txt': contentA,
      'dir/b.bin': contentB,
    });
    final file = File('${tempDir.path}/normal.zip');
    await file.writeAsBytes(zip, flush: true);
    final target = await Directory(
      '${tempDir.path}/normal',
    ).create(recursive: true);

    final entries = await ZipSecurity.extractToDisk(file, target);

    expect(entries, hasLength(2));
    final byPath = {for (final entry in entries) entry.relativePath: entry};
    expect(byPath['a.txt']!.bytes, contentA.length);
    expect(byPath['a.txt']!.sha256, sha256.convert(contentA).toString());
    expect(byPath['dir/b.bin']!.sha256, sha256.convert(contentB).toString());
    expect(await File('${target.path}/a.txt').readAsBytes(), contentA);
    expect(await File('${target.path}/dir/b.bin').readAsBytes(), contentB);
  });

  test('rejects ZIP Slip entries', () async {
    await expectRejected(
      'slip',
      encodeZip(<String, List<int>>{'../evil.txt': utf8.encode('evil')}),
    );
    expect(await File('${tempDir.path}/evil.txt').exists(), isFalse);
  });

  test('rejects absolute, drive-letter and UNC paths', () async {
    var counter = 0;
    for (final name in ['/abs.txt', 'C:/win.txt', '//unc/share.txt']) {
      await expectRejected(
        'abs${counter++}',
        encodeZip(<String, List<int>>{name: utf8.encode('x')}),
      );
    }
  });

  test('rejects duplicate paths', () async {
    // The archive package deduplicates equal names, so craft the duplicate
    // by renaming the first entry (CDE + LFH) to the second entry's name.
    final zip = encodeZip(<String, List<int>>{
      'b.txt': utf8.encode('x'),
      'c.txt': utf8.encode('y'),
    });
    final cde = cdeOffsets(zip).first;
    final lfh = lfhOffsetOf(zip, cde);
    final renamed = utf8.encode('c.txt');
    zip.setRange(lfh + 30, lfh + 30 + renamed.length, renamed);
    zip.setRange(cde + 46, cde + 46 + renamed.length, renamed);
    await expectRejected('dup', zip, messagePart: '重复条目路径');
  });

  test('rejects paths that only differ by case', () async {
    await expectRejected(
      'case',
      encodeZip(<String, List<int>>{
        'A.txt': utf8.encode('x'),
        'a.txt': utf8.encode('y'),
      }),
      messagePart: '大小写',
    );
  });

  test('rejects symlink entries via external attributes', () async {
    final zip = encodeZip(<String, List<int>>{'link.txt': utf8.encode('x')});
    final cde = cdeOffsets(zip).single;
    writeUint32At(zip, cde + 38, 0xA000 << 16); // Unix symlink file type
    await expectRejected('symlink', zip, messagePart: '符号链接');
  });

  test('rejects encrypted entries via flags', () async {
    final zip = encodeZip(<String, List<int>>{'secret.txt': utf8.encode('x')});
    final cde = cdeOffsets(zip).single;
    zip[cde + 8] = zip[cde + 8] | 0x1; // set the encryption flag bit
    await expectRejected('encrypted', zip, messagePart: '加密');
  });

  test('rejects CDE/LFH filename mismatch (spoofing)', () async {
    final zip = encodeZip(<String, List<int>>{'safe.txt': utf8.encode('x')});
    final cde = cdeOffsets(zip).single;
    final lfh = lfhOffsetOf(zip, cde);
    expect(uint32At(zip, lfh), 0x04034B50);
    // Rewrite the local header filename to a different same-length name.
    zip[lfh + 30] = 'X'.codeUnitAt(0);
    await expectRejected('spoofed', zip, messagePart: '文件名不一致');
  });

  test('rejects declared oversized single file without extracting', () async {
    final zip = encodeZip(<String, List<int>>{'big.bin': utf8.encode('tiny')});
    final cde = cdeOffsets(zip).single;
    writeUint32At(zip, cde + 24, 600 * 1024 * 1024); // uncompressed size
    await expectRejected('big', zip, messagePart: '大小超出限制');
  });

  test('rejects zip bombs by compression ratio', () async {
    final payload = List<int>.filled(2 * 1024 * 1024, 0x41); // 2MB of 'A'
    final zip = encodeZip(<String, List<int>>{'bomb.txt': payload});
    // deflate collapses the payload far beyond the 100:1 ratio limit.
    expect(zip.length, lessThan(payload.length ~/ 100));
    await expectRejected('bomb', zip, messagePart: '压缩比');
  });

  test('enforces the entry count limit', () async {
    await expectRejected(
      'count',
      encodeZip(<String, List<int>>{
        'a.txt': utf8.encode('a'),
        'b.txt': utf8.encode('b'),
        'c.txt': utf8.encode('c'),
      }),
      limits: const ZipSecurityLimits(maxEntryCount: 2),
    );
  });

  test('enforces the total uncompressed size limit during extraction',
      () async {
    await expectRejected(
      'total',
      encodeZip(<String, List<int>>{
        'a.txt': List<int>.filled(60, 0x61),
        'b.txt': List<int>.filled(60, 0x62),
      }),
      limits: const ZipSecurityLimits(maxTotalUncompressedBytes: 100),
    );
  });

  test('rejects truncated zips', () async {
    final zip = encodeZip(<String, List<int>>{'a.txt': utf8.encode('hello')});
    await expectRejected(
      'truncated',
      Uint8List.sublistView(zip, 0, zip.length - 30),
    );
  });

  test('rejects zips whose entry count does not match the directory',
      () async {
    final zip = encodeZip(<String, List<int>>{'a.txt': utf8.encode('hello')});
    final eocd = eocdOffset(zip);
    zip[eocd + 10] = 2; // claim one more entry than the CD contains
    zip[eocd + 8] = 2;
    await expectRejected('mismatch', zip);
  });

  test('normalizes backslash separators in entry names', () async {
    final archive = Archive()
      ..addFile(ArchiveFile(r'dir\b.txt', 3, utf8.encode('abc')));
    final zip = Uint8List.fromList(ZipEncoder().encode(archive));
    final file = File('${tempDir.path}/backslash.zip');
    await file.writeAsBytes(zip, flush: true);
    final target = await Directory(
      '${tempDir.path}/backslash',
    ).create(recursive: true);

    final entries = await ZipSecurity.extractToDisk(file, target);
    expect(entries.single.relativePath, 'dir/b.txt');
    expect(
      await File('${target.path}/dir/b.txt').readAsBytes(),
      utf8.encode('abc'),
    );
  });
}
