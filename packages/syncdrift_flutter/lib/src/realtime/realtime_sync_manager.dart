import 'dart:async';
import '../sync/sync_driver.dart';
import 'realtime_event.dart';
import 'realtime_adapter.dart';

/// Coordinates real-time sync adapters and applies updates locally
/// while preventing feedback loops.
class RealtimeSyncManager {
  final SyncDatabaseDriver dbDriver;
  final List<RealtimeAdapter> adapters;
  final String primaryKeyName;
  final void Function(Object error, StackTrace stackTrace)? onError;

  final List<StreamSubscription> _subscriptions = [];
  bool _isRunning = false;

  RealtimeSyncManager({
    required this.dbDriver,
    required this.adapters,
    this.primaryKeyName = 'id',
    this.onError,
  });

  /// Connects all adapters and starts listening to remote changes.
  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;

    for (final adapter in adapters) {
      try {
        await adapter.connect();

        final subscription = adapter.events.listen(
          _handleRealtimeEvent,
          onError: (Object err, StackTrace stack) {
            onError?.call(err, stack);
          },
        );
        _subscriptions.add(subscription);
      } catch (e, stack) {
        onError?.call(e, stack);
      }
    }
  }

  /// Stop listening and disconnect all adapters.
  Future<void> stop() async {
    if (!_isRunning) return;
    _isRunning = false;

    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();

    for (final adapter in adapters) {
      try {
        await adapter.disconnect();
      } catch (e, stack) {
        onError?.call(e, stack);
      }
    }
  }

  Future<void> _handleRealtimeEvent(RealtimeEvent event) async {
    try {
      // Execute the database modifications bypassing the local sync queue enqueuer.
      await SyncDatabaseDriver.runWithoutQueue(() async {
        final table = event.table;
        final type = event.eventType.toLowerCase();

        if (type == 'insert') {
          await dbDriver.insert(table, event.record);
        } else if (type == 'update') {
          final id =
              event.record[primaryKeyName] ?? event.oldRecord?[primaryKeyName];
          if (id == null) {
            throw StateError(
                'Missing primary key "$primaryKeyName" in update event: $event');
          }
          await dbDriver.update(
            table,
            event.record,
            where: '$primaryKeyName = ?',
            whereArgs: [id],
          );
        } else if (type == 'delete') {
          final id =
              event.oldRecord?[primaryKeyName] ?? event.record[primaryKeyName];
          if (id == null) {
            throw StateError(
                'Missing primary key "$primaryKeyName" in delete event: $event');
          }
          await dbDriver.delete(
            table,
            where: '$primaryKeyName = ?',
            whereArgs: [id],
          );
        }
      });
    } catch (e, stack) {
      onError?.call(e, stack);
    }
  }
}
