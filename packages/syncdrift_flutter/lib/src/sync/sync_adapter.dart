/// Contract definition for remote server sync actions.
///
/// Implemented by backend adapters (Supabase, Firebase, REST APIs).
abstract class SyncAdapter {
  /// Synchronizes a local operation to the remote server.
  ///
  /// [table]: The database table name.
  /// [operationType]: The operation type ('insert', 'update', 'delete').
  /// [payload]: The serialized representation of the row data.
  Future<void> sync(
    String table,
    String operationType,
    Map<String, dynamic> payload,
  );

  /// Helper to extract the primary key value from insert, update, or delete payloads.
  static Object? extractPrimaryKey(Map<String, dynamic> payload,
      {String keyName = 'id'}) {
    final where = payload['where'] as String?;
    final whereArgs = payload['whereArgs'] as List?;

    if (where == null || whereArgs == null || whereArgs.isEmpty) {
      // For insert operations, the payload is the row itself
      final data = payload['data'];
      if (data is Map && data.containsKey(keyName)) {
        return data[keyName];
      }
      return payload[keyName];
    }

    // Matches 'id = ?' or similar in where clause
    final regex = RegExp(r'\b' + RegExp.escape(keyName) + r'\s*=\s*\?');
    if (regex.hasMatch(where)) {
      final match = regex.firstMatch(where)!;
      final beforeMatch = where.substring(0, match.start);
      final paramIndex = '?'.allMatches(beforeMatch).length;
      if (paramIndex < whereArgs.length) {
        return whereArgs[paramIndex];
      }
    }

    // Fallback if there is a single whereArg
    if (whereArgs.length == 1) {
      return whereArgs.first;
    }
    return null;
  }
}
