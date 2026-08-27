import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_text.dart';
import '../services/api_service.dart';
import '../services/local_cache_service.dart';
import '../widgets/app_toast.dart';
import '../widgets/tranviko_refresh.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  final Set<int> _selected = {};
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _nextOffset = 0;
  bool _archived = false;
  bool _searching = false;
  Timer? _friendshipRefreshTimer;

  List<Map<String, dynamic>> get _displayItems {
    final grouped = <Map<String, dynamic>>[];
    final search = _search.text.trim().toLowerCase();
    final source = search.isEmpty
        ? _items
        : _items.where((item) => _matchesNotificationSearch(item, search));
    for (final rawItem in source) {
      final item = Map<String, dynamic>.from(rawItem);
      if (_isFriendshipNotification(item)) continue;
      final category = item['category']?.toString() ?? '';
      final notificationType = _field(item, 'type').toLowerCase();
      // Only actual chat-message notifications are collapsed by sender.
      // Friend requests, contact discoveries, story likes and replies need
      // their own current action and must never inherit another card's data.
      if (category != 'message' || notificationType != 'message') {
        grouped.add(item);
        continue;
      }
      final sender = _field(item, 'senderId');
      final conversation = _field(item, 'conversationId');
      final key = sender.isNotEmpty
          ? 'sender:$sender'
          : conversation.isNotEmpty
          ? 'conversation:$conversation'
          : 'title:${item['title']}';
      final previousIndex = grouped.lastIndexWhere(
        (candidate) => candidate['_messageGroupKey'] == key,
      );
      if (previousIndex < 0) {
        item['_messageGroupKey'] = key;
        item['_notificationIds'] = [item['id']];
        grouped.add(item);
        continue;
      }
      final previous = Map<String, dynamic>.from(grouped[previousIndex]);
      final ids = List<dynamic>.from(
        previous['_notificationIds'] as List? ?? const [],
      )..add(item['id']);
      previous['_notificationIds'] = ids;
      previous['groupedCount'] = ids.length;
      previous['isRead'] = previous['isRead'] == true && item['isRead'] == true;
      // The list is newest-first: keep the visible text of the latest message.
      grouped[previousIndex] = previous;
    }
    return grouped;
  }

  List<_NotificationSectionGroup> _sectionGroups(
    List<Map<String, dynamic>> items,
  ) {
    final grouped = <_NotificationSection, List<Map<String, dynamic>>>{};
    for (final item in items) {
      grouped.putIfAbsent(_sectionFor(item), () => []).add(item);
    }
    return _NotificationSection.values
        .where((section) => grouped[section]?.isNotEmpty == true)
        .map(
          (section) => _NotificationSectionGroup(
            section: section,
            items: grouped[section]!,
          ),
        )
        .toList();
  }

  _NotificationSection _sectionFor(Map<String, dynamic> item) {
    final category = (item['category'] ?? '').toString().toLowerCase();
    final type = _field(item, 'type').toLowerCase();
    final signature = '$category $type';
    const systemSignals = <String>[
      'system',
      'security',
      'login',
      'device',
      'permission',
      'maintenance',
      'update',
      'session',
      'verification',
      'otp',
    ];
    if (systemSignals.any(signature.contains)) {
      return _NotificationSection.system;
    }
    const companySignals = <String>[
      'company',
      'reservation',
      'package',
      'parcel',
      'ticket',
      'trip',
      'route',
      'bus',
      'finance',
      'payment',
      'promotion',
      'offer',
      'fare',
      'global_message',
    ];
    if (companySignals.any(signature.contains) ||
        _field(item, 'companyId').isNotEmpty) {
      return _NotificationSection.company;
    }
    return _NotificationSection.personal;
  }

  bool _isFriendshipNotification(Map<String, dynamic> item) {
    final type = _field(item, 'type').trim().toLowerCase();
    return type == 'friend_request' || type == 'contact_joined';
  }

  bool _matchesNotificationSearch(Map<String, dynamic> item, String search) {
    final haystack = [
      item['title'],
      item['message'],
      item['category'],
      _field(item, 'type'),
      _field(item, 'senderName'),
      _field(item, 'conversationId'),
      _field(item, 'senderId'),
    ].join(' ').toLowerCase();
    return haystack.contains(search);
  }

  List<int> _expandIds(Iterable<int> ids) {
    final resolved = <int>{};
    for (final id in ids) {
      final item = _displayItems.cast<Map<String, dynamic>?>().firstWhere(
        (candidate) => candidate?['id'] == id,
        orElse: () => null,
      );
      final groupedIds = item?['_notificationIds'];
      if (groupedIds is Iterable) {
        resolved.addAll(groupedIds.map((value) => value as int));
      } else {
        resolved.add(id);
      }
    }
    return resolved.toList();
  }

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      if (mounted) setState(() {});
    });
    ApiService.friendshipRevision.addListener(_onFriendshipChanged);
    _load();
  }

  void _onFriendshipChanged() {
    _friendshipRefreshTimer?.cancel();
    _friendshipRefreshTimer = Timer(const Duration(milliseconds: 180), _load);
  }

  @override
  void dispose() {
    ApiService.friendshipRevision.removeListener(_onFriendshipChanged);
    _friendshipRefreshTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (ApiService.activeToken == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    final cacheKey = 'notifications_${_archived ? 'archived' : 'active'}';
    final cached = await LocalCacheService.readList(cacheKey);
    if (mounted && cached.isNotEmpty && _search.text.trim().isEmpty) {
      setState(() {
        _items = cached.take(20).toList();
        _loading = false;
      });
    }
    try {
      final page = await ApiService.fetchNotificationsPage(
        archived: _archived,
        limit: 20,
        offset: 0,
      );
      final items = List<Map<String, dynamic>>.from(page['results'] as List);
      if (_search.text.trim().isEmpty) {
        await LocalCacheService.writeList(cacheKey, items);
      }
      if (mounted) {
        setState(() {
          _items = items;
          _nextOffset = (page['nextOffset'] as num?)?.toInt() ?? items.length;
          _hasMore = page['hasMore'] == true && items.length >= 20;
          _selected.clear();
        });
      }
    } catch (error) {
      if (mounted && cached.isEmpty) {
        AppToast.show(
          context,
          AppToast.friendlyError(
            error,
            fallback:
                'Impossible de charger les notifications. Verifiez votre connexion.',
          ),
          tone: AppToastTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await ApiService.fetchNotificationsPage(
        archived: _archived,
        limit: 20,
        offset: _nextOffset,
      );
      final items = List<Map<String, dynamic>>.from(page['results'] as List);
      if (!mounted) return;
      setState(() {
        final existingIds = _items.map((item) => item['id']).toSet();
        _items.addAll(items.where((item) => !existingIds.contains(item['id'])));
        _nextOffset = (page['nextOffset'] as num?)?.toInt() ?? _items.length;
        _hasMore =
            items.isNotEmpty && page['hasMore'] == true && items.length >= 20;
      });
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _action(String action, {List<int>? ids}) async {
    final targets = _expandIds(ids ?? _selected.toList());
    if (targets.isEmpty) return;
    try {
      await ApiService.notificationAction(action, targets);
      if (action == 'delete' || action == 'archive') {
        _items.removeWhere((item) => targets.contains(item['id']));
        await LocalCacheService.writeList(
          'notifications_${_archived ? 'archived' : 'active'}',
          _items,
        );
      }
      await _load();
    } catch (error) {
      if (!mounted) return;
      AppToast.show(
        context,
        AppToast.friendlyError(error, fallback: 'Action impossible.'),
        tone: AppToastTone.error,
      );
    }
  }

  Map<String, dynamic> _notificationData(Map<String, dynamic> item) {
    final data = item['data'];
    if (data is Map) {
      return data.map((key, value) => MapEntry(key.toString(), value));
    }
    return const {};
  }

  String _field(Map<String, dynamic> item, String key) {
    final data = _notificationData(item);
    return (item[key] ?? data[key] ?? '').toString();
  }

  List<String> _statusValues(Map<String, dynamic> item) {
    final data = _notificationData(item);
    final values = <String>[
      _field(item, 'action'),
      _field(item, 'status'),
      _field(item, 'friendshipStatus'),
      _field(item, 'relationshipStatus'),
      _field(item, 'requestStatus'),
    ];
    for (final source in [item, data]) {
      for (final key in ['friendship', 'request', 'relationship']) {
        final nested = source[key];
        if (nested is Map) {
          values.add((nested['status'] ?? '').toString());
          values.add((nested['action'] ?? '').toString());
        }
      }
    }
    return values;
  }

  bool _truthyField(Map<String, dynamic> item, String key) {
    final raw = _field(item, key).trim().toLowerCase();
    return raw == 'true' || raw == '1' || raw == 'yes' || raw == 'oui';
  }

  bool _isFriendRequest(Map<String, dynamic> item) =>
      _field(item, 'type') == 'friend_request';

  bool _isContactDiscovery(Map<String, dynamic> item) =>
      _field(item, 'type') == 'contact_joined';

  bool _canAcceptFriendRequest(Map<String, dynamic> item) {
    if (!_isFriendRequest(item)) return false;
    final action = _field(item, 'action');
    final status = _field(item, 'status');
    final direction = _field(item, 'friendshipDirection');
    if (_statusValues(item).any(_isAlreadyFriendStatus) ||
        _truthyField(item, 'isFriend') ||
        _truthyField(item, 'alreadyFriend')) {
      return false;
    }
    return direction == 'incoming' ||
        action == 'incoming' ||
        (status == 'pending' && direction.isEmpty && action.isEmpty);
  }

  bool _canAddContact(Map<String, dynamic> item) {
    if (_canAcceptFriendRequest(item)) return true;
    if (!_isContactDiscovery(item)) return false;
    final action = _field(item, 'action');
    final status = _field(item, 'status');
    if (_statusValues(item).any(_isAlreadyFriendStatus) ||
        _truthyField(item, 'isFriend') ||
        _truthyField(item, 'alreadyFriend')) {
      return false;
    }
    return action.isEmpty && (status.isEmpty || status == 'none');
  }

  bool _isAlreadyFriendStatus(String value) {
    final clean = value.trim().toLowerCase();
    return clean == 'accepted' ||
        clean == 'friend' ||
        clean == 'friends' ||
        clean == 'already_friend' ||
        clean == 'deja_ami' ||
        clean == 'ami';
  }

  void _markContactNotificationHandled(
    Map<String, dynamic> source, {
    required bool accepted,
  }) {
    final sourceUserId = _field(source, 'targetUserId').isNotEmpty
        ? _field(source, 'targetUserId')
        : _field(source, 'senderId');
    setState(() {
      for (var index = 0; index < _items.length; index++) {
        final candidate = _items[index];
        final candidateUserId = _field(candidate, 'targetUserId').isNotEmpty
            ? _field(candidate, 'targetUserId')
            : _field(candidate, 'senderId');
        if (sourceUserId.isNotEmpty && candidateUserId != sourceUserId) {
          continue;
        }
        if (sourceUserId.isEmpty && candidate['id'] != source['id']) continue;
        final item = Map<String, dynamic>.from(candidate);
        final data = Map<String, dynamic>.from(
          item['data'] is Map ? item['data'] as Map : const {},
        );
        data['status'] = accepted ? 'accepted' : 'pending';
        data['action'] = accepted ? 'accepted' : 'outgoing';
        data['friendshipStatus'] = data['status'];
        data['friendshipDirection'] = accepted ? '' : 'outgoing';
        data['alreadyFriend'] = accepted;
        data['isFriend'] = accepted;
        item['status'] = data['status'];
        item['action'] = data['action'];
        item['friendshipStatus'] = data['friendshipStatus'];
        item['friendshipDirection'] = data['friendshipDirection'];
        item['isRead'] = true;
        item['data'] = data;
        _items[index] = item;
      }
    });
  }

  Future<void> _handleContactNotification(Map<String, dynamic> item) async {
    final friendshipStatus = _field(item, 'friendshipStatus').toLowerCase();
    final direction = _field(item, 'friendshipDirection').toLowerCase();
    final requestId = int.tryParse(
      _field(item, 'friendshipRequestId').isNotEmpty
          ? _field(item, 'friendshipRequestId')
          : _field(item, 'requestId'),
    );
    final targetUserId = int.tryParse(
      _field(item, 'targetUserId').isNotEmpty
          ? _field(item, 'targetUserId')
          : _field(item, 'senderId'),
    );
    final notificationId = int.tryParse(item['id']?.toString() ?? '');
    if (friendshipStatus == 'accepted') {
      _markContactNotificationHandled(item, accepted: true);
      return;
    }
    if (friendshipStatus == 'pending' && direction == 'outgoing') {
      _markContactNotificationHandled(item, accepted: false);
      return;
    }
    if (requestId == null && targetUserId == null) return;
    try {
      if (requestId != null && direction != 'outgoing') {
        await ApiService.friendRequestAction(
          requestId: requestId,
          action: 'accept',
        );
      } else if (targetUserId != null) {
        final response = await ApiService.sendFriendRequest(targetUserId);
        final request = response['request'];
        final accepted =
            response['accepted'] == true ||
            (request is Map && request['status'] == 'accepted');
        if (!mounted) return;
        _markContactNotificationHandled(item, accepted: accepted);
        if (notificationId != null) {
          await ApiService.notificationAction('read', [notificationId]);
        }
        if (!mounted) return;
        AppToast.show(
          context,
          accepted ? 'Contact ajoute a vos amis.' : 'Demande d ami envoyee.',
          tone: AppToastTone.success,
        );
        unawaited(_load());
        return;
      }
      if (notificationId != null) {
        await ApiService.notificationAction('read', [notificationId]);
      }
      if (!mounted) return;
      _markContactNotificationHandled(item, accepted: requestId != null);
      AppToast.show(
        context,
        requestId != null
            ? 'Contact ajoute a vos amis.'
            : 'Demande d ami envoyee.',
        tone: AppToastTone.success,
      );
      unawaited(_load());
    } catch (error) {
      if (!mounted) return;
      final message = AppToast.friendlyError(
        error,
        fallback: 'Ajout du contact impossible.',
      );
      final lower = message.toLowerCase();
      if (lower.contains('deja') ||
          lower.contains('déjà') ||
          lower.contains('already') ||
          lower.contains('ami') ||
          lower.contains('friend')) {
        _markContactNotificationHandled(item, accepted: true);
        AppToast.show(
          context,
          'Ce contact est deja dans vos amis.',
          tone: AppToastTone.info,
        );
        unawaited(_load());
        return;
      }
      AppToast.show(context, message, tone: AppToastTone.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selecting = _selected.isNotEmpty;
    final displayItems = _displayItems;
    final sectionGroups = _sectionGroups(displayItems);
    return PopScope(
      canPop: !selecting && !_searching,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _searching) {
          setState(() => _searching = false);
          _search.clear();
          return;
        }
        if (!didPop && selecting) setState(_selected.clear);
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).colorScheme.surface
            : Colors.white,
        appBar: AppBar(
          backgroundColor: Theme.of(context).brightness == Brightness.dark
              ? Theme.of(context).colorScheme.surface
              : Colors.white,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: !_searching,
          titleSpacing: _searching ? 8 : null,
          title: _searching
              ? Container(
                  height: 44,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: .68),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: appTC(context, 'back'),
                        onPressed: () {
                          setState(() => _searching = false);
                          _search.clear();
                        },
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _search,
                          autofocus: true,
                          decoration: InputDecoration(
                            hintText: appTC(context, 'searchNotification'),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                      if (_search.text.isNotEmpty)
                        IconButton(
                          tooltip: 'Effacer',
                          onPressed: _search.clear,
                          icon: const Icon(Icons.close_rounded),
                        ),
                    ],
                  ),
                )
              : Text(
                  selecting
                      ? '${_selected.length} ${appTC(context, 'selected')}'
                      : appTC(context, 'notifications'),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
          actions: _searching
              ? const []
              : [
                  if (selecting) ...[
                    _NotificationTopButton(
                      tooltip: appTC(context, 'markRead'),
                      onPressed: () => _action('read'),
                      icon: Icons.done_all_rounded,
                    ),
                    _NotificationTopButton(
                      tooltip: _archived
                          ? appTC(context, 'restore')
                          : appTC(context, 'archive'),
                      onPressed: () =>
                          _action(_archived ? 'restore' : 'archive'),
                      icon: _archived
                          ? Icons.unarchive_rounded
                          : Icons.archive_rounded,
                    ),
                    _NotificationTopButton(
                      tooltip: appTC(context, 'delete'),
                      onPressed: () => _action('delete'),
                      icon: Icons.delete_outline_rounded,
                      danger: true,
                    ),
                  ] else
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _NotificationTopButton(
                          tooltip: appTC(context, 'search'),
                          onPressed: () {
                            setState(() => _searching = true);
                          },
                          icon: Icons.manage_search_rounded,
                        ),
                        const SizedBox(width: 6),
                        _NotificationTopButton(
                          tooltip: _archived
                              ? appTC(context, 'activeNotifications')
                              : appTC(context, 'archives'),
                          onPressed: () {
                            setState(() => _archived = !_archived);
                            _load();
                          },
                          icon: _archived
                              ? Icons.notifications_none_rounded
                              : Icons.archive_outlined,
                          active: _archived,
                        ),
                        const SizedBox(width: 10),
                      ],
                    ),
                ],
        ),
        body: ApiService.activeToken == null
            ? _emptyAccount()
            : Column(
                children: [
                  if (displayItems.isNotEmpty && !_searching)
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: .42),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        children: [
                          TextButton.icon(
                            onPressed: () => setState(
                              () => _selected.addAll(
                                _displayItems.map((item) => item['id'] as int),
                              ),
                            ),
                            icon: const Icon(Icons.checklist_rounded, size: 19),
                            label: Text(appTC(context, 'selectAll')),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () => _action(
                              'read',
                              ids: _displayItems
                                  .map((e) => e['id'] as int)
                                  .toList(),
                            ),
                            icon: const Icon(Icons.done_all_rounded, size: 18),
                            label: Text(appTC(context, 'readAll')),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : displayItems.isEmpty
                        ? Center(
                            child: Text(
                              _search.text.trim().isNotEmpty
                                  ? appTC(context, 'noResult')
                                  : _archived
                                  ? appTC(context, 'noArchive')
                                  : appTC(context, 'noNotification'),
                            ),
                          )
                        : TranvikoRefresh(
                            onRefresh: _load,
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(0, 4, 0, 30),
                              children: [
                                for (final group in sectionGroups) ...[
                                  _sectionHeader(group),
                                  for (final item in group.items) _tile(item),
                                ],
                                if (_hasMore && _search.text.trim().isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      10,
                                      16,
                                      18,
                                    ),
                                    child: Material(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest
                                          .withValues(alpha: .55),
                                      borderRadius: BorderRadius.circular(18),
                                      child: InkWell(
                                        onTap: _loadingMore ? null : _loadMore,
                                        borderRadius: BorderRadius.circular(18),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 12,
                                          ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              if (_loadingMore)
                                                const SizedBox(
                                                  width: 17,
                                                  height: 17,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                )
                                              else
                                                Icon(
                                                  Icons
                                                      .expand_circle_down_outlined,
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.primary,
                                                ),
                                              const SizedBox(width: 9),
                                              Text(
                                                appTC(context, 'seeMore'),
                                                style: TextStyle(
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.primary,
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _sectionHeader(_NotificationSectionGroup group) {
    final scheme = Theme.of(context).colorScheme;
    final metadata = switch (group.section) {
      _NotificationSection.system => (
        label: appTC(context, 'notificationSectionSystem'),
        icon: Icons.shield_outlined,
        color: const Color(0xFF64748B),
      ),
      _NotificationSection.company => (
        label: appTC(context, 'notificationSectionCompany'),
        icon: Icons.apartment_rounded,
        color: scheme.primary,
      ),
      _NotificationSection.personal => (
        label: appTC(context, 'notificationSectionPersonal'),
        icon: Icons.person_outline_rounded,
        color: const Color(0xFF10B981),
      ),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 14, 9),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: metadata.color.withValues(alpha: .10),
              shape: BoxShape.circle,
            ),
            child: Icon(metadata.icon, color: metadata.color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              metadata.label,
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Container(
            constraints: const BoxConstraints(minWidth: 28),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: metadata.color.withValues(alpha: .09),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              '${group.items.length}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: metadata.color,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(Map<String, dynamic> item) {
    final id = item['id'] as int;
    final selected = _selected.contains(id);
    final unread = item['isRead'] != true;
    final category = item['category']?.toString() ?? 'general';
    final tone = _toneFor(category, item);
    final icon = _iconFor(category, item);
    final groupedCount = (item['groupedCount'] as num?)?.toInt() ?? 1;
    final senderName = _field(item, 'senderName').isNotEmpty
        ? _field(item, 'senderName')
        : (item['title']?.toString() ?? '');
    final scheme = Theme.of(context).colorScheme;
    final lightSurface = Theme.of(context).brightness == Brightness.dark
        ? scheme.surface
        : Colors.white;
    final bg = selected
        ? Color.alphaBlend(tone.withValues(alpha: .18), scheme.surface)
        : unread
        ? lightSurface
        : Color.alphaBlend(
            scheme.onSurface.withValues(alpha: .035),
            lightSurface,
          );
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Color.alphaBlend(
                tone.withValues(alpha: unread ? .16 : .08),
                const Color(0xFF111C2A),
              )
            : bg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            minTileHeight: 78,
            contentPadding: const EdgeInsets.fromLTRB(16, 8, 14, 7),
            onLongPress: () {
              HapticFeedback.selectionClick();
              setState(() => _selected.add(id));
            },
            onTap: () {
              if (_selected.isNotEmpty) {
                HapticFeedback.selectionClick();
                setState(
                  () => selected ? _selected.remove(id) : _selected.add(id),
                );
                return;
              }
              final notificationType = _field(item, 'type').toLowerCase();
              if (notificationType == 'seat_available') {
                if (unread) _action('read', ids: [id]);
                final tripId = int.tryParse(_field(item, 'tripId'));
                if (tripId == null) return;
                final totalSeats =
                    int.tryParse(_field(item, 'totalSeats')) ?? 40;
                final requestedSeats =
                    int.tryParse(_field(item, 'requestedSeats')) ?? 1;
                final priceValue =
                    int.tryParse(_field(item, 'priceValue')) ?? 0;
                Navigator.pushNamed(
                  context,
                  '/seat_plan',
                  arguments: {
                    'departure': _field(item, 'departure'),
                    'destination': _field(item, 'destination'),
                    'date': _field(item, 'travelDate'),
                    'passengerCount': requestedSeats,
                    'allowFlexibleSeatCount': true,
                    'bus': {
                      'id': tripId,
                      'companyId': _field(item, 'companyId'),
                      'companyName': _field(item, 'companyName'),
                      'travelDate': _field(item, 'travelDate'),
                      'time': _field(item, 'departureTime'),
                      'arrival': _field(item, 'arrivalTime'),
                      'type': _field(item, 'busType'),
                      'price': '$priceValue FCFA',
                      'priceValue': priceValue,
                      'totalSeats': totalSeats,
                      'occupiedSeats': const <int>[],
                    },
                  },
                );
              } else if (category == 'message') {
                final targetId = int.tryParse(
                  _field(item, 'senderId').isNotEmpty
                      ? _field(item, 'senderId')
                      : _field(item, 'conversationId'),
                );
                if (unread) _action('read', ids: [id]);
                Navigator.pushNamed(
                  context,
                  '/messages',
                  arguments: {if (targetId != null) 'senderId': targetId},
                );
              } else if (unread) {
                _action('read', ids: [id]);
              }
            },
            leading: Stack(
              clipBehavior: Clip.none,
              children: [
                _NotificationAvatar(
                  category: category,
                  icon: icon,
                  tone: tone,
                  name: senderName,
                  photoBase64: _field(item, 'senderProfilePhotoBase64'),
                  photoUrl: _field(item, 'senderProfilePhotoUrl'),
                ),
                if (unread)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981),
                        shape: BoxShape.circle,
                        border: Border.all(color: scheme.surface, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            title: Text(
              item['title']?.toString() ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: scheme.onSurface,
                fontWeight: unread ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                item['message']?.toString() ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            trailing: selected
                ? Icon(Icons.check_circle_rounded, color: tone)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: tone.withValues(alpha: .10),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _categoryLabel(category),
                          style: TextStyle(
                            color: tone,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (groupedCount > 1) ...[
                        const SizedBox(height: 6),
                        Text(
                          '+${groupedCount - 1}',
                          style: TextStyle(
                            color: tone,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
          if (_canAddContact(item))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer,
                    foregroundColor: Theme.of(
                      context,
                    ).colorScheme.onPrimaryContainer,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  onPressed: () => _handleContactNotification(item),
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: Text(
                    _isContactDiscovery(item)
                        ? appTC(context, 'sendFriendRequest')
                        : appTC(context, 'addContact'),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Color _toneFor(String category, Map<String, dynamic> item) {
    final type = _field(item, 'type');
    if (type == 'friend_request' || type == 'contact_joined') {
      return const Color(0xFF8B5CF6);
    }
    return switch (category) {
      'reservation' => const Color(0xFF2563EB),
      'package' => const Color(0xFF0EA5E9),
      'message' => const Color(0xFF10B981),
      'security' => const Color(0xFFEF4444),
      'finance' => const Color(0xFFF59E0B),
      _ => Theme.of(context).colorScheme.primary,
    };
  }

  IconData _iconFor(String category, Map<String, dynamic> item) {
    final type = _field(item, 'type');
    if (type == 'friend_request') return Icons.person_add_alt_1_rounded;
    if (type == 'contact_joined') return Icons.diversity_3_rounded;
    return switch (category) {
      'reservation' => Icons.confirmation_number_rounded,
      'package' => Icons.inventory_2_rounded,
      'message' => Icons.chat_bubble_rounded,
      'security' => Icons.shield_rounded,
      'finance' => Icons.payments_rounded,
      _ => Icons.notifications_active_rounded,
    };
  }

  String _categoryLabel(String category) {
    return switch (category) {
      'reservation' => 'Billet',
      'package' => 'Colis',
      'message' => 'Message',
      'security' => 'Securite',
      'finance' => 'Finance',
      _ => 'Info',
    };
  }

  Widget _emptyAccount() => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_person_outlined, size: 58),
          const SizedBox(height: 12),
          Text(appTC(context, 'profileLoginBody'), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.pushNamed(context, '/profile'),
            child: Text(appTC(context, 'profile')),
          ),
        ],
      ),
    ),
  );
}

class _NotificationTopButton extends StatelessWidget {
  final String tooltip;
  final VoidCallback? onPressed;
  final IconData icon;
  final bool active;
  final bool danger;

  const _NotificationTopButton({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    this.active = false,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = danger
        ? const Color(0xFFBE123C)
        : active
        ? scheme.primary
        : scheme.onSurfaceVariant;
    final background = danger
        ? const Color(0xFFFFE7EA)
        : active
        ? scheme.primary.withValues(alpha: .12)
        : scheme.surfaceContainerHighest.withValues(alpha: .54);
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          minimumSize: const Size(42, 42),
          shape: const CircleBorder(),
        ),
        icon: Icon(icon, size: 20),
      ),
    );
  }
}

class _NotificationAvatar extends StatelessWidget {
  final String category;
  final IconData icon;
  final Color tone;
  final String name;
  final String photoBase64;
  final String photoUrl;

  const _NotificationAvatar({
    required this.category,
    required this.icon,
    required this.tone,
    required this.name,
    required this.photoBase64,
    required this.photoUrl,
  });

  ImageProvider<Object>? _photoProvider() {
    final cleanBase64 = photoBase64.trim();
    if (cleanBase64.isNotEmpty) {
      try {
        return MemoryImage(base64Decode(cleanBase64));
      } catch (_) {
        // Fallback below keeps broken legacy payloads from breaking the list.
      }
    }
    final cleanUrl = photoUrl.trim();
    if (cleanUrl.startsWith('http://') || cleanUrl.startsWith('https://')) {
      return NetworkImage(cleanUrl);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final provider = category == 'message' ? _photoProvider() : null;
    final initial = name.trim().isEmpty
        ? 'M'
        : name.trim().characters.first.toUpperCase();
    if (provider != null || category == 'message') {
      return Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: provider == null
              ? LinearGradient(
                  colors: [tone, Color.lerp(tone, scheme.secondary, .30)!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          image: provider == null
              ? null
              : DecorationImage(image: provider, fit: BoxFit.cover),
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: tone.withValues(alpha: .18),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: provider == null
            ? Center(
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              )
            : null,
      );
    }
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [tone, Color.lerp(tone, scheme.secondary, .28)!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(19),
      ),
      child: Icon(icon, color: Colors.white, size: 24),
    );
  }
}

enum _NotificationSection { system, company, personal }

class _NotificationSectionGroup {
  final _NotificationSection section;
  final List<Map<String, dynamic>> items;

  const _NotificationSectionGroup({required this.section, required this.items});
}
