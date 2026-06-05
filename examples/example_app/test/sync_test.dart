import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:syncdrift_flutter/syncdrift_flutter.dart';
import 'package:example_app/database.dart';
import 'package:example_app/database.syncdrift.dart';

/// Mock Connectivity implementation to control connection states.
class MockConnectivity implements Connectivity {
  final _controller = StreamController<List<ConnectivityResult>>.broadcast();
  List<ConnectivityResult> _current = [ConnectivityResult.none];

  void setConnection(List<ConnectivityResult> results) {
    _current = results;
    _controller.add(results);
  }

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _controller.stream;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async {
    return _current;
  }
}

/// Mock SyncAdapter implementation to track synchronization calls and errors.
class MockSyncAdapter implements SyncAdapter {
  final List<Map<String, dynamic>> syncCalls = [];
  Object? errorToThrow;

  @override
  Future<void> sync(
    String table,
    String operationType,
    Map<String, dynamic> payload,
  ) async {
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    syncCalls.add({
      'table': table,
      'type': operationType,
      'payload': payload,
    });
  }
}

void main() {
  late AppDatabase db;
  late DriftDatabaseDriver baseDriver;
  late SyncDatabaseDriver syncDriver;
  late MockConnectivity mockConnectivity;
  late MockSyncAdapter mockSyncAdapter;
  late SyncQueueProcessor queueProcessor;
  late UserRepository userRepo;

  setUp(() async {
    db = AppDatabase();
    baseDriver = DriftDatabaseDriver(db);
    mockConnectivity = MockConnectivity();
    mockSyncAdapter = MockSyncAdapter();

    syncDriver = SyncDatabaseDriver(
      delegate: baseDriver,
      syncTables: syncdriftSyncTables, // generated 'users', 'posts'
      onMutation: () {
        queueProcessor.triggerProcess();
      },
    );

    await syncDriver.init();

    queueProcessor = SyncQueueProcessor(
      dbDriver: syncDriver,
      syncAdapter: mockSyncAdapter,
      connectivity: mockConnectivity,
      maxRetries: 3, // transient limit
    );

    queueProcessor.init();

    userRepo = UserRepository(syncDriver);
  });

  tearDown(() async {
    queueProcessor.dispose();
    await syncDriver.close();
  });

  group('Sync Queue - Offline Enqueuing', () {
    test(
        'Offline writes persist locally and queue mutations in pending_operations',
        () async {
      mockConnectivity.setConnection([ConnectivityResult.none]);

      // 1. Write user while offline
      final id =
          await userRepo.insertCompanion(UsersCompanion.insert(name: 'Alice'));
      expect(id, 1);

      // Verify row exists locally
      final users = await userRepo.selectAll();
      expect(users.length, 1);
      expect(users.first.name, 'Alice');

      // 2. Verify queue entry exists
      final pending = await syncDriver.select('pending_operations');
      expect(pending.length, 1);
      expect(pending.first['table_name'], 'users');
      expect(pending.first['operation_type'], 'insert');
      expect(pending.first['retries'], 0);
      expect(mockSyncAdapter.syncCalls, isEmpty); // not synced yet
    });
  });

  group('Sync Queue - Connectivity Recovery', () {
    test('Drains persistent queue when network recovers to online wifi/mobile',
        () async {
      mockConnectivity.setConnection([ConnectivityResult.none]);

      // 1. Enqueue two operations offline
      await userRepo.insertCompanion(UsersCompanion.insert(name: 'Alice'));
      await userRepo.insertCompanion(UsersCompanion.insert(name: 'Bob'));

      final pendingBefore = await syncDriver.select('pending_operations');
      expect(pendingBefore.length, 2);

      // 2. Set connected wifi state
      mockConnectivity.setConnection([ConnectivityResult.wifi]);

      // Wait a tiny bit for queue processor to process in the background
      await Future.delayed(const Duration(milliseconds: 200));

      // 3. Verify queue is drained and adapter received calls
      final pendingAfter = await syncDriver.select('pending_operations');
      expect(pendingAfter, isEmpty);
      expect(mockSyncAdapter.syncCalls.length, 2);

      expect(mockSyncAdapter.syncCalls[0]['type'], 'insert');
      expect(mockSyncAdapter.syncCalls[0]['payload']['name'], 'Alice');

      expect(mockSyncAdapter.syncCalls[1]['type'], 'insert');
      expect(mockSyncAdapter.syncCalls[1]['payload']['name'], 'Bob');
    });
  });

  group('Sync Queue - Retry & Backoff', () {
    test(
        'Transient failures increment retry counts and pause queue, eventually evicting',
        () async {
      mockConnectivity.setConnection([ConnectivityResult.wifi]);
      mockSyncAdapter.errorToThrow = Exception('Transient connection lost');

      // 1. Insert row -> triggers processor
      await userRepo.insertCompanion(UsersCompanion.insert(name: 'Alice'));

      // Wait for background process to fail
      await Future.delayed(const Duration(milliseconds: 100));

      // 2. Verify retry count is incremented to 1
      var pending = await syncDriver.select('pending_operations');
      expect(pending.length, 1);
      expect(pending.first['retries'], 1);

      // 3. Run again, verify retries incremented, then evicted to failed operations
      // Wait to bypass backoff if needed, or manually trigger queue processor
      mockSyncAdapter.errorToThrow = Exception('Transient connection lost');

      // Let's force process to bypass backoff for testing retries exhaustion
      // Trigger 2nd retry
      await queueProcessor.dbDriver.update('pending_operations', {'retries': 2},
          where: 'id = ?', whereArgs: [pending.first['id']]);

      // Reset backoff to allow immediate retry execution
      queueProcessor.resetBackoff();

      // Trigger processor (this will be 3rd try, reaching maxRetries limit)
      await queueProcessor.triggerProcess();
      await Future.delayed(const Duration(milliseconds: 100));

      // 4. Verify entry is evicted to failed operations table
      pending = await syncDriver.select('pending_operations');
      expect(pending, isEmpty);

      final failed = await syncDriver.select('failed_operations');
      expect(failed.length, 1);
      expect(failed.first['table_name'], 'users');
      expect(
          failed.first['error_message'], contains('Max retries (3) exceeded'));
    });

    test('TerminalSyncException evicts operations immediately to failed logs',
        () async {
      mockConnectivity.setConnection([ConnectivityResult.wifi]);
      mockSyncAdapter.errorToThrow =
          TerminalSyncException('Duplicate Key / Validation Error');

      await userRepo.insertCompanion(UsersCompanion.insert(name: 'Alice'));
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify immediate eviction without retrying
      final pending = await syncDriver.select('pending_operations');
      expect(pending, isEmpty);

      final failed = await syncDriver.select('failed_operations');
      expect(failed.length, 1);
      expect(failed.first['table_name'], 'users');
      expect(failed.first['error_message'],
          contains('TerminalSyncException: Duplicate Key'));
    });
  });

  group('Sync Queue - Concurrency & Delta Sync', () {
    test('Drains in strict FIFO order and updates sync_metadata timestamps',
        () async {
      mockConnectivity.setConnection([ConnectivityResult.none]);

      // Enqueue 3 mutations
      await userRepo.insertCompanion(UsersCompanion.insert(name: 'User 1'));
      await userRepo.insertCompanion(UsersCompanion.insert(name: 'User 2'));
      await userRepo.insertCompanion(UsersCompanion.insert(name: 'User 3'));

      // Toggle online
      mockConnectivity.setConnection([ConnectivityResult.mobile]);
      await Future.delayed(const Duration(milliseconds: 200));

      // Verify FIFO order execution
      expect(mockSyncAdapter.syncCalls.length, 3);
      expect(mockSyncAdapter.syncCalls[0]['payload']['name'], 'User 1');
      expect(mockSyncAdapter.syncCalls[1]['payload']['name'], 'User 2');
      expect(mockSyncAdapter.syncCalls[2]['payload']['name'], 'User 3');

      // Verify sync metadata updated
      final metadata = await syncDriver.select('sync_metadata');
      expect(metadata.length, 1);
      expect(metadata.first['table_name'], 'users');
      expect(metadata.first['last_synced_at'], isNotNull);
    });
  });
}
