// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'isar_schemas.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetActiveSessionCollection on Isar {
  IsarCollection<ActiveSession> get activeSessions => this.collection();
}

const ActiveSessionSchema = CollectionSchema(
  name: r'ActiveSession',
  id: -3138477134689118396,
  properties: {
    r'courseName': PropertySchema(
      id: 0,
      name: r'courseName',
      type: IsarType.string,
    ),
    r'facultyName': PropertySchema(
      id: 1,
      name: r'facultyName',
      type: IsarType.string,
    ),
    r'rosterCount': PropertySchema(
      id: 2,
      name: r'rosterCount',
      type: IsarType.long,
    ),
    r'scheduledEndTime': PropertySchema(
      id: 3,
      name: r'scheduledEndTime',
      type: IsarType.dateTime,
    ),
    r'sectionId': PropertySchema(
      id: 4,
      name: r'sectionId',
      type: IsarType.string,
    ),
    r'sessionId': PropertySchema(
      id: 5,
      name: r'sessionId',
      type: IsarType.string,
    ),
    r'verifiedStudentIds': PropertySchema(
      id: 6,
      name: r'verifiedStudentIds',
      type: IsarType.stringList,
    )
  },
  estimateSize: _activeSessionEstimateSize,
  serialize: _activeSessionSerialize,
  deserialize: _activeSessionDeserialize,
  deserializeProp: _activeSessionDeserializeProp,
  idName: r'id',
  indexes: {
    r'sessionId': IndexSchema(
      id: 6949518585047923839,
      name: r'sessionId',
      unique: true,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'sessionId',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _activeSessionGetId,
  getLinks: _activeSessionGetLinks,
  attach: _activeSessionAttach,
  version: '3.1.0+1',
);

int _activeSessionEstimateSize(
  ActiveSession object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.courseName.length * 3;
  bytesCount += 3 + object.facultyName.length * 3;
  bytesCount += 3 + object.sectionId.length * 3;
  bytesCount += 3 + object.sessionId.length * 3;
  bytesCount += 3 + object.verifiedStudentIds.length * 3;
  {
    for (var i = 0; i < object.verifiedStudentIds.length; i++) {
      final value = object.verifiedStudentIds[i];
      bytesCount += value.length * 3;
    }
  }
  return bytesCount;
}

void _activeSessionSerialize(
  ActiveSession object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.courseName);
  writer.writeString(offsets[1], object.facultyName);
  writer.writeLong(offsets[2], object.rosterCount);
  writer.writeDateTime(offsets[3], object.scheduledEndTime);
  writer.writeString(offsets[4], object.sectionId);
  writer.writeString(offsets[5], object.sessionId);
  writer.writeStringList(offsets[6], object.verifiedStudentIds);
}

ActiveSession _activeSessionDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = ActiveSession();
  object.courseName = reader.readString(offsets[0]);
  object.facultyName = reader.readString(offsets[1]);
  object.id = id;
  object.rosterCount = reader.readLong(offsets[2]);
  object.scheduledEndTime = reader.readDateTime(offsets[3]);
  object.sectionId = reader.readString(offsets[4]);
  object.sessionId = reader.readString(offsets[5]);
  object.verifiedStudentIds = reader.readStringList(offsets[6]) ?? [];
  return object;
}

P _activeSessionDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readString(offset)) as P;
    case 1:
      return (reader.readString(offset)) as P;
    case 2:
      return (reader.readLong(offset)) as P;
    case 3:
      return (reader.readDateTime(offset)) as P;
    case 4:
      return (reader.readString(offset)) as P;
    case 5:
      return (reader.readString(offset)) as P;
    case 6:
      return (reader.readStringList(offset) ?? []) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _activeSessionGetId(ActiveSession object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _activeSessionGetLinks(ActiveSession object) {
  return [];
}

void _activeSessionAttach(
    IsarCollection<dynamic> col, Id id, ActiveSession object) {
  object.id = id;
}

extension ActiveSessionByIndex on IsarCollection<ActiveSession> {
  Future<ActiveSession?> getBySessionId(String sessionId) {
    return getByIndex(r'sessionId', [sessionId]);
  }

  ActiveSession? getBySessionIdSync(String sessionId) {
    return getByIndexSync(r'sessionId', [sessionId]);
  }

  Future<bool> deleteBySessionId(String sessionId) {
    return deleteByIndex(r'sessionId', [sessionId]);
  }

  bool deleteBySessionIdSync(String sessionId) {
    return deleteByIndexSync(r'sessionId', [sessionId]);
  }

  Future<List<ActiveSession?>> getAllBySessionId(List<String> sessionIdValues) {
    final values = sessionIdValues.map((e) => [e]).toList();
    return getAllByIndex(r'sessionId', values);
  }

  List<ActiveSession?> getAllBySessionIdSync(List<String> sessionIdValues) {
    final values = sessionIdValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'sessionId', values);
  }

  Future<int> deleteAllBySessionId(List<String> sessionIdValues) {
    final values = sessionIdValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'sessionId', values);
  }

  int deleteAllBySessionIdSync(List<String> sessionIdValues) {
    final values = sessionIdValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'sessionId', values);
  }

  Future<Id> putBySessionId(ActiveSession object) {
    return putByIndex(r'sessionId', object);
  }

  Id putBySessionIdSync(ActiveSession object, {bool saveLinks = true}) {
    return putByIndexSync(r'sessionId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllBySessionId(List<ActiveSession> objects) {
    return putAllByIndex(r'sessionId', objects);
  }

  List<Id> putAllBySessionIdSync(List<ActiveSession> objects,
      {bool saveLinks = true}) {
    return putAllByIndexSync(r'sessionId', objects, saveLinks: saveLinks);
  }
}

extension ActiveSessionQueryWhereSort
    on QueryBuilder<ActiveSession, ActiveSession, QWhere> {
  QueryBuilder<ActiveSession, ActiveSession, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension ActiveSessionQueryWhere
    on QueryBuilder<ActiveSession, ActiveSession, QWhereClause> {
  QueryBuilder<ActiveSession, ActiveSession, QAfterWhereClause> idEqualTo(
      Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterWhereClause> idNotEqualTo(
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

  QueryBuilder<ActiveSession, ActiveSession, QAfterWhereClause> idGreaterThan(
      Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterWhereClause> idLessThan(
      Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterWhereClause> idBetween(
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

  QueryBuilder<ActiveSession, ActiveSession, QAfterWhereClause>
      sessionIdEqualTo(String sessionId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'sessionId',
        value: [sessionId],
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterWhereClause>
      sessionIdNotEqualTo(String sessionId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'sessionId',
              lower: [],
              upper: [sessionId],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'sessionId',
              lower: [sessionId],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'sessionId',
              lower: [sessionId],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'sessionId',
              lower: [],
              upper: [sessionId],
              includeUpper: false,
            ));
      }
    });
  }
}

extension ActiveSessionQueryFilter
    on QueryBuilder<ActiveSession, ActiveSession, QFilterCondition> {
  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      courseNameEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'courseName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      courseNameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'courseName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      courseNameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'courseName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      courseNameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'courseName',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      courseNameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'courseName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      courseNameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'courseName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      courseNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'courseName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      courseNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'courseName',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      courseNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'courseName',
        value: '',
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      courseNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'courseName',
        value: '',
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      facultyNameEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'facultyName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      facultyNameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'facultyName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      facultyNameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'facultyName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      facultyNameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'facultyName',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      facultyNameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'facultyName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      facultyNameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'facultyName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      facultyNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'facultyName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      facultyNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'facultyName',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      facultyNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'facultyName',
        value: '',
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      facultyNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'facultyName',
        value: '',
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition> idEqualTo(
      Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      idGreaterThan(
    Id value, {
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

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition> idLessThan(
    Id value, {
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

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
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

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      rosterCountEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'rosterCount',
        value: value,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      rosterCountGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'rosterCount',
        value: value,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      rosterCountLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'rosterCount',
        value: value,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      rosterCountBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'rosterCount',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      scheduledEndTimeEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'scheduledEndTime',
        value: value,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      scheduledEndTimeGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'scheduledEndTime',
        value: value,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      scheduledEndTimeLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'scheduledEndTime',
        value: value,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      scheduledEndTimeBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'scheduledEndTime',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      sectionIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sectionId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      sectionIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'sectionId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      sectionIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'sectionId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      sectionIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'sectionId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      sectionIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'sectionId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      sectionIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'sectionId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      sectionIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'sectionId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      sectionIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'sectionId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      sectionIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sectionId',
        value: '',
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      sectionIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'sectionId',
        value: '',
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      sessionIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sessionId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      sessionIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'sessionId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      sessionIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'sessionId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      sessionIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'sessionId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      sessionIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'sessionId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      sessionIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'sessionId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      sessionIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'sessionId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      sessionIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'sessionId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      sessionIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sessionId',
        value: '',
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      sessionIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'sessionId',
        value: '',
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      verifiedStudentIdsElementEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'verifiedStudentIds',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      verifiedStudentIdsElementGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'verifiedStudentIds',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      verifiedStudentIdsElementLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'verifiedStudentIds',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      verifiedStudentIdsElementBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'verifiedStudentIds',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      verifiedStudentIdsElementStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'verifiedStudentIds',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      verifiedStudentIdsElementEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'verifiedStudentIds',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      verifiedStudentIdsElementContains(String value,
          {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'verifiedStudentIds',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      verifiedStudentIdsElementMatches(String pattern,
          {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'verifiedStudentIds',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      verifiedStudentIdsElementIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'verifiedStudentIds',
        value: '',
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      verifiedStudentIdsElementIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'verifiedStudentIds',
        value: '',
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      verifiedStudentIdsLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'verifiedStudentIds',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      verifiedStudentIdsIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'verifiedStudentIds',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      verifiedStudentIdsIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'verifiedStudentIds',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      verifiedStudentIdsLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'verifiedStudentIds',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      verifiedStudentIdsLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'verifiedStudentIds',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      verifiedStudentIdsLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'verifiedStudentIds',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }
}

extension ActiveSessionQueryObject
    on QueryBuilder<ActiveSession, ActiveSession, QFilterCondition> {}

extension ActiveSessionQueryLinks
    on QueryBuilder<ActiveSession, ActiveSession, QFilterCondition> {}

extension ActiveSessionQuerySortBy
    on QueryBuilder<ActiveSession, ActiveSession, QSortBy> {
  QueryBuilder<ActiveSession, ActiveSession, QAfterSortBy> sortByCourseName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'courseName', Sort.asc);
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterSortBy>
      sortByCourseNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'courseName', Sort.desc);
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterSortBy> sortByFacultyName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'facultyName', Sort.asc);
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterSortBy>
      sortByFacultyNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'facultyName', Sort.desc);
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterSortBy> sortByRosterCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'rosterCount', Sort.asc);
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterSortBy>
      sortByRosterCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'rosterCount', Sort.desc);
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterSortBy>
      sortByScheduledEndTime() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'scheduledEndTime', Sort.asc);
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterSortBy>
      sortByScheduledEndTimeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'scheduledEndTime', Sort.desc);
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterSortBy> sortBySectionId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sectionId', Sort.asc);
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterSortBy>
      sortBySectionIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sectionId', Sort.desc);
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterSortBy> sortBySessionId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sessionId', Sort.asc);
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterSortBy>
      sortBySessionIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sessionId', Sort.desc);
    });
  }
}

extension ActiveSessionQuerySortThenBy
    on QueryBuilder<ActiveSession, ActiveSession, QSortThenBy> {
  QueryBuilder<ActiveSession, ActiveSession, QAfterSortBy> thenByCourseName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'courseName', Sort.asc);
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterSortBy>
      thenByCourseNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'courseName', Sort.desc);
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterSortBy> thenByFacultyName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'facultyName', Sort.asc);
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterSortBy>
      thenByFacultyNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'facultyName', Sort.desc);
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterSortBy> thenByRosterCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'rosterCount', Sort.asc);
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterSortBy>
      thenByRosterCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'rosterCount', Sort.desc);
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterSortBy>
      thenByScheduledEndTime() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'scheduledEndTime', Sort.asc);
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterSortBy>
      thenByScheduledEndTimeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'scheduledEndTime', Sort.desc);
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterSortBy> thenBySectionId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sectionId', Sort.asc);
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterSortBy>
      thenBySectionIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sectionId', Sort.desc);
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterSortBy> thenBySessionId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sessionId', Sort.asc);
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterSortBy>
      thenBySessionIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sessionId', Sort.desc);
    });
  }
}

extension ActiveSessionQueryWhereDistinct
    on QueryBuilder<ActiveSession, ActiveSession, QDistinct> {
  QueryBuilder<ActiveSession, ActiveSession, QDistinct> distinctByCourseName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'courseName', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QDistinct> distinctByFacultyName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'facultyName', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QDistinct>
      distinctByRosterCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'rosterCount');
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QDistinct>
      distinctByScheduledEndTime() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'scheduledEndTime');
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QDistinct> distinctBySectionId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'sectionId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QDistinct> distinctBySessionId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'sessionId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QDistinct>
      distinctByVerifiedStudentIds() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'verifiedStudentIds');
    });
  }
}

extension ActiveSessionQueryProperty
    on QueryBuilder<ActiveSession, ActiveSession, QQueryProperty> {
  QueryBuilder<ActiveSession, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<ActiveSession, String, QQueryOperations> courseNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'courseName');
    });
  }

  QueryBuilder<ActiveSession, String, QQueryOperations> facultyNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'facultyName');
    });
  }

  QueryBuilder<ActiveSession, int, QQueryOperations> rosterCountProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'rosterCount');
    });
  }

  QueryBuilder<ActiveSession, DateTime, QQueryOperations>
      scheduledEndTimeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'scheduledEndTime');
    });
  }

  QueryBuilder<ActiveSession, String, QQueryOperations> sectionIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'sectionId');
    });
  }

  QueryBuilder<ActiveSession, String, QQueryOperations> sessionIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'sessionId');
    });
  }

  QueryBuilder<ActiveSession, List<String>, QQueryOperations>
      verifiedStudentIdsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'verifiedStudentIds');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetQueuedScanCollection on Isar {
  IsarCollection<QueuedScan> get queuedScans => this.collection();
}

const QueuedScanSchema = CollectionSchema(
  name: r'QueuedScan',
  id: -3943572717429933023,
  properties: {
    r'scanTimestamp': PropertySchema(
      id: 0,
      name: r'scanTimestamp',
      type: IsarType.dateTime,
    ),
    r'scannedTotpHash': PropertySchema(
      id: 1,
      name: r'scannedTotpHash',
      type: IsarType.string,
    ),
    r'sessionId': PropertySchema(
      id: 2,
      name: r'sessionId',
      type: IsarType.string,
    ),
    r'studentId': PropertySchema(
      id: 3,
      name: r'studentId',
      type: IsarType.string,
    )
  },
  estimateSize: _queuedScanEstimateSize,
  serialize: _queuedScanSerialize,
  deserialize: _queuedScanDeserialize,
  deserializeProp: _queuedScanDeserializeProp,
  idName: r'id',
  indexes: {
    r'sessionId': IndexSchema(
      id: 6949518585047923839,
      name: r'sessionId',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'sessionId',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _queuedScanGetId,
  getLinks: _queuedScanGetLinks,
  attach: _queuedScanAttach,
  version: '3.1.0+1',
);

int _queuedScanEstimateSize(
  QueuedScan object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.scannedTotpHash.length * 3;
  bytesCount += 3 + object.sessionId.length * 3;
  bytesCount += 3 + object.studentId.length * 3;
  return bytesCount;
}

void _queuedScanSerialize(
  QueuedScan object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeDateTime(offsets[0], object.scanTimestamp);
  writer.writeString(offsets[1], object.scannedTotpHash);
  writer.writeString(offsets[2], object.sessionId);
  writer.writeString(offsets[3], object.studentId);
}

QueuedScan _queuedScanDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = QueuedScan();
  object.id = id;
  object.scanTimestamp = reader.readDateTime(offsets[0]);
  object.scannedTotpHash = reader.readString(offsets[1]);
  object.sessionId = reader.readString(offsets[2]);
  object.studentId = reader.readString(offsets[3]);
  return object;
}

P _queuedScanDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readDateTime(offset)) as P;
    case 1:
      return (reader.readString(offset)) as P;
    case 2:
      return (reader.readString(offset)) as P;
    case 3:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _queuedScanGetId(QueuedScan object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _queuedScanGetLinks(QueuedScan object) {
  return [];
}

void _queuedScanAttach(IsarCollection<dynamic> col, Id id, QueuedScan object) {
  object.id = id;
}

extension QueuedScanQueryWhereSort
    on QueryBuilder<QueuedScan, QueuedScan, QWhere> {
  QueryBuilder<QueuedScan, QueuedScan, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension QueuedScanQueryWhere
    on QueryBuilder<QueuedScan, QueuedScan, QWhereClause> {
  QueryBuilder<QueuedScan, QueuedScan, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterWhereClause> idNotEqualTo(Id id) {
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

  QueryBuilder<QueuedScan, QueuedScan, QAfterWhereClause> idGreaterThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterWhereClause> idLessThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterWhereClause> idBetween(
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

  QueryBuilder<QueuedScan, QueuedScan, QAfterWhereClause> sessionIdEqualTo(
      String sessionId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'sessionId',
        value: [sessionId],
      ));
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterWhereClause> sessionIdNotEqualTo(
      String sessionId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'sessionId',
              lower: [],
              upper: [sessionId],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'sessionId',
              lower: [sessionId],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'sessionId',
              lower: [sessionId],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'sessionId',
              lower: [],
              upper: [sessionId],
              includeUpper: false,
            ));
      }
    });
  }
}

extension QueuedScanQueryFilter
    on QueryBuilder<QueuedScan, QueuedScan, QFilterCondition> {
  QueryBuilder<QueuedScan, QueuedScan, QAfterFilterCondition> idEqualTo(
      Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterFilterCondition> idGreaterThan(
    Id value, {
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

  QueryBuilder<QueuedScan, QueuedScan, QAfterFilterCondition> idLessThan(
    Id value, {
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

  QueryBuilder<QueuedScan, QueuedScan, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
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

  QueryBuilder<QueuedScan, QueuedScan, QAfterFilterCondition>
      scanTimestampEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'scanTimestamp',
        value: value,
      ));
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterFilterCondition>
      scanTimestampGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'scanTimestamp',
        value: value,
      ));
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterFilterCondition>
      scanTimestampLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'scanTimestamp',
        value: value,
      ));
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterFilterCondition>
      scanTimestampBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'scanTimestamp',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterFilterCondition>
      scannedTotpHashEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'scannedTotpHash',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterFilterCondition>
      scannedTotpHashGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'scannedTotpHash',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterFilterCondition>
      scannedTotpHashLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'scannedTotpHash',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterFilterCondition>
      scannedTotpHashBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'scannedTotpHash',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterFilterCondition>
      scannedTotpHashStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'scannedTotpHash',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterFilterCondition>
      scannedTotpHashEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'scannedTotpHash',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterFilterCondition>
      scannedTotpHashContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'scannedTotpHash',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterFilterCondition>
      scannedTotpHashMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'scannedTotpHash',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterFilterCondition>
      scannedTotpHashIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'scannedTotpHash',
        value: '',
      ));
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterFilterCondition>
      scannedTotpHashIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'scannedTotpHash',
        value: '',
      ));
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterFilterCondition> sessionIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sessionId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterFilterCondition>
      sessionIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'sessionId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterFilterCondition> sessionIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'sessionId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterFilterCondition> sessionIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'sessionId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterFilterCondition>
      sessionIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'sessionId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterFilterCondition> sessionIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'sessionId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterFilterCondition> sessionIdContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'sessionId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterFilterCondition> sessionIdMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'sessionId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterFilterCondition>
      sessionIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sessionId',
        value: '',
      ));
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterFilterCondition>
      sessionIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'sessionId',
        value: '',
      ));
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterFilterCondition> studentIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'studentId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterFilterCondition>
      studentIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'studentId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterFilterCondition> studentIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'studentId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterFilterCondition> studentIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'studentId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterFilterCondition>
      studentIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'studentId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterFilterCondition> studentIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'studentId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterFilterCondition> studentIdContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'studentId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterFilterCondition> studentIdMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'studentId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterFilterCondition>
      studentIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'studentId',
        value: '',
      ));
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterFilterCondition>
      studentIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'studentId',
        value: '',
      ));
    });
  }
}

extension QueuedScanQueryObject
    on QueryBuilder<QueuedScan, QueuedScan, QFilterCondition> {}

extension QueuedScanQueryLinks
    on QueryBuilder<QueuedScan, QueuedScan, QFilterCondition> {}

extension QueuedScanQuerySortBy
    on QueryBuilder<QueuedScan, QueuedScan, QSortBy> {
  QueryBuilder<QueuedScan, QueuedScan, QAfterSortBy> sortByScanTimestamp() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'scanTimestamp', Sort.asc);
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterSortBy> sortByScanTimestampDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'scanTimestamp', Sort.desc);
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterSortBy> sortByScannedTotpHash() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'scannedTotpHash', Sort.asc);
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterSortBy>
      sortByScannedTotpHashDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'scannedTotpHash', Sort.desc);
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterSortBy> sortBySessionId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sessionId', Sort.asc);
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterSortBy> sortBySessionIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sessionId', Sort.desc);
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterSortBy> sortByStudentId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'studentId', Sort.asc);
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterSortBy> sortByStudentIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'studentId', Sort.desc);
    });
  }
}

extension QueuedScanQuerySortThenBy
    on QueryBuilder<QueuedScan, QueuedScan, QSortThenBy> {
  QueryBuilder<QueuedScan, QueuedScan, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterSortBy> thenByScanTimestamp() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'scanTimestamp', Sort.asc);
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterSortBy> thenByScanTimestampDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'scanTimestamp', Sort.desc);
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterSortBy> thenByScannedTotpHash() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'scannedTotpHash', Sort.asc);
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterSortBy>
      thenByScannedTotpHashDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'scannedTotpHash', Sort.desc);
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterSortBy> thenBySessionId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sessionId', Sort.asc);
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterSortBy> thenBySessionIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sessionId', Sort.desc);
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterSortBy> thenByStudentId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'studentId', Sort.asc);
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QAfterSortBy> thenByStudentIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'studentId', Sort.desc);
    });
  }
}

extension QueuedScanQueryWhereDistinct
    on QueryBuilder<QueuedScan, QueuedScan, QDistinct> {
  QueryBuilder<QueuedScan, QueuedScan, QDistinct> distinctByScanTimestamp() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'scanTimestamp');
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QDistinct> distinctByScannedTotpHash(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'scannedTotpHash',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QDistinct> distinctBySessionId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'sessionId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<QueuedScan, QueuedScan, QDistinct> distinctByStudentId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'studentId', caseSensitive: caseSensitive);
    });
  }
}

extension QueuedScanQueryProperty
    on QueryBuilder<QueuedScan, QueuedScan, QQueryProperty> {
  QueryBuilder<QueuedScan, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<QueuedScan, DateTime, QQueryOperations> scanTimestampProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'scanTimestamp');
    });
  }

  QueryBuilder<QueuedScan, String, QQueryOperations> scannedTotpHashProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'scannedTotpHash');
    });
  }

  QueryBuilder<QueuedScan, String, QQueryOperations> sessionIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'sessionId');
    });
  }

  QueryBuilder<QueuedScan, String, QQueryOperations> studentIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'studentId');
    });
  }
}
