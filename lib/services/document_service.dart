import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../core/config/app_config.dart';
import '../core/utils/logger.dart';

class DocumentService {
  static final DocumentService _instance = DocumentService._internal();
  factory DocumentService() => _instance;
  DocumentService._internal();

  final Dio _dio = Dio();
  final Map<String, String> _cache = {};
  bool _initialized = false;

  String get _documentsDir => 'documents';

  Future<void> init() async {
    if (_initialized) return;
    final dir = await getApplicationDocumentsDirectory();
    final docsDir = Directory('${dir.path}/$_documentsDir');
    if (!await docsDir.exists()) {
      await docsDir.create(recursive: true);
    }
    _initialized = true;
    _cleanup().catchError((e) {
      Log.w('[DocumentService] Cache cleanup failed: $e');
    });
    Log.i('[DocumentService] Initialized (cache dir: ${docsDir.path})');
  }

  String? getCachedPath(String url) => _cache[url];

  bool isCached(String url) => _cache.containsKey(url);

  Future<String?> downloadDocument(
    String url,
    String fileName, {
    void Function(double progress)? onProgress,
  }) async {
    if (!_initialized) await init();

    // Local file path — just verify it exists and return directly
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      final localFile = File(url);
      if (await localFile.exists()) {
        _cache[url] = url;
        Log.i('[DocumentService] Using local file: $url');
        return url;
      }
      Log.e('[DocumentService] Local file not found: $url');
      return null;
    }

    if (_cache.containsKey(url)) return _cache[url];

    final dir = await getApplicationDocumentsDirectory();
    final docsDir = '${dir.path}/$_documentsDir';
    final safeName = _sanitizeFileName(fileName);
    final filePath = '$docsDir/$safeName';
    final file = File(filePath);

    if (await file.exists()) {
      _cache[url] = filePath;
      Log.i('[DocumentService] Using cached document: $filePath');
      return filePath;
    }

    try {
      Log.i('[DocumentService] Downloading: $url -> $filePath');
      await _dio.download(
        url,
        filePath,
        onReceiveProgress: (received, total) {
          if (total > 0 && onProgress != null) {
            onProgress(received / total);
          }
        },
      );
      _cache[url] = filePath;
      Log.i('[DocumentService] Downloaded: $filePath');
      return filePath;
    } catch (e) {
      Log.e('[DocumentService] Download failed: $e');
      if (await file.exists()) {
        await file.delete();
      }
      return null;
    }
  }

  Future<void> clearCache() async {
    _cache.clear();
    final dir = await getApplicationDocumentsDirectory();
    final docsDir = Directory('${dir.path}/$_documentsDir');
    if (await docsDir.exists()) {
      await docsDir.delete(recursive: true);
      await docsDir.create(recursive: true);
    }
    Log.i('[DocumentService] Cache cleared');
  }

  Future<void> _cleanup() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final docsDir = Directory('${dir.path}/$_documentsDir');
      if (!await docsDir.exists()) return;

      final cutoff = DateTime.now().subtract(
        Duration(days: AppConfig.documentCacheMaxDays),
      );
      int totalSize = 0;
      final files = <FileSystemEntity>[];
      await for (final entity in docsDir.list()) {
        files.add(entity);
        if (entity is File) {
          try {
            totalSize += await entity.length();
          } catch (_) {}
        }
      }

      for (final file in files) {
        try {
          final stat = await file.stat();
          if (stat.modified.isBefore(cutoff)) {
            await file.delete();
            Log.i('[DocumentService] Cleaned expired: ${file.path}');
          }
        } catch (_) {}
      }

      if (totalSize > AppConfig.documentCacheMaxMb * 1024 * 1024) {
        files.sort((a, b) {
          final sa = a is File ? (a.statSync().modified) : DateTime.now();
          final sb = b is File ? (b.statSync().modified) : DateTime.now();
          return sa.compareTo(sb);
        });
        for (final file in files) {
          if (totalSize <= AppConfig.documentCacheMaxMb * 1024 * 1024) break;
          try {
            final len = file is File ? await file.length() : 0;
            await file.delete();
            totalSize -= len;
            Log.i('[DocumentService] Cleaned oversized: ${file.path}');
          } catch (_) {}
        }
      }
    } catch (e) {
      Log.w('[DocumentService] Cleanup error: $e');
    }
  }

  String _sanitizeFileName(String name) {
    final safe = name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final now = DateTime.now().millisecondsSinceEpoch;
    if (safe.length > 100) {
      final ext = safe.contains('.')
          ? '.${safe.split('.').last}'
          : '';
      return '${safe.substring(0, 80)}_$now$ext';
    }
    if (!safe.contains('.')) return safe;
    return safe;
  }
}
