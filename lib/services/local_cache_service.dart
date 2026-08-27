import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'push_notification_service.dart';

class LocalCacheService {
  static const _cacheVersion = 'account_cache_v2';
  static String _accountScope = 'anonymous';

  static String get accountScope => _accountScope;

  static void activateAccountScope({
    required String accountType,
    required Object? accountId,
    Object? companyId,
  }) {
    final type = accountType.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9_-]'),
      '_',
    );
    final id = (accountId?.toString().trim().isNotEmpty == true)
        ? accountId.toString().trim()
        : 'unknown';
    final company = companyId?.toString().trim() ?? '';
    _accountScope = [
      type.isEmpty ? 'account' : type,
      if (company.isNotEmpty) company,
      id,
    ].join('_');
  }

  static void useAnonymousScope() {
    _accountScope = 'anonymous';
  }

  static String _scopedFor(String scope, String key) =>
      '$_cacheVersion:$scope:$key';

  static Future<bool> contains(String key) async {
    return containsForScope(_accountScope, key);
  }

  static Future<bool> containsForScope(String scope, String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_scopedFor(scope, key));
  }

  static Future<List<Map<String, dynamic>>> readList(String key) async {
    return readListForScope(_accountScope, key);
  }

  static Future<List<Map<String, dynamic>>> readListForScope(
    String scope,
    String key,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_scopedFor(scope, key));
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map(
            (item) => item.map((key, value) => MapEntry(key.toString(), value)),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> writeList(
    String key,
    List<Map<String, dynamic>> items,
  ) async {
    return writeListForScope(_accountScope, key, items);
  }

  static Future<void> writeListForScope(
    String scope,
    String key,
    List<Map<String, dynamic>> items,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scopedFor(scope, key), jsonEncode(items));
  }

  static Future<Map<String, dynamic>?> readMap(String key) async {
    return readMapForScope(_accountScope, key);
  }

  static Future<Map<String, dynamic>?> readMapForScope(
    String scope,
    String key,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_scopedFor(scope, key));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    } catch (_) {
      return null;
    }
  }

  static Future<void> writeMap(String key, Map<String, dynamic> item) async {
    return writeMapForScope(_accountScope, key, item);
  }

  static Future<void> writeMapForScope(
    String scope,
    String key,
    Map<String, dynamic> item,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scopedFor(scope, key), jsonEncode(item));
  }

  static Future<void> upsertById(String key, Map<String, dynamic> item) async {
    final items = await readList(key);
    final id =
        item['id']?.toString() ??
        item['qrData']?.toString() ??
        item['code']?.toString();
    final index = items.indexWhere((row) {
      final rowId =
          row['id']?.toString() ??
          row['qrData']?.toString() ??
          row['code']?.toString();
      return id != null && rowId == id;
    });
    if (index >= 0) {
      items[index] = {...items[index], ...item};
    } else {
      items.insert(0, item);
    }
    await writeList(key, items);
  }

  static Future<void> clearAuth() async {
    await PushNotificationService.cancelTicketDepartureReminders();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('remember_me');
    await prefs.remove('user_token');
    await prefs.remove('agent_token');
    await prefs.remove('current_user');
    await prefs.remove('current_agent');
    await prefs.remove('profile_cache');
    await prefs.remove('pending_native_accepted_call');
    // Remove only legacy, unscoped caches. Account-scoped data remains
    // available for an instant and private restore when this account returns.
    for (final key in prefs.getKeys().toList()) {
      if (key == 'reservations_cache' ||
          key.startsWith('notifications_') ||
          key.startsWith('chat_conversations_') ||
          key.startsWith('chat_messages_') ||
          key.startsWith('travel_stories_')) {
        await prefs.remove(key);
      }
    }
    useAnonymousScope();
  }
}
