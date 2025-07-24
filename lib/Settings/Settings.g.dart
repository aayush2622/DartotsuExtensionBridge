// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'Settings.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetBridgeSettingsCollection on Isar {
  IsarCollection<BridgeSettings> get bridgeSettings => this.collection();
}

const BridgeSettingsSchema = CollectionSchema(
  name: r'BridgeSettings',
  id: 8010510632874811587,
  properties: {
    r'sortedAnimeExtensions': PropertySchema(
      id: 0,
      name: r'sortedAnimeExtensions',
      type: IsarType.stringList,
    ),
    r'sortedMangaExtensions': PropertySchema(
      id: 1,
      name: r'sortedMangaExtensions',
      type: IsarType.stringList,
    ),
    r'sortedNovelExtensions': PropertySchema(
      id: 2,
      name: r'sortedNovelExtensions',
      type: IsarType.stringList,
    )
  },
  estimateSize: _bridgeSettingsEstimateSize,
  serialize: _bridgeSettingsSerialize,
  deserialize: _bridgeSettingsDeserialize,
  deserializeProp: _bridgeSettingsDeserializeProp,
  idName: r'id',
  indexes: {},
  links: {},
  embeddedSchemas: {},
  getId: _bridgeSettingsGetId,
  getLinks: _bridgeSettingsGetLinks,
  attach: _bridgeSettingsAttach,
  version: '3.1.0+1',
);

int _bridgeSettingsEstimateSize(
  BridgeSettings object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.sortedAnimeExtensions.length * 3;
  {
    for (var i = 0; i < object.sortedAnimeExtensions.length; i++) {
      final value = object.sortedAnimeExtensions[i];
      bytesCount += value.length * 3;
    }
  }
  bytesCount += 3 + object.sortedMangaExtensions.length * 3;
  {
    for (var i = 0; i < object.sortedMangaExtensions.length; i++) {
      final value = object.sortedMangaExtensions[i];
      bytesCount += value.length * 3;
    }
  }
  bytesCount += 3 + object.sortedNovelExtensions.length * 3;
  {
    for (var i = 0; i < object.sortedNovelExtensions.length; i++) {
      final value = object.sortedNovelExtensions[i];
      bytesCount += value.length * 3;
    }
  }
  return bytesCount;
}

void _bridgeSettingsSerialize(
  BridgeSettings object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeStringList(offsets[0], object.sortedAnimeExtensions);
  writer.writeStringList(offsets[1], object.sortedMangaExtensions);
  writer.writeStringList(offsets[2], object.sortedNovelExtensions);
}

BridgeSettings _bridgeSettingsDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = BridgeSettings(
    sortedAnimeExtensions: reader.readStringList(offsets[0]) ?? const [],
    sortedMangaExtensions: reader.readStringList(offsets[1]) ?? const [],
    sortedNovelExtensions: reader.readStringList(offsets[2]) ?? const [],
  );
  object.id = id;
  return object;
}

P _bridgeSettingsDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readStringList(offset) ?? const []) as P;
    case 1:
      return (reader.readStringList(offset) ?? const []) as P;
    case 2:
      return (reader.readStringList(offset) ?? const []) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _bridgeSettingsGetId(BridgeSettings object) {
  return object.id ?? Isar.autoIncrement;
}

List<IsarLinkBase<dynamic>> _bridgeSettingsGetLinks(BridgeSettings object) {
  return [];
}

void _bridgeSettingsAttach(
    IsarCollection<dynamic> col, Id id, BridgeSettings object) {
  object.id = id;
}

extension BridgeSettingsQueryWhereSort
    on QueryBuilder<BridgeSettings, BridgeSettings, QWhere> {
  QueryBuilder<BridgeSettings, BridgeSettings, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension BridgeSettingsQueryWhere
    on QueryBuilder<BridgeSettings, BridgeSettings, QWhereClause> {
  QueryBuilder<BridgeSettings, BridgeSettings, QAfterWhereClause> idEqualTo(
      Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterWhereClause> idNotEqualTo(
      Id id) {
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

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterWhereClause> idGreaterThan(
      Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterWhereClause> idLessThan(
      Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension BridgeSettingsQueryFilter
    on QueryBuilder<BridgeSettings, BridgeSettings, QFilterCondition> {
  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      idIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'id',
      ));
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      idIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'id',
      ));
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition> idEqualTo(
      Id? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      idGreaterThan(
    Id? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      idLessThan(
    Id? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition> idBetween(
    Id? lower,
    Id? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedAnimeExtensionsElementEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sortedAnimeExtensions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedAnimeExtensionsElementGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'sortedAnimeExtensions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedAnimeExtensionsElementLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'sortedAnimeExtensions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedAnimeExtensionsElementBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'sortedAnimeExtensions',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedAnimeExtensionsElementStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'sortedAnimeExtensions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedAnimeExtensionsElementEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'sortedAnimeExtensions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedAnimeExtensionsElementContains(String value,
          {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'sortedAnimeExtensions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedAnimeExtensionsElementMatches(String pattern,
          {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'sortedAnimeExtensions',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedAnimeExtensionsElementIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sortedAnimeExtensions',
        value: '',
      ));
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedAnimeExtensionsElementIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'sortedAnimeExtensions',
        value: '',
      ));
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedAnimeExtensionsLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'sortedAnimeExtensions',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedAnimeExtensionsIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'sortedAnimeExtensions',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedAnimeExtensionsIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'sortedAnimeExtensions',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedAnimeExtensionsLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'sortedAnimeExtensions',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedAnimeExtensionsLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'sortedAnimeExtensions',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedAnimeExtensionsLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'sortedAnimeExtensions',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedMangaExtensionsElementEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sortedMangaExtensions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedMangaExtensionsElementGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'sortedMangaExtensions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedMangaExtensionsElementLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'sortedMangaExtensions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedMangaExtensionsElementBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'sortedMangaExtensions',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedMangaExtensionsElementStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'sortedMangaExtensions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedMangaExtensionsElementEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'sortedMangaExtensions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedMangaExtensionsElementContains(String value,
          {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'sortedMangaExtensions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedMangaExtensionsElementMatches(String pattern,
          {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'sortedMangaExtensions',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedMangaExtensionsElementIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sortedMangaExtensions',
        value: '',
      ));
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedMangaExtensionsElementIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'sortedMangaExtensions',
        value: '',
      ));
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedMangaExtensionsLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'sortedMangaExtensions',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedMangaExtensionsIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'sortedMangaExtensions',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedMangaExtensionsIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'sortedMangaExtensions',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedMangaExtensionsLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'sortedMangaExtensions',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedMangaExtensionsLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'sortedMangaExtensions',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedMangaExtensionsLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'sortedMangaExtensions',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedNovelExtensionsElementEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sortedNovelExtensions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedNovelExtensionsElementGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'sortedNovelExtensions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedNovelExtensionsElementLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'sortedNovelExtensions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedNovelExtensionsElementBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'sortedNovelExtensions',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedNovelExtensionsElementStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'sortedNovelExtensions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedNovelExtensionsElementEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'sortedNovelExtensions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedNovelExtensionsElementContains(String value,
          {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'sortedNovelExtensions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedNovelExtensionsElementMatches(String pattern,
          {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'sortedNovelExtensions',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedNovelExtensionsElementIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sortedNovelExtensions',
        value: '',
      ));
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedNovelExtensionsElementIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'sortedNovelExtensions',
        value: '',
      ));
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedNovelExtensionsLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'sortedNovelExtensions',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedNovelExtensionsIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'sortedNovelExtensions',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedNovelExtensionsIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'sortedNovelExtensions',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedNovelExtensionsLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'sortedNovelExtensions',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedNovelExtensionsLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'sortedNovelExtensions',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterFilterCondition>
      sortedNovelExtensionsLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'sortedNovelExtensions',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }
}

extension BridgeSettingsQueryObject
    on QueryBuilder<BridgeSettings, BridgeSettings, QFilterCondition> {}

extension BridgeSettingsQueryLinks
    on QueryBuilder<BridgeSettings, BridgeSettings, QFilterCondition> {}

extension BridgeSettingsQuerySortBy
    on QueryBuilder<BridgeSettings, BridgeSettings, QSortBy> {}

extension BridgeSettingsQuerySortThenBy
    on QueryBuilder<BridgeSettings, BridgeSettings, QSortThenBy> {
  QueryBuilder<BridgeSettings, BridgeSettings, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }
}

extension BridgeSettingsQueryWhereDistinct
    on QueryBuilder<BridgeSettings, BridgeSettings, QDistinct> {
  QueryBuilder<BridgeSettings, BridgeSettings, QDistinct>
      distinctBySortedAnimeExtensions() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'sortedAnimeExtensions');
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QDistinct>
      distinctBySortedMangaExtensions() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'sortedMangaExtensions');
    });
  }

  QueryBuilder<BridgeSettings, BridgeSettings, QDistinct>
      distinctBySortedNovelExtensions() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'sortedNovelExtensions');
    });
  }
}

extension BridgeSettingsQueryProperty
    on QueryBuilder<BridgeSettings, BridgeSettings, QQueryProperty> {
  QueryBuilder<BridgeSettings, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<BridgeSettings, List<String>, QQueryOperations>
      sortedAnimeExtensionsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'sortedAnimeExtensions');
    });
  }

  QueryBuilder<BridgeSettings, List<String>, QQueryOperations>
      sortedMangaExtensionsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'sortedMangaExtensions');
    });
  }

  QueryBuilder<BridgeSettings, List<String>, QQueryOperations>
      sortedNovelExtensionsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'sortedNovelExtensions');
    });
  }
}
