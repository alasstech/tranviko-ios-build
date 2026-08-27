import 'dart:async';

import '../models/reservation_store.dart';
import 'api_service.dart';
import 'local_cache_service.dart';

class AccountWarmupService {
  static const _notificationPageSize = 20;
  static const _messagePageSize = 24;
  static final Set<String> _runningScopes = <String>{};

  static bool _scopeIsActive(String scope) =>
      LocalCacheService.accountScope == scope && ApiService.activeToken != null;

  static Future<void> warmCurrentAccount() async {
    final scope = LocalCacheService.accountScope;
    if (scope == 'anonymous' ||
        ApiService.activeToken == null ||
        !_runningScopes.add(scope)) {
      return;
    }

    try {
      // Let the first authenticated frame render before starting network work.
      await Future<void>.delayed(const Duration(milliseconds: 280));
      if (!_scopeIsActive(scope)) return;
      final conversations = await _warmMessaging(scope);
      await Future.wait<void>([
        _warmRecentConversations(scope, conversations.take(3)),
        _warmNotifications(scope),
      ]);
      await Future.wait<void>([_warmReservations(scope), _warmStories(scope)]);
    } finally {
      _runningScopes.remove(scope);
    }
  }

  static Future<List<Map<String, dynamic>>> _warmMessaging(String scope) async {
    if (!_scopeIsActive(scope)) return const [];
    const key = 'chat_conversations_active';
    if (await LocalCacheService.containsForScope(scope, key)) {
      return LocalCacheService.readListForScope(scope, key);
    }
    try {
      final items = await ApiService.fetchConversations();
      if (!_scopeIsActive(scope)) return const [];
      await LocalCacheService.writeListForScope(scope, key, items);
      return items;
    } catch (_) {
      return const [];
    }
  }

  static Future<void> _warmNotifications(String scope) async {
    if (!_scopeIsActive(scope)) return;
    const key = 'notifications_active';
    if (await LocalCacheService.containsForScope(scope, key)) return;
    try {
      final page = await ApiService.fetchNotificationsPage(
        limit: _notificationPageSize,
        offset: 0,
      );
      final items = List<Map<String, dynamic>>.from(
        page['results'] as List? ?? const [],
      );
      if (!_scopeIsActive(scope)) return;
      await LocalCacheService.writeListForScope(scope, key, items);
    } catch (_) {}
  }

  static Future<void> _warmReservations(String scope) async {
    if (!_scopeIsActive(scope)) return;
    const key = 'reservations_cache';
    await _claimCachedGuestReservations(scope);
    if (!_scopeIsActive(scope)) return;
    if (await LocalCacheService.containsForScope(scope, key)) return;
    try {
      final items = await ApiService.fetchReservations();
      if (!_scopeIsActive(scope)) return;
      await LocalCacheService.writeListForScope(scope, key, items);
      if (LocalCacheService.accountScope == scope) {
        await ReservationStore.replaceAll(items);
      }
    } catch (_) {}
  }

  static Future<void> _claimCachedGuestReservations(String scope) async {
    const key = 'reservations_cache';
    final cached = await LocalCacheService.readListForScope(scope, key);
    final candidates = cached
        .where(
          (item) =>
              (item['guestAccessToken']?.toString().isNotEmpty ?? false) &&
              item['bookedAsGuest'] == true,
        )
        .toList();
    if (candidates.isEmpty || !_scopeIsActive(scope)) return;
    try {
      final payload = await ApiService.claimGuestReservations(candidates);
      if (!_scopeIsActive(scope)) return;
      final claimed =
          List<Map<String, dynamic>>.from(
                payload['results'] as List? ?? const [],
              )
              .map(
                (item) => <String, dynamic>{
                  ...item,
                  'bookedAsGuest': true,
                  'guestClaimed': true,
                  'guestAccessToken': '',
                  'pendingGuestClaim': false,
                },
              )
              .toList();
      final claimedIds = (payload['claimedIds'] as List? ?? const [])
          .map((id) => id.toString())
          .toSet();
      final rejectedIds = (payload['rejectedIds'] as List? ?? const [])
          .map((id) => id.toString())
          .toSet();

      if (rejectedIds.isNotEmpty) {
        final kept = cached
            .where((item) => !rejectedIds.contains(item['id']?.toString()))
            .toList();
        await LocalCacheService.writeListForScope(scope, key, kept);
        if (LocalCacheService.accountScope == scope) {
          await ReservationStore.replaceAll(kept);
        }
      }
      if (claimed.isNotEmpty) {
        await ReservationStore.mergeAll(claimed);
      }
      if (claimedIds.isNotEmpty) {
        final anonymous = await ReservationStore.readAnonymousReservations();
        await LocalCacheService.writeListForScope(
          'anonymous',
          key,
          anonymous
              .where((item) => !claimedIds.contains(item['id']?.toString()))
              .toList(),
        );
      }
    } catch (_) {
      // The proof remains cached and the claim is retried on the next session.
    }
  }

  static Future<void> _warmStories(String scope) async {
    if (!_scopeIsActive(scope)) return;
    if (ApiService.currentAgent != null || ApiService.currentUser == null) {
      return;
    }
    final company = ApiService.companyId ?? ApiService.companySlug ?? 'global';
    final user =
        ApiService.currentUser?['id']?.toString() ??
        ApiService.currentUser?['userId']?.toString() ??
        'traveler';
    final key = 'travel_stories_${company}_$user';
    if (await LocalCacheService.containsForScope(scope, key)) return;
    try {
      final items = await ApiService.fetchTravelStories();
      if (!_scopeIsActive(scope)) return;
      await LocalCacheService.writeListForScope(scope, key, items);
    } catch (_) {}
  }

  static Future<void> _warmRecentConversations(
    String scope,
    Iterable<Map<String, dynamic>> conversations,
  ) async {
    for (final conversation in conversations) {
      if (!_scopeIsActive(scope)) return;
      final userId = (conversation['userId'] as num?)?.toInt();
      if (userId == null || userId <= 0) continue;
      final cacheKey = 'chat_messages_$userId';
      if (await LocalCacheService.containsForScope(scope, cacheKey)) continue;
      try {
        final page = await ApiService.fetchMessagesPage(
          userId,
          limit: _messagePageSize,
        );
        final items = List<Map<String, dynamic>>.from(
          page['results'] as List? ?? const [],
        );
        if (!_scopeIsActive(scope)) return;
        await LocalCacheService.writeListForScope(scope, cacheKey, items);
        await LocalCacheService.writeMapForScope(scope, '${cacheKey}_meta', {
          'hasMore': page['hasMore'] == true,
          'nextBefore': page['nextBefore']?.toString() ?? '',
          'savedAt': DateTime.now().toIso8601String(),
        });
      } catch (_) {}
    }
  }
}
