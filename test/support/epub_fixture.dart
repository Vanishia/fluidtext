import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

Uint8List buildTestEpub({
  String title = 'Integration Book',
  String paragraph = '第一段测试文字。第二段测试文字。',
  bool includeImage = true,
  bool includeChapterFile = true,
}) {
  final archive = Archive()
    ..addFile(ArchiveFile.string('mimetype', 'application/epub+zip'))
    ..addFile(
      ArchiveFile.string(
        'META-INF/container.xml',
        '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/content.opf',
        '''<?xml version="1.0" encoding="UTF-8"?>
<package version="2.0" unique-identifier="BookId" xmlns="http://www.idpf.org/2007/opf">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="BookId">fluidtext-integration</dc:identifier>
    <dc:title>$title</dc:title>
    <dc:language>zh</dc:language>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/>
    ${includeImage ? '<item id="pixel" href="images/pixel.png" media-type="image/png"/>' : ''}
  </manifest>
  <spine toc="ncx"><itemref idref="chapter"/></spine>
</package>''',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/toc.ncx',
        '''<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head><meta name="dtb:uid" content="fluidtext-integration"/></head>
  <docTitle><text>$title</text></docTitle>
  <navMap>
    <navPoint id="chapter" playOrder="1">
      <navLabel><text>第一章</text></navLabel>
      <content src="chapter.xhtml"/>
    </navPoint>
  </navMap>
</ncx>''',
      ),
    );

  if (includeChapterFile) {
    archive.addFile(
      ArchiveFile.string(
        'OEBPS/chapter.xhtml',
        '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><title>第一章</title></head>
  <body><p>$paragraph</p>${includeImage ? '<img src="images/pixel.png" alt="测试图片"/>' : ''}</body>
</html>''',
      ),
    );
  }

  if (includeImage) {
    archive.addFile(
      ArchiveFile.bytes(
        'OEBPS/images/pixel.png',
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
      ),
    );
  }

  return Uint8List.fromList(ZipEncoder().encode(archive));
}
