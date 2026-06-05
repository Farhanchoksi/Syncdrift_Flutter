import 'dart:async';
import 'package:supabase/supabase.dart';
import '../realtime_event.dart';
import '../realtime_adapter.dart';

/// A [RealtimeAdapter] that listens to PostgreSQL replication changes
/// from Supabase Realtime channels.
class SupabaseRealtimeAdapter implements RealtimeAdapter {
  final SupabaseClient supabase;
  final List<String> tables;
  final String schema;

  final StreamController<RealtimeEvent> _controller =
      StreamController<RealtimeEvent>.broadcast();
  RealtimeChannel? _channel;

  SupabaseRealtimeAdapter({
    required this.supabase,
    required this.tables,
    this.schema = 'public',
  });

  @override
  Stream<RealtimeEvent> get events => _controller.stream;

  @override
  Future<void> connect() async {
    if (_channel != null) {
      return;
    }

    final channel = supabase.channel('syncdrift-postgres-changes');

    for (final table in tables) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: schema,
        table: table,
        callback: (PostgresChangePayload payload) {
          final eventTypeStr = payload.eventType.name.toLowerCase();

          // Standardize insert/update/delete records
          final record = payload.newRecord;
          final oldRecord = payload.oldRecord;

          _controller.add(RealtimeEvent(
            table: table,
            eventType: eventTypeStr,
            record: record,
            oldRecord: oldRecord,
          ));
        },
      );
    }

    _channel = channel;
    channel.subscribe();
  }

  @override
  Future<void> disconnect() async {
    if (_channel == null) {
      return;
    }

    await supabase.removeChannel(_channel!);
    _channel = null;
  }
}
