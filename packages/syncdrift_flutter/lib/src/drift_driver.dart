import 'package:drift/drift.dart';
import 'driver.dart';

/// An implementation of [DatabaseDriver] using Drift's [GeneratedDatabase].
class DriftDatabaseDriver implements DatabaseDriver {
  /// The underlying Drift generated database instance.
  final GeneratedDatabase db;

  DriftDatabaseDriver(this.db);

  @override
  Future<void> init() async {
    // Drift database initializes on first query or open
  }

  @override
  Future<void> close() async {
    await db.close();
  }

  @override
  Future<void> execute(String sql, [List<dynamic>? arguments]) async {
    final variables = arguments?.map((e) => Variable(e)).toList() ?? const [];
    await db.customStatement(sql, variables);
  }

  TableInfo? _getTableInfo(String name) {
    try {
      return db.allTables.firstWhere(
        (t) => t.actualTableName == name || t.entityName == name,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> select(
    String table, {
    List<String>? columns,
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    final querySql = _buildSelectSql(
      table: table,
      columns: columns,
      where: where,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );

    final variables = whereArgs?.map((e) => Variable(e)).toList() ?? const [];
    final rows = await db.customSelect(querySql, variables: variables).get();
    return rows.map((r) => r.data).toList();
  }

  @override
  Future<int> insert(String table, Map<String, dynamic> data) async {
    final keys = data.keys.toList();
    final values = data.values.toList();
    final sql =
        'INSERT INTO $table (${keys.join(', ')}) VALUES (${List.filled(keys.length, '?').join(', ')})';

    final variables = values.map((e) => Variable(e)).toList();
    final tableInfo = _getTableInfo(table);
    return await db.customInsert(
      sql,
      variables: variables,
      updates: tableInfo != null ? {tableInfo} : const {},
    );
  }

  @override
  Future<int> update(
    String table,
    Map<String, dynamic> data, {
    String? where,
    List<dynamic>? whereArgs,
  }) async {
    final keys = data.keys.toList();
    final values = data.values.toList();
    final setClause = keys.map((k) => '$k = ?').join(', ');
    final sql = StringBuffer('UPDATE $table SET $setClause');
    if (where != null) {
      sql.write(' WHERE $where');
    }

    final variables = <Variable>[
      ...values.map((e) => Variable(e)),
      if (whereArgs != null) ...whereArgs.map((e) => Variable(e)),
    ];

    final tableInfo = _getTableInfo(table);
    return await db.customUpdate(
      sql.toString(),
      variables: variables,
      updates: tableInfo != null ? {tableInfo} : const {},
    );
  }

  @override
  Future<int> delete(String table,
      {String? where, List<dynamic>? whereArgs}) async {
    final sql = StringBuffer('DELETE FROM $table');
    if (where != null) {
      sql.write(' WHERE $where');
    }
    final variables = whereArgs?.map((e) => Variable(e)).toList() ?? const [];
    final tableInfo = _getTableInfo(table);
    return await db.customUpdate(
      sql.toString(),
      variables: variables,
      updates: tableInfo != null ? {tableInfo} : const {},
    );
  }

  @override
  Stream<List<Map<String, dynamic>>> watch(
    String table, {
    List<String>? columns,
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
    int? limit,
    int? offset,
  }) {
    final querySql = _buildSelectSql(
      table: table,
      columns: columns,
      where: where,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );

    final variables = whereArgs?.map((e) => Variable(e)).toList() ?? const [];
    final tableInfo = _getTableInfo(table);

    final stream = db
        .customSelect(
          querySql,
          variables: variables,
          readsFrom: tableInfo != null ? {tableInfo} : const {},
        )
        .watch();

    return stream.map((rows) => rows.map((r) => r.data).toList());
  }

  String _buildSelectSql({
    required String table,
    List<String>? columns,
    String? where,
    String? orderBy,
    int? limit,
    int? offset,
  }) {
    final sql = StringBuffer('SELECT ');
    if (columns != null && columns.isNotEmpty) {
      sql.write(columns.join(', '));
    } else {
      sql.write('*');
    }
    sql.write(' FROM $table');
    if (where != null) {
      sql.write(' WHERE $where');
    }
    if (orderBy != null) {
      sql.write(' ORDER BY $orderBy');
    }
    if (limit != null) {
      sql.write(' LIMIT $limit');
    }
    if (offset != null) {
      sql.write(' OFFSET $offset');
    }
    return sql.toString();
  }
}
