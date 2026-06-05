import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../driver.dart';
import '../sync/sync_queue.dart';
import 'storage_models.dart';
import 'storage_adapter.dart';

/// Manages caching remote files locally and background queue synchronization of offline writes.
class SyncdriftStorageManager {
  final DatabaseDriver dbDriver;
  final StorageAdapter storageAdapter;
  final Connectivity connectivity;
  final int maxRetries;
  final String? customCacheDir;
  final void Function(Object error, StackTrace stackTrace)? onError;

  late String _baseCacheDir;
  bool _isProcessing = false;
  DateTime? _backoffUntil;
  StreamSubscription? _connectivitySubscription;
  bool _initialized = false;

  SyncdriftStorageManager({
    required this.dbDriver,
    required this.storageAdapter,
    Connectivity? connectivity,
    this.maxRetries = 5,
    this.customCacheDir,
    this.onError,
  }) : connectivity = connectivity ?? Connectivity();

  /// Resolves filesystem folders and creates tracking tables in SQLite.
  Future<void> init() async {
    if (_initialized) return;

    // Resolve local cache folder
    if (customCacheDir != null) {
      _baseCacheDir = customCacheDir!;
    } else {
      final appDir = await getApplicationDocumentsDirectory();
      _baseCacheDir = p.join(appDir.path, 'syncdrift_storage_cache');
    }

    final cacheDir = Directory(_baseCacheDir);
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }

    // Create database tables if they do not exist
    await dbDriver.execute('''
      CREATE TABLE IF NOT EXISTS pending_uploads (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        bucket TEXT NOT NULL,
        remote_path TEXT NOT NULL,
        local_path TEXT NOT NULL,
        content_type TEXT,
        retries INTEGER DEFAULT 0,
        created_at TEXT NOT NULL
      );
    ''');

    await dbDriver.execute('''
      CREATE TABLE IF NOT EXISTS failed_uploads (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        bucket TEXT NOT NULL,
        remote_path TEXT NOT NULL,
        local_path TEXT NOT NULL,
        error_message TEXT,
        created_at TEXT NOT NULL
      );
    ''');

    // Setup network listener
    _connectivitySubscription =
        connectivity.onConnectivityChanged.listen((event) {
      final isOnline = event.any((r) => r != ConnectivityResult.none);
      if (isOnline) {
        triggerUploadQueue();
      }
    });

    _initialized = true;
  }

  /// Closes network subscriptions.
  void dispose() {
    _connectivitySubscription?.cancel();
  }

  /// Resets the exponential backoff timer, allowing sync to run immediately.
  void resetBackoff() {
    _backoffUntil = null;
  }

  /// Retrieves a local file path.
  ///
  /// Instantly serves the local cached path if the file exists.
  /// Otherwise, downloads the remote file from cloud storage.
  Future<String> getFile(String bucket, String remotePath) async {
    final cachedLocalPath = p.join(_baseCacheDir, bucket, remotePath);
    final file = File(cachedLocalPath);

    if (await file.exists()) {
      return cachedLocalPath;
    }

    // Download from remote bucket
    await file.create(recursive: true);
    try {
      await storageAdapter.download(bucket, remotePath, cachedLocalPath);
    } catch (e) {
      // Clean up empty file on error
      if (await file.exists()) {
        await file.delete();
      }
      rethrow;
    }

    return cachedLocalPath;
  }

  /// Queues a local file for upload to the remote storage bucket.
  ///
  /// Instantly saves a copy of the file in the local cache, enabling offline access,
  /// and schedules the upload when connectivity is available.
  Future<void> queueUpload(
    String bucket,
    String remotePath,
    String localPath, {
    String? contentType,
  }) async {
    final cachedLocalPath = p.join(_baseCacheDir, bucket, remotePath);

    // Copy to secure cached directory if not already there
    if (localPath != cachedLocalPath) {
      final cachedFile = File(cachedLocalPath);
      await cachedFile.create(recursive: true);
      await File(localPath).copy(cachedLocalPath);
    }

    final op = PendingUpload(
      bucket: bucket,
      remotePath: remotePath,
      localPath: cachedLocalPath,
      contentType: contentType,
      createdAt: DateTime.now(),
    );

    await dbDriver.insert('pending_uploads', op.toMap());
    triggerUploadQueue();
  }

  /// Manually trigger upload queue processing.
  Future<void> triggerUploadQueue() async {
    if (_isProcessing) return;
    if (_backoffUntil != null && DateTime.now().isBefore(_backoffUntil!)) {
      return;
    }

    _isProcessing = true;
    try {
      await _processUploadQueue();
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _processUploadQueue() async {
    while (true) {
      // Check connectivity
      final status = await connectivity.checkConnectivity();
      final isOnline = status.any((r) => r != ConnectivityResult.none);
      if (!isOnline) break;

      // Select oldest pending upload
      final rows = await dbDriver.select(
        'pending_uploads',
        orderBy: 'id ASC',
        limit: 1,
      );

      if (rows.isEmpty) break;

      final op = PendingUpload.fromMap(rows.first);

      try {
        await storageAdapter.upload(
          op.bucket,
          op.remotePath,
          op.localPath,
          op.contentType,
        );

        // Delete from local queue
        await dbDriver.delete(
          'pending_uploads',
          where: 'id = ?',
          whereArgs: [op.id],
        );
      } catch (e) {
        if (e is TerminalSyncException) {
          await _evictToFailed(op, e.toString());
        } else {
          final nextRetries = op.retries + 1;
          if (nextRetries >= maxRetries) {
            await _evictToFailed(
              op,
              'Max retries ($maxRetries) exceeded. Error: $e',
            );
          } else {
            await dbDriver.update(
              'pending_uploads',
              {'retries': nextRetries},
              where: 'id = ?',
              whereArgs: [op.id],
            );

            // Apply exponential backoff delay (2^retries seconds)
            final backoffSeconds = 1 << nextRetries;
            _backoffUntil =
                DateTime.now().add(Duration(seconds: backoffSeconds));
            break; // Break loop
          }
        }
      }
    }
  }

  Future<void> _evictToFailed(PendingUpload op, String error) async {
    final failedRecord = {
      'bucket': op.bucket,
      'remote_path': op.remotePath,
      'local_path': op.localPath,
      'error_message': error,
      'created_at': DateTime.now().toIso8601String(),
    };

    await dbDriver.insert('failed_uploads', failedRecord);

    await dbDriver.delete(
      'pending_uploads',
      where: 'id = ?',
      whereArgs: [op.id],
    );
  }
}
