/// Represents a file queued locally that needs to be uploaded to a remote storage bucket.
class PendingUpload {
  final int? id;
  final String bucket;
  final String remotePath;
  final String localPath;
  final String? contentType;
  final int retries;
  final DateTime createdAt;

  PendingUpload({
    this.id,
    required this.bucket,
    required this.remotePath,
    required this.localPath,
    this.contentType,
    this.retries = 0,
    required this.createdAt,
  });

  factory PendingUpload.fromMap(Map<String, dynamic> map) {
    return PendingUpload(
      id: map['id'] as int?,
      bucket: map['bucket'] as String,
      remotePath: map['remote_path'] as String,
      localPath: map['local_path'] as String,
      contentType: map['content_type'] as String?,
      retries: map['retries'] as int? ?? 0,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'bucket': bucket,
      'remote_path': remotePath,
      'local_path': localPath,
      'content_type': contentType,
      'retries': retries,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
