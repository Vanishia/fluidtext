// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'library_database.dart';

// ignore_for_file: type=lint
class $SqliteBooksTable extends SqliteBooks
    with TableInfo<$SqliteBooksTable, SqliteBook> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SqliteBooksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMsMeta = const VerificationMeta(
    'createdAtMs',
  );
  @override
  late final GeneratedColumn<int> createdAtMs = GeneratedColumn<int>(
    'created_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileHashMeta = const VerificationMeta(
    'fileHash',
  );
  @override
  late final GeneratedColumn<String> fileHash = GeneratedColumn<String>(
    'file_hash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _contentFingerprintMeta =
      const VerificationMeta('contentFingerprint');
  @override
  late final GeneratedColumn<String> contentFingerprint =
      GeneratedColumn<String>(
        'content_fingerprint',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _sourceFileNameMeta = const VerificationMeta(
    'sourceFileName',
  );
  @override
  late final GeneratedColumn<String> sourceFileName = GeneratedColumn<String>(
    'source_file_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _importedAtMsMeta = const VerificationMeta(
    'importedAtMs',
  );
  @override
  late final GeneratedColumn<int> importedAtMs = GeneratedColumn<int>(
    'imported_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cardCountMeta = const VerificationMeta(
    'cardCount',
  );
  @override
  late final GeneratedColumn<int> cardCount = GeneratedColumn<int>(
    'card_count',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _textCharCountMeta = const VerificationMeta(
    'textCharCount',
  );
  @override
  late final GeneratedColumn<int> textCharCount = GeneratedColumn<int>(
    'text_char_count',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _assetRootKeyMeta = const VerificationMeta(
    'assetRootKey',
  );
  @override
  late final GeneratedColumn<String> assetRootKey = GeneratedColumn<String>(
    'asset_root_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    createdAtMs,
    fileHash,
    contentFingerprint,
    sourceFileName,
    importedAtMs,
    cardCount,
    textCharCount,
    assetRootKey,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'books';
  @override
  VerificationContext validateIntegrity(
    Insertable<SqliteBook> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('created_at_ms')) {
      context.handle(
        _createdAtMsMeta,
        createdAtMs.isAcceptableOrUnknown(
          data['created_at_ms']!,
          _createdAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMsMeta);
    }
    if (data.containsKey('file_hash')) {
      context.handle(
        _fileHashMeta,
        fileHash.isAcceptableOrUnknown(data['file_hash']!, _fileHashMeta),
      );
    }
    if (data.containsKey('content_fingerprint')) {
      context.handle(
        _contentFingerprintMeta,
        contentFingerprint.isAcceptableOrUnknown(
          data['content_fingerprint']!,
          _contentFingerprintMeta,
        ),
      );
    }
    if (data.containsKey('source_file_name')) {
      context.handle(
        _sourceFileNameMeta,
        sourceFileName.isAcceptableOrUnknown(
          data['source_file_name']!,
          _sourceFileNameMeta,
        ),
      );
    }
    if (data.containsKey('imported_at_ms')) {
      context.handle(
        _importedAtMsMeta,
        importedAtMs.isAcceptableOrUnknown(
          data['imported_at_ms']!,
          _importedAtMsMeta,
        ),
      );
    }
    if (data.containsKey('card_count')) {
      context.handle(
        _cardCountMeta,
        cardCount.isAcceptableOrUnknown(data['card_count']!, _cardCountMeta),
      );
    }
    if (data.containsKey('text_char_count')) {
      context.handle(
        _textCharCountMeta,
        textCharCount.isAcceptableOrUnknown(
          data['text_char_count']!,
          _textCharCountMeta,
        ),
      );
    }
    if (data.containsKey('asset_root_key')) {
      context.handle(
        _assetRootKeyMeta,
        assetRootKey.isAcceptableOrUnknown(
          data['asset_root_key']!,
          _assetRootKeyMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SqliteBook map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SqliteBook(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      createdAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_ms'],
      )!,
      fileHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_hash'],
      ),
      contentFingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_fingerprint'],
      ),
      sourceFileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_file_name'],
      ),
      importedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}imported_at_ms'],
      ),
      cardCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}card_count'],
      ),
      textCharCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}text_char_count'],
      ),
      assetRootKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}asset_root_key'],
      ),
    );
  }

  @override
  $SqliteBooksTable createAlias(String alias) {
    return $SqliteBooksTable(attachedDatabase, alias);
  }
}

class SqliteBook extends DataClass implements Insertable<SqliteBook> {
  final int id;
  final String title;
  final int createdAtMs;
  final String? fileHash;
  final String? contentFingerprint;
  final String? sourceFileName;
  final int? importedAtMs;
  final int? cardCount;
  final int? textCharCount;
  final String? assetRootKey;
  const SqliteBook({
    required this.id,
    required this.title,
    required this.createdAtMs,
    this.fileHash,
    this.contentFingerprint,
    this.sourceFileName,
    this.importedAtMs,
    this.cardCount,
    this.textCharCount,
    this.assetRootKey,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['title'] = Variable<String>(title);
    map['created_at_ms'] = Variable<int>(createdAtMs);
    if (!nullToAbsent || fileHash != null) {
      map['file_hash'] = Variable<String>(fileHash);
    }
    if (!nullToAbsent || contentFingerprint != null) {
      map['content_fingerprint'] = Variable<String>(contentFingerprint);
    }
    if (!nullToAbsent || sourceFileName != null) {
      map['source_file_name'] = Variable<String>(sourceFileName);
    }
    if (!nullToAbsent || importedAtMs != null) {
      map['imported_at_ms'] = Variable<int>(importedAtMs);
    }
    if (!nullToAbsent || cardCount != null) {
      map['card_count'] = Variable<int>(cardCount);
    }
    if (!nullToAbsent || textCharCount != null) {
      map['text_char_count'] = Variable<int>(textCharCount);
    }
    if (!nullToAbsent || assetRootKey != null) {
      map['asset_root_key'] = Variable<String>(assetRootKey);
    }
    return map;
  }

  SqliteBooksCompanion toCompanion(bool nullToAbsent) {
    return SqliteBooksCompanion(
      id: Value(id),
      title: Value(title),
      createdAtMs: Value(createdAtMs),
      fileHash: fileHash == null && nullToAbsent
          ? const Value.absent()
          : Value(fileHash),
      contentFingerprint: contentFingerprint == null && nullToAbsent
          ? const Value.absent()
          : Value(contentFingerprint),
      sourceFileName: sourceFileName == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceFileName),
      importedAtMs: importedAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(importedAtMs),
      cardCount: cardCount == null && nullToAbsent
          ? const Value.absent()
          : Value(cardCount),
      textCharCount: textCharCount == null && nullToAbsent
          ? const Value.absent()
          : Value(textCharCount),
      assetRootKey: assetRootKey == null && nullToAbsent
          ? const Value.absent()
          : Value(assetRootKey),
    );
  }

  factory SqliteBook.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SqliteBook(
      id: serializer.fromJson<int>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      createdAtMs: serializer.fromJson<int>(json['createdAtMs']),
      fileHash: serializer.fromJson<String?>(json['fileHash']),
      contentFingerprint: serializer.fromJson<String?>(
        json['contentFingerprint'],
      ),
      sourceFileName: serializer.fromJson<String?>(json['sourceFileName']),
      importedAtMs: serializer.fromJson<int?>(json['importedAtMs']),
      cardCount: serializer.fromJson<int?>(json['cardCount']),
      textCharCount: serializer.fromJson<int?>(json['textCharCount']),
      assetRootKey: serializer.fromJson<String?>(json['assetRootKey']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'title': serializer.toJson<String>(title),
      'createdAtMs': serializer.toJson<int>(createdAtMs),
      'fileHash': serializer.toJson<String?>(fileHash),
      'contentFingerprint': serializer.toJson<String?>(contentFingerprint),
      'sourceFileName': serializer.toJson<String?>(sourceFileName),
      'importedAtMs': serializer.toJson<int?>(importedAtMs),
      'cardCount': serializer.toJson<int?>(cardCount),
      'textCharCount': serializer.toJson<int?>(textCharCount),
      'assetRootKey': serializer.toJson<String?>(assetRootKey),
    };
  }

  SqliteBook copyWith({
    int? id,
    String? title,
    int? createdAtMs,
    Value<String?> fileHash = const Value.absent(),
    Value<String?> contentFingerprint = const Value.absent(),
    Value<String?> sourceFileName = const Value.absent(),
    Value<int?> importedAtMs = const Value.absent(),
    Value<int?> cardCount = const Value.absent(),
    Value<int?> textCharCount = const Value.absent(),
    Value<String?> assetRootKey = const Value.absent(),
  }) => SqliteBook(
    id: id ?? this.id,
    title: title ?? this.title,
    createdAtMs: createdAtMs ?? this.createdAtMs,
    fileHash: fileHash.present ? fileHash.value : this.fileHash,
    contentFingerprint: contentFingerprint.present
        ? contentFingerprint.value
        : this.contentFingerprint,
    sourceFileName: sourceFileName.present
        ? sourceFileName.value
        : this.sourceFileName,
    importedAtMs: importedAtMs.present ? importedAtMs.value : this.importedAtMs,
    cardCount: cardCount.present ? cardCount.value : this.cardCount,
    textCharCount: textCharCount.present
        ? textCharCount.value
        : this.textCharCount,
    assetRootKey: assetRootKey.present ? assetRootKey.value : this.assetRootKey,
  );
  @override
  String toString() {
    return (StringBuffer('SqliteBook(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('fileHash: $fileHash, ')
          ..write('contentFingerprint: $contentFingerprint, ')
          ..write('sourceFileName: $sourceFileName, ')
          ..write('importedAtMs: $importedAtMs, ')
          ..write('cardCount: $cardCount, ')
          ..write('textCharCount: $textCharCount, ')
          ..write('assetRootKey: $assetRootKey')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    createdAtMs,
    fileHash,
    contentFingerprint,
    sourceFileName,
    importedAtMs,
    cardCount,
    textCharCount,
    assetRootKey,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SqliteBook &&
          other.id == this.id &&
          other.title == this.title &&
          other.createdAtMs == this.createdAtMs &&
          other.fileHash == this.fileHash &&
          other.contentFingerprint == this.contentFingerprint &&
          other.sourceFileName == this.sourceFileName &&
          other.importedAtMs == this.importedAtMs &&
          other.cardCount == this.cardCount &&
          other.textCharCount == this.textCharCount &&
          other.assetRootKey == this.assetRootKey);
}

class SqliteBooksCompanion extends UpdateCompanion<SqliteBook> {
  final Value<int> id;
  final Value<String> title;
  final Value<int> createdAtMs;
  final Value<String?> fileHash;
  final Value<String?> contentFingerprint;
  final Value<String?> sourceFileName;
  final Value<int?> importedAtMs;
  final Value<int?> cardCount;
  final Value<int?> textCharCount;
  final Value<String?> assetRootKey;
  const SqliteBooksCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.createdAtMs = const Value.absent(),
    this.fileHash = const Value.absent(),
    this.contentFingerprint = const Value.absent(),
    this.sourceFileName = const Value.absent(),
    this.importedAtMs = const Value.absent(),
    this.cardCount = const Value.absent(),
    this.textCharCount = const Value.absent(),
    this.assetRootKey = const Value.absent(),
  });
  SqliteBooksCompanion.insert({
    this.id = const Value.absent(),
    required String title,
    required int createdAtMs,
    this.fileHash = const Value.absent(),
    this.contentFingerprint = const Value.absent(),
    this.sourceFileName = const Value.absent(),
    this.importedAtMs = const Value.absent(),
    this.cardCount = const Value.absent(),
    this.textCharCount = const Value.absent(),
    this.assetRootKey = const Value.absent(),
  }) : title = Value(title),
       createdAtMs = Value(createdAtMs);
  static Insertable<SqliteBook> custom({
    Expression<int>? id,
    Expression<String>? title,
    Expression<int>? createdAtMs,
    Expression<String>? fileHash,
    Expression<String>? contentFingerprint,
    Expression<String>? sourceFileName,
    Expression<int>? importedAtMs,
    Expression<int>? cardCount,
    Expression<int>? textCharCount,
    Expression<String>? assetRootKey,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (createdAtMs != null) 'created_at_ms': createdAtMs,
      if (fileHash != null) 'file_hash': fileHash,
      if (contentFingerprint != null) 'content_fingerprint': contentFingerprint,
      if (sourceFileName != null) 'source_file_name': sourceFileName,
      if (importedAtMs != null) 'imported_at_ms': importedAtMs,
      if (cardCount != null) 'card_count': cardCount,
      if (textCharCount != null) 'text_char_count': textCharCount,
      if (assetRootKey != null) 'asset_root_key': assetRootKey,
    });
  }

  SqliteBooksCompanion copyWith({
    Value<int>? id,
    Value<String>? title,
    Value<int>? createdAtMs,
    Value<String?>? fileHash,
    Value<String?>? contentFingerprint,
    Value<String?>? sourceFileName,
    Value<int?>? importedAtMs,
    Value<int?>? cardCount,
    Value<int?>? textCharCount,
    Value<String?>? assetRootKey,
  }) {
    return SqliteBooksCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      fileHash: fileHash ?? this.fileHash,
      contentFingerprint: contentFingerprint ?? this.contentFingerprint,
      sourceFileName: sourceFileName ?? this.sourceFileName,
      importedAtMs: importedAtMs ?? this.importedAtMs,
      cardCount: cardCount ?? this.cardCount,
      textCharCount: textCharCount ?? this.textCharCount,
      assetRootKey: assetRootKey ?? this.assetRootKey,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (createdAtMs.present) {
      map['created_at_ms'] = Variable<int>(createdAtMs.value);
    }
    if (fileHash.present) {
      map['file_hash'] = Variable<String>(fileHash.value);
    }
    if (contentFingerprint.present) {
      map['content_fingerprint'] = Variable<String>(contentFingerprint.value);
    }
    if (sourceFileName.present) {
      map['source_file_name'] = Variable<String>(sourceFileName.value);
    }
    if (importedAtMs.present) {
      map['imported_at_ms'] = Variable<int>(importedAtMs.value);
    }
    if (cardCount.present) {
      map['card_count'] = Variable<int>(cardCount.value);
    }
    if (textCharCount.present) {
      map['text_char_count'] = Variable<int>(textCharCount.value);
    }
    if (assetRootKey.present) {
      map['asset_root_key'] = Variable<String>(assetRootKey.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SqliteBooksCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('fileHash: $fileHash, ')
          ..write('contentFingerprint: $contentFingerprint, ')
          ..write('sourceFileName: $sourceFileName, ')
          ..write('importedAtMs: $importedAtMs, ')
          ..write('cardCount: $cardCount, ')
          ..write('textCharCount: $textCharCount, ')
          ..write('assetRootKey: $assetRootKey')
          ..write(')'))
        .toString();
  }
}

class $SqliteBookCardsTable extends SqliteBookCards
    with TableInfo<$SqliteBookCardsTable, SqliteBookCard> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SqliteBookCardsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<int> bookId = GeneratedColumn<int>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL REFERENCES books(id) ON DELETE CASCADE CHECK(book_id > 0)',
  );
  static const VerificationMeta _bookTitleMeta = const VerificationMeta(
    'bookTitle',
  );
  @override
  late final GeneratedColumn<String> bookTitle = GeneratedColumn<String>(
    'book_title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cardIndexMeta = const VerificationMeta(
    'cardIndex',
  );
  @override
  late final GeneratedColumn<int> cardIndex = GeneratedColumn<int>(
    'card_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chapterIndexMeta = const VerificationMeta(
    'chapterIndex',
  );
  @override
  late final GeneratedColumn<int> chapterIndex = GeneratedColumn<int>(
    'chapter_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chapterCardIndexMeta = const VerificationMeta(
    'chapterCardIndex',
  );
  @override
  late final GeneratedColumn<int> chapterCardIndex = GeneratedColumn<int>(
    'chapter_card_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chapterTitleMeta = const VerificationMeta(
    'chapterTitle',
  );
  @override
  late final GeneratedColumn<String> chapterTitle = GeneratedColumn<String>(
    'chapter_title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _blocksJsonMeta = const VerificationMeta(
    'blocksJson',
  );
  @override
  late final GeneratedColumn<String> blocksJson = GeneratedColumn<String>(
    'blocks_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isReadMeta = const VerificationMeta('isRead');
  @override
  late final GeneratedColumn<bool> isRead = GeneratedColumn<bool>(
    'is_read',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_read" IN (0, 1))',
    ),
  );
  static const VerificationMeta _readAtMsMeta = const VerificationMeta(
    'readAtMs',
  );
  @override
  late final GeneratedColumn<int> readAtMs = GeneratedColumn<int>(
    'read_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isFavoriteMeta = const VerificationMeta(
    'isFavorite',
  );
  @override
  late final GeneratedColumn<bool> isFavorite = GeneratedColumn<bool>(
    'is_favorite',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_favorite" IN (0, 1))',
    ),
  );
  static const VerificationMeta _favoritedAtMsMeta = const VerificationMeta(
    'favoritedAtMs',
  );
  @override
  late final GeneratedColumn<int> favoritedAtMs = GeneratedColumn<int>(
    'favorited_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    bookId,
    bookTitle,
    cardIndex,
    chapterIndex,
    chapterCardIndex,
    chapterTitle,
    content,
    blocksJson,
    isRead,
    readAtMs,
    isFavorite,
    favoritedAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'book_cards';
  @override
  VerificationContext validateIntegrity(
    Insertable<SqliteBookCard> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('book_title')) {
      context.handle(
        _bookTitleMeta,
        bookTitle.isAcceptableOrUnknown(data['book_title']!, _bookTitleMeta),
      );
    } else if (isInserting) {
      context.missing(_bookTitleMeta);
    }
    if (data.containsKey('card_index')) {
      context.handle(
        _cardIndexMeta,
        cardIndex.isAcceptableOrUnknown(data['card_index']!, _cardIndexMeta),
      );
    } else if (isInserting) {
      context.missing(_cardIndexMeta);
    }
    if (data.containsKey('chapter_index')) {
      context.handle(
        _chapterIndexMeta,
        chapterIndex.isAcceptableOrUnknown(
          data['chapter_index']!,
          _chapterIndexMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_chapterIndexMeta);
    }
    if (data.containsKey('chapter_card_index')) {
      context.handle(
        _chapterCardIndexMeta,
        chapterCardIndex.isAcceptableOrUnknown(
          data['chapter_card_index']!,
          _chapterCardIndexMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_chapterCardIndexMeta);
    }
    if (data.containsKey('chapter_title')) {
      context.handle(
        _chapterTitleMeta,
        chapterTitle.isAcceptableOrUnknown(
          data['chapter_title']!,
          _chapterTitleMeta,
        ),
      );
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('blocks_json')) {
      context.handle(
        _blocksJsonMeta,
        blocksJson.isAcceptableOrUnknown(data['blocks_json']!, _blocksJsonMeta),
      );
    }
    if (data.containsKey('is_read')) {
      context.handle(
        _isReadMeta,
        isRead.isAcceptableOrUnknown(data['is_read']!, _isReadMeta),
      );
    } else if (isInserting) {
      context.missing(_isReadMeta);
    }
    if (data.containsKey('read_at_ms')) {
      context.handle(
        _readAtMsMeta,
        readAtMs.isAcceptableOrUnknown(data['read_at_ms']!, _readAtMsMeta),
      );
    }
    if (data.containsKey('is_favorite')) {
      context.handle(
        _isFavoriteMeta,
        isFavorite.isAcceptableOrUnknown(data['is_favorite']!, _isFavoriteMeta),
      );
    } else if (isInserting) {
      context.missing(_isFavoriteMeta);
    }
    if (data.containsKey('favorited_at_ms')) {
      context.handle(
        _favoritedAtMsMeta,
        favoritedAtMs.isAcceptableOrUnknown(
          data['favorited_at_ms']!,
          _favoritedAtMsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {bookId, cardIndex},
  ];
  @override
  SqliteBookCard map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SqliteBookCard(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}book_id'],
      )!,
      bookTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_title'],
      )!,
      cardIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}card_index'],
      )!,
      chapterIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}chapter_index'],
      )!,
      chapterCardIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}chapter_card_index'],
      )!,
      chapterTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chapter_title'],
      ),
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      blocksJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}blocks_json'],
      ),
      isRead: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_read'],
      )!,
      readAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}read_at_ms'],
      ),
      isFavorite: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_favorite'],
      )!,
      favoritedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}favorited_at_ms'],
      ),
    );
  }

  @override
  $SqliteBookCardsTable createAlias(String alias) {
    return $SqliteBookCardsTable(attachedDatabase, alias);
  }
}

class SqliteBookCard extends DataClass implements Insertable<SqliteBookCard> {
  final int id;
  final int bookId;
  final String bookTitle;
  final int cardIndex;
  final int chapterIndex;
  final int chapterCardIndex;
  final String? chapterTitle;
  final String content;
  final String? blocksJson;
  final bool isRead;
  final int? readAtMs;
  final bool isFavorite;
  final int? favoritedAtMs;
  const SqliteBookCard({
    required this.id,
    required this.bookId,
    required this.bookTitle,
    required this.cardIndex,
    required this.chapterIndex,
    required this.chapterCardIndex,
    this.chapterTitle,
    required this.content,
    this.blocksJson,
    required this.isRead,
    this.readAtMs,
    required this.isFavorite,
    this.favoritedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['book_id'] = Variable<int>(bookId);
    map['book_title'] = Variable<String>(bookTitle);
    map['card_index'] = Variable<int>(cardIndex);
    map['chapter_index'] = Variable<int>(chapterIndex);
    map['chapter_card_index'] = Variable<int>(chapterCardIndex);
    if (!nullToAbsent || chapterTitle != null) {
      map['chapter_title'] = Variable<String>(chapterTitle);
    }
    map['content'] = Variable<String>(content);
    if (!nullToAbsent || blocksJson != null) {
      map['blocks_json'] = Variable<String>(blocksJson);
    }
    map['is_read'] = Variable<bool>(isRead);
    if (!nullToAbsent || readAtMs != null) {
      map['read_at_ms'] = Variable<int>(readAtMs);
    }
    map['is_favorite'] = Variable<bool>(isFavorite);
    if (!nullToAbsent || favoritedAtMs != null) {
      map['favorited_at_ms'] = Variable<int>(favoritedAtMs);
    }
    return map;
  }

  SqliteBookCardsCompanion toCompanion(bool nullToAbsent) {
    return SqliteBookCardsCompanion(
      id: Value(id),
      bookId: Value(bookId),
      bookTitle: Value(bookTitle),
      cardIndex: Value(cardIndex),
      chapterIndex: Value(chapterIndex),
      chapterCardIndex: Value(chapterCardIndex),
      chapterTitle: chapterTitle == null && nullToAbsent
          ? const Value.absent()
          : Value(chapterTitle),
      content: Value(content),
      blocksJson: blocksJson == null && nullToAbsent
          ? const Value.absent()
          : Value(blocksJson),
      isRead: Value(isRead),
      readAtMs: readAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(readAtMs),
      isFavorite: Value(isFavorite),
      favoritedAtMs: favoritedAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(favoritedAtMs),
    );
  }

  factory SqliteBookCard.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SqliteBookCard(
      id: serializer.fromJson<int>(json['id']),
      bookId: serializer.fromJson<int>(json['bookId']),
      bookTitle: serializer.fromJson<String>(json['bookTitle']),
      cardIndex: serializer.fromJson<int>(json['cardIndex']),
      chapterIndex: serializer.fromJson<int>(json['chapterIndex']),
      chapterCardIndex: serializer.fromJson<int>(json['chapterCardIndex']),
      chapterTitle: serializer.fromJson<String?>(json['chapterTitle']),
      content: serializer.fromJson<String>(json['content']),
      blocksJson: serializer.fromJson<String?>(json['blocksJson']),
      isRead: serializer.fromJson<bool>(json['isRead']),
      readAtMs: serializer.fromJson<int?>(json['readAtMs']),
      isFavorite: serializer.fromJson<bool>(json['isFavorite']),
      favoritedAtMs: serializer.fromJson<int?>(json['favoritedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'bookId': serializer.toJson<int>(bookId),
      'bookTitle': serializer.toJson<String>(bookTitle),
      'cardIndex': serializer.toJson<int>(cardIndex),
      'chapterIndex': serializer.toJson<int>(chapterIndex),
      'chapterCardIndex': serializer.toJson<int>(chapterCardIndex),
      'chapterTitle': serializer.toJson<String?>(chapterTitle),
      'content': serializer.toJson<String>(content),
      'blocksJson': serializer.toJson<String?>(blocksJson),
      'isRead': serializer.toJson<bool>(isRead),
      'readAtMs': serializer.toJson<int?>(readAtMs),
      'isFavorite': serializer.toJson<bool>(isFavorite),
      'favoritedAtMs': serializer.toJson<int?>(favoritedAtMs),
    };
  }

  SqliteBookCard copyWith({
    int? id,
    int? bookId,
    String? bookTitle,
    int? cardIndex,
    int? chapterIndex,
    int? chapterCardIndex,
    Value<String?> chapterTitle = const Value.absent(),
    String? content,
    Value<String?> blocksJson = const Value.absent(),
    bool? isRead,
    Value<int?> readAtMs = const Value.absent(),
    bool? isFavorite,
    Value<int?> favoritedAtMs = const Value.absent(),
  }) => SqliteBookCard(
    id: id ?? this.id,
    bookId: bookId ?? this.bookId,
    bookTitle: bookTitle ?? this.bookTitle,
    cardIndex: cardIndex ?? this.cardIndex,
    chapterIndex: chapterIndex ?? this.chapterIndex,
    chapterCardIndex: chapterCardIndex ?? this.chapterCardIndex,
    chapterTitle: chapterTitle.present ? chapterTitle.value : this.chapterTitle,
    content: content ?? this.content,
    blocksJson: blocksJson.present ? blocksJson.value : this.blocksJson,
    isRead: isRead ?? this.isRead,
    readAtMs: readAtMs.present ? readAtMs.value : this.readAtMs,
    isFavorite: isFavorite ?? this.isFavorite,
    favoritedAtMs: favoritedAtMs.present
        ? favoritedAtMs.value
        : this.favoritedAtMs,
  );
  @override
  String toString() {
    return (StringBuffer('SqliteBookCard(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('bookTitle: $bookTitle, ')
          ..write('cardIndex: $cardIndex, ')
          ..write('chapterIndex: $chapterIndex, ')
          ..write('chapterCardIndex: $chapterCardIndex, ')
          ..write('chapterTitle: $chapterTitle, ')
          ..write('content: $content, ')
          ..write('blocksJson: $blocksJson, ')
          ..write('isRead: $isRead, ')
          ..write('readAtMs: $readAtMs, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('favoritedAtMs: $favoritedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    bookId,
    bookTitle,
    cardIndex,
    chapterIndex,
    chapterCardIndex,
    chapterTitle,
    content,
    blocksJson,
    isRead,
    readAtMs,
    isFavorite,
    favoritedAtMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SqliteBookCard &&
          other.id == this.id &&
          other.bookId == this.bookId &&
          other.bookTitle == this.bookTitle &&
          other.cardIndex == this.cardIndex &&
          other.chapterIndex == this.chapterIndex &&
          other.chapterCardIndex == this.chapterCardIndex &&
          other.chapterTitle == this.chapterTitle &&
          other.content == this.content &&
          other.blocksJson == this.blocksJson &&
          other.isRead == this.isRead &&
          other.readAtMs == this.readAtMs &&
          other.isFavorite == this.isFavorite &&
          other.favoritedAtMs == this.favoritedAtMs);
}

class SqliteBookCardsCompanion extends UpdateCompanion<SqliteBookCard> {
  final Value<int> id;
  final Value<int> bookId;
  final Value<String> bookTitle;
  final Value<int> cardIndex;
  final Value<int> chapterIndex;
  final Value<int> chapterCardIndex;
  final Value<String?> chapterTitle;
  final Value<String> content;
  final Value<String?> blocksJson;
  final Value<bool> isRead;
  final Value<int?> readAtMs;
  final Value<bool> isFavorite;
  final Value<int?> favoritedAtMs;
  const SqliteBookCardsCompanion({
    this.id = const Value.absent(),
    this.bookId = const Value.absent(),
    this.bookTitle = const Value.absent(),
    this.cardIndex = const Value.absent(),
    this.chapterIndex = const Value.absent(),
    this.chapterCardIndex = const Value.absent(),
    this.chapterTitle = const Value.absent(),
    this.content = const Value.absent(),
    this.blocksJson = const Value.absent(),
    this.isRead = const Value.absent(),
    this.readAtMs = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.favoritedAtMs = const Value.absent(),
  });
  SqliteBookCardsCompanion.insert({
    this.id = const Value.absent(),
    required int bookId,
    required String bookTitle,
    required int cardIndex,
    required int chapterIndex,
    required int chapterCardIndex,
    this.chapterTitle = const Value.absent(),
    required String content,
    this.blocksJson = const Value.absent(),
    required bool isRead,
    this.readAtMs = const Value.absent(),
    required bool isFavorite,
    this.favoritedAtMs = const Value.absent(),
  }) : bookId = Value(bookId),
       bookTitle = Value(bookTitle),
       cardIndex = Value(cardIndex),
       chapterIndex = Value(chapterIndex),
       chapterCardIndex = Value(chapterCardIndex),
       content = Value(content),
       isRead = Value(isRead),
       isFavorite = Value(isFavorite);
  static Insertable<SqliteBookCard> custom({
    Expression<int>? id,
    Expression<int>? bookId,
    Expression<String>? bookTitle,
    Expression<int>? cardIndex,
    Expression<int>? chapterIndex,
    Expression<int>? chapterCardIndex,
    Expression<String>? chapterTitle,
    Expression<String>? content,
    Expression<String>? blocksJson,
    Expression<bool>? isRead,
    Expression<int>? readAtMs,
    Expression<bool>? isFavorite,
    Expression<int>? favoritedAtMs,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (bookId != null) 'book_id': bookId,
      if (bookTitle != null) 'book_title': bookTitle,
      if (cardIndex != null) 'card_index': cardIndex,
      if (chapterIndex != null) 'chapter_index': chapterIndex,
      if (chapterCardIndex != null) 'chapter_card_index': chapterCardIndex,
      if (chapterTitle != null) 'chapter_title': chapterTitle,
      if (content != null) 'content': content,
      if (blocksJson != null) 'blocks_json': blocksJson,
      if (isRead != null) 'is_read': isRead,
      if (readAtMs != null) 'read_at_ms': readAtMs,
      if (isFavorite != null) 'is_favorite': isFavorite,
      if (favoritedAtMs != null) 'favorited_at_ms': favoritedAtMs,
    });
  }

  SqliteBookCardsCompanion copyWith({
    Value<int>? id,
    Value<int>? bookId,
    Value<String>? bookTitle,
    Value<int>? cardIndex,
    Value<int>? chapterIndex,
    Value<int>? chapterCardIndex,
    Value<String?>? chapterTitle,
    Value<String>? content,
    Value<String?>? blocksJson,
    Value<bool>? isRead,
    Value<int?>? readAtMs,
    Value<bool>? isFavorite,
    Value<int?>? favoritedAtMs,
  }) {
    return SqliteBookCardsCompanion(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      bookTitle: bookTitle ?? this.bookTitle,
      cardIndex: cardIndex ?? this.cardIndex,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      chapterCardIndex: chapterCardIndex ?? this.chapterCardIndex,
      chapterTitle: chapterTitle ?? this.chapterTitle,
      content: content ?? this.content,
      blocksJson: blocksJson ?? this.blocksJson,
      isRead: isRead ?? this.isRead,
      readAtMs: readAtMs ?? this.readAtMs,
      isFavorite: isFavorite ?? this.isFavorite,
      favoritedAtMs: favoritedAtMs ?? this.favoritedAtMs,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (bookId.present) {
      map['book_id'] = Variable<int>(bookId.value);
    }
    if (bookTitle.present) {
      map['book_title'] = Variable<String>(bookTitle.value);
    }
    if (cardIndex.present) {
      map['card_index'] = Variable<int>(cardIndex.value);
    }
    if (chapterIndex.present) {
      map['chapter_index'] = Variable<int>(chapterIndex.value);
    }
    if (chapterCardIndex.present) {
      map['chapter_card_index'] = Variable<int>(chapterCardIndex.value);
    }
    if (chapterTitle.present) {
      map['chapter_title'] = Variable<String>(chapterTitle.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (blocksJson.present) {
      map['blocks_json'] = Variable<String>(blocksJson.value);
    }
    if (isRead.present) {
      map['is_read'] = Variable<bool>(isRead.value);
    }
    if (readAtMs.present) {
      map['read_at_ms'] = Variable<int>(readAtMs.value);
    }
    if (isFavorite.present) {
      map['is_favorite'] = Variable<bool>(isFavorite.value);
    }
    if (favoritedAtMs.present) {
      map['favorited_at_ms'] = Variable<int>(favoritedAtMs.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SqliteBookCardsCompanion(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('bookTitle: $bookTitle, ')
          ..write('cardIndex: $cardIndex, ')
          ..write('chapterIndex: $chapterIndex, ')
          ..write('chapterCardIndex: $chapterCardIndex, ')
          ..write('chapterTitle: $chapterTitle, ')
          ..write('content: $content, ')
          ..write('blocksJson: $blocksJson, ')
          ..write('isRead: $isRead, ')
          ..write('readAtMs: $readAtMs, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('favoritedAtMs: $favoritedAtMs')
          ..write(')'))
        .toString();
  }
}

class $SqliteBookAssetsTable extends SqliteBookAssets
    with TableInfo<$SqliteBookAssetsTable, SqliteBookAsset> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SqliteBookAssetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<int> bookId = GeneratedColumn<int>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL REFERENCES books(id) ON DELETE CASCADE CHECK(book_id > 0)',
  );
  static const VerificationMeta _assetKeyMeta = const VerificationMeta(
    'assetKey',
  );
  @override
  late final GeneratedColumn<String> assetKey = GeneratedColumn<String>(
    'asset_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _originalHrefMeta = const VerificationMeta(
    'originalHref',
  );
  @override
  late final GeneratedColumn<String> originalHref = GeneratedColumn<String>(
    'original_href',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _normalizedHrefMeta = const VerificationMeta(
    'normalizedHref',
  );
  @override
  late final GeneratedColumn<String> normalizedHref = GeneratedColumn<String>(
    'normalized_href',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mimeTypeMeta = const VerificationMeta(
    'mimeType',
  );
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
    'mime_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _relativePathMeta = const VerificationMeta(
    'relativePath',
  );
  @override
  late final GeneratedColumn<String> relativePath = GeneratedColumn<String>(
    'relative_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _byteLengthMeta = const VerificationMeta(
    'byteLength',
  );
  @override
  late final GeneratedColumn<int> byteLength = GeneratedColumn<int>(
    'byte_length',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMsMeta = const VerificationMeta(
    'createdAtMs',
  );
  @override
  late final GeneratedColumn<int> createdAtMs = GeneratedColumn<int>(
    'created_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    bookId,
    assetKey,
    originalHref,
    normalizedHref,
    mimeType,
    relativePath,
    byteLength,
    createdAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'book_assets';
  @override
  VerificationContext validateIntegrity(
    Insertable<SqliteBookAsset> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('asset_key')) {
      context.handle(
        _assetKeyMeta,
        assetKey.isAcceptableOrUnknown(data['asset_key']!, _assetKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_assetKeyMeta);
    }
    if (data.containsKey('original_href')) {
      context.handle(
        _originalHrefMeta,
        originalHref.isAcceptableOrUnknown(
          data['original_href']!,
          _originalHrefMeta,
        ),
      );
    }
    if (data.containsKey('normalized_href')) {
      context.handle(
        _normalizedHrefMeta,
        normalizedHref.isAcceptableOrUnknown(
          data['normalized_href']!,
          _normalizedHrefMeta,
        ),
      );
    }
    if (data.containsKey('mime_type')) {
      context.handle(
        _mimeTypeMeta,
        mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta),
      );
    }
    if (data.containsKey('relative_path')) {
      context.handle(
        _relativePathMeta,
        relativePath.isAcceptableOrUnknown(
          data['relative_path']!,
          _relativePathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_relativePathMeta);
    }
    if (data.containsKey('byte_length')) {
      context.handle(
        _byteLengthMeta,
        byteLength.isAcceptableOrUnknown(data['byte_length']!, _byteLengthMeta),
      );
    }
    if (data.containsKey('created_at_ms')) {
      context.handle(
        _createdAtMsMeta,
        createdAtMs.isAcceptableOrUnknown(
          data['created_at_ms']!,
          _createdAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SqliteBookAsset map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SqliteBookAsset(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}book_id'],
      )!,
      assetKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}asset_key'],
      )!,
      originalHref: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}original_href'],
      ),
      normalizedHref: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}normalized_href'],
      ),
      mimeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime_type'],
      ),
      relativePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}relative_path'],
      )!,
      byteLength: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}byte_length'],
      ),
      createdAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_ms'],
      )!,
    );
  }

  @override
  $SqliteBookAssetsTable createAlias(String alias) {
    return $SqliteBookAssetsTable(attachedDatabase, alias);
  }
}

class SqliteBookAsset extends DataClass implements Insertable<SqliteBookAsset> {
  final int id;
  final int bookId;
  final String assetKey;
  final String? originalHref;
  final String? normalizedHref;
  final String? mimeType;
  final String relativePath;
  final int? byteLength;
  final int createdAtMs;
  const SqliteBookAsset({
    required this.id,
    required this.bookId,
    required this.assetKey,
    this.originalHref,
    this.normalizedHref,
    this.mimeType,
    required this.relativePath,
    this.byteLength,
    required this.createdAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['book_id'] = Variable<int>(bookId);
    map['asset_key'] = Variable<String>(assetKey);
    if (!nullToAbsent || originalHref != null) {
      map['original_href'] = Variable<String>(originalHref);
    }
    if (!nullToAbsent || normalizedHref != null) {
      map['normalized_href'] = Variable<String>(normalizedHref);
    }
    if (!nullToAbsent || mimeType != null) {
      map['mime_type'] = Variable<String>(mimeType);
    }
    map['relative_path'] = Variable<String>(relativePath);
    if (!nullToAbsent || byteLength != null) {
      map['byte_length'] = Variable<int>(byteLength);
    }
    map['created_at_ms'] = Variable<int>(createdAtMs);
    return map;
  }

  SqliteBookAssetsCompanion toCompanion(bool nullToAbsent) {
    return SqliteBookAssetsCompanion(
      id: Value(id),
      bookId: Value(bookId),
      assetKey: Value(assetKey),
      originalHref: originalHref == null && nullToAbsent
          ? const Value.absent()
          : Value(originalHref),
      normalizedHref: normalizedHref == null && nullToAbsent
          ? const Value.absent()
          : Value(normalizedHref),
      mimeType: mimeType == null && nullToAbsent
          ? const Value.absent()
          : Value(mimeType),
      relativePath: Value(relativePath),
      byteLength: byteLength == null && nullToAbsent
          ? const Value.absent()
          : Value(byteLength),
      createdAtMs: Value(createdAtMs),
    );
  }

  factory SqliteBookAsset.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SqliteBookAsset(
      id: serializer.fromJson<int>(json['id']),
      bookId: serializer.fromJson<int>(json['bookId']),
      assetKey: serializer.fromJson<String>(json['assetKey']),
      originalHref: serializer.fromJson<String?>(json['originalHref']),
      normalizedHref: serializer.fromJson<String?>(json['normalizedHref']),
      mimeType: serializer.fromJson<String?>(json['mimeType']),
      relativePath: serializer.fromJson<String>(json['relativePath']),
      byteLength: serializer.fromJson<int?>(json['byteLength']),
      createdAtMs: serializer.fromJson<int>(json['createdAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'bookId': serializer.toJson<int>(bookId),
      'assetKey': serializer.toJson<String>(assetKey),
      'originalHref': serializer.toJson<String?>(originalHref),
      'normalizedHref': serializer.toJson<String?>(normalizedHref),
      'mimeType': serializer.toJson<String?>(mimeType),
      'relativePath': serializer.toJson<String>(relativePath),
      'byteLength': serializer.toJson<int?>(byteLength),
      'createdAtMs': serializer.toJson<int>(createdAtMs),
    };
  }

  SqliteBookAsset copyWith({
    int? id,
    int? bookId,
    String? assetKey,
    Value<String?> originalHref = const Value.absent(),
    Value<String?> normalizedHref = const Value.absent(),
    Value<String?> mimeType = const Value.absent(),
    String? relativePath,
    Value<int?> byteLength = const Value.absent(),
    int? createdAtMs,
  }) => SqliteBookAsset(
    id: id ?? this.id,
    bookId: bookId ?? this.bookId,
    assetKey: assetKey ?? this.assetKey,
    originalHref: originalHref.present ? originalHref.value : this.originalHref,
    normalizedHref: normalizedHref.present
        ? normalizedHref.value
        : this.normalizedHref,
    mimeType: mimeType.present ? mimeType.value : this.mimeType,
    relativePath: relativePath ?? this.relativePath,
    byteLength: byteLength.present ? byteLength.value : this.byteLength,
    createdAtMs: createdAtMs ?? this.createdAtMs,
  );
  @override
  String toString() {
    return (StringBuffer('SqliteBookAsset(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('assetKey: $assetKey, ')
          ..write('originalHref: $originalHref, ')
          ..write('normalizedHref: $normalizedHref, ')
          ..write('mimeType: $mimeType, ')
          ..write('relativePath: $relativePath, ')
          ..write('byteLength: $byteLength, ')
          ..write('createdAtMs: $createdAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    bookId,
    assetKey,
    originalHref,
    normalizedHref,
    mimeType,
    relativePath,
    byteLength,
    createdAtMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SqliteBookAsset &&
          other.id == this.id &&
          other.bookId == this.bookId &&
          other.assetKey == this.assetKey &&
          other.originalHref == this.originalHref &&
          other.normalizedHref == this.normalizedHref &&
          other.mimeType == this.mimeType &&
          other.relativePath == this.relativePath &&
          other.byteLength == this.byteLength &&
          other.createdAtMs == this.createdAtMs);
}

class SqliteBookAssetsCompanion extends UpdateCompanion<SqliteBookAsset> {
  final Value<int> id;
  final Value<int> bookId;
  final Value<String> assetKey;
  final Value<String?> originalHref;
  final Value<String?> normalizedHref;
  final Value<String?> mimeType;
  final Value<String> relativePath;
  final Value<int?> byteLength;
  final Value<int> createdAtMs;
  const SqliteBookAssetsCompanion({
    this.id = const Value.absent(),
    this.bookId = const Value.absent(),
    this.assetKey = const Value.absent(),
    this.originalHref = const Value.absent(),
    this.normalizedHref = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.relativePath = const Value.absent(),
    this.byteLength = const Value.absent(),
    this.createdAtMs = const Value.absent(),
  });
  SqliteBookAssetsCompanion.insert({
    this.id = const Value.absent(),
    required int bookId,
    required String assetKey,
    this.originalHref = const Value.absent(),
    this.normalizedHref = const Value.absent(),
    this.mimeType = const Value.absent(),
    required String relativePath,
    this.byteLength = const Value.absent(),
    required int createdAtMs,
  }) : bookId = Value(bookId),
       assetKey = Value(assetKey),
       relativePath = Value(relativePath),
       createdAtMs = Value(createdAtMs);
  static Insertable<SqliteBookAsset> custom({
    Expression<int>? id,
    Expression<int>? bookId,
    Expression<String>? assetKey,
    Expression<String>? originalHref,
    Expression<String>? normalizedHref,
    Expression<String>? mimeType,
    Expression<String>? relativePath,
    Expression<int>? byteLength,
    Expression<int>? createdAtMs,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (bookId != null) 'book_id': bookId,
      if (assetKey != null) 'asset_key': assetKey,
      if (originalHref != null) 'original_href': originalHref,
      if (normalizedHref != null) 'normalized_href': normalizedHref,
      if (mimeType != null) 'mime_type': mimeType,
      if (relativePath != null) 'relative_path': relativePath,
      if (byteLength != null) 'byte_length': byteLength,
      if (createdAtMs != null) 'created_at_ms': createdAtMs,
    });
  }

  SqliteBookAssetsCompanion copyWith({
    Value<int>? id,
    Value<int>? bookId,
    Value<String>? assetKey,
    Value<String?>? originalHref,
    Value<String?>? normalizedHref,
    Value<String?>? mimeType,
    Value<String>? relativePath,
    Value<int?>? byteLength,
    Value<int>? createdAtMs,
  }) {
    return SqliteBookAssetsCompanion(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      assetKey: assetKey ?? this.assetKey,
      originalHref: originalHref ?? this.originalHref,
      normalizedHref: normalizedHref ?? this.normalizedHref,
      mimeType: mimeType ?? this.mimeType,
      relativePath: relativePath ?? this.relativePath,
      byteLength: byteLength ?? this.byteLength,
      createdAtMs: createdAtMs ?? this.createdAtMs,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (bookId.present) {
      map['book_id'] = Variable<int>(bookId.value);
    }
    if (assetKey.present) {
      map['asset_key'] = Variable<String>(assetKey.value);
    }
    if (originalHref.present) {
      map['original_href'] = Variable<String>(originalHref.value);
    }
    if (normalizedHref.present) {
      map['normalized_href'] = Variable<String>(normalizedHref.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (relativePath.present) {
      map['relative_path'] = Variable<String>(relativePath.value);
    }
    if (byteLength.present) {
      map['byte_length'] = Variable<int>(byteLength.value);
    }
    if (createdAtMs.present) {
      map['created_at_ms'] = Variable<int>(createdAtMs.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SqliteBookAssetsCompanion(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('assetKey: $assetKey, ')
          ..write('originalHref: $originalHref, ')
          ..write('normalizedHref: $normalizedHref, ')
          ..write('mimeType: $mimeType, ')
          ..write('relativePath: $relativePath, ')
          ..write('byteLength: $byteLength, ')
          ..write('createdAtMs: $createdAtMs')
          ..write(')'))
        .toString();
  }
}

class $SqliteBookRemarksTable extends SqliteBookRemarks
    with TableInfo<$SqliteBookRemarksTable, SqliteBookRemark> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SqliteBookRemarksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<int> bookId = GeneratedColumn<int>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints:
        'NOT NULL REFERENCES books(id) ON DELETE CASCADE CHECK(book_id > 0)',
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [bookId, title, updatedAtMs];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'book_remarks';
  @override
  VerificationContext validateIntegrity(
    Insertable<SqliteBookRemark> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {bookId};
  @override
  SqliteBookRemark map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SqliteBookRemark(
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}book_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
    );
  }

  @override
  $SqliteBookRemarksTable createAlias(String alias) {
    return $SqliteBookRemarksTable(attachedDatabase, alias);
  }
}

class SqliteBookRemark extends DataClass
    implements Insertable<SqliteBookRemark> {
  final int bookId;
  final String title;
  final int updatedAtMs;
  const SqliteBookRemark({
    required this.bookId,
    required this.title,
    required this.updatedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['book_id'] = Variable<int>(bookId);
    map['title'] = Variable<String>(title);
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    return map;
  }

  SqliteBookRemarksCompanion toCompanion(bool nullToAbsent) {
    return SqliteBookRemarksCompanion(
      bookId: Value(bookId),
      title: Value(title),
      updatedAtMs: Value(updatedAtMs),
    );
  }

  factory SqliteBookRemark.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SqliteBookRemark(
      bookId: serializer.fromJson<int>(json['bookId']),
      title: serializer.fromJson<String>(json['title']),
      updatedAtMs: serializer.fromJson<int>(json['updatedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'bookId': serializer.toJson<int>(bookId),
      'title': serializer.toJson<String>(title),
      'updatedAtMs': serializer.toJson<int>(updatedAtMs),
    };
  }

  SqliteBookRemark copyWith({int? bookId, String? title, int? updatedAtMs}) =>
      SqliteBookRemark(
        bookId: bookId ?? this.bookId,
        title: title ?? this.title,
        updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      );
  @override
  String toString() {
    return (StringBuffer('SqliteBookRemark(')
          ..write('bookId: $bookId, ')
          ..write('title: $title, ')
          ..write('updatedAtMs: $updatedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(bookId, title, updatedAtMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SqliteBookRemark &&
          other.bookId == this.bookId &&
          other.title == this.title &&
          other.updatedAtMs == this.updatedAtMs);
}

class SqliteBookRemarksCompanion extends UpdateCompanion<SqliteBookRemark> {
  final Value<int> bookId;
  final Value<String> title;
  final Value<int> updatedAtMs;
  const SqliteBookRemarksCompanion({
    this.bookId = const Value.absent(),
    this.title = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
  });
  SqliteBookRemarksCompanion.insert({
    this.bookId = const Value.absent(),
    required String title,
    required int updatedAtMs,
  }) : title = Value(title),
       updatedAtMs = Value(updatedAtMs);
  static Insertable<SqliteBookRemark> custom({
    Expression<int>? bookId,
    Expression<String>? title,
    Expression<int>? updatedAtMs,
  }) {
    return RawValuesInsertable({
      if (bookId != null) 'book_id': bookId,
      if (title != null) 'title': title,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
    });
  }

  SqliteBookRemarksCompanion copyWith({
    Value<int>? bookId,
    Value<String>? title,
    Value<int>? updatedAtMs,
  }) {
    return SqliteBookRemarksCompanion(
      bookId: bookId ?? this.bookId,
      title: title ?? this.title,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (bookId.present) {
      map['book_id'] = Variable<int>(bookId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SqliteBookRemarksCompanion(')
          ..write('bookId: $bookId, ')
          ..write('title: $title, ')
          ..write('updatedAtMs: $updatedAtMs')
          ..write(')'))
        .toString();
  }
}

class $StorageMetadataTable extends StorageMetadata
    with TableInfo<$StorageMetadataTable, StorageMetadataData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StorageMetadataTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value, updatedAtMs];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'storage_metadata';
  @override
  VerificationContext validateIntegrity(
    Insertable<StorageMetadataData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  StorageMetadataData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StorageMetadataData(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
    );
  }

  @override
  $StorageMetadataTable createAlias(String alias) {
    return $StorageMetadataTable(attachedDatabase, alias);
  }
}

class StorageMetadataData extends DataClass
    implements Insertable<StorageMetadataData> {
  final String key;
  final String value;
  final int updatedAtMs;
  const StorageMetadataData({
    required this.key,
    required this.value,
    required this.updatedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    return map;
  }

  StorageMetadataCompanion toCompanion(bool nullToAbsent) {
    return StorageMetadataCompanion(
      key: Value(key),
      value: Value(value),
      updatedAtMs: Value(updatedAtMs),
    );
  }

  factory StorageMetadataData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StorageMetadataData(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      updatedAtMs: serializer.fromJson<int>(json['updatedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'updatedAtMs': serializer.toJson<int>(updatedAtMs),
    };
  }

  StorageMetadataData copyWith({
    String? key,
    String? value,
    int? updatedAtMs,
  }) => StorageMetadataData(
    key: key ?? this.key,
    value: value ?? this.value,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
  );
  @override
  String toString() {
    return (StringBuffer('StorageMetadataData(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAtMs: $updatedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value, updatedAtMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StorageMetadataData &&
          other.key == this.key &&
          other.value == this.value &&
          other.updatedAtMs == this.updatedAtMs);
}

class StorageMetadataCompanion extends UpdateCompanion<StorageMetadataData> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> updatedAtMs;
  final Value<int> rowid;
  const StorageMetadataCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StorageMetadataCompanion.insert({
    required String key,
    required String value,
    required int updatedAtMs,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value),
       updatedAtMs = Value(updatedAtMs);
  static Insertable<StorageMetadataData> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? updatedAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StorageMetadataCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? updatedAtMs,
    Value<int>? rowid,
  }) {
    return StorageMetadataCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StorageMetadataCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$LibraryDatabase extends GeneratedDatabase {
  _$LibraryDatabase(QueryExecutor e) : super(e);
  late final $SqliteBooksTable sqliteBooks = $SqliteBooksTable(this);
  late final $SqliteBookCardsTable sqliteBookCards = $SqliteBookCardsTable(
    this,
  );
  late final $SqliteBookAssetsTable sqliteBookAssets = $SqliteBookAssetsTable(
    this,
  );
  late final $SqliteBookRemarksTable sqliteBookRemarks =
      $SqliteBookRemarksTable(this);
  late final $StorageMetadataTable storageMetadata = $StorageMetadataTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    sqliteBooks,
    sqliteBookCards,
    sqliteBookAssets,
    sqliteBookRemarks,
    storageMetadata,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'books',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('book_cards', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'books',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('book_assets', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'books',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('book_remarks', kind: UpdateKind.delete)],
    ),
  ]);
}
