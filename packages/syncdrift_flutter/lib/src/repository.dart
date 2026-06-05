import 'driver.dart';
import 'pagination.dart';

/// Base class for all generated table repositories.
///
/// Encapsulates CRUD, pagination, and reactive queries in a driver-agnostic manner.
/// Translates between database snake_case keys and Dart camelCase property keys automatically.
abstract class SyncdriftRepository<T, InsertCompanion> {
  /// The underlying database driver.
  final DatabaseDriver driver;

  /// The table name associated with this repository.
  final String tableName;

  SyncdriftRepository(this.driver, this.tableName);

  /// Map database row (camelCase Map) to type [T].
  T mapRow(Map<String, dynamic> row);

  /// Map entity of type [T] or companion to camelCase database map.
  Map<String, dynamic> entityToMap(T entity);

  /// Converts a snake_case key to camelCase.
  String snakeToCamel(String snake) {
    final parts = snake.split('_');
    if (parts.isEmpty) {
      return '';
    }
    final buffer = StringBuffer(parts[0]);
    for (int i = 1; i < parts.length; i++) {
      final part = parts[i];
      if (part.isNotEmpty) {
        buffer.write(part[0].toUpperCase() + part.substring(1));
      }
    }
    return buffer.toString();
  }

  /// Converts a camelCase key to snake_case.
  String camelToSnake(String camel) {
    final exp = RegExp(r'(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])');
    return camel.replaceAll(exp, '_').toLowerCase();
  }

  /// Translates a database row's keys from snake_case to camelCase.
  Map<String, dynamic> convertRowToCamel(Map<String, dynamic> row) {
    return row.map((key, value) => MapEntry(snakeToCamel(key), value));
  }

  /// Translates a Dart map's keys from camelCase to snake_case.
  Map<String, dynamic> convertRowToSnake(Map<String, dynamic> row) {
    return row.map((key, value) => MapEntry(camelToSnake(key), value));
  }

  /// Select records matching filters.
  Future<List<T>> selectAll({
    List<String>? columns,
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    final snakeColumns = columns?.map(camelToSnake).toList();
    final rows = await driver.select(
      tableName,
      columns: snakeColumns,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
    return rows.map((row) => mapRow(convertRowToCamel(row))).toList();
  }

  /// Select a single record matching filters.
  Future<T?> selectOne({
    List<String>? columns,
    String? where,
    List<dynamic>? whereArgs,
  }) async {
    final snakeColumns = columns?.map(camelToSnake).toList();
    final rows = await driver.select(
      tableName,
      columns: snakeColumns,
      where: where,
      whereArgs: whereArgs,
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return mapRow(convertRowToCamel(rows.first));
  }

  /// Watch multiple records reactively.
  Stream<List<T>> watchAll({
    List<String>? columns,
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
    int? limit,
    int? offset,
  }) {
    final snakeColumns = columns?.map(camelToSnake).toList();
    return driver
        .watch(
          tableName,
          columns: snakeColumns,
          where: where,
          whereArgs: whereArgs,
          orderBy: orderBy,
          limit: limit,
          offset: offset,
        )
        .map((rows) =>
            rows.map((row) => mapRow(convertRowToCamel(row))).toList());
  }

  /// Watch a single record reactively.
  Stream<T?> watchOne({
    List<String>? columns,
    String? where,
    List<dynamic>? whereArgs,
  }) {
    final snakeColumns = columns?.map(camelToSnake).toList();
    return driver
        .watch(
          tableName,
          columns: snakeColumns,
          where: where,
          whereArgs: whereArgs,
          limit: 1,
        )
        .map((rows) =>
            rows.isEmpty ? null : mapRow(convertRowToCamel(rows.first)));
  }

  /// Insert a record from a camelCase Map.
  Future<int> insertMap(Map<String, dynamic> data) {
    return driver.insert(tableName, convertRowToSnake(data));
  }

  /// Update records from a camelCase Map.
  Future<int> updateMap(Map<String, dynamic> data,
      {String? where, List<dynamic>? whereArgs}) {
    return driver.update(tableName, convertRowToSnake(data),
        where: where, whereArgs: whereArgs);
  }

  /// Delete records matching filters.
  Future<int> delete({String? where, List<dynamic>? whereArgs}) {
    return driver.delete(tableName, where: where, whereArgs: whereArgs);
  }

  /// Paginate records.
  Future<PaginatedResult<T>> paginate({
    required int page,
    required int pageSize,
    List<String>? columns,
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
  }) async {
    final snakeColumns = columns?.map(camelToSnake).toList();
    final result = await driver.paginate(
      tableName,
      page: page,
      pageSize: pageSize,
      columns: snakeColumns,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
    );
    return result.map((row) => mapRow(convertRowToCamel(row)));
  }
}
