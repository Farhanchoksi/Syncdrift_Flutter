/// Represents an incoming remote database event (insert, update, delete).
class RealtimeEvent {
  final String table;
  final String eventType; // 'insert', 'update', 'delete' (lowercase)
  final Map<String, dynamic> record;
  final Map<String, dynamic>? oldRecord;

  RealtimeEvent({
    required this.table,
    required this.eventType,
    required this.record,
    this.oldRecord,
  });

  @override
  String toString() =>
      'RealtimeEvent(table: $table, eventType: $eventType, record: $record, oldRecord: $oldRecord)';
}
