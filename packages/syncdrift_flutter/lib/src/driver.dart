/// Abstract base class defining the unified interface for database engines.
///
/// This permits interchangeable backends (Drift/SQLite, Supabase, Turso, etc.)
/// while keeping the core repository layer database-agnostic.
abstract class DatabaseDriver {
  /// Initialize the database driver connection/resources.
  Future<void> init();

  /// Close the database driver and release resources.
  Future<void> close();

  /// Execute an arbitrary SQL statement (e.g. DDL like CREATE TABLE).
  Future<void> execute(String sql, [List<dynamic>? arguments]);

  /// Select records from the database.
  Future<List<Map<String, dynamic>>> select(
    String table, {
    List<String>? columns,
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
    int? limit,
    int? offset,
  });

  /// Insert a record into the database. Returns the primary key ID.
  Future<int> insert(String table, Map<String, dynamic> data);

  /// Update records in the database. Returns the number of affected rows.
  Future<int> update(
    String table,
    Map<String, dynamic> data, {
    String? where,
    List<dynamic>? whereArgs,
  });

  /// Delete records from the database. Returns the number of affected rows.
  Future<int> delete(
    String table, {
    String? where,
    List<dynamic>? whereArgs,
  });

  /// Watch query results reactively. Emits a new list whenever tables change.
  Stream<List<Map<String, dynamic>>> watch(
    String table, {
    List<String>? columns,
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
    int? limit,
    int? offset,
  });
}
