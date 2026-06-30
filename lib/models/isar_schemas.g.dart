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
    r'absentIndices': PropertySchema(
      id: 0,
      name: r'absentIndices',
      type: IsarType.longList,
    ),
    r'courseName': PropertySchema(
      id: 1,
      name: r'courseName',
      type: IsarType.string,
    ),
    r'facultyName': PropertySchema(
      id: 2,
      name: r'facultyName',
      type: IsarType.string,
    ),
    r'presentIndices': PropertySchema(
      id: 3,
      name: r'presentIndices',
      type: IsarType.longList,
    ),
    r'rosterCount': PropertySchema(
      id: 4,
      name: r'rosterCount',
      type: IsarType.long,
    ),
    r'scheduledEndTime': PropertySchema(
      id: 5,
      name: r'scheduledEndTime',
      type: IsarType.dateTime,
    ),
    r'sectionId': PropertySchema(
      id: 6,
      name: r'sectionId',
      type: IsarType.string,
    ),
    r'sessionId': PropertySchema(
      id: 7,
      name: r'sessionId',
      type: IsarType.string,
    ),
    r'verifiedStudentIds': PropertySchema(
      id: 8,
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
  bytesCount += 3 + object.absentIndices.length * 8;
  bytesCount += 3 + object.courseName.length * 3;
  bytesCount += 3 + object.facultyName.length * 3;
  bytesCount += 3 + object.presentIndices.length * 8;
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
  writer.writeLongList(offsets[0], object.absentIndices);
  writer.writeString(offsets[1], object.courseName);
  writer.writeString(offsets[2], object.facultyName);
  writer.writeLongList(offsets[3], object.presentIndices);
  writer.writeLong(offsets[4], object.rosterCount);
  writer.writeDateTime(offsets[5], object.scheduledEndTime);
  writer.writeString(offsets[6], object.sectionId);
  writer.writeString(offsets[7], object.sessionId);
  writer.writeStringList(offsets[8], object.verifiedStudentIds);
}

ActiveSession _activeSessionDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = ActiveSession();
  object.absentIndices = reader.readLongList(offsets[0]) ?? [];
  object.courseName = reader.readString(offsets[1]);
  object.facultyName = reader.readString(offsets[2]);
  object.id = id;
  object.presentIndices = reader.readLongList(offsets[3]) ?? [];
  object.rosterCount = reader.readLong(offsets[4]);
  object.scheduledEndTime = reader.readDateTime(offsets[5]);
  object.sectionId = reader.readString(offsets[6]);
  object.sessionId = reader.readString(offsets[7]);
  object.verifiedStudentIds = reader.readStringList(offsets[8]) ?? [];
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
      return (reader.readLongList(offset) ?? []) as P;
    case 1:
      return (reader.readString(offset)) as P;
    case 2:
      return (reader.readString(offset)) as P;
    case 3:
      return (reader.readLongList(offset) ?? []) as P;
    case 4:
      return (reader.readLong(offset)) as P;
    case 5:
      return (reader.readDateTime(offset)) as P;
    case 6:
      return (reader.readString(offset)) as P;
    case 7:
      return (reader.readString(offset)) as P;
    case 8:
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
      absentIndicesElementEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'absentIndices',
        value: value,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      absentIndicesElementGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'absentIndices',
        value: value,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      absentIndicesElementLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'absentIndices',
        value: value,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      absentIndicesElementBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'absentIndices',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      absentIndicesLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'absentIndices',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      absentIndicesIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'absentIndices',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      absentIndicesIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'absentIndices',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      absentIndicesLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'absentIndices',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      absentIndicesLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'absentIndices',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      absentIndicesLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'absentIndices',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

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
      presentIndicesElementEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'presentIndices',
        value: value,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      presentIndicesElementGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'presentIndices',
        value: value,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      presentIndicesElementLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'presentIndices',
        value: value,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      presentIndicesElementBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'presentIndices',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      presentIndicesLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'presentIndices',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      presentIndicesIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'presentIndices',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      presentIndicesIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'presentIndices',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      presentIndicesLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'presentIndices',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      presentIndicesLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'presentIndices',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<ActiveSession, ActiveSession, QAfterFilterCondition>
      presentIndicesLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'presentIndices',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
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
  QueryBuilder<ActiveSession, ActiveSession, QDistinct>
      distinctByAbsentIndices() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'absentIndices');
    });
  }

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
      distinctByPresentIndices() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'presentIndices');
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

  QueryBuilder<ActiveSession, List<int>, QQueryOperations>
      absentIndicesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'absentIndices');
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

  QueryBuilder<ActiveSession, List<int>, QQueryOperations>
      presentIndicesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'presentIndices');
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

extension GetDeviceRegistrationCollection on Isar {
  IsarCollection<DeviceRegistration> get deviceRegistrations =>
      this.collection();
}

const DeviceRegistrationSchema = CollectionSchema(
  name: r'DeviceRegistration',
  id: -214276878105497287,
  properties: {
    r'building': PropertySchema(
      id: 0,
      name: r'building',
      type: IsarType.string,
    ),
    r'capacity': PropertySchema(
      id: 1,
      name: r'capacity',
      type: IsarType.long,
    ),
    r'classroomId': PropertySchema(
      id: 2,
      name: r'classroomId',
      type: IsarType.string,
    ),
    r'department': PropertySchema(
      id: 3,
      name: r'department',
      type: IsarType.string,
    ),
    r'hardwareId': PropertySchema(
      id: 4,
      name: r'hardwareId',
      type: IsarType.string,
    ),
    r'registrationDate': PropertySchema(
      id: 5,
      name: r'registrationDate',
      type: IsarType.dateTime,
    ),
    r'roomName': PropertySchema(
      id: 6,
      name: r'roomName',
      type: IsarType.string,
    ),
    r'smartBoardId': PropertySchema(
      id: 7,
      name: r'smartBoardId',
      type: IsarType.string,
    )
  },
  estimateSize: _deviceRegistrationEstimateSize,
  serialize: _deviceRegistrationSerialize,
  deserialize: _deviceRegistrationDeserialize,
  deserializeProp: _deviceRegistrationDeserializeProp,
  idName: r'id',
  indexes: {
    r'smartBoardId': IndexSchema(
      id: -1445689714503001021,
      name: r'smartBoardId',
      unique: true,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'smartBoardId',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _deviceRegistrationGetId,
  getLinks: _deviceRegistrationGetLinks,
  attach: _deviceRegistrationAttach,
  version: '3.1.0+1',
);

int _deviceRegistrationEstimateSize(
  DeviceRegistration object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.building.length * 3;
  {
    final value = object.classroomId;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.department.length * 3;
  bytesCount += 3 + object.hardwareId.length * 3;
  bytesCount += 3 + object.roomName.length * 3;
  bytesCount += 3 + object.smartBoardId.length * 3;
  return bytesCount;
}

void _deviceRegistrationSerialize(
  DeviceRegistration object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.building);
  writer.writeLong(offsets[1], object.capacity);
  writer.writeString(offsets[2], object.classroomId);
  writer.writeString(offsets[3], object.department);
  writer.writeString(offsets[4], object.hardwareId);
  writer.writeDateTime(offsets[5], object.registrationDate);
  writer.writeString(offsets[6], object.roomName);
  writer.writeString(offsets[7], object.smartBoardId);
}

DeviceRegistration _deviceRegistrationDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = DeviceRegistration();
  object.building = reader.readString(offsets[0]);
  object.capacity = reader.readLong(offsets[1]);
  object.classroomId = reader.readStringOrNull(offsets[2]);
  object.department = reader.readString(offsets[3]);
  object.hardwareId = reader.readString(offsets[4]);
  object.id = id;
  object.registrationDate = reader.readDateTime(offsets[5]);
  object.roomName = reader.readString(offsets[6]);
  object.smartBoardId = reader.readString(offsets[7]);
  return object;
}

P _deviceRegistrationDeserializeProp<P>(
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
      return (reader.readStringOrNull(offset)) as P;
    case 3:
      return (reader.readString(offset)) as P;
    case 4:
      return (reader.readString(offset)) as P;
    case 5:
      return (reader.readDateTime(offset)) as P;
    case 6:
      return (reader.readString(offset)) as P;
    case 7:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _deviceRegistrationGetId(DeviceRegistration object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _deviceRegistrationGetLinks(
    DeviceRegistration object) {
  return [];
}

void _deviceRegistrationAttach(
    IsarCollection<dynamic> col, Id id, DeviceRegistration object) {
  object.id = id;
}

extension DeviceRegistrationByIndex on IsarCollection<DeviceRegistration> {
  Future<DeviceRegistration?> getBySmartBoardId(String smartBoardId) {
    return getByIndex(r'smartBoardId', [smartBoardId]);
  }

  DeviceRegistration? getBySmartBoardIdSync(String smartBoardId) {
    return getByIndexSync(r'smartBoardId', [smartBoardId]);
  }

  Future<bool> deleteBySmartBoardId(String smartBoardId) {
    return deleteByIndex(r'smartBoardId', [smartBoardId]);
  }

  bool deleteBySmartBoardIdSync(String smartBoardId) {
    return deleteByIndexSync(r'smartBoardId', [smartBoardId]);
  }

  Future<List<DeviceRegistration?>> getAllBySmartBoardId(
      List<String> smartBoardIdValues) {
    final values = smartBoardIdValues.map((e) => [e]).toList();
    return getAllByIndex(r'smartBoardId', values);
  }

  List<DeviceRegistration?> getAllBySmartBoardIdSync(
      List<String> smartBoardIdValues) {
    final values = smartBoardIdValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'smartBoardId', values);
  }

  Future<int> deleteAllBySmartBoardId(List<String> smartBoardIdValues) {
    final values = smartBoardIdValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'smartBoardId', values);
  }

  int deleteAllBySmartBoardIdSync(List<String> smartBoardIdValues) {
    final values = smartBoardIdValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'smartBoardId', values);
  }

  Future<Id> putBySmartBoardId(DeviceRegistration object) {
    return putByIndex(r'smartBoardId', object);
  }

  Id putBySmartBoardIdSync(DeviceRegistration object, {bool saveLinks = true}) {
    return putByIndexSync(r'smartBoardId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllBySmartBoardId(List<DeviceRegistration> objects) {
    return putAllByIndex(r'smartBoardId', objects);
  }

  List<Id> putAllBySmartBoardIdSync(List<DeviceRegistration> objects,
      {bool saveLinks = true}) {
    return putAllByIndexSync(r'smartBoardId', objects, saveLinks: saveLinks);
  }
}

extension DeviceRegistrationQueryWhereSort
    on QueryBuilder<DeviceRegistration, DeviceRegistration, QWhere> {
  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension DeviceRegistrationQueryWhere
    on QueryBuilder<DeviceRegistration, DeviceRegistration, QWhereClause> {
  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterWhereClause>
      idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterWhereClause>
      idNotEqualTo(Id id) {
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

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterWhereClause>
      idGreaterThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterWhereClause>
      idLessThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterWhereClause>
      idBetween(
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

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterWhereClause>
      smartBoardIdEqualTo(String smartBoardId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'smartBoardId',
        value: [smartBoardId],
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterWhereClause>
      smartBoardIdNotEqualTo(String smartBoardId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'smartBoardId',
              lower: [],
              upper: [smartBoardId],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'smartBoardId',
              lower: [smartBoardId],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'smartBoardId',
              lower: [smartBoardId],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'smartBoardId',
              lower: [],
              upper: [smartBoardId],
              includeUpper: false,
            ));
      }
    });
  }
}

extension DeviceRegistrationQueryFilter
    on QueryBuilder<DeviceRegistration, DeviceRegistration, QFilterCondition> {
  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      buildingEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'building',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      buildingGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'building',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      buildingLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'building',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      buildingBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'building',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      buildingStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'building',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      buildingEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'building',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      buildingContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'building',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      buildingMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'building',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      buildingIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'building',
        value: '',
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      buildingIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'building',
        value: '',
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      capacityEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'capacity',
        value: value,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      capacityGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'capacity',
        value: value,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      capacityLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'capacity',
        value: value,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      capacityBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'capacity',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      classroomIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'classroomId',
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      classroomIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'classroomId',
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      classroomIdEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'classroomId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      classroomIdGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'classroomId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      classroomIdLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'classroomId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      classroomIdBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'classroomId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      classroomIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'classroomId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      classroomIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'classroomId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      classroomIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'classroomId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      classroomIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'classroomId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      classroomIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'classroomId',
        value: '',
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      classroomIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'classroomId',
        value: '',
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      departmentEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'department',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      departmentGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'department',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      departmentLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'department',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      departmentBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'department',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      departmentStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'department',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      departmentEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'department',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      departmentContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'department',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      departmentMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'department',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      departmentIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'department',
        value: '',
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      departmentIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'department',
        value: '',
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      hardwareIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'hardwareId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      hardwareIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'hardwareId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      hardwareIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'hardwareId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      hardwareIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'hardwareId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      hardwareIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'hardwareId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      hardwareIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'hardwareId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      hardwareIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'hardwareId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      hardwareIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'hardwareId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      hardwareIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'hardwareId',
        value: '',
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      hardwareIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'hardwareId',
        value: '',
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
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

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      idLessThan(
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

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      idBetween(
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

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      registrationDateEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'registrationDate',
        value: value,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      registrationDateGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'registrationDate',
        value: value,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      registrationDateLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'registrationDate',
        value: value,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      registrationDateBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'registrationDate',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      roomNameEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'roomName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      roomNameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'roomName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      roomNameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'roomName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      roomNameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'roomName',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      roomNameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'roomName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      roomNameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'roomName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      roomNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'roomName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      roomNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'roomName',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      roomNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'roomName',
        value: '',
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      roomNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'roomName',
        value: '',
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      smartBoardIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'smartBoardId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      smartBoardIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'smartBoardId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      smartBoardIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'smartBoardId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      smartBoardIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'smartBoardId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      smartBoardIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'smartBoardId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      smartBoardIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'smartBoardId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      smartBoardIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'smartBoardId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      smartBoardIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'smartBoardId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      smartBoardIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'smartBoardId',
        value: '',
      ));
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterFilterCondition>
      smartBoardIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'smartBoardId',
        value: '',
      ));
    });
  }
}

extension DeviceRegistrationQueryObject
    on QueryBuilder<DeviceRegistration, DeviceRegistration, QFilterCondition> {}

extension DeviceRegistrationQueryLinks
    on QueryBuilder<DeviceRegistration, DeviceRegistration, QFilterCondition> {}

extension DeviceRegistrationQuerySortBy
    on QueryBuilder<DeviceRegistration, DeviceRegistration, QSortBy> {
  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterSortBy>
      sortByBuilding() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'building', Sort.asc);
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterSortBy>
      sortByBuildingDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'building', Sort.desc);
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterSortBy>
      sortByCapacity() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'capacity', Sort.asc);
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterSortBy>
      sortByCapacityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'capacity', Sort.desc);
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterSortBy>
      sortByClassroomId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'classroomId', Sort.asc);
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterSortBy>
      sortByClassroomIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'classroomId', Sort.desc);
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterSortBy>
      sortByDepartment() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'department', Sort.asc);
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterSortBy>
      sortByDepartmentDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'department', Sort.desc);
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterSortBy>
      sortByHardwareId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hardwareId', Sort.asc);
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterSortBy>
      sortByHardwareIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hardwareId', Sort.desc);
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterSortBy>
      sortByRegistrationDate() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'registrationDate', Sort.asc);
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterSortBy>
      sortByRegistrationDateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'registrationDate', Sort.desc);
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterSortBy>
      sortByRoomName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'roomName', Sort.asc);
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterSortBy>
      sortByRoomNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'roomName', Sort.desc);
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterSortBy>
      sortBySmartBoardId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'smartBoardId', Sort.asc);
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterSortBy>
      sortBySmartBoardIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'smartBoardId', Sort.desc);
    });
  }
}

extension DeviceRegistrationQuerySortThenBy
    on QueryBuilder<DeviceRegistration, DeviceRegistration, QSortThenBy> {
  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterSortBy>
      thenByBuilding() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'building', Sort.asc);
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterSortBy>
      thenByBuildingDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'building', Sort.desc);
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterSortBy>
      thenByCapacity() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'capacity', Sort.asc);
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterSortBy>
      thenByCapacityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'capacity', Sort.desc);
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterSortBy>
      thenByClassroomId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'classroomId', Sort.asc);
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterSortBy>
      thenByClassroomIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'classroomId', Sort.desc);
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterSortBy>
      thenByDepartment() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'department', Sort.asc);
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterSortBy>
      thenByDepartmentDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'department', Sort.desc);
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterSortBy>
      thenByHardwareId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hardwareId', Sort.asc);
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterSortBy>
      thenByHardwareIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hardwareId', Sort.desc);
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterSortBy>
      thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterSortBy>
      thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterSortBy>
      thenByRegistrationDate() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'registrationDate', Sort.asc);
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterSortBy>
      thenByRegistrationDateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'registrationDate', Sort.desc);
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterSortBy>
      thenByRoomName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'roomName', Sort.asc);
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterSortBy>
      thenByRoomNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'roomName', Sort.desc);
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterSortBy>
      thenBySmartBoardId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'smartBoardId', Sort.asc);
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QAfterSortBy>
      thenBySmartBoardIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'smartBoardId', Sort.desc);
    });
  }
}

extension DeviceRegistrationQueryWhereDistinct
    on QueryBuilder<DeviceRegistration, DeviceRegistration, QDistinct> {
  QueryBuilder<DeviceRegistration, DeviceRegistration, QDistinct>
      distinctByBuilding({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'building', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QDistinct>
      distinctByCapacity() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'capacity');
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QDistinct>
      distinctByClassroomId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'classroomId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QDistinct>
      distinctByDepartment({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'department', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QDistinct>
      distinctByHardwareId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'hardwareId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QDistinct>
      distinctByRegistrationDate() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'registrationDate');
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QDistinct>
      distinctByRoomName({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'roomName', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<DeviceRegistration, DeviceRegistration, QDistinct>
      distinctBySmartBoardId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'smartBoardId', caseSensitive: caseSensitive);
    });
  }
}

extension DeviceRegistrationQueryProperty
    on QueryBuilder<DeviceRegistration, DeviceRegistration, QQueryProperty> {
  QueryBuilder<DeviceRegistration, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<DeviceRegistration, String, QQueryOperations>
      buildingProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'building');
    });
  }

  QueryBuilder<DeviceRegistration, int, QQueryOperations> capacityProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'capacity');
    });
  }

  QueryBuilder<DeviceRegistration, String?, QQueryOperations>
      classroomIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'classroomId');
    });
  }

  QueryBuilder<DeviceRegistration, String, QQueryOperations>
      departmentProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'department');
    });
  }

  QueryBuilder<DeviceRegistration, String, QQueryOperations>
      hardwareIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'hardwareId');
    });
  }

  QueryBuilder<DeviceRegistration, DateTime, QQueryOperations>
      registrationDateProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'registrationDate');
    });
  }

  QueryBuilder<DeviceRegistration, String, QQueryOperations>
      roomNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'roomName');
    });
  }

  QueryBuilder<DeviceRegistration, String, QQueryOperations>
      smartBoardIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'smartBoardId');
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

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetTimetableEntryCollection on Isar {
  IsarCollection<TimetableEntry> get timetableEntrys => this.collection();
}

const TimetableEntrySchema = CollectionSchema(
  name: r'TimetableEntry',
  id: 2359161738487326219,
  properties: {
    r'classType': PropertySchema(
      id: 0,
      name: r'classType',
      type: IsarType.string,
    ),
    r'courseCode': PropertySchema(
      id: 1,
      name: r'courseCode',
      type: IsarType.string,
    ),
    r'courseName': PropertySchema(
      id: 2,
      name: r'courseName',
      type: IsarType.string,
    ),
    r'dayOfWeek': PropertySchema(
      id: 3,
      name: r'dayOfWeek',
      type: IsarType.long,
    ),
    r'endTime': PropertySchema(
      id: 4,
      name: r'endTime',
      type: IsarType.string,
    ),
    r'facultyEmails': PropertySchema(
      id: 5,
      name: r'facultyEmails',
      type: IsarType.stringList,
    ),
    r'facultyName': PropertySchema(
      id: 6,
      name: r'facultyName',
      type: IsarType.string,
    ),
    r'roomNumber': PropertySchema(
      id: 7,
      name: r'roomNumber',
      type: IsarType.string,
    ),
    r'sectionId': PropertySchema(
      id: 8,
      name: r'sectionId',
      type: IsarType.string,
    ),
    r'sectionName': PropertySchema(
      id: 9,
      name: r'sectionName',
      type: IsarType.string,
    ),
    r'slotId': PropertySchema(
      id: 10,
      name: r'slotId',
      type: IsarType.string,
    ),
    r'slotType': PropertySchema(
      id: 11,
      name: r'slotType',
      type: IsarType.string,
    ),
    r'startTime': PropertySchema(
      id: 12,
      name: r'startTime',
      type: IsarType.string,
    ),
    r'subjectCode': PropertySchema(
      id: 13,
      name: r'subjectCode',
      type: IsarType.string,
    ),
    r'subjectName': PropertySchema(
      id: 14,
      name: r'subjectName',
      type: IsarType.string,
    )
  },
  estimateSize: _timetableEntryEstimateSize,
  serialize: _timetableEntrySerialize,
  deserialize: _timetableEntryDeserialize,
  deserializeProp: _timetableEntryDeserializeProp,
  idName: r'id',
  indexes: {
    r'dayOfWeek': IndexSchema(
      id: -5516657708462385134,
      name: r'dayOfWeek',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'dayOfWeek',
          type: IndexType.value,
          caseSensitive: false,
        )
      ],
    ),
    r'startTime': IndexSchema(
      id: -3870335341264752872,
      name: r'startTime',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'startTime',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _timetableEntryGetId,
  getLinks: _timetableEntryGetLinks,
  attach: _timetableEntryAttach,
  version: '3.1.0+1',
);

int _timetableEntryEstimateSize(
  TimetableEntry object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.classType.length * 3;
  bytesCount += 3 + object.courseCode.length * 3;
  bytesCount += 3 + object.courseName.length * 3;
  bytesCount += 3 + object.endTime.length * 3;
  bytesCount += 3 + object.facultyEmails.length * 3;
  {
    for (var i = 0; i < object.facultyEmails.length; i++) {
      final value = object.facultyEmails[i];
      bytesCount += value.length * 3;
    }
  }
  bytesCount += 3 + object.facultyName.length * 3;
  bytesCount += 3 + object.roomNumber.length * 3;
  bytesCount += 3 + object.sectionId.length * 3;
  bytesCount += 3 + object.sectionName.length * 3;
  bytesCount += 3 + object.slotId.length * 3;
  bytesCount += 3 + object.slotType.length * 3;
  bytesCount += 3 + object.startTime.length * 3;
  bytesCount += 3 + object.subjectCode.length * 3;
  bytesCount += 3 + object.subjectName.length * 3;
  return bytesCount;
}

void _timetableEntrySerialize(
  TimetableEntry object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.classType);
  writer.writeString(offsets[1], object.courseCode);
  writer.writeString(offsets[2], object.courseName);
  writer.writeLong(offsets[3], object.dayOfWeek);
  writer.writeString(offsets[4], object.endTime);
  writer.writeStringList(offsets[5], object.facultyEmails);
  writer.writeString(offsets[6], object.facultyName);
  writer.writeString(offsets[7], object.roomNumber);
  writer.writeString(offsets[8], object.sectionId);
  writer.writeString(offsets[9], object.sectionName);
  writer.writeString(offsets[10], object.slotId);
  writer.writeString(offsets[11], object.slotType);
  writer.writeString(offsets[12], object.startTime);
  writer.writeString(offsets[13], object.subjectCode);
  writer.writeString(offsets[14], object.subjectName);
}

TimetableEntry _timetableEntryDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = TimetableEntry();
  object.classType = reader.readString(offsets[0]);
  object.courseCode = reader.readString(offsets[1]);
  object.courseName = reader.readString(offsets[2]);
  object.dayOfWeek = reader.readLong(offsets[3]);
  object.endTime = reader.readString(offsets[4]);
  object.facultyEmails = reader.readStringList(offsets[5]) ?? [];
  object.facultyName = reader.readString(offsets[6]);
  object.id = id;
  object.roomNumber = reader.readString(offsets[7]);
  object.sectionId = reader.readString(offsets[8]);
  object.sectionName = reader.readString(offsets[9]);
  object.slotId = reader.readString(offsets[10]);
  object.slotType = reader.readString(offsets[11]);
  object.startTime = reader.readString(offsets[12]);
  object.subjectCode = reader.readString(offsets[13]);
  object.subjectName = reader.readString(offsets[14]);
  return object;
}

P _timetableEntryDeserializeProp<P>(
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
      return (reader.readString(offset)) as P;
    case 3:
      return (reader.readLong(offset)) as P;
    case 4:
      return (reader.readString(offset)) as P;
    case 5:
      return (reader.readStringList(offset) ?? []) as P;
    case 6:
      return (reader.readString(offset)) as P;
    case 7:
      return (reader.readString(offset)) as P;
    case 8:
      return (reader.readString(offset)) as P;
    case 9:
      return (reader.readString(offset)) as P;
    case 10:
      return (reader.readString(offset)) as P;
    case 11:
      return (reader.readString(offset)) as P;
    case 12:
      return (reader.readString(offset)) as P;
    case 13:
      return (reader.readString(offset)) as P;
    case 14:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _timetableEntryGetId(TimetableEntry object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _timetableEntryGetLinks(TimetableEntry object) {
  return [];
}

void _timetableEntryAttach(
    IsarCollection<dynamic> col, Id id, TimetableEntry object) {
  object.id = id;
}

extension TimetableEntryQueryWhereSort
    on QueryBuilder<TimetableEntry, TimetableEntry, QWhere> {
  QueryBuilder<TimetableEntry, TimetableEntry, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterWhere> anyDayOfWeek() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'dayOfWeek'),
      );
    });
  }
}

extension TimetableEntryQueryWhere
    on QueryBuilder<TimetableEntry, TimetableEntry, QWhereClause> {
  QueryBuilder<TimetableEntry, TimetableEntry, QAfterWhereClause> idEqualTo(
      Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterWhereClause> idNotEqualTo(
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

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterWhereClause> idGreaterThan(
      Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterWhereClause> idLessThan(
      Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterWhereClause> idBetween(
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

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterWhereClause>
      dayOfWeekEqualTo(int dayOfWeek) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'dayOfWeek',
        value: [dayOfWeek],
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterWhereClause>
      dayOfWeekNotEqualTo(int dayOfWeek) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'dayOfWeek',
              lower: [],
              upper: [dayOfWeek],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'dayOfWeek',
              lower: [dayOfWeek],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'dayOfWeek',
              lower: [dayOfWeek],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'dayOfWeek',
              lower: [],
              upper: [dayOfWeek],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterWhereClause>
      dayOfWeekGreaterThan(
    int dayOfWeek, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'dayOfWeek',
        lower: [dayOfWeek],
        includeLower: include,
        upper: [],
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterWhereClause>
      dayOfWeekLessThan(
    int dayOfWeek, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'dayOfWeek',
        lower: [],
        upper: [dayOfWeek],
        includeUpper: include,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterWhereClause>
      dayOfWeekBetween(
    int lowerDayOfWeek,
    int upperDayOfWeek, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'dayOfWeek',
        lower: [lowerDayOfWeek],
        includeLower: includeLower,
        upper: [upperDayOfWeek],
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterWhereClause>
      startTimeEqualTo(String startTime) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'startTime',
        value: [startTime],
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterWhereClause>
      startTimeNotEqualTo(String startTime) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'startTime',
              lower: [],
              upper: [startTime],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'startTime',
              lower: [startTime],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'startTime',
              lower: [startTime],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'startTime',
              lower: [],
              upper: [startTime],
              includeUpper: false,
            ));
      }
    });
  }
}

extension TimetableEntryQueryFilter
    on QueryBuilder<TimetableEntry, TimetableEntry, QFilterCondition> {
  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      classTypeEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'classType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      classTypeGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'classType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      classTypeLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'classType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      classTypeBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'classType',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      classTypeStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'classType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      classTypeEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'classType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      classTypeContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'classType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      classTypeMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'classType',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      classTypeIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'classType',
        value: '',
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      classTypeIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'classType',
        value: '',
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      courseCodeEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'courseCode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      courseCodeGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'courseCode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      courseCodeLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'courseCode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      courseCodeBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'courseCode',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      courseCodeStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'courseCode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      courseCodeEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'courseCode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      courseCodeContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'courseCode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      courseCodeMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'courseCode',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      courseCodeIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'courseCode',
        value: '',
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      courseCodeIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'courseCode',
        value: '',
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
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

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
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

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
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

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
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

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
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

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
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

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      courseNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'courseName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      courseNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'courseName',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      courseNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'courseName',
        value: '',
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      courseNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'courseName',
        value: '',
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      dayOfWeekEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'dayOfWeek',
        value: value,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      dayOfWeekGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'dayOfWeek',
        value: value,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      dayOfWeekLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'dayOfWeek',
        value: value,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      dayOfWeekBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'dayOfWeek',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      endTimeEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'endTime',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      endTimeGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'endTime',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      endTimeLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'endTime',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      endTimeBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'endTime',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      endTimeStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'endTime',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      endTimeEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'endTime',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      endTimeContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'endTime',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      endTimeMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'endTime',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      endTimeIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'endTime',
        value: '',
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      endTimeIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'endTime',
        value: '',
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      facultyEmailsElementEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'facultyEmails',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      facultyEmailsElementGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'facultyEmails',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      facultyEmailsElementLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'facultyEmails',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      facultyEmailsElementBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'facultyEmails',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      facultyEmailsElementStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'facultyEmails',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      facultyEmailsElementEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'facultyEmails',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      facultyEmailsElementContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'facultyEmails',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      facultyEmailsElementMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'facultyEmails',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      facultyEmailsElementIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'facultyEmails',
        value: '',
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      facultyEmailsElementIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'facultyEmails',
        value: '',
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      facultyEmailsLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'facultyEmails',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      facultyEmailsIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'facultyEmails',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      facultyEmailsIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'facultyEmails',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      facultyEmailsLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'facultyEmails',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      facultyEmailsLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'facultyEmails',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      facultyEmailsLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'facultyEmails',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
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

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
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

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
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

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
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

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
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

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
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

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      facultyNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'facultyName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      facultyNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'facultyName',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      facultyNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'facultyName',
        value: '',
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      facultyNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'facultyName',
        value: '',
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition> idEqualTo(
      Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
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

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      idLessThan(
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

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition> idBetween(
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

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      roomNumberEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'roomNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      roomNumberGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'roomNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      roomNumberLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'roomNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      roomNumberBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'roomNumber',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      roomNumberStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'roomNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      roomNumberEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'roomNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      roomNumberContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'roomNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      roomNumberMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'roomNumber',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      roomNumberIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'roomNumber',
        value: '',
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      roomNumberIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'roomNumber',
        value: '',
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
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

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
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

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
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

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
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

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
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

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
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

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      sectionIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'sectionId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      sectionIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'sectionId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      sectionIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sectionId',
        value: '',
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      sectionIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'sectionId',
        value: '',
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      sectionNameEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sectionName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      sectionNameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'sectionName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      sectionNameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'sectionName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      sectionNameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'sectionName',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      sectionNameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'sectionName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      sectionNameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'sectionName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      sectionNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'sectionName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      sectionNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'sectionName',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      sectionNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sectionName',
        value: '',
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      sectionNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'sectionName',
        value: '',
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      slotIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'slotId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      slotIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'slotId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      slotIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'slotId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      slotIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'slotId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      slotIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'slotId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      slotIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'slotId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      slotIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'slotId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      slotIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'slotId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      slotIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'slotId',
        value: '',
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      slotIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'slotId',
        value: '',
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      slotTypeEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'slotType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      slotTypeGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'slotType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      slotTypeLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'slotType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      slotTypeBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'slotType',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      slotTypeStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'slotType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      slotTypeEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'slotType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      slotTypeContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'slotType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      slotTypeMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'slotType',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      slotTypeIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'slotType',
        value: '',
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      slotTypeIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'slotType',
        value: '',
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      startTimeEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'startTime',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      startTimeGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'startTime',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      startTimeLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'startTime',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      startTimeBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'startTime',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      startTimeStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'startTime',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      startTimeEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'startTime',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      startTimeContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'startTime',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      startTimeMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'startTime',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      startTimeIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'startTime',
        value: '',
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      startTimeIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'startTime',
        value: '',
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      subjectCodeEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'subjectCode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      subjectCodeGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'subjectCode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      subjectCodeLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'subjectCode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      subjectCodeBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'subjectCode',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      subjectCodeStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'subjectCode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      subjectCodeEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'subjectCode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      subjectCodeContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'subjectCode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      subjectCodeMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'subjectCode',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      subjectCodeIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'subjectCode',
        value: '',
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      subjectCodeIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'subjectCode',
        value: '',
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      subjectNameEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'subjectName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      subjectNameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'subjectName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      subjectNameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'subjectName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      subjectNameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'subjectName',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      subjectNameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'subjectName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      subjectNameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'subjectName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      subjectNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'subjectName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      subjectNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'subjectName',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      subjectNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'subjectName',
        value: '',
      ));
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterFilterCondition>
      subjectNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'subjectName',
        value: '',
      ));
    });
  }
}

extension TimetableEntryQueryObject
    on QueryBuilder<TimetableEntry, TimetableEntry, QFilterCondition> {}

extension TimetableEntryQueryLinks
    on QueryBuilder<TimetableEntry, TimetableEntry, QFilterCondition> {}

extension TimetableEntryQuerySortBy
    on QueryBuilder<TimetableEntry, TimetableEntry, QSortBy> {
  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy> sortByClassType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'classType', Sort.asc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy>
      sortByClassTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'classType', Sort.desc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy>
      sortByCourseCode() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'courseCode', Sort.asc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy>
      sortByCourseCodeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'courseCode', Sort.desc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy>
      sortByCourseName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'courseName', Sort.asc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy>
      sortByCourseNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'courseName', Sort.desc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy> sortByDayOfWeek() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dayOfWeek', Sort.asc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy>
      sortByDayOfWeekDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dayOfWeek', Sort.desc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy> sortByEndTime() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endTime', Sort.asc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy>
      sortByEndTimeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endTime', Sort.desc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy>
      sortByFacultyName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'facultyName', Sort.asc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy>
      sortByFacultyNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'facultyName', Sort.desc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy>
      sortByRoomNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'roomNumber', Sort.asc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy>
      sortByRoomNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'roomNumber', Sort.desc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy> sortBySectionId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sectionId', Sort.asc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy>
      sortBySectionIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sectionId', Sort.desc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy>
      sortBySectionName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sectionName', Sort.asc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy>
      sortBySectionNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sectionName', Sort.desc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy> sortBySlotId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'slotId', Sort.asc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy>
      sortBySlotIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'slotId', Sort.desc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy> sortBySlotType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'slotType', Sort.asc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy>
      sortBySlotTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'slotType', Sort.desc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy> sortByStartTime() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'startTime', Sort.asc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy>
      sortByStartTimeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'startTime', Sort.desc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy>
      sortBySubjectCode() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'subjectCode', Sort.asc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy>
      sortBySubjectCodeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'subjectCode', Sort.desc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy>
      sortBySubjectName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'subjectName', Sort.asc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy>
      sortBySubjectNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'subjectName', Sort.desc);
    });
  }
}

extension TimetableEntryQuerySortThenBy
    on QueryBuilder<TimetableEntry, TimetableEntry, QSortThenBy> {
  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy> thenByClassType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'classType', Sort.asc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy>
      thenByClassTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'classType', Sort.desc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy>
      thenByCourseCode() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'courseCode', Sort.asc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy>
      thenByCourseCodeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'courseCode', Sort.desc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy>
      thenByCourseName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'courseName', Sort.asc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy>
      thenByCourseNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'courseName', Sort.desc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy> thenByDayOfWeek() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dayOfWeek', Sort.asc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy>
      thenByDayOfWeekDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dayOfWeek', Sort.desc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy> thenByEndTime() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endTime', Sort.asc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy>
      thenByEndTimeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endTime', Sort.desc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy>
      thenByFacultyName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'facultyName', Sort.asc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy>
      thenByFacultyNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'facultyName', Sort.desc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy>
      thenByRoomNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'roomNumber', Sort.asc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy>
      thenByRoomNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'roomNumber', Sort.desc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy> thenBySectionId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sectionId', Sort.asc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy>
      thenBySectionIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sectionId', Sort.desc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy>
      thenBySectionName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sectionName', Sort.asc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy>
      thenBySectionNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sectionName', Sort.desc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy> thenBySlotId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'slotId', Sort.asc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy>
      thenBySlotIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'slotId', Sort.desc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy> thenBySlotType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'slotType', Sort.asc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy>
      thenBySlotTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'slotType', Sort.desc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy> thenByStartTime() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'startTime', Sort.asc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy>
      thenByStartTimeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'startTime', Sort.desc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy>
      thenBySubjectCode() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'subjectCode', Sort.asc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy>
      thenBySubjectCodeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'subjectCode', Sort.desc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy>
      thenBySubjectName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'subjectName', Sort.asc);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QAfterSortBy>
      thenBySubjectNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'subjectName', Sort.desc);
    });
  }
}

extension TimetableEntryQueryWhereDistinct
    on QueryBuilder<TimetableEntry, TimetableEntry, QDistinct> {
  QueryBuilder<TimetableEntry, TimetableEntry, QDistinct> distinctByClassType(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'classType', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QDistinct> distinctByCourseCode(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'courseCode', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QDistinct> distinctByCourseName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'courseName', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QDistinct>
      distinctByDayOfWeek() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'dayOfWeek');
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QDistinct> distinctByEndTime(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'endTime', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QDistinct>
      distinctByFacultyEmails() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'facultyEmails');
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QDistinct> distinctByFacultyName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'facultyName', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QDistinct> distinctByRoomNumber(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'roomNumber', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QDistinct> distinctBySectionId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'sectionId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QDistinct> distinctBySectionName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'sectionName', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QDistinct> distinctBySlotId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'slotId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QDistinct> distinctBySlotType(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'slotType', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QDistinct> distinctByStartTime(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'startTime', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QDistinct> distinctBySubjectCode(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'subjectCode', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<TimetableEntry, TimetableEntry, QDistinct> distinctBySubjectName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'subjectName', caseSensitive: caseSensitive);
    });
  }
}

extension TimetableEntryQueryProperty
    on QueryBuilder<TimetableEntry, TimetableEntry, QQueryProperty> {
  QueryBuilder<TimetableEntry, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<TimetableEntry, String, QQueryOperations> classTypeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'classType');
    });
  }

  QueryBuilder<TimetableEntry, String, QQueryOperations> courseCodeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'courseCode');
    });
  }

  QueryBuilder<TimetableEntry, String, QQueryOperations> courseNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'courseName');
    });
  }

  QueryBuilder<TimetableEntry, int, QQueryOperations> dayOfWeekProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'dayOfWeek');
    });
  }

  QueryBuilder<TimetableEntry, String, QQueryOperations> endTimeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'endTime');
    });
  }

  QueryBuilder<TimetableEntry, List<String>, QQueryOperations>
      facultyEmailsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'facultyEmails');
    });
  }

  QueryBuilder<TimetableEntry, String, QQueryOperations> facultyNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'facultyName');
    });
  }

  QueryBuilder<TimetableEntry, String, QQueryOperations> roomNumberProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'roomNumber');
    });
  }

  QueryBuilder<TimetableEntry, String, QQueryOperations> sectionIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'sectionId');
    });
  }

  QueryBuilder<TimetableEntry, String, QQueryOperations> sectionNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'sectionName');
    });
  }

  QueryBuilder<TimetableEntry, String, QQueryOperations> slotIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'slotId');
    });
  }

  QueryBuilder<TimetableEntry, String, QQueryOperations> slotTypeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'slotType');
    });
  }

  QueryBuilder<TimetableEntry, String, QQueryOperations> startTimeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'startTime');
    });
  }

  QueryBuilder<TimetableEntry, String, QQueryOperations> subjectCodeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'subjectCode');
    });
  }

  QueryBuilder<TimetableEntry, String, QQueryOperations> subjectNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'subjectName');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetHydrationProfileCollection on Isar {
  IsarCollection<HydrationProfile> get hydrationProfiles => this.collection();
}

const HydrationProfileSchema = CollectionSchema(
  name: r'HydrationProfile',
  id: -7112348308411187072,
  properties: {
    r'boardId': PropertySchema(
      id: 0,
      name: r'boardId',
      type: IsarType.string,
    ),
    r'boardName': PropertySchema(
      id: 1,
      name: r'boardName',
      type: IsarType.string,
    ),
    r'building': PropertySchema(
      id: 2,
      name: r'building',
      type: IsarType.string,
    ),
    r'floor': PropertySchema(
      id: 3,
      name: r'floor',
      type: IsarType.string,
    ),
    r'institutionId': PropertySchema(
      id: 4,
      name: r'institutionId',
      type: IsarType.string,
    ),
    r'institutionName': PropertySchema(
      id: 5,
      name: r'institutionName',
      type: IsarType.string,
    ),
    r'isRegistered': PropertySchema(
      id: 6,
      name: r'isRegistered',
      type: IsarType.bool,
    ),
    r'roomId': PropertySchema(
      id: 7,
      name: r'roomId',
      type: IsarType.string,
    ),
    r'roomNumber': PropertySchema(
      id: 8,
      name: r'roomNumber',
      type: IsarType.string,
    ),
    r'timezone': PropertySchema(
      id: 9,
      name: r'timezone',
      type: IsarType.string,
    )
  },
  estimateSize: _hydrationProfileEstimateSize,
  serialize: _hydrationProfileSerialize,
  deserialize: _hydrationProfileDeserialize,
  deserializeProp: _hydrationProfileDeserializeProp,
  idName: r'id',
  indexes: {},
  links: {},
  embeddedSchemas: {},
  getId: _hydrationProfileGetId,
  getLinks: _hydrationProfileGetLinks,
  attach: _hydrationProfileAttach,
  version: '3.1.0+1',
);

int _hydrationProfileEstimateSize(
  HydrationProfile object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.boardId.length * 3;
  bytesCount += 3 + object.boardName.length * 3;
  {
    final value = object.building;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.floor;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.institutionId;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.institutionName;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.roomId.length * 3;
  {
    final value = object.roomNumber;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.timezone;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  return bytesCount;
}

void _hydrationProfileSerialize(
  HydrationProfile object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.boardId);
  writer.writeString(offsets[1], object.boardName);
  writer.writeString(offsets[2], object.building);
  writer.writeString(offsets[3], object.floor);
  writer.writeString(offsets[4], object.institutionId);
  writer.writeString(offsets[5], object.institutionName);
  writer.writeBool(offsets[6], object.isRegistered);
  writer.writeString(offsets[7], object.roomId);
  writer.writeString(offsets[8], object.roomNumber);
  writer.writeString(offsets[9], object.timezone);
}

HydrationProfile _hydrationProfileDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = HydrationProfile();
  object.boardId = reader.readString(offsets[0]);
  object.boardName = reader.readString(offsets[1]);
  object.building = reader.readStringOrNull(offsets[2]);
  object.floor = reader.readStringOrNull(offsets[3]);
  object.id = id;
  object.institutionId = reader.readStringOrNull(offsets[4]);
  object.institutionName = reader.readStringOrNull(offsets[5]);
  object.isRegistered = reader.readBool(offsets[6]);
  object.roomId = reader.readString(offsets[7]);
  object.roomNumber = reader.readStringOrNull(offsets[8]);
  object.timezone = reader.readStringOrNull(offsets[9]);
  return object;
}

P _hydrationProfileDeserializeProp<P>(
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
      return (reader.readStringOrNull(offset)) as P;
    case 3:
      return (reader.readStringOrNull(offset)) as P;
    case 4:
      return (reader.readStringOrNull(offset)) as P;
    case 5:
      return (reader.readStringOrNull(offset)) as P;
    case 6:
      return (reader.readBool(offset)) as P;
    case 7:
      return (reader.readString(offset)) as P;
    case 8:
      return (reader.readStringOrNull(offset)) as P;
    case 9:
      return (reader.readStringOrNull(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _hydrationProfileGetId(HydrationProfile object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _hydrationProfileGetLinks(HydrationProfile object) {
  return [];
}

void _hydrationProfileAttach(
    IsarCollection<dynamic> col, Id id, HydrationProfile object) {
  object.id = id;
}

extension HydrationProfileQueryWhereSort
    on QueryBuilder<HydrationProfile, HydrationProfile, QWhere> {
  QueryBuilder<HydrationProfile, HydrationProfile, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension HydrationProfileQueryWhere
    on QueryBuilder<HydrationProfile, HydrationProfile, QWhereClause> {
  QueryBuilder<HydrationProfile, HydrationProfile, QAfterWhereClause> idEqualTo(
      Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterWhereClause>
      idNotEqualTo(Id id) {
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

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterWhereClause>
      idGreaterThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterWhereClause>
      idLessThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterWhereClause> idBetween(
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

extension HydrationProfileQueryFilter
    on QueryBuilder<HydrationProfile, HydrationProfile, QFilterCondition> {
  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      boardIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'boardId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      boardIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'boardId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      boardIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'boardId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      boardIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'boardId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      boardIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'boardId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      boardIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'boardId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      boardIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'boardId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      boardIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'boardId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      boardIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'boardId',
        value: '',
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      boardIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'boardId',
        value: '',
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      boardNameEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'boardName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      boardNameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'boardName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      boardNameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'boardName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      boardNameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'boardName',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      boardNameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'boardName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      boardNameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'boardName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      boardNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'boardName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      boardNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'boardName',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      boardNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'boardName',
        value: '',
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      boardNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'boardName',
        value: '',
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      buildingIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'building',
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      buildingIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'building',
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      buildingEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'building',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      buildingGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'building',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      buildingLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'building',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      buildingBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'building',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      buildingStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'building',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      buildingEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'building',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      buildingContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'building',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      buildingMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'building',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      buildingIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'building',
        value: '',
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      buildingIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'building',
        value: '',
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      floorIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'floor',
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      floorIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'floor',
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      floorEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'floor',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      floorGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'floor',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      floorLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'floor',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      floorBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'floor',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      floorStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'floor',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      floorEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'floor',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      floorContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'floor',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      floorMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'floor',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      floorIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'floor',
        value: '',
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      floorIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'floor',
        value: '',
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
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

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      idLessThan(
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

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      idBetween(
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

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      institutionIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'institutionId',
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      institutionIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'institutionId',
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      institutionIdEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'institutionId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      institutionIdGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'institutionId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      institutionIdLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'institutionId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      institutionIdBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'institutionId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      institutionIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'institutionId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      institutionIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'institutionId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      institutionIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'institutionId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      institutionIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'institutionId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      institutionIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'institutionId',
        value: '',
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      institutionIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'institutionId',
        value: '',
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      institutionNameIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'institutionName',
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      institutionNameIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'institutionName',
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      institutionNameEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'institutionName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      institutionNameGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'institutionName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      institutionNameLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'institutionName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      institutionNameBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'institutionName',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      institutionNameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'institutionName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      institutionNameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'institutionName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      institutionNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'institutionName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      institutionNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'institutionName',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      institutionNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'institutionName',
        value: '',
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      institutionNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'institutionName',
        value: '',
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      isRegisteredEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isRegistered',
        value: value,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      roomIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'roomId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      roomIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'roomId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      roomIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'roomId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      roomIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'roomId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      roomIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'roomId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      roomIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'roomId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      roomIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'roomId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      roomIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'roomId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      roomIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'roomId',
        value: '',
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      roomIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'roomId',
        value: '',
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      roomNumberIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'roomNumber',
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      roomNumberIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'roomNumber',
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      roomNumberEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'roomNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      roomNumberGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'roomNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      roomNumberLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'roomNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      roomNumberBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'roomNumber',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      roomNumberStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'roomNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      roomNumberEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'roomNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      roomNumberContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'roomNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      roomNumberMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'roomNumber',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      roomNumberIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'roomNumber',
        value: '',
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      roomNumberIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'roomNumber',
        value: '',
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      timezoneIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'timezone',
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      timezoneIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'timezone',
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      timezoneEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'timezone',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      timezoneGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'timezone',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      timezoneLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'timezone',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      timezoneBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'timezone',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      timezoneStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'timezone',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      timezoneEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'timezone',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      timezoneContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'timezone',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      timezoneMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'timezone',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      timezoneIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'timezone',
        value: '',
      ));
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterFilterCondition>
      timezoneIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'timezone',
        value: '',
      ));
    });
  }
}

extension HydrationProfileQueryObject
    on QueryBuilder<HydrationProfile, HydrationProfile, QFilterCondition> {}

extension HydrationProfileQueryLinks
    on QueryBuilder<HydrationProfile, HydrationProfile, QFilterCondition> {}

extension HydrationProfileQuerySortBy
    on QueryBuilder<HydrationProfile, HydrationProfile, QSortBy> {
  QueryBuilder<HydrationProfile, HydrationProfile, QAfterSortBy>
      sortByBoardId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'boardId', Sort.asc);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterSortBy>
      sortByBoardIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'boardId', Sort.desc);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterSortBy>
      sortByBoardName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'boardName', Sort.asc);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterSortBy>
      sortByBoardNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'boardName', Sort.desc);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterSortBy>
      sortByBuilding() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'building', Sort.asc);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterSortBy>
      sortByBuildingDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'building', Sort.desc);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterSortBy> sortByFloor() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'floor', Sort.asc);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterSortBy>
      sortByFloorDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'floor', Sort.desc);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterSortBy>
      sortByInstitutionId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'institutionId', Sort.asc);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterSortBy>
      sortByInstitutionIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'institutionId', Sort.desc);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterSortBy>
      sortByInstitutionName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'institutionName', Sort.asc);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterSortBy>
      sortByInstitutionNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'institutionName', Sort.desc);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterSortBy>
      sortByIsRegistered() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isRegistered', Sort.asc);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterSortBy>
      sortByIsRegisteredDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isRegistered', Sort.desc);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterSortBy>
      sortByRoomId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'roomId', Sort.asc);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterSortBy>
      sortByRoomIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'roomId', Sort.desc);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterSortBy>
      sortByRoomNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'roomNumber', Sort.asc);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterSortBy>
      sortByRoomNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'roomNumber', Sort.desc);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterSortBy>
      sortByTimezone() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'timezone', Sort.asc);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterSortBy>
      sortByTimezoneDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'timezone', Sort.desc);
    });
  }
}

extension HydrationProfileQuerySortThenBy
    on QueryBuilder<HydrationProfile, HydrationProfile, QSortThenBy> {
  QueryBuilder<HydrationProfile, HydrationProfile, QAfterSortBy>
      thenByBoardId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'boardId', Sort.asc);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterSortBy>
      thenByBoardIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'boardId', Sort.desc);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterSortBy>
      thenByBoardName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'boardName', Sort.asc);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterSortBy>
      thenByBoardNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'boardName', Sort.desc);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterSortBy>
      thenByBuilding() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'building', Sort.asc);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterSortBy>
      thenByBuildingDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'building', Sort.desc);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterSortBy> thenByFloor() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'floor', Sort.asc);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterSortBy>
      thenByFloorDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'floor', Sort.desc);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterSortBy>
      thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterSortBy>
      thenByInstitutionId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'institutionId', Sort.asc);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterSortBy>
      thenByInstitutionIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'institutionId', Sort.desc);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterSortBy>
      thenByInstitutionName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'institutionName', Sort.asc);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterSortBy>
      thenByInstitutionNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'institutionName', Sort.desc);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterSortBy>
      thenByIsRegistered() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isRegistered', Sort.asc);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterSortBy>
      thenByIsRegisteredDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isRegistered', Sort.desc);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterSortBy>
      thenByRoomId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'roomId', Sort.asc);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterSortBy>
      thenByRoomIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'roomId', Sort.desc);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterSortBy>
      thenByRoomNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'roomNumber', Sort.asc);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterSortBy>
      thenByRoomNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'roomNumber', Sort.desc);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterSortBy>
      thenByTimezone() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'timezone', Sort.asc);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QAfterSortBy>
      thenByTimezoneDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'timezone', Sort.desc);
    });
  }
}

extension HydrationProfileQueryWhereDistinct
    on QueryBuilder<HydrationProfile, HydrationProfile, QDistinct> {
  QueryBuilder<HydrationProfile, HydrationProfile, QDistinct> distinctByBoardId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'boardId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QDistinct>
      distinctByBoardName({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'boardName', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QDistinct>
      distinctByBuilding({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'building', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QDistinct> distinctByFloor(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'floor', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QDistinct>
      distinctByInstitutionId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'institutionId',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QDistinct>
      distinctByInstitutionName({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'institutionName',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QDistinct>
      distinctByIsRegistered() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isRegistered');
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QDistinct> distinctByRoomId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'roomId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QDistinct>
      distinctByRoomNumber({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'roomNumber', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<HydrationProfile, HydrationProfile, QDistinct>
      distinctByTimezone({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'timezone', caseSensitive: caseSensitive);
    });
  }
}

extension HydrationProfileQueryProperty
    on QueryBuilder<HydrationProfile, HydrationProfile, QQueryProperty> {
  QueryBuilder<HydrationProfile, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<HydrationProfile, String, QQueryOperations> boardIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'boardId');
    });
  }

  QueryBuilder<HydrationProfile, String, QQueryOperations> boardNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'boardName');
    });
  }

  QueryBuilder<HydrationProfile, String?, QQueryOperations> buildingProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'building');
    });
  }

  QueryBuilder<HydrationProfile, String?, QQueryOperations> floorProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'floor');
    });
  }

  QueryBuilder<HydrationProfile, String?, QQueryOperations>
      institutionIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'institutionId');
    });
  }

  QueryBuilder<HydrationProfile, String?, QQueryOperations>
      institutionNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'institutionName');
    });
  }

  QueryBuilder<HydrationProfile, bool, QQueryOperations>
      isRegisteredProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isRegistered');
    });
  }

  QueryBuilder<HydrationProfile, String, QQueryOperations> roomIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'roomId');
    });
  }

  QueryBuilder<HydrationProfile, String?, QQueryOperations>
      roomNumberProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'roomNumber');
    });
  }

  QueryBuilder<HydrationProfile, String?, QQueryOperations> timezoneProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'timezone');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetHydrationRosterCollection on Isar {
  IsarCollection<HydrationRoster> get hydrationRosters => this.collection();
}

const HydrationRosterSchema = CollectionSchema(
  name: r'HydrationRoster',
  id: -4203312746987116354,
  properties: {
    r'name': PropertySchema(
      id: 0,
      name: r'name',
      type: IsarType.string,
    ),
    r'rollNumber': PropertySchema(
      id: 1,
      name: r'rollNumber',
      type: IsarType.string,
    ),
    r'rosterKey': PropertySchema(
      id: 2,
      name: r'rosterKey',
      type: IsarType.string,
    ),
    r'studentId': PropertySchema(
      id: 3,
      name: r'studentId',
      type: IsarType.string,
    )
  },
  estimateSize: _hydrationRosterEstimateSize,
  serialize: _hydrationRosterSerialize,
  deserialize: _hydrationRosterDeserialize,
  deserializeProp: _hydrationRosterDeserializeProp,
  idName: r'id',
  indexes: {
    r'rosterKey': IndexSchema(
      id: -1260579504002278642,
      name: r'rosterKey',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'rosterKey',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _hydrationRosterGetId,
  getLinks: _hydrationRosterGetLinks,
  attach: _hydrationRosterAttach,
  version: '3.1.0+1',
);

int _hydrationRosterEstimateSize(
  HydrationRoster object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.name.length * 3;
  {
    final value = object.rollNumber;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.rosterKey.length * 3;
  bytesCount += 3 + object.studentId.length * 3;
  return bytesCount;
}

void _hydrationRosterSerialize(
  HydrationRoster object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.name);
  writer.writeString(offsets[1], object.rollNumber);
  writer.writeString(offsets[2], object.rosterKey);
  writer.writeString(offsets[3], object.studentId);
}

HydrationRoster _hydrationRosterDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = HydrationRoster();
  object.id = id;
  object.name = reader.readString(offsets[0]);
  object.rollNumber = reader.readStringOrNull(offsets[1]);
  object.rosterKey = reader.readString(offsets[2]);
  object.studentId = reader.readString(offsets[3]);
  return object;
}

P _hydrationRosterDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readString(offset)) as P;
    case 1:
      return (reader.readStringOrNull(offset)) as P;
    case 2:
      return (reader.readString(offset)) as P;
    case 3:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _hydrationRosterGetId(HydrationRoster object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _hydrationRosterGetLinks(HydrationRoster object) {
  return [];
}

void _hydrationRosterAttach(
    IsarCollection<dynamic> col, Id id, HydrationRoster object) {
  object.id = id;
}

extension HydrationRosterQueryWhereSort
    on QueryBuilder<HydrationRoster, HydrationRoster, QWhere> {
  QueryBuilder<HydrationRoster, HydrationRoster, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension HydrationRosterQueryWhere
    on QueryBuilder<HydrationRoster, HydrationRoster, QWhereClause> {
  QueryBuilder<HydrationRoster, HydrationRoster, QAfterWhereClause> idEqualTo(
      Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterWhereClause>
      idNotEqualTo(Id id) {
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

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterWhereClause>
      idGreaterThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterWhereClause> idLessThan(
      Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterWhereClause> idBetween(
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

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterWhereClause>
      rosterKeyEqualTo(String rosterKey) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'rosterKey',
        value: [rosterKey],
      ));
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterWhereClause>
      rosterKeyNotEqualTo(String rosterKey) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'rosterKey',
              lower: [],
              upper: [rosterKey],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'rosterKey',
              lower: [rosterKey],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'rosterKey',
              lower: [rosterKey],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'rosterKey',
              lower: [],
              upper: [rosterKey],
              includeUpper: false,
            ));
      }
    });
  }
}

extension HydrationRosterQueryFilter
    on QueryBuilder<HydrationRoster, HydrationRoster, QFilterCondition> {
  QueryBuilder<HydrationRoster, HydrationRoster, QAfterFilterCondition>
      idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterFilterCondition>
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

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterFilterCondition>
      idLessThan(
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

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterFilterCondition>
      idBetween(
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

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterFilterCondition>
      nameEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterFilterCondition>
      nameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterFilterCondition>
      nameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterFilterCondition>
      nameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'name',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterFilterCondition>
      nameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterFilterCondition>
      nameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterFilterCondition>
      nameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterFilterCondition>
      nameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'name',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterFilterCondition>
      nameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'name',
        value: '',
      ));
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterFilterCondition>
      nameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'name',
        value: '',
      ));
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterFilterCondition>
      rollNumberIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'rollNumber',
      ));
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterFilterCondition>
      rollNumberIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'rollNumber',
      ));
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterFilterCondition>
      rollNumberEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'rollNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterFilterCondition>
      rollNumberGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'rollNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterFilterCondition>
      rollNumberLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'rollNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterFilterCondition>
      rollNumberBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'rollNumber',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterFilterCondition>
      rollNumberStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'rollNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterFilterCondition>
      rollNumberEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'rollNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterFilterCondition>
      rollNumberContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'rollNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterFilterCondition>
      rollNumberMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'rollNumber',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterFilterCondition>
      rollNumberIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'rollNumber',
        value: '',
      ));
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterFilterCondition>
      rollNumberIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'rollNumber',
        value: '',
      ));
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterFilterCondition>
      rosterKeyEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'rosterKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterFilterCondition>
      rosterKeyGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'rosterKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterFilterCondition>
      rosterKeyLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'rosterKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterFilterCondition>
      rosterKeyBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'rosterKey',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterFilterCondition>
      rosterKeyStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'rosterKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterFilterCondition>
      rosterKeyEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'rosterKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterFilterCondition>
      rosterKeyContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'rosterKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterFilterCondition>
      rosterKeyMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'rosterKey',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterFilterCondition>
      rosterKeyIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'rosterKey',
        value: '',
      ));
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterFilterCondition>
      rosterKeyIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'rosterKey',
        value: '',
      ));
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterFilterCondition>
      studentIdEqualTo(
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

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterFilterCondition>
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

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterFilterCondition>
      studentIdLessThan(
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

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterFilterCondition>
      studentIdBetween(
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

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterFilterCondition>
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

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterFilterCondition>
      studentIdEndsWith(
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

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterFilterCondition>
      studentIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'studentId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterFilterCondition>
      studentIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'studentId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterFilterCondition>
      studentIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'studentId',
        value: '',
      ));
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterFilterCondition>
      studentIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'studentId',
        value: '',
      ));
    });
  }
}

extension HydrationRosterQueryObject
    on QueryBuilder<HydrationRoster, HydrationRoster, QFilterCondition> {}

extension HydrationRosterQueryLinks
    on QueryBuilder<HydrationRoster, HydrationRoster, QFilterCondition> {}

extension HydrationRosterQuerySortBy
    on QueryBuilder<HydrationRoster, HydrationRoster, QSortBy> {
  QueryBuilder<HydrationRoster, HydrationRoster, QAfterSortBy> sortByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterSortBy>
      sortByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterSortBy>
      sortByRollNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'rollNumber', Sort.asc);
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterSortBy>
      sortByRollNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'rollNumber', Sort.desc);
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterSortBy>
      sortByRosterKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'rosterKey', Sort.asc);
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterSortBy>
      sortByRosterKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'rosterKey', Sort.desc);
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterSortBy>
      sortByStudentId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'studentId', Sort.asc);
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterSortBy>
      sortByStudentIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'studentId', Sort.desc);
    });
  }
}

extension HydrationRosterQuerySortThenBy
    on QueryBuilder<HydrationRoster, HydrationRoster, QSortThenBy> {
  QueryBuilder<HydrationRoster, HydrationRoster, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterSortBy> thenByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterSortBy>
      thenByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterSortBy>
      thenByRollNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'rollNumber', Sort.asc);
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterSortBy>
      thenByRollNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'rollNumber', Sort.desc);
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterSortBy>
      thenByRosterKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'rosterKey', Sort.asc);
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterSortBy>
      thenByRosterKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'rosterKey', Sort.desc);
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterSortBy>
      thenByStudentId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'studentId', Sort.asc);
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QAfterSortBy>
      thenByStudentIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'studentId', Sort.desc);
    });
  }
}

extension HydrationRosterQueryWhereDistinct
    on QueryBuilder<HydrationRoster, HydrationRoster, QDistinct> {
  QueryBuilder<HydrationRoster, HydrationRoster, QDistinct> distinctByName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'name', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QDistinct>
      distinctByRollNumber({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'rollNumber', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QDistinct> distinctByRosterKey(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'rosterKey', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<HydrationRoster, HydrationRoster, QDistinct> distinctByStudentId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'studentId', caseSensitive: caseSensitive);
    });
  }
}

extension HydrationRosterQueryProperty
    on QueryBuilder<HydrationRoster, HydrationRoster, QQueryProperty> {
  QueryBuilder<HydrationRoster, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<HydrationRoster, String, QQueryOperations> nameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'name');
    });
  }

  QueryBuilder<HydrationRoster, String?, QQueryOperations>
      rollNumberProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'rollNumber');
    });
  }

  QueryBuilder<HydrationRoster, String, QQueryOperations> rosterKeyProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'rosterKey');
    });
  }

  QueryBuilder<HydrationRoster, String, QQueryOperations> studentIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'studentId');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetStoredNotificationCollection on Isar {
  IsarCollection<StoredNotification> get storedNotifications =>
      this.collection();
}

const StoredNotificationSchema = CollectionSchema(
  name: r'StoredNotification',
  id: 2191948281567647997,
  properties: {
    r'assemblyPoint': PropertySchema(
      id: 0,
      name: r'assemblyPoint',
      type: IsarType.string,
    ),
    r'attachmentName': PropertySchema(
      id: 1,
      name: r'attachmentName',
      type: IsarType.string,
    ),
    r'attachmentSize': PropertySchema(
      id: 2,
      name: r'attachmentSize',
      type: IsarType.long,
    ),
    r'attachmentType': PropertySchema(
      id: 3,
      name: r'attachmentType',
      type: IsarType.string,
    ),
    r'attachmentUrl': PropertySchema(
      id: 4,
      name: r'attachmentUrl',
      type: IsarType.string,
    ),
    r'body': PropertySchema(
      id: 5,
      name: r'body',
      type: IsarType.string,
    ),
    r'courseName': PropertySchema(
      id: 6,
      name: r'courseName',
      type: IsarType.string,
    ),
    r'displayMode': PropertySchema(
      id: 7,
      name: r'displayMode',
      type: IsarType.string,
    ),
    r'durationSeconds': PropertySchema(
      id: 8,
      name: r'durationSeconds',
      type: IsarType.long,
    ),
    r'facultyName': PropertySchema(
      id: 9,
      name: r'facultyName',
      type: IsarType.string,
    ),
    r'localId': PropertySchema(
      id: 10,
      name: r'localId',
      type: IsarType.string,
    ),
    r'location': PropertySchema(
      id: 11,
      name: r'location',
      type: IsarType.string,
    ),
    r'notificationId': PropertySchema(
      id: 12,
      name: r'notificationId',
      type: IsarType.string,
    ),
    r'precautionarySteps': PropertySchema(
      id: 13,
      name: r'precautionarySteps',
      type: IsarType.stringList,
    ),
    r'priority': PropertySchema(
      id: 14,
      name: r'priority',
      type: IsarType.string,
    ),
    r'read': PropertySchema(
      id: 15,
      name: r'read',
      type: IsarType.bool,
    ),
    r'requiresAcknowledgement': PropertySchema(
      id: 16,
      name: r'requiresAcknowledgement',
      type: IsarType.bool,
    ),
    r'roomNumber': PropertySchema(
      id: 17,
      name: r'roomNumber',
      type: IsarType.string,
    ),
    r'safeExit': PropertySchema(
      id: 18,
      name: r'safeExit',
      type: IsarType.string,
    ),
    r'sectionId': PropertySchema(
      id: 19,
      name: r'sectionId',
      type: IsarType.string,
    ),
    r'slotId': PropertySchema(
      id: 20,
      name: r'slotId',
      type: IsarType.string,
    ),
    r'storedAt': PropertySchema(
      id: 21,
      name: r'storedAt',
      type: IsarType.dateTime,
    ),
    r'timestamp': PropertySchema(
      id: 22,
      name: r'timestamp',
      type: IsarType.dateTime,
    ),
    r'title': PropertySchema(
      id: 23,
      name: r'title',
      type: IsarType.string,
    ),
    r'type': PropertySchema(
      id: 24,
      name: r'type',
      type: IsarType.string,
    )
  },
  estimateSize: _storedNotificationEstimateSize,
  serialize: _storedNotificationSerialize,
  deserialize: _storedNotificationDeserialize,
  deserializeProp: _storedNotificationDeserializeProp,
  idName: r'id',
  indexes: {
    r'notificationId': IndexSchema(
      id: 1533036797414670656,
      name: r'notificationId',
      unique: true,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'notificationId',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _storedNotificationGetId,
  getLinks: _storedNotificationGetLinks,
  attach: _storedNotificationAttach,
  version: '3.1.0+1',
);

int _storedNotificationEstimateSize(
  StoredNotification object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  {
    final value = object.assemblyPoint;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.attachmentName;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.attachmentType;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.attachmentUrl;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.body.length * 3;
  {
    final value = object.courseName;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.displayMode;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.facultyName;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.localId.length * 3;
  {
    final value = object.location;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.notificationId.length * 3;
  bytesCount += 3 + object.precautionarySteps.length * 3;
  {
    for (var i = 0; i < object.precautionarySteps.length; i++) {
      final value = object.precautionarySteps[i];
      bytesCount += value.length * 3;
    }
  }
  bytesCount += 3 + object.priority.length * 3;
  {
    final value = object.roomNumber;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.safeExit;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.sectionId;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.slotId;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.title.length * 3;
  bytesCount += 3 + object.type.length * 3;
  return bytesCount;
}

void _storedNotificationSerialize(
  StoredNotification object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.assemblyPoint);
  writer.writeString(offsets[1], object.attachmentName);
  writer.writeLong(offsets[2], object.attachmentSize);
  writer.writeString(offsets[3], object.attachmentType);
  writer.writeString(offsets[4], object.attachmentUrl);
  writer.writeString(offsets[5], object.body);
  writer.writeString(offsets[6], object.courseName);
  writer.writeString(offsets[7], object.displayMode);
  writer.writeLong(offsets[8], object.durationSeconds);
  writer.writeString(offsets[9], object.facultyName);
  writer.writeString(offsets[10], object.localId);
  writer.writeString(offsets[11], object.location);
  writer.writeString(offsets[12], object.notificationId);
  writer.writeStringList(offsets[13], object.precautionarySteps);
  writer.writeString(offsets[14], object.priority);
  writer.writeBool(offsets[15], object.read);
  writer.writeBool(offsets[16], object.requiresAcknowledgement);
  writer.writeString(offsets[17], object.roomNumber);
  writer.writeString(offsets[18], object.safeExit);
  writer.writeString(offsets[19], object.sectionId);
  writer.writeString(offsets[20], object.slotId);
  writer.writeDateTime(offsets[21], object.storedAt);
  writer.writeDateTime(offsets[22], object.timestamp);
  writer.writeString(offsets[23], object.title);
  writer.writeString(offsets[24], object.type);
}

StoredNotification _storedNotificationDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = StoredNotification();
  object.assemblyPoint = reader.readStringOrNull(offsets[0]);
  object.attachmentName = reader.readStringOrNull(offsets[1]);
  object.attachmentSize = reader.readLongOrNull(offsets[2]);
  object.attachmentType = reader.readStringOrNull(offsets[3]);
  object.attachmentUrl = reader.readStringOrNull(offsets[4]);
  object.body = reader.readString(offsets[5]);
  object.courseName = reader.readStringOrNull(offsets[6]);
  object.displayMode = reader.readStringOrNull(offsets[7]);
  object.durationSeconds = reader.readLongOrNull(offsets[8]);
  object.facultyName = reader.readStringOrNull(offsets[9]);
  object.id = id;
  object.localId = reader.readString(offsets[10]);
  object.location = reader.readStringOrNull(offsets[11]);
  object.notificationId = reader.readString(offsets[12]);
  object.precautionarySteps = reader.readStringList(offsets[13]) ?? [];
  object.priority = reader.readString(offsets[14]);
  object.read = reader.readBool(offsets[15]);
  object.requiresAcknowledgement = reader.readBool(offsets[16]);
  object.roomNumber = reader.readStringOrNull(offsets[17]);
  object.safeExit = reader.readStringOrNull(offsets[18]);
  object.sectionId = reader.readStringOrNull(offsets[19]);
  object.slotId = reader.readStringOrNull(offsets[20]);
  object.storedAt = reader.readDateTime(offsets[21]);
  object.timestamp = reader.readDateTime(offsets[22]);
  object.title = reader.readString(offsets[23]);
  object.type = reader.readString(offsets[24]);
  return object;
}

P _storedNotificationDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readStringOrNull(offset)) as P;
    case 1:
      return (reader.readStringOrNull(offset)) as P;
    case 2:
      return (reader.readLongOrNull(offset)) as P;
    case 3:
      return (reader.readStringOrNull(offset)) as P;
    case 4:
      return (reader.readStringOrNull(offset)) as P;
    case 5:
      return (reader.readString(offset)) as P;
    case 6:
      return (reader.readStringOrNull(offset)) as P;
    case 7:
      return (reader.readStringOrNull(offset)) as P;
    case 8:
      return (reader.readLongOrNull(offset)) as P;
    case 9:
      return (reader.readStringOrNull(offset)) as P;
    case 10:
      return (reader.readString(offset)) as P;
    case 11:
      return (reader.readStringOrNull(offset)) as P;
    case 12:
      return (reader.readString(offset)) as P;
    case 13:
      return (reader.readStringList(offset) ?? []) as P;
    case 14:
      return (reader.readString(offset)) as P;
    case 15:
      return (reader.readBool(offset)) as P;
    case 16:
      return (reader.readBool(offset)) as P;
    case 17:
      return (reader.readStringOrNull(offset)) as P;
    case 18:
      return (reader.readStringOrNull(offset)) as P;
    case 19:
      return (reader.readStringOrNull(offset)) as P;
    case 20:
      return (reader.readStringOrNull(offset)) as P;
    case 21:
      return (reader.readDateTime(offset)) as P;
    case 22:
      return (reader.readDateTime(offset)) as P;
    case 23:
      return (reader.readString(offset)) as P;
    case 24:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _storedNotificationGetId(StoredNotification object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _storedNotificationGetLinks(
    StoredNotification object) {
  return [];
}

void _storedNotificationAttach(
    IsarCollection<dynamic> col, Id id, StoredNotification object) {
  object.id = id;
}

extension StoredNotificationByIndex on IsarCollection<StoredNotification> {
  Future<StoredNotification?> getByNotificationId(String notificationId) {
    return getByIndex(r'notificationId', [notificationId]);
  }

  StoredNotification? getByNotificationIdSync(String notificationId) {
    return getByIndexSync(r'notificationId', [notificationId]);
  }

  Future<bool> deleteByNotificationId(String notificationId) {
    return deleteByIndex(r'notificationId', [notificationId]);
  }

  bool deleteByNotificationIdSync(String notificationId) {
    return deleteByIndexSync(r'notificationId', [notificationId]);
  }

  Future<List<StoredNotification?>> getAllByNotificationId(
      List<String> notificationIdValues) {
    final values = notificationIdValues.map((e) => [e]).toList();
    return getAllByIndex(r'notificationId', values);
  }

  List<StoredNotification?> getAllByNotificationIdSync(
      List<String> notificationIdValues) {
    final values = notificationIdValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'notificationId', values);
  }

  Future<int> deleteAllByNotificationId(List<String> notificationIdValues) {
    final values = notificationIdValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'notificationId', values);
  }

  int deleteAllByNotificationIdSync(List<String> notificationIdValues) {
    final values = notificationIdValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'notificationId', values);
  }

  Future<Id> putByNotificationId(StoredNotification object) {
    return putByIndex(r'notificationId', object);
  }

  Id putByNotificationIdSync(StoredNotification object,
      {bool saveLinks = true}) {
    return putByIndexSync(r'notificationId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByNotificationId(List<StoredNotification> objects) {
    return putAllByIndex(r'notificationId', objects);
  }

  List<Id> putAllByNotificationIdSync(List<StoredNotification> objects,
      {bool saveLinks = true}) {
    return putAllByIndexSync(r'notificationId', objects, saveLinks: saveLinks);
  }
}

extension StoredNotificationQueryWhereSort
    on QueryBuilder<StoredNotification, StoredNotification, QWhere> {
  QueryBuilder<StoredNotification, StoredNotification, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension StoredNotificationQueryWhere
    on QueryBuilder<StoredNotification, StoredNotification, QWhereClause> {
  QueryBuilder<StoredNotification, StoredNotification, QAfterWhereClause>
      idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterWhereClause>
      idNotEqualTo(Id id) {
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

  QueryBuilder<StoredNotification, StoredNotification, QAfterWhereClause>
      idGreaterThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterWhereClause>
      idLessThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterWhereClause>
      idBetween(
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

  QueryBuilder<StoredNotification, StoredNotification, QAfterWhereClause>
      notificationIdEqualTo(String notificationId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'notificationId',
        value: [notificationId],
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterWhereClause>
      notificationIdNotEqualTo(String notificationId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'notificationId',
              lower: [],
              upper: [notificationId],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'notificationId',
              lower: [notificationId],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'notificationId',
              lower: [notificationId],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'notificationId',
              lower: [],
              upper: [notificationId],
              includeUpper: false,
            ));
      }
    });
  }
}

extension StoredNotificationQueryFilter
    on QueryBuilder<StoredNotification, StoredNotification, QFilterCondition> {
  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      assemblyPointIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'assemblyPoint',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      assemblyPointIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'assemblyPoint',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      assemblyPointEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'assemblyPoint',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      assemblyPointGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'assemblyPoint',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      assemblyPointLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'assemblyPoint',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      assemblyPointBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'assemblyPoint',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      assemblyPointStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'assemblyPoint',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      assemblyPointEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'assemblyPoint',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      assemblyPointContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'assemblyPoint',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      assemblyPointMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'assemblyPoint',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      assemblyPointIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'assemblyPoint',
        value: '',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      assemblyPointIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'assemblyPoint',
        value: '',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      attachmentNameIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'attachmentName',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      attachmentNameIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'attachmentName',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      attachmentNameEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'attachmentName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      attachmentNameGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'attachmentName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      attachmentNameLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'attachmentName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      attachmentNameBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'attachmentName',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      attachmentNameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'attachmentName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      attachmentNameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'attachmentName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      attachmentNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'attachmentName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      attachmentNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'attachmentName',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      attachmentNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'attachmentName',
        value: '',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      attachmentNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'attachmentName',
        value: '',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      attachmentSizeIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'attachmentSize',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      attachmentSizeIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'attachmentSize',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      attachmentSizeEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'attachmentSize',
        value: value,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      attachmentSizeGreaterThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'attachmentSize',
        value: value,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      attachmentSizeLessThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'attachmentSize',
        value: value,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      attachmentSizeBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'attachmentSize',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      attachmentTypeIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'attachmentType',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      attachmentTypeIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'attachmentType',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      attachmentTypeEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'attachmentType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      attachmentTypeGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'attachmentType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      attachmentTypeLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'attachmentType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      attachmentTypeBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'attachmentType',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      attachmentTypeStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'attachmentType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      attachmentTypeEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'attachmentType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      attachmentTypeContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'attachmentType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      attachmentTypeMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'attachmentType',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      attachmentTypeIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'attachmentType',
        value: '',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      attachmentTypeIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'attachmentType',
        value: '',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      attachmentUrlIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'attachmentUrl',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      attachmentUrlIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'attachmentUrl',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      attachmentUrlEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'attachmentUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      attachmentUrlGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'attachmentUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      attachmentUrlLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'attachmentUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      attachmentUrlBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'attachmentUrl',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      attachmentUrlStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'attachmentUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      attachmentUrlEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'attachmentUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      attachmentUrlContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'attachmentUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      attachmentUrlMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'attachmentUrl',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      attachmentUrlIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'attachmentUrl',
        value: '',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      attachmentUrlIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'attachmentUrl',
        value: '',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      bodyEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'body',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      bodyGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'body',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      bodyLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'body',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      bodyBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'body',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      bodyStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'body',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      bodyEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'body',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      bodyContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'body',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      bodyMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'body',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      bodyIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'body',
        value: '',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      bodyIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'body',
        value: '',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      courseNameIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'courseName',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      courseNameIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'courseName',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      courseNameEqualTo(
    String? value, {
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

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      courseNameGreaterThan(
    String? value, {
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

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      courseNameLessThan(
    String? value, {
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

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      courseNameBetween(
    String? lower,
    String? upper, {
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

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
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

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
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

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      courseNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'courseName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      courseNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'courseName',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      courseNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'courseName',
        value: '',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      courseNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'courseName',
        value: '',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      displayModeIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'displayMode',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      displayModeIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'displayMode',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      displayModeEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'displayMode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      displayModeGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'displayMode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      displayModeLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'displayMode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      displayModeBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'displayMode',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      displayModeStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'displayMode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      displayModeEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'displayMode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      displayModeContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'displayMode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      displayModeMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'displayMode',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      displayModeIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'displayMode',
        value: '',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      displayModeIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'displayMode',
        value: '',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      durationSecondsIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'durationSeconds',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      durationSecondsIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'durationSeconds',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      durationSecondsEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'durationSeconds',
        value: value,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      durationSecondsGreaterThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'durationSeconds',
        value: value,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      durationSecondsLessThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'durationSeconds',
        value: value,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      durationSecondsBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'durationSeconds',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      facultyNameIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'facultyName',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      facultyNameIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'facultyName',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      facultyNameEqualTo(
    String? value, {
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

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      facultyNameGreaterThan(
    String? value, {
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

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      facultyNameLessThan(
    String? value, {
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

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      facultyNameBetween(
    String? lower,
    String? upper, {
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

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
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

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
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

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      facultyNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'facultyName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      facultyNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'facultyName',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      facultyNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'facultyName',
        value: '',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      facultyNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'facultyName',
        value: '',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
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

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      idLessThan(
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

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      idBetween(
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

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      localIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'localId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      localIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'localId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      localIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'localId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      localIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'localId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      localIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'localId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      localIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'localId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      localIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'localId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      localIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'localId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      localIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'localId',
        value: '',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      localIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'localId',
        value: '',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      locationIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'location',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      locationIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'location',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      locationEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'location',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      locationGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'location',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      locationLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'location',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      locationBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'location',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      locationStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'location',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      locationEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'location',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      locationContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'location',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      locationMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'location',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      locationIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'location',
        value: '',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      locationIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'location',
        value: '',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      notificationIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'notificationId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      notificationIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'notificationId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      notificationIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'notificationId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      notificationIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'notificationId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      notificationIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'notificationId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      notificationIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'notificationId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      notificationIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'notificationId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      notificationIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'notificationId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      notificationIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'notificationId',
        value: '',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      notificationIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'notificationId',
        value: '',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      precautionaryStepsElementEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'precautionarySteps',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      precautionaryStepsElementGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'precautionarySteps',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      precautionaryStepsElementLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'precautionarySteps',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      precautionaryStepsElementBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'precautionarySteps',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      precautionaryStepsElementStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'precautionarySteps',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      precautionaryStepsElementEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'precautionarySteps',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      precautionaryStepsElementContains(String value,
          {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'precautionarySteps',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      precautionaryStepsElementMatches(String pattern,
          {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'precautionarySteps',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      precautionaryStepsElementIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'precautionarySteps',
        value: '',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      precautionaryStepsElementIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'precautionarySteps',
        value: '',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      precautionaryStepsLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'precautionarySteps',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      precautionaryStepsIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'precautionarySteps',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      precautionaryStepsIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'precautionarySteps',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      precautionaryStepsLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'precautionarySteps',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      precautionaryStepsLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'precautionarySteps',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      precautionaryStepsLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'precautionarySteps',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      priorityEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'priority',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      priorityGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'priority',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      priorityLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'priority',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      priorityBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'priority',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      priorityStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'priority',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      priorityEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'priority',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      priorityContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'priority',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      priorityMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'priority',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      priorityIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'priority',
        value: '',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      priorityIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'priority',
        value: '',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      readEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'read',
        value: value,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      requiresAcknowledgementEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'requiresAcknowledgement',
        value: value,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      roomNumberIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'roomNumber',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      roomNumberIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'roomNumber',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      roomNumberEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'roomNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      roomNumberGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'roomNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      roomNumberLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'roomNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      roomNumberBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'roomNumber',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      roomNumberStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'roomNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      roomNumberEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'roomNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      roomNumberContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'roomNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      roomNumberMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'roomNumber',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      roomNumberIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'roomNumber',
        value: '',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      roomNumberIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'roomNumber',
        value: '',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      safeExitIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'safeExit',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      safeExitIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'safeExit',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      safeExitEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'safeExit',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      safeExitGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'safeExit',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      safeExitLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'safeExit',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      safeExitBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'safeExit',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      safeExitStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'safeExit',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      safeExitEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'safeExit',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      safeExitContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'safeExit',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      safeExitMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'safeExit',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      safeExitIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'safeExit',
        value: '',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      safeExitIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'safeExit',
        value: '',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      sectionIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'sectionId',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      sectionIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'sectionId',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      sectionIdEqualTo(
    String? value, {
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

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      sectionIdGreaterThan(
    String? value, {
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

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      sectionIdLessThan(
    String? value, {
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

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      sectionIdBetween(
    String? lower,
    String? upper, {
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

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
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

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
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

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      sectionIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'sectionId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      sectionIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'sectionId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      sectionIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sectionId',
        value: '',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      sectionIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'sectionId',
        value: '',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      slotIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'slotId',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      slotIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'slotId',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      slotIdEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'slotId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      slotIdGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'slotId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      slotIdLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'slotId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      slotIdBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'slotId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      slotIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'slotId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      slotIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'slotId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      slotIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'slotId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      slotIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'slotId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      slotIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'slotId',
        value: '',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      slotIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'slotId',
        value: '',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      storedAtEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'storedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      storedAtGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'storedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      storedAtLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'storedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      storedAtBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'storedAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      timestampEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'timestamp',
        value: value,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      timestampGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'timestamp',
        value: value,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      timestampLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'timestamp',
        value: value,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      timestampBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'timestamp',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      titleEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      titleGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      titleLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      titleBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'title',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      titleStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      titleEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      titleContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      titleMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'title',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      titleIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'title',
        value: '',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      titleIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'title',
        value: '',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      typeEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'type',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      typeGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'type',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      typeLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'type',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      typeBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'type',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      typeStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'type',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      typeEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'type',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      typeContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'type',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      typeMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'type',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      typeIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'type',
        value: '',
      ));
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterFilterCondition>
      typeIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'type',
        value: '',
      ));
    });
  }
}

extension StoredNotificationQueryObject
    on QueryBuilder<StoredNotification, StoredNotification, QFilterCondition> {}

extension StoredNotificationQueryLinks
    on QueryBuilder<StoredNotification, StoredNotification, QFilterCondition> {}

extension StoredNotificationQuerySortBy
    on QueryBuilder<StoredNotification, StoredNotification, QSortBy> {
  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortByAssemblyPoint() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'assemblyPoint', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortByAssemblyPointDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'assemblyPoint', Sort.desc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortByAttachmentName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'attachmentName', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortByAttachmentNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'attachmentName', Sort.desc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortByAttachmentSize() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'attachmentSize', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortByAttachmentSizeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'attachmentSize', Sort.desc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortByAttachmentType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'attachmentType', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortByAttachmentTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'attachmentType', Sort.desc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortByAttachmentUrl() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'attachmentUrl', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortByAttachmentUrlDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'attachmentUrl', Sort.desc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortByBody() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'body', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortByBodyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'body', Sort.desc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortByCourseName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'courseName', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortByCourseNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'courseName', Sort.desc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortByDisplayMode() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'displayMode', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortByDisplayModeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'displayMode', Sort.desc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortByDurationSeconds() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'durationSeconds', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortByDurationSecondsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'durationSeconds', Sort.desc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortByFacultyName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'facultyName', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortByFacultyNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'facultyName', Sort.desc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortByLocalId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'localId', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortByLocalIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'localId', Sort.desc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortByLocation() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'location', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortByLocationDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'location', Sort.desc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortByNotificationId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'notificationId', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortByNotificationIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'notificationId', Sort.desc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortByPriority() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'priority', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortByPriorityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'priority', Sort.desc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortByRead() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'read', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortByReadDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'read', Sort.desc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortByRequiresAcknowledgement() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'requiresAcknowledgement', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortByRequiresAcknowledgementDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'requiresAcknowledgement', Sort.desc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortByRoomNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'roomNumber', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortByRoomNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'roomNumber', Sort.desc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortBySafeExit() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'safeExit', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortBySafeExitDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'safeExit', Sort.desc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortBySectionId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sectionId', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortBySectionIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sectionId', Sort.desc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortBySlotId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'slotId', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortBySlotIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'slotId', Sort.desc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortByStoredAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'storedAt', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortByStoredAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'storedAt', Sort.desc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortByTimestamp() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'timestamp', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortByTimestampDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'timestamp', Sort.desc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortByTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortByTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.desc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortByType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'type', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      sortByTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'type', Sort.desc);
    });
  }
}

extension StoredNotificationQuerySortThenBy
    on QueryBuilder<StoredNotification, StoredNotification, QSortThenBy> {
  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenByAssemblyPoint() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'assemblyPoint', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenByAssemblyPointDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'assemblyPoint', Sort.desc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenByAttachmentName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'attachmentName', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenByAttachmentNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'attachmentName', Sort.desc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenByAttachmentSize() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'attachmentSize', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenByAttachmentSizeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'attachmentSize', Sort.desc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenByAttachmentType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'attachmentType', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenByAttachmentTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'attachmentType', Sort.desc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenByAttachmentUrl() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'attachmentUrl', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenByAttachmentUrlDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'attachmentUrl', Sort.desc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenByBody() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'body', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenByBodyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'body', Sort.desc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenByCourseName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'courseName', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenByCourseNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'courseName', Sort.desc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenByDisplayMode() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'displayMode', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenByDisplayModeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'displayMode', Sort.desc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenByDurationSeconds() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'durationSeconds', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenByDurationSecondsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'durationSeconds', Sort.desc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenByFacultyName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'facultyName', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenByFacultyNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'facultyName', Sort.desc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenByLocalId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'localId', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenByLocalIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'localId', Sort.desc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenByLocation() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'location', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenByLocationDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'location', Sort.desc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenByNotificationId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'notificationId', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenByNotificationIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'notificationId', Sort.desc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenByPriority() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'priority', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenByPriorityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'priority', Sort.desc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenByRead() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'read', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenByReadDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'read', Sort.desc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenByRequiresAcknowledgement() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'requiresAcknowledgement', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenByRequiresAcknowledgementDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'requiresAcknowledgement', Sort.desc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenByRoomNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'roomNumber', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenByRoomNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'roomNumber', Sort.desc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenBySafeExit() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'safeExit', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenBySafeExitDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'safeExit', Sort.desc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenBySectionId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sectionId', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenBySectionIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sectionId', Sort.desc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenBySlotId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'slotId', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenBySlotIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'slotId', Sort.desc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenByStoredAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'storedAt', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenByStoredAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'storedAt', Sort.desc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenByTimestamp() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'timestamp', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenByTimestampDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'timestamp', Sort.desc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenByTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenByTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.desc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenByType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'type', Sort.asc);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QAfterSortBy>
      thenByTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'type', Sort.desc);
    });
  }
}

extension StoredNotificationQueryWhereDistinct
    on QueryBuilder<StoredNotification, StoredNotification, QDistinct> {
  QueryBuilder<StoredNotification, StoredNotification, QDistinct>
      distinctByAssemblyPoint({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'assemblyPoint',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QDistinct>
      distinctByAttachmentName({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'attachmentName',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QDistinct>
      distinctByAttachmentSize() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'attachmentSize');
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QDistinct>
      distinctByAttachmentType({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'attachmentType',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QDistinct>
      distinctByAttachmentUrl({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'attachmentUrl',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QDistinct>
      distinctByBody({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'body', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QDistinct>
      distinctByCourseName({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'courseName', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QDistinct>
      distinctByDisplayMode({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'displayMode', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QDistinct>
      distinctByDurationSeconds() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'durationSeconds');
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QDistinct>
      distinctByFacultyName({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'facultyName', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QDistinct>
      distinctByLocalId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'localId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QDistinct>
      distinctByLocation({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'location', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QDistinct>
      distinctByNotificationId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'notificationId',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QDistinct>
      distinctByPrecautionarySteps() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'precautionarySteps');
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QDistinct>
      distinctByPriority({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'priority', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QDistinct>
      distinctByRead() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'read');
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QDistinct>
      distinctByRequiresAcknowledgement() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'requiresAcknowledgement');
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QDistinct>
      distinctByRoomNumber({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'roomNumber', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QDistinct>
      distinctBySafeExit({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'safeExit', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QDistinct>
      distinctBySectionId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'sectionId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QDistinct>
      distinctBySlotId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'slotId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QDistinct>
      distinctByStoredAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'storedAt');
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QDistinct>
      distinctByTimestamp() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'timestamp');
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QDistinct>
      distinctByTitle({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'title', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<StoredNotification, StoredNotification, QDistinct>
      distinctByType({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'type', caseSensitive: caseSensitive);
    });
  }
}

extension StoredNotificationQueryProperty
    on QueryBuilder<StoredNotification, StoredNotification, QQueryProperty> {
  QueryBuilder<StoredNotification, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<StoredNotification, String?, QQueryOperations>
      assemblyPointProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'assemblyPoint');
    });
  }

  QueryBuilder<StoredNotification, String?, QQueryOperations>
      attachmentNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'attachmentName');
    });
  }

  QueryBuilder<StoredNotification, int?, QQueryOperations>
      attachmentSizeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'attachmentSize');
    });
  }

  QueryBuilder<StoredNotification, String?, QQueryOperations>
      attachmentTypeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'attachmentType');
    });
  }

  QueryBuilder<StoredNotification, String?, QQueryOperations>
      attachmentUrlProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'attachmentUrl');
    });
  }

  QueryBuilder<StoredNotification, String, QQueryOperations> bodyProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'body');
    });
  }

  QueryBuilder<StoredNotification, String?, QQueryOperations>
      courseNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'courseName');
    });
  }

  QueryBuilder<StoredNotification, String?, QQueryOperations>
      displayModeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'displayMode');
    });
  }

  QueryBuilder<StoredNotification, int?, QQueryOperations>
      durationSecondsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'durationSeconds');
    });
  }

  QueryBuilder<StoredNotification, String?, QQueryOperations>
      facultyNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'facultyName');
    });
  }

  QueryBuilder<StoredNotification, String, QQueryOperations> localIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'localId');
    });
  }

  QueryBuilder<StoredNotification, String?, QQueryOperations>
      locationProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'location');
    });
  }

  QueryBuilder<StoredNotification, String, QQueryOperations>
      notificationIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'notificationId');
    });
  }

  QueryBuilder<StoredNotification, List<String>, QQueryOperations>
      precautionaryStepsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'precautionarySteps');
    });
  }

  QueryBuilder<StoredNotification, String, QQueryOperations>
      priorityProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'priority');
    });
  }

  QueryBuilder<StoredNotification, bool, QQueryOperations> readProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'read');
    });
  }

  QueryBuilder<StoredNotification, bool, QQueryOperations>
      requiresAcknowledgementProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'requiresAcknowledgement');
    });
  }

  QueryBuilder<StoredNotification, String?, QQueryOperations>
      roomNumberProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'roomNumber');
    });
  }

  QueryBuilder<StoredNotification, String?, QQueryOperations>
      safeExitProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'safeExit');
    });
  }

  QueryBuilder<StoredNotification, String?, QQueryOperations>
      sectionIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'sectionId');
    });
  }

  QueryBuilder<StoredNotification, String?, QQueryOperations> slotIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'slotId');
    });
  }

  QueryBuilder<StoredNotification, DateTime, QQueryOperations>
      storedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'storedAt');
    });
  }

  QueryBuilder<StoredNotification, DateTime, QQueryOperations>
      timestampProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'timestamp');
    });
  }

  QueryBuilder<StoredNotification, String, QQueryOperations> titleProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'title');
    });
  }

  QueryBuilder<StoredNotification, String, QQueryOperations> typeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'type');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetCompletedSessionCollection on Isar {
  IsarCollection<CompletedSession> get completedSessions => this.collection();
}

const CompletedSessionSchema = CollectionSchema(
  name: r'CompletedSession',
  id: 777898689076140995,
  properties: {
    r'attendeeCount': PropertySchema(
      id: 0,
      name: r'attendeeCount',
      type: IsarType.long,
    ),
    r'completedAt': PropertySchema(
      id: 1,
      name: r'completedAt',
      type: IsarType.dateTime,
    ),
    r'courseName': PropertySchema(
      id: 2,
      name: r'courseName',
      type: IsarType.string,
    ),
    r'facultyName': PropertySchema(
      id: 3,
      name: r'facultyName',
      type: IsarType.string,
    ),
    r'sessionId': PropertySchema(
      id: 4,
      name: r'sessionId',
      type: IsarType.string,
    ),
    r'slotId': PropertySchema(
      id: 5,
      name: r'slotId',
      type: IsarType.string,
    )
  },
  estimateSize: _completedSessionEstimateSize,
  serialize: _completedSessionSerialize,
  deserialize: _completedSessionDeserialize,
  deserializeProp: _completedSessionDeserializeProp,
  idName: r'id',
  indexes: {
    r'slotId': IndexSchema(
      id: -665048265905431799,
      name: r'slotId',
      unique: true,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'slotId',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _completedSessionGetId,
  getLinks: _completedSessionGetLinks,
  attach: _completedSessionAttach,
  version: '3.1.0+1',
);

int _completedSessionEstimateSize(
  CompletedSession object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.courseName.length * 3;
  bytesCount += 3 + object.facultyName.length * 3;
  bytesCount += 3 + object.sessionId.length * 3;
  bytesCount += 3 + object.slotId.length * 3;
  return bytesCount;
}

void _completedSessionSerialize(
  CompletedSession object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeLong(offsets[0], object.attendeeCount);
  writer.writeDateTime(offsets[1], object.completedAt);
  writer.writeString(offsets[2], object.courseName);
  writer.writeString(offsets[3], object.facultyName);
  writer.writeString(offsets[4], object.sessionId);
  writer.writeString(offsets[5], object.slotId);
}

CompletedSession _completedSessionDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = CompletedSession();
  object.attendeeCount = reader.readLong(offsets[0]);
  object.completedAt = reader.readDateTime(offsets[1]);
  object.courseName = reader.readString(offsets[2]);
  object.facultyName = reader.readString(offsets[3]);
  object.id = id;
  object.sessionId = reader.readString(offsets[4]);
  object.slotId = reader.readString(offsets[5]);
  return object;
}

P _completedSessionDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readLong(offset)) as P;
    case 1:
      return (reader.readDateTime(offset)) as P;
    case 2:
      return (reader.readString(offset)) as P;
    case 3:
      return (reader.readString(offset)) as P;
    case 4:
      return (reader.readString(offset)) as P;
    case 5:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _completedSessionGetId(CompletedSession object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _completedSessionGetLinks(CompletedSession object) {
  return [];
}

void _completedSessionAttach(
    IsarCollection<dynamic> col, Id id, CompletedSession object) {
  object.id = id;
}

extension CompletedSessionByIndex on IsarCollection<CompletedSession> {
  Future<CompletedSession?> getBySlotId(String slotId) {
    return getByIndex(r'slotId', [slotId]);
  }

  CompletedSession? getBySlotIdSync(String slotId) {
    return getByIndexSync(r'slotId', [slotId]);
  }

  Future<bool> deleteBySlotId(String slotId) {
    return deleteByIndex(r'slotId', [slotId]);
  }

  bool deleteBySlotIdSync(String slotId) {
    return deleteByIndexSync(r'slotId', [slotId]);
  }

  Future<List<CompletedSession?>> getAllBySlotId(List<String> slotIdValues) {
    final values = slotIdValues.map((e) => [e]).toList();
    return getAllByIndex(r'slotId', values);
  }

  List<CompletedSession?> getAllBySlotIdSync(List<String> slotIdValues) {
    final values = slotIdValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'slotId', values);
  }

  Future<int> deleteAllBySlotId(List<String> slotIdValues) {
    final values = slotIdValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'slotId', values);
  }

  int deleteAllBySlotIdSync(List<String> slotIdValues) {
    final values = slotIdValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'slotId', values);
  }

  Future<Id> putBySlotId(CompletedSession object) {
    return putByIndex(r'slotId', object);
  }

  Id putBySlotIdSync(CompletedSession object, {bool saveLinks = true}) {
    return putByIndexSync(r'slotId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllBySlotId(List<CompletedSession> objects) {
    return putAllByIndex(r'slotId', objects);
  }

  List<Id> putAllBySlotIdSync(List<CompletedSession> objects,
      {bool saveLinks = true}) {
    return putAllByIndexSync(r'slotId', objects, saveLinks: saveLinks);
  }
}

extension CompletedSessionQueryWhereSort
    on QueryBuilder<CompletedSession, CompletedSession, QWhere> {
  QueryBuilder<CompletedSession, CompletedSession, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension CompletedSessionQueryWhere
    on QueryBuilder<CompletedSession, CompletedSession, QWhereClause> {
  QueryBuilder<CompletedSession, CompletedSession, QAfterWhereClause> idEqualTo(
      Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterWhereClause>
      idNotEqualTo(Id id) {
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

  QueryBuilder<CompletedSession, CompletedSession, QAfterWhereClause>
      idGreaterThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterWhereClause>
      idLessThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterWhereClause> idBetween(
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

  QueryBuilder<CompletedSession, CompletedSession, QAfterWhereClause>
      slotIdEqualTo(String slotId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'slotId',
        value: [slotId],
      ));
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterWhereClause>
      slotIdNotEqualTo(String slotId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'slotId',
              lower: [],
              upper: [slotId],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'slotId',
              lower: [slotId],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'slotId',
              lower: [slotId],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'slotId',
              lower: [],
              upper: [slotId],
              includeUpper: false,
            ));
      }
    });
  }
}

extension CompletedSessionQueryFilter
    on QueryBuilder<CompletedSession, CompletedSession, QFilterCondition> {
  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
      attendeeCountEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'attendeeCount',
        value: value,
      ));
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
      attendeeCountGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'attendeeCount',
        value: value,
      ));
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
      attendeeCountLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'attendeeCount',
        value: value,
      ));
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
      attendeeCountBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'attendeeCount',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
      completedAtEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'completedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
      completedAtGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'completedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
      completedAtLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'completedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
      completedAtBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'completedAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
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

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
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

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
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

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
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

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
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

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
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

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
      courseNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'courseName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
      courseNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'courseName',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
      courseNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'courseName',
        value: '',
      ));
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
      courseNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'courseName',
        value: '',
      ));
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
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

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
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

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
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

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
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

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
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

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
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

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
      facultyNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'facultyName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
      facultyNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'facultyName',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
      facultyNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'facultyName',
        value: '',
      ));
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
      facultyNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'facultyName',
        value: '',
      ));
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
      idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
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

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
      idLessThan(
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

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
      idBetween(
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

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
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

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
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

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
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

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
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

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
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

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
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

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
      sessionIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'sessionId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
      sessionIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'sessionId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
      sessionIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sessionId',
        value: '',
      ));
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
      sessionIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'sessionId',
        value: '',
      ));
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
      slotIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'slotId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
      slotIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'slotId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
      slotIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'slotId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
      slotIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'slotId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
      slotIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'slotId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
      slotIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'slotId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
      slotIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'slotId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
      slotIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'slotId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
      slotIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'slotId',
        value: '',
      ));
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterFilterCondition>
      slotIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'slotId',
        value: '',
      ));
    });
  }
}

extension CompletedSessionQueryObject
    on QueryBuilder<CompletedSession, CompletedSession, QFilterCondition> {}

extension CompletedSessionQueryLinks
    on QueryBuilder<CompletedSession, CompletedSession, QFilterCondition> {}

extension CompletedSessionQuerySortBy
    on QueryBuilder<CompletedSession, CompletedSession, QSortBy> {
  QueryBuilder<CompletedSession, CompletedSession, QAfterSortBy>
      sortByAttendeeCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'attendeeCount', Sort.asc);
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterSortBy>
      sortByAttendeeCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'attendeeCount', Sort.desc);
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterSortBy>
      sortByCompletedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'completedAt', Sort.asc);
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterSortBy>
      sortByCompletedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'completedAt', Sort.desc);
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterSortBy>
      sortByCourseName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'courseName', Sort.asc);
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterSortBy>
      sortByCourseNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'courseName', Sort.desc);
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterSortBy>
      sortByFacultyName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'facultyName', Sort.asc);
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterSortBy>
      sortByFacultyNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'facultyName', Sort.desc);
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterSortBy>
      sortBySessionId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sessionId', Sort.asc);
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterSortBy>
      sortBySessionIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sessionId', Sort.desc);
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterSortBy>
      sortBySlotId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'slotId', Sort.asc);
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterSortBy>
      sortBySlotIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'slotId', Sort.desc);
    });
  }
}

extension CompletedSessionQuerySortThenBy
    on QueryBuilder<CompletedSession, CompletedSession, QSortThenBy> {
  QueryBuilder<CompletedSession, CompletedSession, QAfterSortBy>
      thenByAttendeeCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'attendeeCount', Sort.asc);
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterSortBy>
      thenByAttendeeCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'attendeeCount', Sort.desc);
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterSortBy>
      thenByCompletedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'completedAt', Sort.asc);
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterSortBy>
      thenByCompletedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'completedAt', Sort.desc);
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterSortBy>
      thenByCourseName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'courseName', Sort.asc);
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterSortBy>
      thenByCourseNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'courseName', Sort.desc);
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterSortBy>
      thenByFacultyName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'facultyName', Sort.asc);
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterSortBy>
      thenByFacultyNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'facultyName', Sort.desc);
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterSortBy>
      thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterSortBy>
      thenBySessionId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sessionId', Sort.asc);
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterSortBy>
      thenBySessionIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sessionId', Sort.desc);
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterSortBy>
      thenBySlotId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'slotId', Sort.asc);
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QAfterSortBy>
      thenBySlotIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'slotId', Sort.desc);
    });
  }
}

extension CompletedSessionQueryWhereDistinct
    on QueryBuilder<CompletedSession, CompletedSession, QDistinct> {
  QueryBuilder<CompletedSession, CompletedSession, QDistinct>
      distinctByAttendeeCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'attendeeCount');
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QDistinct>
      distinctByCompletedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'completedAt');
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QDistinct>
      distinctByCourseName({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'courseName', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QDistinct>
      distinctByFacultyName({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'facultyName', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QDistinct>
      distinctBySessionId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'sessionId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CompletedSession, CompletedSession, QDistinct> distinctBySlotId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'slotId', caseSensitive: caseSensitive);
    });
  }
}

extension CompletedSessionQueryProperty
    on QueryBuilder<CompletedSession, CompletedSession, QQueryProperty> {
  QueryBuilder<CompletedSession, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<CompletedSession, int, QQueryOperations>
      attendeeCountProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'attendeeCount');
    });
  }

  QueryBuilder<CompletedSession, DateTime, QQueryOperations>
      completedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'completedAt');
    });
  }

  QueryBuilder<CompletedSession, String, QQueryOperations>
      courseNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'courseName');
    });
  }

  QueryBuilder<CompletedSession, String, QQueryOperations>
      facultyNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'facultyName');
    });
  }

  QueryBuilder<CompletedSession, String, QQueryOperations> sessionIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'sessionId');
    });
  }

  QueryBuilder<CompletedSession, String, QQueryOperations> slotIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'slotId');
    });
  }
}
