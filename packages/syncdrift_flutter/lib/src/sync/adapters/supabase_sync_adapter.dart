import 'package:supabase/supabase.dart';
import '../sync_adapter.dart';
import '../sync_queue.dart';

/// A [SyncAdapter] that pushes mutations to a Supabase database.
class SupabaseSyncAdapter implements SyncAdapter {
  final SupabaseClient supabase;
  final String primaryKeyName;

  SupabaseSyncAdapter({
    required this.supabase,
    this.primaryKeyName = 'id',
  });

  @override
  Future<void> sync(
    String table,
    String operationType,
    Map<String, dynamic> payload,
  ) async {
    try {
      if (operationType == 'insert') {
        await supabase.from(table).insert(payload);
      } else if (operationType == 'update') {
        final id =
            SyncAdapter.extractPrimaryKey(payload, keyName: primaryKeyName);
        if (id == null) {
          throw TerminalSyncException(
              'Could not extract primary key "$primaryKeyName" from update payload.');
        }
        final updateData = payload['data'] ?? {};
        await supabase.from(table).update(updateData).eq(primaryKeyName, id);
      } else if (operationType == 'delete') {
        final id =
            SyncAdapter.extractPrimaryKey(payload, keyName: primaryKeyName);
        if (id == null) {
          throw TerminalSyncException(
              'Could not extract primary key "$primaryKeyName" from delete payload.');
        }
        await supabase.from(table).delete().eq(primaryKeyName, id);
      } else {
        throw TerminalSyncException('Unknown operation type: $operationType');
      }
    } on PostgrestException catch (e) {
      // PostgrestExceptions represent remote database failures, which are terminal
      throw TerminalSyncException(
          'Supabase PostgrestException: ${e.message} (code: ${e.code})');
    } catch (e) {
      if (e is TerminalSyncException) {
        rethrow;
      }
      throw Exception('Supabase transient error: $e');
    }
  }
}
