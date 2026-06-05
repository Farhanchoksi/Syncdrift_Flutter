import 'dart:convert';

/// Represents a local mutation that needs to be synchronized to the remote backend.
class PendingOperation {
  final int? id;
  final String tableName;
  final String operationType; // 'insert', 'update', 'delete'
  final Map<String, dynamic> payload;
  final int retries;
  final DateTime createdAt;

  PendingOperation({
    this.id,
    required this.tableName,
    required this.operationType,
    required this.payload,
    this.retries = 0,
    required this.createdAt,
  });

  factory PendingOperation.fromMap(Map<String, dynamic> map) {
    return PendingOperation(
      id: map['id'] as int?,
      tableName: map['table_name'] as String,
      operationType: map['operation_type'] as String,
      payload: json.decode(map['payload'] as String) as Map<String, dynamic>,
      retries: map['retries'] as int? ?? 0,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'table_name': tableName,
      'operation_type': operationType,
      'payload': json.encode(payload),
      'retries': retries,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

/// Represents a synchronization operation that failed and exhausted all retry thresholds.
class FailedOperation {
  final int? id;
  final String tableName;
  final String operationType;
  final Map<String, dynamic> payload;
  final String errorMessage;
  final DateTime createdAt;

  FailedOperation({
    this.id,
    required this.tableName,
    required this.operationType,
    required this.payload,
    required this.errorMessage,
    required this.createdAt,
  });

  factory FailedOperation.fromMap(Map<String, dynamic> map) {
    return FailedOperation(
      id: map['id'] as int?,
      tableName: map['table_name'] as String,
      operationType: map['operation_type'] as String,
      payload: json.decode(map['payload'] as String) as Map<String, dynamic>,
      errorMessage: map['error_message'] as String? ?? '',
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'table_name': tableName,
      'operation_type': operationType,
      'payload': json.encode(payload),
      'error_message': errorMessage,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

/// Tracks delta synchronization timestamps per database table.
class SyncMetadata {
  final String tableName;
  final DateTime lastSyncedAt;
  final int version;

  SyncMetadata({
    required this.tableName,
    required this.lastSyncedAt,
    this.version = 1,
  });

  factory SyncMetadata.fromMap(Map<String, dynamic> map) {
    return SyncMetadata(
      tableName: map['table_name'] as String,
      lastSyncedAt: DateTime.parse(map['last_synced_at'] as String),
      version: map['version'] as int? ?? 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'table_name': tableName,
      'last_synced_at': lastSyncedAt.toIso8601String(),
      'version': version,
    };
  }
}
