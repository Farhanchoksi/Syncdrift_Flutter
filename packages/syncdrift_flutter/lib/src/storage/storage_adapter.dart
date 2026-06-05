/// Contract definition for remote cloud storage actions.
///
/// Implemented by backend storage adapters (Supabase Storage, REST Storage APIs).
abstract class StorageAdapter {
  /// Uploads a local file to a remote storage bucket.
  ///
  /// Returns the remote URL of the uploaded file on success.
  Future<String> upload(
    String bucket,
    String remotePath,
    String localPath,
    String? contentType,
  );

  /// Downloads a remote file from a bucket to a local filesystem path.
  Future<void> download(
    String bucket,
    String remotePath,
    String localPath,
  );

  /// Deletes a remote file from a bucket.
  Future<void> delete(
    String bucket,
    String remotePath,
  );
}
