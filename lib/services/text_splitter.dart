class TextSplitter {
  TextSplitter({
    this.targetChars = 300,
  });

  final int targetChars;

  Iterable<String> split(String text) sync* {
    if (text.isEmpty) return;

    final bucket = StringBuffer();

    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      bucket.write(ch);

      if (bucket.length >= targetChars && _isBoundary(ch)) {
        yield bucket.toString();
        bucket.clear();
      }
    }

    if (bucket.isNotEmpty) {
      yield bucket.toString();
    }
  }

  bool _isBoundary(String ch) {
    return ch == '。' ||
        ch == '！' ||
        ch == '？' ||
        ch == '.' ||
        ch == '!' ||
        ch == '?' ||
        ch == '\n';
  }
}

