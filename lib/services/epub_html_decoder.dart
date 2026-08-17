import 'dart:convert';

import 'package:charset/charset.dart';

/// Decodes EPUB HTML bytes that failed strict UTF-8 decoding.
///
/// Some real-world EPUBs ship chapters in legacy encodings (GBK/GB2312 is
/// common for Chinese books). epub_plus decodes everything as strict UTF-8
/// and throws on these files; this fallback honours the charset declared in
/// the HTML `<meta>` tag and otherwise probes GBK before salvaging with
/// malformed-tolerant UTF-8.
String decodeHtmlBytesLossy(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    // Not clean UTF-8; probe legacy encodings below.
  }

  final salvagedUtf8 = const Utf8Codec(allowMalformed: true).decode(bytes);

  final declared = _declaredCharset(bytes);
  if (declared != null) {
    if (declared.name == utf8.name) {
      // Declared UTF-8 but malformed: salvage instead of misreading as GBK.
      return salvagedUtf8;
    }
    try {
      return declared.decode(bytes);
    } on FormatException {
      // Wrong declaration; keep probing.
    }
  }

  // Undeclared: a high replacement ratio means the bytes are not UTF-8 at
  // all (typically GBK); just a few bad bytes means slightly corrupt UTF-8,
  // which is safer to salvage than to misread as another encoding.
  if (_replacementRatio(salvagedUtf8) > 0.01) {
    try {
      return gbk.decode(bytes);
    } on FormatException {
      // Not GBK either; fall through to the salvaged UTF-8.
    }
  }
  return salvagedUtf8;
}

/// Sniffs `charset=...` from the raw bytes; the `<meta>` tag itself is ASCII
/// so a lossy latin1 pass over the file head is enough.
Encoding? _declaredCharset(List<int> bytes) {
  final headLength = bytes.length < 4096 ? bytes.length : 4096;
  final head = latin1.decode(bytes.sublist(0, headLength));
  final match = RegExp(
    r'charset\s*=\s*["\x27]?\s*([a-zA-Z0-9_-]+)',
    caseSensitive: false,
  ).firstMatch(head);
  if (match == null) return null;
  final name = match.group(1)!.toLowerCase();
  if (name == 'utf-8' || name == 'utf8') return utf8;
  return Charset.getByName(name);
}

double _replacementRatio(String text) {
  if (text.isEmpty) return 0;
  var replacements = 0;
  for (var index = 0; index < text.length; index++) {
    if (text.codeUnitAt(index) == 0xfffd) replacements++;
  }
  return replacements / text.length;
}
