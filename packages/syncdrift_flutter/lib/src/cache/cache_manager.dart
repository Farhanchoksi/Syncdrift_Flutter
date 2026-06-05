import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

/// Represents a cached query result for a specific database query.
class CacheEntry {
  /// Unique cache key (e.g. table:sql:args).
  final String key;

  /// The table name associated with this query cache.
  final String table;

  /// The cached query result rows.
  final List<Map<String, dynamic>> data;

  /// The timestamp when the cache entry was created.
  final DateTime createdAt;

  /// The duration representing the time-to-live (TTL) of this cache.
  final Duration ttl;

  CacheEntry({
    required this.key,
    required this.table,
    required this.data,
    required this.createdAt,
    required this.ttl,
  });

  /// Check if the cache entry has exceeded its TTL duration.
  bool get isExpired => DateTime.now().difference(createdAt) > ttl;
}

/// The core manager controlling in-memory caches, stale-while-revalidate,
/// table invalidation, background cleanup, and VM service extension telemetry.
class SyncdriftCacheManager {
  final Map<String, CacheEntry> _cache = {};
  Timer? _cleanupTimer;

  SyncdriftCacheManager() {
    _registerDevToolsExtension();
  }

  /// Start a periodic background timer to evict expired cache entries.
  void startCleanupJob(Duration interval) {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(interval, (_) => cleanupExpired());
  }

  /// Stop the periodic background cleanup job.
  void stopCleanupJob() {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
  }

  /// Manually trigger eviction of all expired cache entries.
  void cleanupExpired() {
    final now = DateTime.now();
    _cache.removeWhere(
        (key, entry) => now.difference(entry.createdAt) > entry.ttl);
  }

  /// Retrieve a cached query entry by key.
  CacheEntry? get(String key) {
    return _cache[key];
  }

  /// Put a query output into the cache manager.
  void put(
      String key, String table, List<Map<String, dynamic>> data, Duration ttl) {
    _cache[key] = CacheEntry(
      key: key,
      table: table,
      data: data,
      createdAt: DateTime.now(),
      ttl: ttl,
    );
  }

  /// Invalidate/clear all cached queries associated with a specific table.
  ///
  /// Typically called when table writes (insert, update, delete) occur.
  void invalidateTable(String table) {
    _cache.removeWhere((key, entry) => entry.table == table);
  }

  /// Clear the entire cache.
  void clear() {
    _cache.clear();
  }

  /// Get active cache statistics for DevTools visualization.
  Map<String, dynamic> getStats() {
    return {
      'size': _cache.length,
      'keys': _cache.keys.toList(),
      'entries': _cache.map((key, entry) => MapEntry(key, {
            'table': entry.table,
            'createdAt': entry.createdAt.toIso8601String(),
            'ttlSeconds': entry.ttl.inSeconds,
            'isExpired': entry.isExpired,
          })),
    };
  }

  void _registerDevToolsExtension() {
    try {
      developer.registerExtension('ext.syncdrift.cache.inspect',
          (method, parameters) async {
        return developer.ServiceExtensionResponse.result(
            json.encode(getStats()));
      });
      developer.registerExtension('ext.syncdrift.cache.clear',
          (method, parameters) async {
        clear();
        return developer.ServiceExtensionResponse.result(
            json.encode({'status': 'cleared'}));
      });
    } catch (_) {
      // Fail silently if Dart VM Service is not available (e.g. release mode or unit test contexts)
    }
  }
}
