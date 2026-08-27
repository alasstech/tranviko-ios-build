import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'api_service.dart';
import 'local_cache_service.dart';

class StoryCacheService {
  static String get cacheKey {
    final company = ApiService.companyId ?? ApiService.companySlug ?? 'global';
    final user =
        ApiService.currentUser?['id']?.toString() ??
        ApiService.currentUser?['userId']?.toString() ??
        'traveler';
    return 'travel_stories_${company}_$user';
  }

  static bool stillActive(Map<String, dynamic> story) {
    final expires = DateTime.tryParse(story['expiresAt']?.toString() ?? '');
    return expires == null || expires.isAfter(DateTime.now());
  }

  static Future<List<Map<String, dynamic>>> readCachedStories() async {
    final rows = await LocalCacheService.readList(cacheKey);
    return rows.where(stillActive).map(Map<String, dynamic>.from).toList();
  }

  static Future<List<Map<String, dynamic>>> fetchAndCacheStories({
    bool prefetchMedia = true,
  }) async {
    final items = await ApiService.fetchTravelStories();
    final activeStories = items
        .where(stillActive)
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    await LocalCacheService.writeList(cacheKey, activeStories);
    if (!prefetchMedia) return activeStories;
    return prefetchStoryMedia(activeStories);
  }

  static Future<List<Map<String, dynamic>>> prefetchStoryMedia(
    List<Map<String, dynamic>> stories, {
    int limit = 80,
  }) async {
    if (stories.isEmpty) return stories;
    final cachedStories = <Map<String, dynamic>>[];
    for (var index = 0; index < stories.length; index++) {
      final story = await attachCachedStoryMedia(stories[index]);
      cachedStories.add(
        index < limit && !_mediaIsVideo(story)
            ? await cacheStoryMedia(story)
            : story,
      );
    }
    await LocalCacheService.writeList(cacheKey, cachedStories);
    return cachedStories;
  }

  static Future<Map<String, dynamic>> attachCachedStoryMedia(
    Map<String, dynamic> story,
  ) async {
    final next = Map<String, dynamic>.from(story);
    if (_cachedFileAvailable(next)) return next;
    final file = await _cacheFileFor(next, _mediaUrl(next));
    if (file != null && await file.exists()) {
      next['cachedMediaPath'] = file.path;
    }
    return next;
  }

  static Future<Map<String, dynamic>> cacheStoryMedia(
    Map<String, dynamic> story,
  ) async {
    final next = Map<String, dynamic>.from(story);
    if (_cachedFileAvailable(next)) return next;
    final url = _mediaUrl(next);
    if (url.isEmpty) return next;
    try {
      final file = await _cacheFileFor(next, url);
      if (file == null) return next;
      if (!await file.exists()) {
        final response = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 18));
        if (response.statusCode < 200 ||
            response.statusCode >= 300 ||
            response.bodyBytes.isEmpty) {
          return next;
        }
        await file.writeAsBytes(response.bodyBytes, flush: true);
      }
      next['cachedMediaPath'] = file.path;
    } catch (_) {
      return next;
    }
    return next;
  }

  static String _mediaUrl(Map<String, dynamic> story) {
    final raw =
        (story['mediaUrl'] ??
                story['media_url'] ??
                story['url'] ??
                story['attachmentUrl'] ??
                story['media'])
            ?.toString()
            .trim() ??
        '';
    if (raw.isEmpty) return '';
    if (raw.startsWith('http://') ||
        raw.startsWith('https://') ||
        raw.startsWith('file://') ||
        raw.startsWith('content://') ||
        raw.startsWith('data:')) {
      return raw;
    }
    final origin = ApiService.baseUrl.replaceFirst(RegExp(r'/api/?$'), '');
    if (raw.startsWith('/')) return '$origin$raw';
    return '$origin/$raw';
  }

  static bool _mediaIsVideo(Map<String, dynamic> story) =>
      (story['mediaType'] ?? '').toString().toLowerCase() == 'video';

  static bool _cachedFileAvailable(Map<String, dynamic> story) {
    final path = (story['cachedMediaPath'] ?? '').toString();
    if (path.isEmpty) return false;
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  static Future<File?> _cacheFileFor(
    Map<String, dynamic> story,
    String url,
  ) async {
    if (url.isEmpty) return null;
    final id =
        (story['id'] ?? story['originalStoryId'] ?? story['authorId'] ?? 'story')
            .toString();
    final hash = base64Url
        .encode(utf8.encode(url))
        .replaceAll('=', '')
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    final compactHash = hash.substring(0, math.min(hash.length, 36));
    final directory = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/tranviko_story_cache',
    );
    if (!await directory.exists()) await directory.create(recursive: true);
    return File(
      '${directory.path}/story_${id}_$compactHash${_mediaExtension(story, url)}',
    );
  }

  static String _mediaExtension(Map<String, dynamic> story, String url) {
    final type = (story['mediaType'] ?? '').toString().toLowerCase();
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    for (final ext in [
      '.mp4',
      '.mov',
      '.webm',
      '.jpg',
      '.jpeg',
      '.png',
      '.webp',
    ]) {
      if (path.endsWith(ext)) return ext;
    }
    return type == 'video' ? '.mp4' : '.jpg';
  }
}
