import 'dart:async';
import '../driver.dart';
import 'cache_manager.dart';

/// A decorator for [DatabaseDriver] that adds transparent query caching.
///
/// Implements stale-while-revalidate fetching, table-level invalidation,
/// and instant offline cache access.
class CachedDatabaseDriver implements DatabaseDriver {
  /// The underlying raw database driver (e.g. DriftDatabaseDriver).
  final DatabaseDriver delegate;

  /// The cache manager storing the in-memory results.
  final SyncdriftCacheManager cacheManager;

  /// Cache settings mapping table names to their Time-To-Live (TTL).
  final Map<String, Duration> cacheConfigurations;

  CachedDatabaseDriver({
    required this.delegate,
    required this.cacheManager,
    required this.cacheConfigurations,
  });

  @override
  Future<void> init() => delegate.init();

  @override
  Future<void> close() => delegate.close();

  @override
  Future<void> execute(String sql, [List<dynamic>? arguments]) =>
      delegate.execute(sql, arguments);

  String _buildCacheKey(
    String table,
    List<String>? columns,
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
    int? limit,
    int? offset,
  ) {
    final columnsStr = columns?.join(',') ?? '*';
    final argsStr = whereArgs?.map((e) => e.toString()).join(',') ?? '';
    return '$table:cols=$columnsStr:where=$where:args=$argsStr:orderBy=$orderBy:limit=$limit:offset=$offset';
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
    final ttl = cacheConfigurations[table];
    if (ttl == null) {
      return delegate.select(
        table,
        columns: columns,
        where: where,
        whereArgs: whereArgs,
        orderBy: orderBy,
        limit: limit,
        offset: offset,
      );
    }

    final key = _buildCacheKey(
        table, columns, where, whereArgs, orderBy, limit, offset);
    final cached = cacheManager.get(key);

    if (cached != null) {
      if (!cached.isExpired) {
        return cached.data;
      } else {
        // Stale-While-Revalidate: return stale data immediately,
        // refresh in background.
        _refreshCache(
            key, table, columns, where, whereArgs, orderBy, limit, offset, ttl);
        return cached.data;
      }
    }

    // Cache miss
    final fresh = await delegate.select(
      table,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
    cacheManager.put(key, table, fresh, ttl);
    return fresh;
  }

  void _refreshCache(
    String key,
    String table,
    List<String>? columns,
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
    int? limit,
    int? offset,
    Duration ttl,
  ) {
    delegate
        .select(
      table,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    )
        .then((fresh) {
      cacheManager.put(key, table, fresh, ttl);
    }).catchError((_) {
      // Suppress background errors to keep stale cache (offline resilient fallback)
    });
  }

  @override
  Future<int> insert(String table, Map<String, dynamic> data) async {
    final id = await delegate.insert(table, data);
    cacheManager.invalidateTable(table);
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
    cacheManager.invalidateTable(table);
    return count;
  }

  @override
  Future<int> delete(String table,
      {String? where, List<dynamic>? whereArgs}) async {
    final count =
        await delegate.delete(table, where: where, whereArgs: whereArgs);
    cacheManager.invalidateTable(table);
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
  }) {
    final ttl = cacheConfigurations[table];
    if (ttl == null) {
      return delegate.watch(
        table,
        columns: columns,
        where: where,
        whereArgs: whereArgs,
        orderBy: orderBy,
        limit: limit,
        offset: offset,
      );
    }

    final key = _buildCacheKey(
        table, columns, where, whereArgs, orderBy, limit, offset);
    final cached = cacheManager.get(key);

    final streamController = StreamController<List<Map<String, dynamic>>>();

    // Instant offline cache emission
    if (cached != null) {
      streamController.add(cached.data);
    }

    final subscription = delegate
        .watch(
      table,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    )
        .listen((event) {
      cacheManager.put(key, table, event, ttl);
      streamController.add(event);
    }, onError: streamController.addError, onDone: streamController.close);

    streamController.onCancel = () => subscription.cancel();
    return streamController.stream;
  }
}
