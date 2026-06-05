import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart' hide User;
import 'package:syncdrift_flutter/syncdrift_flutter.dart';
import 'package:example_app/database.dart';
import 'package:example_app/database.syncdrift.dart';

// --- Mocks ---

/// Mock HTTP Client to verify RestSyncAdapter requests.
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

/// Mock Supabase Client to verify SupabaseSyncAdapter operations.
class MockSupabaseClient implements SupabaseClient {
  final List<Map<String, dynamic>> calls = [];
  Object? errorToThrow;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #from) {
      final table = invocation.positionalArguments[0] as String;
      return MockSupabaseQueryBuilder(table, this);
    }
    return super.noSuchMethod(invocation);
  }
}

class MockSupabaseQueryBuilder implements SupabaseQueryBuilder {
  final String table;
  final MockSupabaseClient client;

  MockSupabaseQueryBuilder(this.table, this.client);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    if (name == #insert) {
      final values = invocation.positionalArguments[0];
      client.calls.add({
        'table': table,
        'op': 'insert',
        'values': values,
      });
      if (client.errorToThrow != null) {
        throw client.errorToThrow!;
      }
      return MockPostgrestFilterBuilder(client);
    } else if (name == #update) {
      final values = invocation.positionalArguments[0];
      client.calls.add({
        'table': table,
        'op': 'update',
        'values': values,
      });
      if (client.errorToThrow != null) {
        throw client.errorToThrow!;
      }
      return MockPostgrestFilterBuilder(client);
    } else if (name == #delete) {
      client.calls.add({
        'table': table,
        'op': 'delete',
      });
      if (client.errorToThrow != null) {
        throw client.errorToThrow!;
      }
      return MockPostgrestFilterBuilder(client);
    }
    return super.noSuchMethod(invocation);
  }
}

class MockPostgrestFilterBuilder implements Future, PostgrestFilterBuilder {
  final MockSupabaseClient client;
  final Future<dynamic> _future = Future.value(null);

  MockPostgrestFilterBuilder(this.client);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    if (name == #eq) {
      final column = invocation.positionalArguments[0] as String;
      final value = invocation.positionalArguments[1];
      final lastCall = client.calls.last;
      lastCall['eq_column'] = column;
      lastCall['eq_value'] = value;
      return this;
    }
    return super.noSuchMethod(invocation);
  }

  @override
  Future<R> then<R>(FutureOr<R> Function(dynamic value) onValue,
      {Function? onError}) {
    return _future.then(onValue, onError: onError);
  }

  @override
  Future<dynamic> catchError(Function onError,
      {bool Function(Object error)? test}) {
    return _future.catchError(onError, test: test);
  }

  @override
  Future<dynamic> timeout(Duration timeLimit,
      {FutureOr<dynamic> Function()? onTimeout}) {
    return _future.timeout(timeLimit, onTimeout: onTimeout);
  }

  @override
  Future<dynamic> whenComplete(FutureOr<void> Function() action) {
    return _future.whenComplete(action);
  }

  @override
  Stream<dynamic> asStream() => _future.asStream();
}

/// Mock RealtimeAdapter to push fake remote updates to RealtimeSyncManager.
class MockRealtimeAdapter implements RealtimeAdapter {
  final StreamController<RealtimeEvent> _controller =
      StreamController<RealtimeEvent>.broadcast();
  bool isConnected = false;

  @override
  Stream<RealtimeEvent> get events => _controller.stream;

  @override
  Future<void> connect() async {
    isConnected = true;
  }

  @override
  Future<void> disconnect() async {
    isConnected = false;
  }

  void pushEvent(RealtimeEvent event) {
    _controller.add(event);
  }
}

// --- Tests ---

void main() {
  group('RestSyncAdapter Tests', () {
    late List<Map<String, dynamic>> requests;
    late http.Client mockClient;
    late RestSyncAdapter restAdapter;

    setUp(() {
      requests = [];
      mockClient = MockHttpClient((request) async {
        String? body;
        if (request is http.Request) {
          body = request.body;
        }
        requests.add({
          'method': request.method,
          'url': request.url.toString(),
          'headers': request.headers,
          'body': body != null && body.isNotEmpty ? json.decode(body) : null,
        });
        return http.Response('{"status": "ok"}', 200);
      });

      restAdapter = RestSyncAdapter(
        baseUrl: 'https://api.example.com',
        client: mockClient,
        headersBuilder: () => {'Authorization': 'Bearer test-token'},
      );
    });

    test('Maps insert mutations correctly', () async {
      await restAdapter.sync('users', 'insert', {'id': 10, 'name': 'Alice'});

      expect(requests.length, 1);
      expect(requests[0]['method'], 'POST');
      expect(requests[0]['url'], 'https://api.example.com/users');
      expect(requests[0]['headers']['Authorization'], 'Bearer test-token');
      expect(requests[0]['body']['name'], 'Alice');
      expect(requests[0]['body']['id'], 10);
    });

    test('Maps update mutations correctly extracting URL ID', () async {
      await restAdapter.sync('users', 'update', {
        'data': {'name': 'Bob'},
        'where': 'id = ?',
        'whereArgs': [10]
      });

      expect(requests.length, 1);
      expect(requests[0]['method'], 'PATCH');
      expect(requests[0]['url'], 'https://api.example.com/users/10');
      expect(requests[0]['body']['name'], 'Bob');
    });

    test('Maps delete mutations correctly extracting URL ID', () async {
      await restAdapter.sync('users', 'delete', {
        'where': 'id = ?',
        'whereArgs': [15]
      });

      expect(requests.length, 1);
      expect(requests[0]['method'], 'DELETE');
      expect(requests[0]['url'], 'https://api.example.com/users/15');
      expect(requests[0]['body'], isNull);
    });

    test('HTTP Client errors throw normal transient exception', () async {
      restAdapter = RestSyncAdapter(
        baseUrl: 'https://api.example.com',
        client: MockHttpClient(
            (req) async => throw http.ClientException('timeout')),
      );

      expect(
        () => restAdapter.sync('users', 'insert', {'id': 1}),
        throwsA(isNot(isA<TerminalSyncException>())),
      );
    });

    test('HTTP 400 Client error throws TerminalSyncException', () async {
      restAdapter = RestSyncAdapter(
        baseUrl: 'https://api.example.com',
        client:
            MockHttpClient((req) async => http.Response('Bad Request', 400)),
      );

      expect(
        () => restAdapter.sync('users', 'insert', {'id': 1}),
        throwsA(isA<TerminalSyncException>()),
      );
    });

    test('HTTP 500 Server error throws standard Exception (transient)',
        () async {
      restAdapter = RestSyncAdapter(
        baseUrl: 'https://api.example.com',
        client:
            MockHttpClient((req) async => http.Response('Server error', 500)),
      );

      expect(
        () => restAdapter.sync('users', 'insert', {'id': 1}),
        throwsA(isNot(isA<TerminalSyncException>())),
      );
    });
  });

  group('SupabaseSyncAdapter Tests', () {
    late MockSupabaseClient mockSupabase;
    late SupabaseSyncAdapter supabaseAdapter;

    setUp(() {
      mockSupabase = MockSupabaseClient();
      supabaseAdapter = SupabaseSyncAdapter(supabase: mockSupabase);
    });

    test('Maps mutations to Supabase Client correctly', () async {
      // 1. Insert
      await supabaseAdapter.sync('users', 'insert', {'id': 12, 'name': 'Dave'});
      expect(mockSupabase.calls.length, 1);
      expect(mockSupabase.calls[0]['op'], 'insert');
      expect(mockSupabase.calls[0]['table'], 'users');
      expect(mockSupabase.calls[0]['values']['name'], 'Dave');

      // 2. Update
      await supabaseAdapter.sync('users', 'update', {
        'data': {'name': 'Dave Updated'},
        'where': 'id = ?',
        'whereArgs': [12]
      });
      expect(mockSupabase.calls.length, 2);
      expect(mockSupabase.calls[1]['op'], 'update');
      expect(mockSupabase.calls[1]['values']['name'], 'Dave Updated');
      expect(mockSupabase.calls[1]['eq_column'], 'id');
      expect(mockSupabase.calls[1]['eq_value'], 12);

      // 3. Delete
      await supabaseAdapter.sync('users', 'delete', {
        'where': 'id = ?',
        'whereArgs': [12]
      });
      expect(mockSupabase.calls.length, 3);
      expect(mockSupabase.calls[3 - 1]['op'], 'delete');
      expect(mockSupabase.calls[3 - 1]['eq_column'], 'id');
      expect(mockSupabase.calls[3 - 1]['eq_value'], 12);
    });

    test('Maps PostgrestException to TerminalSyncException', () async {
      mockSupabase.errorToThrow = PostgrestException(
          message: 'Duplicate key value violates unique constraint',
          code: '23505');

      expect(
        () => supabaseAdapter.sync('users', 'insert', {'id': 1}),
        throwsA(isA<TerminalSyncException>()),
      );
    });
  });

  group('Loop Prevention & Realtime synchronization', () {
    late AppDatabase db;
    late DriftDatabaseDriver baseDriver;
    late SyncDatabaseDriver syncDriver;
    late MockRealtimeAdapter mockRealtimeAdapter;
    late RealtimeSyncManager realtimeSyncManager;
    late UserRepository userRepo;

    setUp(() async {
      db = AppDatabase();
      baseDriver = DriftDatabaseDriver(db);

      syncDriver = SyncDatabaseDriver(
        delegate: baseDriver,
        syncTables: syncdriftSyncTables,
      );
      await syncDriver.init();

      mockRealtimeAdapter = MockRealtimeAdapter();

      realtimeSyncManager = RealtimeSyncManager(
        dbDriver: syncDriver,
        adapters: [mockRealtimeAdapter],
        onError: (err, stack) {
          fail('RealtimeSyncManager error: $err\n$stack');
        },
      );

      await realtimeSyncManager.start();

      userRepo = UserRepository(syncDriver);
    });

    tearDown(() async {
      await realtimeSyncManager.stop();
      await syncDriver.close();
    });

    test('runWithoutQueue bypasses pending operations queue completely',
        () async {
      await SyncDatabaseDriver.runWithoutQueue(() async {
        await userRepo
            .insertCompanion(UsersCompanion.insert(name: 'Bypassed User'));
      });

      // Assert row is written locally
      final users = await userRepo.selectAll();
      expect(users.length, 1);
      expect(users[0].name, 'Bypassed User');

      // Assert outbound sync queue remains empty
      final pending = await syncDriver.select('pending_operations');
      expect(pending, isEmpty);
    });

    test('Normal write without runWithoutQueue does enqueue outbound operation',
        () async {
      await userRepo
          .insertCompanion(UsersCompanion.insert(name: 'Normal User'));

      final pending = await syncDriver.select('pending_operations');
      expect(pending.length, 1);
    });

    test(
        'RealtimeSyncManager receives push updates and updates local SQLite bypassing queue',
        () async {
      // 1. Trigger remote push insert
      mockRealtimeAdapter.pushEvent(RealtimeEvent(
        table: 'users',
        eventType: 'insert',
        record: {'id': 42, 'name': 'Push User'},
      ));

      // Wait for stream event to propagate
      await Future.delayed(const Duration(milliseconds: 100));

      // Assert applied locally
      final users = await userRepo.selectAll();
      expect(users.length, 1);
      expect(users[0].id, 42);
      expect(users[0].name, 'Push User');

      // Assert loop prevention worked (outbound queue remains empty)
      var pending = await syncDriver.select('pending_operations');
      expect(pending, isEmpty);

      // 2. Trigger remote push update
      mockRealtimeAdapter.pushEvent(RealtimeEvent(
        table: 'users',
        eventType: 'update',
        record: {'id': 42, 'name': 'Push User Updated'},
      ));

      await Future.delayed(const Duration(milliseconds: 100));

      final updatedUsers = await userRepo.selectAll();
      expect(updatedUsers.length, 1);
      expect(updatedUsers[0].name, 'Push User Updated');

      pending = await syncDriver.select('pending_operations');
      expect(pending, isEmpty);

      // 3. Trigger remote push delete
      mockRealtimeAdapter.pushEvent(RealtimeEvent(
        table: 'users',
        eventType: 'delete',
        record: {'id': 42},
        oldRecord: {'id': 42},
      ));

      await Future.delayed(const Duration(milliseconds: 100));

      final finalUsers = await userRepo.selectAll();
      expect(finalUsers, isEmpty);

      pending = await syncDriver.select('pending_operations');
      expect(pending, isEmpty);
    });

    test(
        'RealtimeSyncManager triggers reactive streams (.obs) and updates watchers',
        () async {
      final streamList = <List<User>>[];
      final sub = userRepo.watchAll().listen(streamList.add);

      // Initial state
      await Future.delayed(Duration.zero);
      expect(streamList.length, 1);
      expect(streamList[0], isEmpty);

      // Push insert event
      mockRealtimeAdapter.pushEvent(RealtimeEvent(
        table: 'users',
        eventType: 'insert',
        record: {'id': 99, 'name': 'Reactive Push'},
      ));

      await Future.delayed(const Duration(milliseconds: 100));

      // Watcher must receive update
      expect(streamList.length, 2);
      expect(streamList[1].length, 1);
      expect(streamList[1][0].name, 'Reactive Push');

      await sub.cancel();
    });
  });
}
