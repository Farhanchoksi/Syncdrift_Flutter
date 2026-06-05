import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path/path.dart' as p;
import 'package:syncdrift_flutter/syncdrift_flutter.dart';
import 'package:example_app/database.dart';

// --- Mocks ---

class MockConnectivity implements Connectivity {
  final _controller = StreamController<List<ConnectivityResult>>.broadcast();
  List<ConnectivityResult> _current = [ConnectivityResult.none];

  void setConnection(List<ConnectivityResult> results) {
    _current = results;
    _controller.add(results);
  }

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _controller.stream;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async {
    return _current;
  }
}

class MockHttpClient extends http.BaseClient {
  final Future<http.Response> Function(http.BaseRequest request) handler;
  MockHttpClient(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final res = await handler(request);
    final stream = Stream.value(res.bodyBytes);
    return http.StreamedResponse(
      stream,
      res.statusCode,
      contentLength: res.contentLength,
      request: request,
      headers: res.headers,
      isRedirect: res.isRedirect,
      persistentConnection: res.persistentConnection,
      reasonPhrase: res.reasonPhrase,
    );
  }
}

class MockSupabaseClient implements SupabaseClient {
  final List<Map<String, dynamic>> calls = [];
  Object? errorToThrow;

  @override
  MockSupabaseStorageClient get storage => MockSupabaseStorageClient(this);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockSupabaseStorageClient implements SupabaseStorageClient {
  final MockSupabaseClient client;
  MockSupabaseStorageClient(this.client);

  @override
  StorageFileApi from(String id) {
    return MockSupabaseStorageBucketApi(id, client);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockSupabaseStorageBucketApi implements StorageFileApi {
  final String bucketId;
  final MockSupabaseClient client;

  MockSupabaseStorageBucketApi(this.bucketId, this.client);

  @override
  Future<String> upload(
    String path,
    File file, {
    FileOptions fileOptions = const FileOptions(),
    int? retryAttempts,
    StorageRetryController? retryController,
  }) async {
    client.calls.add({
      'bucket': bucketId,
      'op': 'upload',
      'path': path,
      'file_path': file.path,
      'contentType': fileOptions.contentType,
    });
    if (client.errorToThrow != null) {
      throw client.errorToThrow!;
    }
    return 'uploaded_url';
  }

  @override
  Future<Uint8List> download(
    String path, {
    TransformOptions? transform,
    Map<String, String>? queryParams,
  }) async {
    client.calls.add({
      'bucket': bucketId,
      'op': 'download',
      'path': path,
    });
    if (client.errorToThrow != null) {
      throw client.errorToThrow!;
    }
    return Uint8List.fromList(utf8.encode('remote content'));
  }

  @override
  Future<List<FileObject>> remove(List<String> paths) async {
    client.calls.add({
      'bucket': bucketId,
      'op': 'remove',
      'paths': paths,
    });
    if (client.errorToThrow != null) {
      throw client.errorToThrow!;
    }
    return [];
  }

  @override
  String getPublicUrl(
    String path, {
    TransformOptions? transform,
  }) {
    return 'https://supabase-storage.co/$bucketId/$path';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockStorageAdapter implements StorageAdapter {
  final List<Map<String, dynamic>> calls = [];
  Object? errorToThrow;
  String Function(String bucket, String remotePath, String localPath)?
      downloadHandler;

  @override
  Future<String> upload(
    String bucket,
    String remotePath,
    String localPath,
    String? contentType,
  ) async {
    calls.add({
      'op': 'upload',
      'bucket': bucket,
      'remotePath': remotePath,
      'localPath': localPath,
      'contentType': contentType,
    });
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    return 'https://remote-storage.com/$bucket/$remotePath';
  }

  @override
  Future<void> download(
      String bucket, String remotePath, String localPath) async {
    calls.add({
      'op': 'download',
      'bucket': bucket,
      'remotePath': remotePath,
      'localPath': localPath,
    });
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    if (downloadHandler != null) {
      downloadHandler!(bucket, remotePath, localPath);
    } else {
      final file = File(localPath);
      await file.create(recursive: true);
      await file.writeAsString('remote mock content');
    }
  }

  @override
  Future<void> delete(String bucket, String remotePath) async {
    calls.add({
      'op': 'delete',
      'bucket': bucket,
      'remotePath': remotePath,
    });
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
  }
}

// --- Tests ---

void main() {
  group('RestStorageAdapter Tests', () {
    late List<Map<String, dynamic>> requests;
    late http.Client mockClient;
    late RestStorageAdapter adapter;
    late Directory tempDir;
    late File tempFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp();
      tempFile = File(p.join(tempDir.path, 'upload_me.png'));
      await tempFile.writeAsString('image data bytes');

      requests = [];
      mockClient = MockHttpClient((request) async {
        requests.add({
          'method': request.method,
          'url': request.url.toString(),
          'headers': request.headers,
          'type': request.runtimeType.toString(),
        });
        return http.Response('{"status": "ok"}', 200);
      });

      adapter = RestStorageAdapter(
        baseUrl: 'https://storage-api.co',
        client: mockClient,
        headersBuilder: () => {'Authorization': 'Bearer storage-token'},
      );
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('Upload sends multipart request correctly', () async {
      final remoteUrl = await adapter.upload(
        'photos',
        'avatars/alice.png',
        tempFile.path,
        'image/png',
      );

      expect(remoteUrl, 'https://storage-api.co/photos/avatars/alice.png');
      expect(requests.length, 1);
      expect(requests[0]['method'], 'POST');
      expect(requests[0]['url'],
          'https://storage-api.co/photos/avatars/alice.png');
      expect(requests[0]['headers']['Authorization'], 'Bearer storage-token');
      expect(requests[0]['type'], contains('MultipartRequest'));
    });

    test('Download writes remote bytes to local path correctly', () async {
      mockClient = MockHttpClient((req) async {
        return http.Response('mocked download payload', 200);
      });
      adapter = RestStorageAdapter(
          baseUrl: 'https://storage-api.co', client: mockClient);

      final savePath = p.join(tempDir.path, 'downloaded.txt');
      await adapter.download('docs', 'manual.txt', savePath);

      final downloadedFile = File(savePath);
      expect(await downloadedFile.exists(), isTrue);
      expect(await downloadedFile.readAsString(), 'mocked download payload');
    });

    test('HTTP 403 Forbidden throws TerminalSyncException', () async {
      adapter = RestStorageAdapter(
        baseUrl: 'https://storage-api.co',
        client: MockHttpClient((req) async => http.Response('Forbidden', 403)),
      );

      expect(
        () => adapter.upload('p', 'r', tempFile.path, 'text/plain'),
        throwsA(isA<TerminalSyncException>()),
      );
    });
  });

  group('SupabaseStorageAdapter Tests', () {
    late MockSupabaseClient mockSupabase;
    late SupabaseStorageAdapter adapter;
    late Directory tempDir;
    late File tempFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp();
      tempFile = File(p.join(tempDir.path, 'upload_me.txt'));
      await tempFile.writeAsString('supabase upload test');

      mockSupabase = MockSupabaseClient();
      adapter = SupabaseStorageAdapter(supabase: mockSupabase);
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('Maps uploads, downloads, and deletions to Supabase client API',
        () async {
      // 1. Upload
      final publicUrl = await adapter.upload(
          'docs', 'resumes/john.txt', tempFile.path, 'text/plain');
      expect(publicUrl, 'https://supabase-storage.co/docs/resumes/john.txt');
      expect(mockSupabase.calls.length, 1);
      expect(mockSupabase.calls[0]['op'], 'upload');
      expect(mockSupabase.calls[0]['bucket'], 'docs');
      expect(mockSupabase.calls[0]['path'], 'resumes/john.txt');
      expect(mockSupabase.calls[0]['contentType'], 'text/plain');

      // 2. Download
      final downloadPath = p.join(tempDir.path, 'download.txt');
      await adapter.download('docs', 'resumes/john.txt', downloadPath);
      expect(mockSupabase.calls.length, 2);
      expect(mockSupabase.calls[1]['op'], 'download');
      expect(File(downloadPath).existsSync(), isTrue);
      expect(File(downloadPath).readAsStringSync(), 'remote content');

      // 3. Delete
      await adapter.delete('docs', 'resumes/john.txt');
      expect(mockSupabase.calls.length, 3);
      expect(mockSupabase.calls[2]['op'], 'remove');
      expect(mockSupabase.calls[2]['paths'], ['resumes/john.txt']);
    });
  });

  group('SyncdriftStorageManager caching & queuing', () {
    late AppDatabase db;
    late DriftDatabaseDriver baseDriver;
    late MockStorageAdapter mockAdapter;
    late MockConnectivity mockConnectivity;
    late SyncdriftStorageManager manager;
    late Directory cacheDir;
    late Directory tempDir;

    setUp(() async {
      db = AppDatabase();
      baseDriver = DriftDatabaseDriver(db);
      mockAdapter = MockStorageAdapter();
      mockConnectivity = MockConnectivity();

      cacheDir = await Directory.systemTemp.createTemp();
      tempDir = await Directory.systemTemp.createTemp();

      manager = SyncdriftStorageManager(
        dbDriver: baseDriver,
        storageAdapter: mockAdapter,
        connectivity: mockConnectivity,
        customCacheDir: cacheDir.path,
        maxRetries: 3,
      );

      await manager.init();
    });

    tearDown(() async {
      manager.dispose();
      await db.close();
      await cacheDir.delete(recursive: true);
      await tempDir.delete(recursive: true);
    });

    test(
        'getFile downloads remote if missing, then serves instantly from cache',
        () async {
      // 1. First retrieval -> triggers adapter download
      final path = await manager.getFile('media', 'images/photo.jpg');

      expect(mockAdapter.calls.length, 1);
      expect(mockAdapter.calls[0]['op'], 'download');
      expect(File(path).existsSync(), isTrue);
      expect(File(path).readAsStringSync(), 'remote mock content');

      // 2. Second retrieval -> does not trigger download, instant resolution
      final path2 = await manager.getFile('media', 'images/photo.jpg');
      expect(path2, path);
      expect(mockAdapter.calls.length, 1); // no new download calls
    });

    test(
        'Offline upload enqueuing copies file locally and persists queue in SQLite',
        () async {
      mockConnectivity.setConnection([ConnectivityResult.none]);

      final fileToUpload = File(p.join(tempDir.path, 'item.pdf'));
      await fileToUpload.writeAsString('offline pdf payload');

      // Queue upload offline
      await manager.queueUpload(
          'files', 'documents/item.pdf', fileToUpload.path);

      // Verify file copied to cache folder (accessible offline instantly)
      final expectedCachePath =
          p.join(cacheDir.path, 'files', 'documents/item.pdf');
      expect(File(expectedCachePath).existsSync(), isTrue);
      expect(File(expectedCachePath).readAsStringSync(), 'offline pdf payload');

      // Verify enqueued in SQLite pending table
      final pending = await baseDriver.select('pending_uploads');
      expect(pending.length, 1);
      expect(pending[0]['bucket'], 'files');
      expect(pending[0]['remote_path'], 'documents/item.pdf');
      expect(pending[0]['local_path'], expectedCachePath);
      expect(mockAdapter.calls, isEmpty); // no upload calls yet

      // Trigger online recovery
      mockConnectivity.setConnection([ConnectivityResult.wifi]);
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify queue is drained and adapter received upload request
      final pendingAfter = await baseDriver.select('pending_uploads');
      expect(pendingAfter, isEmpty);
      expect(mockAdapter.calls.length, 1);
      expect(mockAdapter.calls[0]['op'], 'upload');
      expect(mockAdapter.calls[0]['bucket'], 'files');
      expect(mockAdapter.calls[0]['remotePath'], 'documents/item.pdf');
    });

    test(
        'Transient failures increment retries and pause queue, eventually evicting',
        () async {
      mockConnectivity.setConnection([ConnectivityResult.wifi]);
      mockAdapter.errorToThrow = Exception('Transient upload timeout');

      final uploadFile = File(p.join(tempDir.path, 'file.txt'));
      await uploadFile.writeAsString('transient content');

      await manager.queueUpload('txt', 'docs/file.txt', uploadFile.path);
      await Future.delayed(const Duration(milliseconds: 100));

      // Check retries incremented to 1
      var pending = await baseDriver.select('pending_uploads');
      expect(pending.length, 1);
      expect(pending[0]['retries'], 1);

      // Force mock updates for next tests
      mockAdapter.errorToThrow = Exception('Transient upload timeout');

      // Force retries increment to 2 and run trigger again (reaches 3, max retries limit)
      await baseDriver.update('pending_uploads', {'retries': 2},
          where: 'id = ?', whereArgs: [pending[0]['id']]);
      manager.resetBackoff();

      await manager.triggerUploadQueue();
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify evicted to failed uploads
      pending = await baseDriver.select('pending_uploads');
      expect(pending, isEmpty);

      final failed = await baseDriver.select('failed_uploads');
      expect(failed.length, 1);
      expect(failed[0]['bucket'], 'txt');
      expect(failed[0]['remote_path'], 'docs/file.txt');
      expect(failed[0]['error_message'], contains('Max retries (3) exceeded'));
    });
  });
}
