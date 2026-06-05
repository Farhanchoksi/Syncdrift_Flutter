import 'dart:async';
import '../driver.dart';
import 'sync_models.dart';

/// A decorator for [DatabaseDriver] that persistently queues modifications.
///
/// Automatically creates tracking tables and intercepts mutation calls
/// (insert, update, delete) on tables annotated with `@SyncTable()`.
class SyncDatabaseDriver implements DatabaseDriver {
  /// The underlying database driver.
  final DatabaseDriver delegate;

  /// Set of database table names to synchronize.
  final Set<String> syncTables;

  /// Callback executed when a mutation is persistently enqueued.
  final void Function()? onMutation;

  SyncDatabaseDriver({
    required this.delegate,
    required this.syncTables,
    this.onMutation,
  });

  static final _bypassQueueKey = Object();

  /// Executes an asynchronous operation while bypassing the persistent synchronization queue.
  ///
  /// Useful for applying remote updates locally without triggering outbound sync loops.
  static Future<T> runWithoutQueue<T>(Future<T> Function() action) {
    return runZoned(action, zoneValues: {_bypassQueueKey: true});
  }

  bool get _shouldBypassQueue => Zone.current[_bypassQueueKey] == true;

  @override
  Future<void> init() async {
    await delegate.init();
    await _createSyncTables();
  }

  @override
  Future<void> close() => delegate.close();

  @override
  Future<void> execute(String sql, [List<dynamic>? arguments]) =>
      delegate.execute(sql, arguments);

  Future<void> _createSyncTables() async {
    await delegate.execute('''
      CREATE TABLE IF NOT EXISTS pending_operations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        table_name TEXT NOT NULL,
        operation_type TEXT NOT NULL,
        payload TEXT NOT NULL,
        retries INTEGER DEFAULT 0,
        created_at TEXT NOT NULL
      );
    ''');

    await delegate.execute('''
      CREATE TABLE IF NOT EXISTS failed_operations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        table_name TEXT NOT NULL,
        operation_type TEXT NOT NULL,
        payload TEXT NOT NULL,
        error_message TEXT,
        created_at TEXT NOT NULL
      );
    ''');

    await delegate.execute('''
      CREATE TABLE IF NOT EXISTS sync_metadata (
        table_name TEXT PRIMARY KEY,
        last_synced_at TEXT NOT NULL,
        version INTEGER DEFAULT 1
      );
    ''');
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
  }) =>
      delegate.select(
        table,
        columns: columns,
        where: where,
        whereArgs: whereArgs,
        orderBy: orderBy,
        limit: limit,
        offset: offset,
      );

  @override
  Future<int> insert(String table, Map<String, dynamic> data) async {
    final id = await delegate.insert(table, data);

    if (syncTables.contains(table) && !_shouldBypassQueue) {
      final payload = Map<String, dynamic>.from(data);
      if (!payload.containsKey('id')) {
        payload['id'] = id;
      }

      final op = PendingOperation(
        tableName: table,
        operationType: 'insert',
        payload: payload,
        createdAt: DateTime.now(),
      );

      await delegate.insert('pending_operations', op.toMap());
      onMutation?.call();
    }

    return id;
  }

  @override
  Future<int> update(
    String table,
    Map<String, dynamic> data, {
    String? where,
    List<dynamic>? whereArgs,
  }) async {
    final count =
        await delegate.update(table, data, where: where, whereArgs: whereArgs);

    if (syncTables.contains(table) && !_shouldBypassQueue) {
      final op = PendingOperation(
        tableName: table,
        operationType: 'update',
        payload: {
          'data': data,
          'where': where,
          'whereArgs': whereArgs,
        },
        createdAt: DateTime.now(),
      );

      await delegate.insert('pending_operations', op.toMap());
      onMutation?.call();
    }

    return count;
  }

  @override
  Future<int> delete(String table,
      {String? where, List<dynamic>? whereArgs}) async {
    final count =
        await delegate.delete(table, where: where, whereArgs: whereArgs);

    if (syncTables.contains(table) && !_shouldBypassQueue) {
      final op = PendingOperation(
        tableName: table,
        operationType: 'delete',
        payload: {
          'where': where,
          'whereArgs': whereArgs,
        },
        createdAt: DateTime.now(),
      );

      await delegate.insert('pending_operations', op.toMap());
      onMutation?.call();
    }

    return count;
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
  }) =>
      delegate.watch(
        table,
        columns: columns,
        where: where,
        whereArgs: whereArgs,
        orderBy: orderBy,
        limit: limit,
        offset: offset,
      );
}
