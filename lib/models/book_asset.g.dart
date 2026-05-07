// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'book_asset.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetBookAssetCollection on Isar {
  IsarCollection<BookAsset> get bookAssets => this.collection();
}

const BookAssetSchema = CollectionSchema(
  name: r'BookAsset',
  id: 4360494551680147439,
  properties: {
    r'assetKey': PropertySchema(
      id: 0,
      name: r'assetKey',
      type: IsarType.string,
    ),
    r'bookId': PropertySchema(id: 1, name: r'bookId', type: IsarType.long),
    r'byteLength': PropertySchema(
      id: 2,
      name: r'byteLength',
      type: IsarType.long,
    ),
    r'createdAt': PropertySchema(
      id: 3,
      name: r'createdAt',
      type: IsarType.dateTime,
    ),
    r'mimeType': PropertySchema(
      id: 4,
      name: r'mimeType',
      type: IsarType.string,
    ),
    r'normalizedHref': PropertySchema(
      id: 5,
      name: r'normalizedHref',
      type: IsarType.string,
    ),
    r'originalHref': PropertySchema(
      id: 6,
      name: r'originalHref',
      type: IsarType.string,
    ),
    r'relativePath': PropertySchema(
      id: 7,
      name: r'relativePath',
      type: IsarType.string,
    ),
  },
  estimateSize: _bookAssetEstimateSize,
  serialize: _bookAssetSerialize,
  deserialize: _bookAssetDeserialize,
  deserializeProp: _bookAssetDeserializeProp,
  idName: r'id',
  indexes: {
    r'bookId': IndexSchema(
      id: 3567540928881766442,
      name: r'bookId',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'bookId',
          type: IndexType.value,
          caseSensitive: false,
        ),
      ],
    ),
    r'assetKey': IndexSchema(
      id: -4226561376857100125,
      name: r'assetKey',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'assetKey',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
    r'normalizedHref': IndexSchema(
      id: -3345513885909986565,
      name: r'normalizedHref',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'normalizedHref',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
  },
  links: {},
  embeddedSchemas: {},
  getId: _bookAssetGetId,
  getLinks: _bookAssetGetLinks,
  attach: _bookAssetAttach,
  version: '3.1.0+1',
);

int _bookAssetEstimateSize(
  BookAsset object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.assetKey.length * 3;
  {
    final value = object.mimeType;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.normalizedHref;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.originalHref;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.relativePath.length * 3;
  return bytesCount;
}

void _bookAssetSerialize(
  BookAsset object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.assetKey);
  writer.writeLong(offsets[1], object.bookId);
  writer.writeLong(offsets[2], object.byteLength);
  writer.writeDateTime(offsets[3], object.createdAt);
  writer.writeString(offsets[4], object.mimeType);
  writer.writeString(offsets[5], object.normalizedHref);
  writer.writeString(offsets[6], object.originalHref);
  writer.writeString(offsets[7], object.relativePath);
}

BookAsset _bookAssetDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = BookAsset();
  object.assetKey = reader.readString(offsets[0]);
  object.bookId = reader.readLong(offsets[1]);
  object.byteLength = reader.readLongOrNull(offsets[2]);
  object.createdAt = reader.readDateTime(offsets[3]);
  object.id = id;
  object.mimeType = reader.readStringOrNull(offsets[4]);
  object.normalizedHref = reader.readStringOrNull(offsets[5]);
  object.originalHref = reader.readStringOrNull(offsets[6]);
  object.relativePath = reader.readString(offsets[7]);
  return object;
}

P _bookAssetDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readString(offset)) as P;
    case 1:
      return (reader.readLong(offset)) as P;
    case 2:
      return (reader.readLongOrNull(offset)) as P;
    case 3:
      return (reader.readDateTime(offset)) as P;
    case 4:
      return (reader.readStringOrNull(offset)) as P;
    case 5:
      return (reader.readStringOrNull(offset)) as P;
    case 6:
      return (reader.readStringOrNull(offset)) as P;
    case 7:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _bookAssetGetId(BookAsset object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _bookAssetGetLinks(BookAsset object) {
  return [];
}

void _bookAssetAttach(IsarCollection<dynamic> col, Id id, BookAsset object) {
  object.id = id;
}

extension BookAssetQueryWhereSort
    on QueryBuilder<BookAsset, BookAsset, QWhere> {
  QueryBuilder<BookAsset, BookAsset, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterWhere> anyBookId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'bookId'),
      );
    });
  }
}

extension BookAssetQueryWhere
    on QueryBuilder<BookAsset, BookAsset, QWhereClause> {
  QueryBuilder<BookAsset, BookAsset, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterWhereClause> idNotEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterWhereClause> idGreaterThan(
    Id id, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterWhereClause> idLessThan(
    Id id, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.between(
          lower: lowerId,
          includeLower: includeLower,
          upper: upperId,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterWhereClause> bookIdEqualTo(
    int bookId,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'bookId', value: [bookId]),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterWhereClause> bookIdNotEqualTo(
    int bookId,
  ) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'bookId',
                lower: [],
                upper: [bookId],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'bookId',
                lower: [bookId],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'bookId',
                lower: [bookId],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'bookId',
                lower: [],
                upper: [bookId],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterWhereClause> bookIdGreaterThan(
    int bookId, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'bookId',
          lower: [bookId],
          includeLower: include,
          upper: [],
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterWhereClause> bookIdLessThan(
    int bookId, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'bookId',
          lower: [],
          upper: [bookId],
          includeUpper: include,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterWhereClause> bookIdBetween(
    int lowerBookId,
    int upperBookId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'bookId',
          lower: [lowerBookId],
          includeLower: includeLower,
          upper: [upperBookId],
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterWhereClause> assetKeyEqualTo(
    String assetKey,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'assetKey', value: [assetKey]),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterWhereClause> assetKeyNotEqualTo(
    String assetKey,
  ) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'assetKey',
                lower: [],
                upper: [assetKey],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'assetKey',
                lower: [assetKey],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'assetKey',
                lower: [assetKey],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'assetKey',
                lower: [],
                upper: [assetKey],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterWhereClause> normalizedHrefIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'normalizedHref', value: [null]),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterWhereClause>
  normalizedHrefIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'normalizedHref',
          lower: [null],
          includeLower: false,
          upper: [],
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterWhereClause> normalizedHrefEqualTo(
    String? normalizedHref,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(
          indexName: r'normalizedHref',
          value: [normalizedHref],
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterWhereClause>
  normalizedHrefNotEqualTo(String? normalizedHref) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'normalizedHref',
                lower: [],
                upper: [normalizedHref],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'normalizedHref',
                lower: [normalizedHref],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'normalizedHref',
                lower: [normalizedHref],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'normalizedHref',
                lower: [],
                upper: [normalizedHref],
                includeUpper: false,
              ),
            );
      }
    });
  }
}

extension BookAssetQueryFilter
    on QueryBuilder<BookAsset, BookAsset, QFilterCondition> {
  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition> assetKeyEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'assetKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition> assetKeyGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'assetKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition> assetKeyLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'assetKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition> assetKeyBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'assetKey',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition> assetKeyStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'assetKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition> assetKeyEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'assetKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition> assetKeyContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'assetKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition> assetKeyMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'assetKey',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition> assetKeyIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'assetKey', value: ''),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition>
  assetKeyIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'assetKey', value: ''),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition> bookIdEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'bookId', value: value),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition> bookIdGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'bookId',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition> bookIdLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'bookId',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition> bookIdBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'bookId',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition> byteLengthIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'byteLength'),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition>
  byteLengthIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'byteLength'),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition> byteLengthEqualTo(
    int? value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'byteLength', value: value),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition>
  byteLengthGreaterThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'byteLength',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition> byteLengthLessThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'byteLength',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition> byteLengthBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'byteLength',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition> createdAtEqualTo(
    DateTime value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'createdAt', value: value),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition>
  createdAtGreaterThan(DateTime value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'createdAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition> createdAtLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'createdAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition> createdAtBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'createdAt',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition> idEqualTo(
    Id value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'id', value: value),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition> idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'id',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'id',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'id',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition> mimeTypeIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'mimeType'),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition>
  mimeTypeIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'mimeType'),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition> mimeTypeEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'mimeType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition> mimeTypeGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'mimeType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition> mimeTypeLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'mimeType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition> mimeTypeBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'mimeType',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition> mimeTypeStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'mimeType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition> mimeTypeEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'mimeType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition> mimeTypeContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'mimeType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition> mimeTypeMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'mimeType',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition> mimeTypeIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'mimeType', value: ''),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition>
  mimeTypeIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'mimeType', value: ''),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition>
  normalizedHrefIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'normalizedHref'),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition>
  normalizedHrefIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'normalizedHref'),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition>
  normalizedHrefEqualTo(String? value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'normalizedHref',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition>
  normalizedHrefGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'normalizedHref',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition>
  normalizedHrefLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'normalizedHref',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition>
  normalizedHrefBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'normalizedHref',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition>
  normalizedHrefStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'normalizedHref',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition>
  normalizedHrefEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'normalizedHref',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition>
  normalizedHrefContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'normalizedHref',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition>
  normalizedHrefMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'normalizedHref',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition>
  normalizedHrefIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'normalizedHref', value: ''),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition>
  normalizedHrefIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'normalizedHref', value: ''),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition>
  originalHrefIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'originalHref'),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition>
  originalHrefIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'originalHref'),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition> originalHrefEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'originalHref',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition>
  originalHrefGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'originalHref',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition>
  originalHrefLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'originalHref',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition> originalHrefBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'originalHref',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition>
  originalHrefStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'originalHref',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition>
  originalHrefEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'originalHref',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition>
  originalHrefContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'originalHref',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition> originalHrefMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'originalHref',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition>
  originalHrefIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'originalHref', value: ''),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition>
  originalHrefIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'originalHref', value: ''),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition> relativePathEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'relativePath',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition>
  relativePathGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'relativePath',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition>
  relativePathLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'relativePath',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition> relativePathBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'relativePath',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition>
  relativePathStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'relativePath',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition>
  relativePathEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'relativePath',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition>
  relativePathContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'relativePath',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition> relativePathMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'relativePath',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition>
  relativePathIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'relativePath', value: ''),
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterFilterCondition>
  relativePathIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'relativePath', value: ''),
      );
    });
  }
}

extension BookAssetQueryObject
    on QueryBuilder<BookAsset, BookAsset, QFilterCondition> {}

extension BookAssetQueryLinks
    on QueryBuilder<BookAsset, BookAsset, QFilterCondition> {}

extension BookAssetQuerySortBy on QueryBuilder<BookAsset, BookAsset, QSortBy> {
  QueryBuilder<BookAsset, BookAsset, QAfterSortBy> sortByAssetKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'assetKey', Sort.asc);
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterSortBy> sortByAssetKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'assetKey', Sort.desc);
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterSortBy> sortByBookId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'bookId', Sort.asc);
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterSortBy> sortByBookIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'bookId', Sort.desc);
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterSortBy> sortByByteLength() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'byteLength', Sort.asc);
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterSortBy> sortByByteLengthDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'byteLength', Sort.desc);
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterSortBy> sortByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterSortBy> sortByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterSortBy> sortByMimeType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mimeType', Sort.asc);
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterSortBy> sortByMimeTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mimeType', Sort.desc);
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterSortBy> sortByNormalizedHref() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'normalizedHref', Sort.asc);
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterSortBy> sortByNormalizedHrefDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'normalizedHref', Sort.desc);
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterSortBy> sortByOriginalHref() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'originalHref', Sort.asc);
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterSortBy> sortByOriginalHrefDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'originalHref', Sort.desc);
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterSortBy> sortByRelativePath() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'relativePath', Sort.asc);
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterSortBy> sortByRelativePathDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'relativePath', Sort.desc);
    });
  }
}

extension BookAssetQuerySortThenBy
    on QueryBuilder<BookAsset, BookAsset, QSortThenBy> {
  QueryBuilder<BookAsset, BookAsset, QAfterSortBy> thenByAssetKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'assetKey', Sort.asc);
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterSortBy> thenByAssetKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'assetKey', Sort.desc);
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterSortBy> thenByBookId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'bookId', Sort.asc);
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterSortBy> thenByBookIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'bookId', Sort.desc);
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterSortBy> thenByByteLength() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'byteLength', Sort.asc);
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterSortBy> thenByByteLengthDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'byteLength', Sort.desc);
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterSortBy> thenByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterSortBy> thenByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterSortBy> thenByMimeType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mimeType', Sort.asc);
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterSortBy> thenByMimeTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mimeType', Sort.desc);
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterSortBy> thenByNormalizedHref() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'normalizedHref', Sort.asc);
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterSortBy> thenByNormalizedHrefDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'normalizedHref', Sort.desc);
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterSortBy> thenByOriginalHref() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'originalHref', Sort.asc);
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterSortBy> thenByOriginalHrefDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'originalHref', Sort.desc);
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterSortBy> thenByRelativePath() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'relativePath', Sort.asc);
    });
  }

  QueryBuilder<BookAsset, BookAsset, QAfterSortBy> thenByRelativePathDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'relativePath', Sort.desc);
    });
  }
}

extension BookAssetQueryWhereDistinct
    on QueryBuilder<BookAsset, BookAsset, QDistinct> {
  QueryBuilder<BookAsset, BookAsset, QDistinct> distinctByAssetKey({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'assetKey', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<BookAsset, BookAsset, QDistinct> distinctByBookId() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'bookId');
    });
  }

  QueryBuilder<BookAsset, BookAsset, QDistinct> distinctByByteLength() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'byteLength');
    });
  }

  QueryBuilder<BookAsset, BookAsset, QDistinct> distinctByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'createdAt');
    });
  }

  QueryBuilder<BookAsset, BookAsset, QDistinct> distinctByMimeType({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'mimeType', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<BookAsset, BookAsset, QDistinct> distinctByNormalizedHref({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'normalizedHref',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<BookAsset, BookAsset, QDistinct> distinctByOriginalHref({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'originalHref', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<BookAsset, BookAsset, QDistinct> distinctByRelativePath({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'relativePath', caseSensitive: caseSensitive);
    });
  }
}

extension BookAssetQueryProperty
    on QueryBuilder<BookAsset, BookAsset, QQueryProperty> {
  QueryBuilder<BookAsset, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<BookAsset, String, QQueryOperations> assetKeyProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'assetKey');
    });
  }

  QueryBuilder<BookAsset, int, QQueryOperations> bookIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'bookId');
    });
  }

  QueryBuilder<BookAsset, int?, QQueryOperations> byteLengthProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'byteLength');
    });
  }

  QueryBuilder<BookAsset, DateTime, QQueryOperations> createdAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'createdAt');
    });
  }

  QueryBuilder<BookAsset, String?, QQueryOperations> mimeTypeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'mimeType');
    });
  }

  QueryBuilder<BookAsset, String?, QQueryOperations> normalizedHrefProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'normalizedHref');
    });
  }

  QueryBuilder<BookAsset, String?, QQueryOperations> originalHrefProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'originalHref');
    });
  }

  QueryBuilder<BookAsset, String, QQueryOperations> relativePathProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'relativePath');
    });
  }
}
