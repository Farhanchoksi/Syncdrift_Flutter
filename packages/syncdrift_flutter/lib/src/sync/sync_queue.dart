import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../driver.dart';
import 'sync_models.dart';
import 'sync_adapter.dart';

/// Exception thrown by [SyncAdapter] when synchronization is terminally rejected.
///
/// Terminal operations will be moved directly to `failed_operations` and not retried.
class TerminalSyncException implements Exception {
  final String message;
  TerminalSyncException(this.message);

  @override
  String toString() => 'TerminalSyncException: $message';
}

/// The queue worker that sequentially processes pending operations,
/// monitors internet connectivity, and handles exponential retries.
class SyncQueueProcessor {
  /// The database driver where the sync queues reside.
  final DatabaseDriver dbDriver;

  /// The active remote synchronization adapter.
  final SyncAdapter syncAdapter;

  /// The connectivity listener instance.
  final Connectivity connectivity;

  /// Maximum retry threshold for transient failures.
  final int maxRetries;

  bool _isProcessing = false;
  DateTime? _backoffUntil;
  StreamSubscription? _connectivitySubscription;

  SyncQueueProcessor({
    required this.dbDriver,
    required this.syncAdapter,
    Connectivity? connectivity,
    this.maxRetries = 5,
  }) : connectivity = connectivity ?? Connectivity();

  /// Start listening to connectivity state transitions.
  void init() {
    _connectivitySubscription =
        connectivity.onConnectivityChanged.listen((event) {
      final isOnline = event.any((r) => r != ConnectivityResult.none);

      if (isOnline) {
        triggerProcess();
      }
    });
  }

  /// Close downstream subscriptions.
  void dispose() {
    _connectivitySubscription?.cancel();
  }

  /// Reset the exponential backoff timer, allowing sync to run immediately.
  void resetBackoff() {
    _backoffUntil = null;
  }

  /// Manually trigger queue processing.
  Future<void> triggerProcess() async {
    if (_isProcessing) return;
    if (_backoffUntil != null && DateTime.now().isBefore(_backoffUntil!))
      return;

    _isProcessing = true;
    try {
      await _processQueue();
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _processQueue() async {
    while (true) {
      // Check current connectivity
      final status = await connectivity.checkConnectivity();
      final isOnline = status.any((r) => r != ConnectivityResult.none);

      if (!isOnline) break;

      // Select oldest pending item (FIFO)
      final rows = await dbDriver.select(
        'pending_operations',
        orderBy: 'id ASC',
        limit: 1,
      );

      if (rows.isEmpty) break;

      final op = PendingOperation.fromMap(rows.first);

      try {
        // Run remote sync callback
        await syncAdapter.sync(op.tableName, op.operationType, op.payload);

        // Delete from local queue
        await dbDriver.delete(
          'pending_operations',
          where: 'id = ?',
          whereArgs: [op.id],
        );

        // Update delta sync last synced timestamp
        final metadata = SyncMetadata(
          tableName: op.tableName,
          lastSyncedAt: DateTime.now(),
        );

        // Upsert metadata
        final metadataRows = await dbDriver.select(
          'sync_metadata',
          where: 'table_name = ?',
          whereArgs: [op.tableName],
        );

        if (metadataRows.isEmpty) {
          await dbDriver.insert('sync_metadata', metadata.toMap());
        } else {
          await dbDriver.update(
            'sync_metadata',
            metadata.toMap(),
            where: 'table_name = ?',
            whereArgs: [op.tableName],
          );
        }
      } catch (e) {
        if (e is TerminalSyncException) {
          // Terminal failure: evict directly to failed logs
          await _evictToFailed(op, e.toString());
        } else {
          // Transient failure: increment retries or evict
          final nextRetries = op.retries + 1;
          if (nextRetries >= maxRetries) {
            await _evictToFailed(
                op, 'Max retries ($maxRetries) exceeded. Error: $e');
          } else {
            await dbDriver.update(
              'pending_operations',
              {'retries': nextRetries},
              where: 'id = ?',
              whereArgs: [op.id],
            );

            // Apply exponential backoff delay (e.g. 2^retries seconds)
            final backoffSeconds = 1 << nextRetries;
            _backoffUntil =
                DateTime.now().add(Duration(seconds: backoffSeconds));
            break; // Break queue processing loop
          }
        }
      }
    }
  }

  Future<void> _evictToFailed(PendingOperation op, String error) async {
    final failedOp = FailedOperation(
      tableName: op.tableName,
      operationType: op.operationType,
      payload: op.payload,
      errorMessage: error,
      createdAt: DateTime.now(),
    );

    // Write to failed_operations
    await dbDriver.insert('failed_operations', failedOp.toMap());

    // Remove from pending_operations
    await dbDriver.delete(
      'pending_operations',
      where: 'id = ?',
      whereArgs: [op.id],
    );
  }
}
