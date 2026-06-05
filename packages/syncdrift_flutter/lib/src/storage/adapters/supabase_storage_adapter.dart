import 'dart:io';
import 'package:supabase/supabase.dart';
import '../../sync/sync_queue.dart';
import '../storage_adapter.dart';

/// A [StorageAdapter] that reads/writes files to Supabase Storage buckets.
class SupabaseStorageAdapter implements StorageAdapter {
  final SupabaseClient supabase;

  SupabaseStorageAdapter({required this.supabase});

  @override
  Future<String> upload(
    String bucket,
    String remotePath,
    String localPath,
    String? contentType,
  ) async {
    final file = File(localPath);
    if (!await file.exists()) {
      throw TerminalSyncException('Local file does not exist at: $localPath');
    }

    try {
      await supabase.storage.from(bucket).upload(
            remotePath,
            file,
            fileOptions: FileOptions(
              contentType: contentType,
              upsert: true,
            ),
          );

      return supabase.storage.from(bucket).getPublicUrl(remotePath);
    } on StorageException catch (e) {
      final errorMsg =
          'Supabase storage upload failed: ${e.message} (status: ${e.statusCode})';

      // Status codes >= 400 and < 500 (excluding 408/429) represent terminal client-side failures
      final status = int.tryParse(e.statusCode ?? '') ?? 0;
      if (status >= 400 && status < 500 && status != 408 && status != 429) {
        throw TerminalSyncException(errorMsg);
      } else {
        throw Exception(errorMsg);
      }
    } catch (e) {
      throw Exception('Supabase storage upload transient error: $e');
    }
  }

  @override
  Future<void> download(
    String bucket,
    String remotePath,
    String localPath,
  ) async {
    try {
      final bytes = await supabase.storage.from(bucket).download(remotePath);
      final file = File(localPath);
      await file.create(recursive: true);
      await file.writeAsBytes(bytes);
    } on StorageException catch (e) {
      final errorMsg =
          'Supabase storage download failed: ${e.message} (status: ${e.statusCode})';
      final status = int.tryParse(e.statusCode ?? '') ?? 0;
      if (status >= 400 && status < 500 && status != 408 && status != 429) {
        throw TerminalSyncException(errorMsg);
      } else {
        throw Exception(errorMsg);
      }
    } catch (e) {
      throw Exception('Supabase storage download transient error: $e');
    }
  }

  @override
  Future<void> delete(String bucket, String remotePath) async {
    try {
      await supabase.storage.from(bucket).remove([remotePath]);
    } on StorageException catch (e) {
      final errorMsg =
          'Supabase storage delete failed: ${e.message} (status: ${e.statusCode})';
      final status = int.tryParse(e.statusCode ?? '') ?? 0;
      if (status >= 400 && status < 500 && status != 408 && status != 429) {
        throw TerminalSyncException(errorMsg);
      } else {
        throw Exception(errorMsg);
      }
    } catch (e) {
      throw Exception('Supabase storage delete transient error: $e');
    }
  }
}
