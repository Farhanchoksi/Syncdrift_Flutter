import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncdrift_flutter/syncdrift_flutter.dart';
import 'package:example_app/database.dart';
import 'package:example_app/database.syncdrift.dart';

/// Spy DatabaseDriver to verify whether queries are hitting the database.
class SpyDatabaseDriver implements DatabaseDriver {
  int selectCount = 0;
  final DatabaseDriver delegate;

  SpyDatabaseDriver(this.delegate);

  @override
  Future<void> init() => delegate.init();

  @override
  Future<void> close() => delegate.close();

  @override
  Future<void> execute(String sql, [List<dynamic>? arguments]) =>
      delegate.execute(sql, arguments);

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
    selectCount++;
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

  @override
  Future<int> insert(String table, Map<String, dynamic> data) =>
      delegate.insert(table, data);

  @override
  Future<int> update(
    String table,
    Map<String, dynamic> data, {
    String? where,
    List<dynamic>? whereArgs,
  }) =>
      delegate.update(table, data, where: where, whereArgs: whereArgs);

  @override
  Future<int> delete(String table, {String? where, List<dynamic>? whereArgs}) =>
      delegate.delete(table, where: where, whereArgs: whereArgs);

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

void main() {
  late AppDatabase db;
  late SpyDatabaseDriver spyDriver;
  late SyncdriftCacheManager cacheManager;
  late CachedDatabaseDriver cachedDriver;
  late UserRepository userRepo;

  setUp(() {
    db = AppDatabase();
    spyDriver = SpyDatabaseDriver(DriftDatabaseDriver(db));
    cacheManager = SyncdriftCacheManager();
    cachedDriver = CachedDatabaseDriver(
      delegate: spyDriver,
      cacheManager: cacheManager,
      cacheConfigurations:
          syncdriftCacheConfigurations, // generated users: 2s, posts: 5s
    );
    userRepo = UserRepository(cachedDriver);
  });

  tearDown(() async {
    cacheManager.stopCleanupJob();
    await cachedDriver.close();
  });

  group('Smart Cache - Hits & Misses', () {
    test('Subsequent queries return cached data without hitting database',
        () async {
      await userRepo.insertCompanion(UsersCompanion.insert(name: 'Alice'));
      spyDriver.selectCount = 0;

      // 1st Fetch: Cache Miss -> Hits Database
      final users1 = await userRepo.selectAll();
      expect(users1.length, 1);
      expect(spyDriver.selectCount, 1);

      // 2nd Fetch: Cache Hit -> Bypasses Database
      final users2 = await userRepo.selectAll();
      expect(users2.length, 1);
      expect(spyDriver.selectCount, 1); // Select count remains 1!
    });
  });

  group('Smart Cache - Invalidation', () {
    test('Mutations invalidate table caches causing subsequent fetch to miss',
        () async {
      await userRepo.insertCompanion(UsersCompanion.insert(name: 'Alice'));
      spyDriver.selectCount = 0;

      // Fill cache
      await userRepo.selectAll();
      expect(spyDriver.selectCount, 1);

      // Mutate
      await userRepo.insertCompanion(UsersCompanion.insert(name: 'Bob'));

      // Fetch again -> Cache was invalidated, should hit database
      final users = await userRepo.selectAll();
      expect(users.length, 2);
      expect(spyDriver.selectCount, 2);
    });
  });

  group('Smart Cache - Stale-While-Revalidate', () {
    test('Stale data returns instantly and triggers background revalidation',
        () async {
      await userRepo.insertCompanion(UsersCompanion.insert(name: 'Alice'));
      spyDriver.selectCount = 0;

      // 1. Fill Cache
      await userRepo.selectAll();
      expect(spyDriver.selectCount, 1);

      // 2. Sleep for 2.2 seconds to expire cache (TTL is 2 seconds)
      await Future.delayed(const Duration(milliseconds: 2200));

      // 3. Query. SWR returns stale data immediately, selectCount is still 1
      final users = await userRepo.selectAll();
      expect(users.length, 1);

      // 4. Wait for background refresh to execute and update cache
      await Future.delayed(const Duration(milliseconds: 200));
      expect(spyDriver.selectCount,
          2); // Select count is now 2 after revalidation!
    });
  });

  group('Smart Cache - Cleanup jobs', () {
    test('Cleanup job evicts expired entries automatically', () async {
      // 1. Put entry
      final key = 'test_key';
      cacheManager.put(
          key,
          'users',
          [
            {'id': 1, 'name': 'Alice'}
          ],
          const Duration(milliseconds: 100));

      // 2. Start cleanup job with 50ms interval
      cacheManager.startCleanupJob(const Duration(milliseconds: 50));

      // Check not evicted yet
      expect(cacheManager.get(key), isNotNull);

      // 3. Wait 150ms
      await Future.delayed(const Duration(milliseconds: 150));

      // 4. Verify entry is evicted
      expect(cacheManager.get(key), devNullOrNull);
    });
  });

  group('Smart Cache - DevTools inspector telemetry', () {
    test('Exposes stats and clear extension telemetry', () async {
      cacheManager.clear();
      cacheManager.put(
          'k1',
          'users',
          [
            {'id': 1}
          ],
          const Duration(seconds: 10));
      cacheManager.put(
          'k2',
          'posts',
          [
            {'id': 2}
          ],
          const Duration(seconds: 10));

      final stats = cacheManager.getStats();
      expect(stats['size'], 2);
      expect(stats['keys'], contains('k1'));
      expect(stats['keys'], contains('k2'));

      final entries = stats['entries'] as Map;
      expect(entries['k1']['table'], 'users');
      expect(entries['k2']['table'], 'posts');
    });
  });

  group('Smart Cache - Benchmarks', () {
    test('Performance comparison: Cache vs raw SQLite', () async {
      // Warm up
      await userRepo.insertCompanion(UsersCompanion.insert(name: 'Alice'));

      // Raw SQLite Benchmark
      final rawDriver = DriftDatabaseDriver(db);
      final rawUserRepo = UserRepository(rawDriver);

      final stopwatchRaw = Stopwatch()..start();
      for (int i = 0; i < 500; i++) {
        await rawUserRepo.selectAll();
      }
      stopwatchRaw.stop();

      // Cache Benchmark
      final stopwatchCache = Stopwatch()..start();
      for (int i = 0; i < 500; i++) {
        await userRepo.selectAll();
      }
      stopwatchCache.stop();

      print('--------------------------------------------------');
      print('⚡ SYNCDRIFT BENCHMARK RESULTS (500 reads)');
      print('SQLite raw read time: ${stopwatchRaw.elapsedMilliseconds} ms');
      print('Cached read time:     ${stopwatchCache.elapsedMilliseconds} ms');
      final speedup =
          stopwatchRaw.elapsedMilliseconds / stopwatchCache.elapsedMilliseconds;
      print('Speedup factor:       ${speedup.toStringAsFixed(2)}x faster');
      print('--------------------------------------------------');

      expect(stopwatchCache.elapsedMilliseconds,
          lessThan(stopwatchRaw.elapsedMilliseconds));
    });
  });
}

// Helper matcher for null check
const devNullOrNull = AssertionErrorCollector();

class AssertionErrorCollector extends Matcher {
  const AssertionErrorCollector();
  @override
  Description describe(Description description) => description.add('is null');
  @override
  bool matches(dynamic item, Map matchState) => item == null;
}
