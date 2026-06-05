import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../sync_adapter.dart';
import '../sync_queue.dart';

/// A [SyncAdapter] that pushes mutations to a REST API.
class RestSyncAdapter implements SyncAdapter {
  final String baseUrl;
  final FutureOr<Map<String, String>> Function()? headersBuilder;
  final http.Client _client;
  final String primaryKeyName;
  final bool usePutForUpdate;

  RestSyncAdapter({
    required this.baseUrl,
    this.headersBuilder,
    http.Client? client,
    this.primaryKeyName = 'id',
    this.usePutForUpdate = false,
  }) : _client = client ?? http.Client();

  @override
  Future<void> sync(
    String table,
    String operationType,
    Map<String, dynamic> payload,
  ) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (headersBuilder != null) {
      headers.addAll(await headersBuilder!());
    }

    http.Response response;

    try {
      if (operationType == 'insert') {
        final uri = Uri.parse('$baseUrl/$table');
        response = await _client.post(
          uri,
          headers: headers,
          body: json.encode(payload),
        );
      } else if (operationType == 'update') {
        final id =
            SyncAdapter.extractPrimaryKey(payload, keyName: primaryKeyName);
        if (id == null) {
          throw TerminalSyncException(
              'Could not extract primary key "$primaryKeyName" from update payload.');
        }

        final uri = Uri.parse('$baseUrl/$table/$id');
        final updateData = payload['data'] ?? {};

        if (usePutForUpdate) {
          response = await _client.put(
            uri,
            headers: headers,
            body: json.encode(updateData),
          );
        } else {
          response = await _client.patch(
            uri,
            headers: headers,
            body: json.encode(updateData),
          );
        }
      } else if (operationType == 'delete') {
        final id =
            SyncAdapter.extractPrimaryKey(payload, keyName: primaryKeyName);
        if (id == null) {
          throw TerminalSyncException(
              'Could not extract primary key "$primaryKeyName" from delete payload.');
        }

        final uri = Uri.parse('$baseUrl/$table/$id');
        response = await _client.delete(
          uri,
          headers: headers,
        );
      } else {
        throw TerminalSyncException('Unknown operation type: $operationType');
      }
    } on http.ClientException catch (e) {
      // ClientExceptions are typically network errors, meaning they are transient
      throw Exception('Network connection failed: $e');
    } on TimeoutException catch (e) {
      throw Exception('Network request timed out: $e');
    }

    // Process HTTP response
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return; // Success!
    }

    // Handle failure modes
    final errorMsg =
        'REST sync failed status: ${response.statusCode}, body: ${response.body}';

    // 4xx client errors (except 408 Timeout and 429 Too Many Requests) are terminal
    if (response.statusCode >= 400 &&
        response.statusCode < 500 &&
        response.statusCode != 408 &&
        response.statusCode != 429) {
      throw TerminalSyncException(errorMsg);
    } else {
      // 5xx and other statuses are treated as transient failures for retry
      throw Exception(errorMsg);
    }
  }
}
