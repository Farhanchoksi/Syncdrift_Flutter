import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../../sync/sync_queue.dart';
import '../storage_adapter.dart';

/// A [StorageAdapter] that reads/writes files to a REST API.
class RestStorageAdapter implements StorageAdapter {
  final String baseUrl;
  final FutureOr<Map<String, String>> Function()? headersBuilder;
  final http.Client _client;
  final bool usePutForUpload;

  RestStorageAdapter({
    required this.baseUrl,
    this.headersBuilder,
    http.Client? client,
    this.usePutForUpload = false,
  }) : _client = client ?? http.Client();

  @override
  Future<String> upload(
    String bucket,
    String remotePath,
    String localPath,
    String? contentType,
  ) async {
    final uri = Uri.parse('$baseUrl/$bucket/$remotePath');
    final file = File(localPath);
    if (!await file.exists()) {
      throw TerminalSyncException('Local file does not exist at: $localPath');
    }

    final request = http.MultipartRequest(
      usePutForUpload ? 'PUT' : 'POST',
      uri,
    );

    if (headersBuilder != null) {
      request.headers.addAll(await headersBuilder!());
    }

    final mimeType = contentType ?? 'application/octet-stream';
    final parts = mimeType.split('/');
    final mediaType = parts.length == 2
        ? MediaType(parts[0], parts[1])
        : MediaType('application', 'octet-stream');

    final multipartFile = await http.MultipartFile.fromPath(
      'file',
      localPath,
      contentType: mediaType,
    );

    request.files.add(multipartFile);

    try {
      final streamedResponse = await _client.send(request);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return uri.toString(); // Return remote URL
      }

      final errorMsg =
          'REST storage upload failed status: ${response.statusCode}, body: ${response.body}';

      if (response.statusCode >= 400 &&
          response.statusCode < 500 &&
          response.statusCode != 408 &&
          response.statusCode != 429) {
        throw TerminalSyncException(errorMsg);
      } else {
        throw Exception(errorMsg);
      }
    } on http.ClientException catch (e) {
      throw Exception('Network connection failed: $e');
    } on TimeoutException catch (e) {
      throw Exception('Request timed out: $e');
    }
  }

  @override
  Future<void> download(
    String bucket,
    String remotePath,
    String localPath,
  ) async {
    final uri = Uri.parse('$baseUrl/$bucket/$remotePath');
    final headers = <String, String>{};
    if (headersBuilder != null) {
      headers.addAll(await headersBuilder!());
    }

    try {
      final response = await _client.get(uri, headers: headers);

      if (response.statusCode == 200) {
        final file = File(localPath);
        await file.create(recursive: true);
        await file.writeAsBytes(response.bodyBytes);
        return;
      }

      final errorMsg =
          'REST storage download failed status: ${response.statusCode}, body: ${response.body}';

      if (response.statusCode >= 400 &&
          response.statusCode < 500 &&
          response.statusCode != 408 &&
          response.statusCode != 429) {
        throw TerminalSyncException(errorMsg);
      } else {
        throw Exception(errorMsg);
      }
    } on http.ClientException catch (e) {
      throw Exception('Network connection failed: $e');
    } on TimeoutException catch (e) {
      throw Exception('Request timed out: $e');
    }
  }

  @override
  Future<void> delete(String bucket, String remotePath) async {
    final uri = Uri.parse('$baseUrl/$bucket/$remotePath');
    final headers = <String, String>{};
    if (headersBuilder != null) {
      headers.addAll(await headersBuilder!());
    }

    try {
      final response = await _client.delete(uri, headers: headers);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return;
      }

      final errorMsg =
          'REST storage delete failed status: ${response.statusCode}, body: ${response.body}';

      if (response.statusCode >= 400 &&
          response.statusCode < 500 &&
          response.statusCode != 408 &&
          response.statusCode != 429) {
        throw TerminalSyncException(errorMsg);
      } else {
        throw Exception(errorMsg);
      }
    } on http.ClientException catch (e) {
      throw Exception('Network connection failed: $e');
    } on TimeoutException catch (e) {
      throw Exception('Request timed out: $e');
    }
  }
}
