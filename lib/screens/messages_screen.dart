import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:latlong2/latlong.dart' as latlng;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../l10n/app_text.dart';
import '../services/api_service.dart';
import '../services/interaction_feedback_service.dart';
import '../services/local_cache_service.dart';
import '../services/screen_awake_service.dart';
import '../services/story_cache_service.dart';
import '../utils/gps_speed.dart';
import '../widgets/app_toast.dart';
import '../widgets/tranviko_map_tiles.dart';
import 'audio_call_screen.dart';
import 'trip_chat_screen.dart';

const _pageBg = Color(0xFFFFFFFF);
const _panel = Color(0xFFFFFFFF);
const _softBlue = Color(0xFFFFFFFF);
const _blue = Color(0xFF2563EB);
const _ink = Color(0xFF123047);
const _galleryChannel = MethodChannel('mali_compagnie/media_gallery');
const _contactsChannel = MethodChannel('mali_compagnie/contacts');
const _shareToStoryTargetId = -770001;

const List<Map<String, String>> _defaultGifCatalog = [
  {
    'id': 'gif-bravo',
    'name': 'Bravo',
    'tags': 'bravo felicitation oui',
    'url': 'https://media.giphy.com/media/111ebonMs90YLu/giphy.gif',
  },
  {
    'id': 'gif-happy',
    'name': 'Heureux',
    'tags': 'heureux joie danse',
    'url': 'https://media.giphy.com/media/5GoVLqeAOo6PK/giphy.gif',
  },
  {
    'id': 'gif-amazing',
    'name': 'Incroyable',
    'tags': 'incroyable surpris wow',
    'url': 'https://media.giphy.com/media/26ufdipQqU2lhNA4g/giphy.gif',
  },
  {
    'id': 'gif-thinking',
    'name': 'Je reflechis',
    'tags': 'penser attendre reflexion',
    'url': 'https://media.giphy.com/media/l0HlBO7eyXzSZkJri/giphy.gif',
  },
  {
    'id': 'gif-yes',
    'name': 'Oui',
    'tags': 'oui accord parfait',
    'url': 'https://media.giphy.com/media/3o7abKhOpu0NwenH3O/giphy.gif',
  },
  {
    'id': 'gif-laugh',
    'name': 'Rire',
    'tags': 'rire drole humour',
    'url': 'https://media.giphy.com/media/10JhviFuU2gWD6/giphy.gif',
  },
  {
    'id': 'gif-applause',
    'name': 'Applaudir',
    'tags': 'bravo applaudir merci',
    'url': 'https://media.giphy.com/media/l3q2XhfQ8oCkm1Ts4/giphy.gif',
  },
  {
    'id': 'gif-ok',
    'name': 'D accord',
    'tags': 'ok accord compris',
    'url': 'https://media.giphy.com/media/g9582DNuQppxC/giphy.gif',
  },
  {
    'id': 'gif-shocked',
    'name': 'Surpris',
    'tags': 'surpris wow incroyable',
    'url': 'https://media.giphy.com/media/l3q2K5jinAlChoCLS/giphy.gif',
  },
  {
    'id': 'gif-ready',
    'name': 'On y va',
    'tags': 'depart pret action',
    'url': 'https://media.giphy.com/media/xT9IgG50Fb7Mi0prBC/giphy.gif',
  },
  {
    'id': 'gif-celebrate',
    'name': 'Celebration',
    'tags': 'fete victoire celebration',
    'url': 'https://media.giphy.com/media/26BRv0ThflsHCqDrG/giphy.gif',
  },
  {
    'id': 'gif-wait',
    'name': 'Un instant',
    'tags': 'attendre patience minute',
    'url': 'https://media.giphy.com/media/13hxeOYjoTWtK8/giphy.gif',
  },
];

const List<Map<String, String>> _defaultStickerCatalog = [
  {'id': 'sticker-heart', 'emoji': '❤️', 'tags': 'amour coeur merci'},
  {'id': 'sticker-laugh', 'emoji': '😂', 'tags': 'rire drole'},
  {'id': 'sticker-fire', 'emoji': '🔥', 'tags': 'feu excellent'},
  {'id': 'sticker-clap', 'emoji': '👏', 'tags': 'bravo applaudir'},
  {'id': 'sticker-ok', 'emoji': '👌', 'tags': 'ok parfait'},
  {'id': 'sticker-thanks', 'emoji': '🙏', 'tags': 'merci prie'},
  {'id': 'sticker-love', 'emoji': '😍', 'tags': 'amour adore'},
  {'id': 'sticker-party', 'emoji': '🎉', 'tags': 'fete victoire'},
  {'id': 'sticker-strong', 'emoji': '💪', 'tags': 'force courage'},
  {'id': 'sticker-star', 'emoji': '⭐', 'tags': 'etoile favori'},
  {'id': 'sticker-idea', 'emoji': '💡', 'tags': 'idee solution'},
  {'id': 'sticker-bus', 'emoji': '🚌', 'tags': 'bus trajet voyage'},
  {'id': 'sticker-ticket', 'emoji': '🎫', 'tags': 'ticket billet'},
  {'id': 'sticker-location', 'emoji': '📍', 'tags': 'position lieu'},
  {'id': 'sticker-check', 'emoji': '✅', 'tags': 'valide termine'},
  {'id': 'sticker-warning', 'emoji': '⚠️', 'tags': 'attention alerte'},
  {'id': 'sticker-wave', 'emoji': '👋', 'tags': 'bonjour salut'},
  {'id': 'sticker-thinking', 'emoji': '🤔', 'tags': 'penser question'},
];

Color _screenBg(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF0B1118)
    : _pageBg;

Color _surfacePanel(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF14202B)
    : _panel;

Color _primaryText(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? Colors.white : _ink;

DateTime _messageDate(dynamic value) =>
    DateTime.tryParse((value ?? '').toString()) ??
    DateTime.fromMillisecondsSinceEpoch(0);

DateTime _messageLocalDate(dynamic value) => _messageDate(value).toLocal();

bool _sameMessageDay(dynamic first, dynamic second) {
  final a = _messageLocalDate(first);
  final b = _messageLocalDate(second);
  if (a.millisecondsSinceEpoch == 0 || b.millisecondsSinceEpoch == 0) {
    return false;
  }
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

String _messageDayLabel(dynamic value) {
  final date = _messageLocalDate(value);
  if (date.millisecondsSinceEpoch == 0) return '';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  final difference = today.difference(day).inDays;
  if (difference == 0) return "Aujourd'hui";
  if (difference == 1) return 'Hier';
  const months = <String>[
    'janvier',
    'fevrier',
    'mars',
    'avril',
    'mai',
    'juin',
    'juillet',
    'aout',
    'septembre',
    'octobre',
    'novembre',
    'decembre',
  ];
  final suffix = date.year == now.year ? '' : ' ${date.year}';
  return '${date.day} ${months[date.month - 1]}$suffix';
}

String _relativeStoryTime(dynamic value) {
  final date = _messageLocalDate(value);
  if (date.millisecondsSinceEpoch == 0) return '';
  final elapsed = DateTime.now().difference(date);
  if (elapsed.inSeconds < 60) return "a l'instant";
  if (elapsed.inMinutes < 60) return 'il y a ${elapsed.inMinutes} min';
  if (elapsed.inHours < 24) return 'il y a ${elapsed.inHours} h';
  return 'il y a ${elapsed.inDays} j';
}

List<Map<String, dynamic>> _sortedConversations(
  List<Map<String, dynamic>> items,
) {
  final next = items.map((item) => Map<String, dynamic>.from(item)).toList();
  next.sort((a, b) {
    final pinned = (b['isPinned'] == true ? 1 : 0).compareTo(
      a['isPinned'] == true ? 1 : 0,
    );
    if (pinned != 0) return pinned;
    return _messageDate(b['lastAt']).compareTo(_messageDate(a['lastAt']));
  });
  return next;
}

String _conversationPreview(Map<String, dynamic> item) {
  final last = (item['lastMessage'] ?? '').toString().trim();
  if (last.isEmpty) return item['role']?.toString() ?? '';
  return item['lastFromMe'] == true ? 'Vous : $last' : last;
}

bool _storyStillActive(Map<String, dynamic> story) {
  final expires = DateTime.tryParse(story['expiresAt']?.toString() ?? '');
  return expires == null || expires.isAfter(DateTime.now());
}

String _storyMediaUrl(Map<String, dynamic> story) {
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

String _storyCachedMediaPath(Map<String, dynamic> story) =>
    (story['cachedMediaPath'] ?? '').toString();

bool _storyCachedFileAvailable(Map<String, dynamic> story) {
  final path = _storyCachedMediaPath(story);
  if (path.isEmpty) return false;
  try {
    return File(path).existsSync();
  } catch (_) {
    return false;
  }
}

bool _storyMediaIsVideo(Map<String, dynamic> story) =>
    (story['mediaType'] ?? '').toString().toLowerCase() == 'video';

Future<File?> _storyCacheFileFor(Map<String, dynamic> story, String url) async {
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
    '${directory.path}/story_${id}_$compactHash${_storyMediaExtension(story, url)}',
  );
}

Future<Map<String, dynamic>> _attachCachedStoryMedia(
  Map<String, dynamic> story,
) async {
  final next = Map<String, dynamic>.from(story);
  if (_storyCachedFileAvailable(next)) return next;
  final file = await _storyCacheFileFor(next, _storyMediaUrl(next));
  if (file != null && await file.exists()) {
    next['cachedMediaPath'] = file.path;
  }
  return next;
}

String _storyAudiencePrefsKey() {
  final company = ApiService.companyId ?? ApiService.companySlug ?? 'global';
  final user =
      ApiService.currentUser?['id']?.toString() ??
      ApiService.currentUser?['userId']?.toString() ??
      'traveler';
  return 'travel_story_audience_${company}_$user';
}

OverlayEntry? _showStoryPickerLoading(BuildContext context, String label) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return null;
  final entry = OverlayEntry(
    builder: (context) => IgnorePointer(
      child: Material(
        color: Colors.black.withValues(alpha: .22),
        child: Center(
          child: Container(
            width: 252,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _surfacePanel(context),
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 28,
                  offset: Offset(0, 14),
                ),
              ],
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: _primaryText(context),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  return entry;
}

Future<_PickedAttachment?> _pickSingleStoryMedia(
  BuildContext context,
  String type,
) async {
  final photo = type == 'image';
  OverlayEntry? loading;
  try {
    final hasAccess =
        await _galleryChannel.invokeMethod<bool>('hasMediaAccess') ?? false;
    final granted =
        hasAccess ||
        (await _galleryChannel.invokeMethod<bool>('requestMediaAccess') ??
            false);
    if (!granted) return null;
    if (!context.mounted) return null;
    loading = _showStoryPickerLoading(
      context,
      photo ? 'Ouverture des photos...' : 'Ouverture des videos...',
    );
    final raw = await _galleryChannel.invokeMethod<List<dynamic>>('listMedia', {
      'kind': photo ? 'image' : 'video',
      'limit': 160,
    });
    loading?.remove();
    loading = null;
    final items = (raw ?? const [])
        .whereType<Map>()
        .map((item) => _GalleryMediaItem.fromNative(item))
        .where((item) => item.uri.isNotEmpty)
        .toList();
    if (!context.mounted || items.isEmpty) return null;
    final selected = await Navigator.push<List<_GalleryMediaItem>>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _CustomMediaGalleryScreen(
          items: items,
          multiSelect: false,
          title: photo ? 'Choisir une photo' : 'Choisir une video',
        ),
      ),
    );
    if (!context.mounted || selected == null || selected.isEmpty) return null;
    final item = selected.first;
    final bytes = await _galleryChannel.invokeMethod<Uint8List>('readMedia', {
      'uri': item.uri,
    });
    if (bytes == null || bytes.isEmpty) return null;
    return _PickedAttachment(
      bytes: bytes,
      name: item.name.isNotEmpty
          ? item.name
          : (item.isVideo ? 'story.mp4' : 'story.jpg'),
      mime: item.mime.isNotEmpty
          ? item.mime
          : (item.isVideo ? 'video/mp4' : 'image/jpeg'),
      localPath: item.uri,
    );
  } catch (_) {
    return null;
  } finally {
    loading?.remove();
  }
}

String _storyMediaExtension(Map<String, dynamic> story, String url) {
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

String _safeDownloadName(String value) {
  final cleaned = value.trim().isEmpty ? 'tranviko-media' : value.trim();
  return cleaned.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
}

String _downloadMimeFromName(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.mp4')) return 'video/mp4';
  if (lower.endsWith('.mov')) return 'video/quicktime';
  if (lower.endsWith('.webm')) return 'video/webm';
  return 'application/octet-stream';
}

Future<void> _saveMediaToDevice(
  BuildContext context, {
  required String name,
  String url = '',
  Uint8List? bytes,
  String? localPath,
}) async {
  try {
    Uint8List? data = bytes;
    final file = localPath == null || localPath.trim().isEmpty
        ? null
        : File(localPath);
    if (data == null && file != null && await file.exists()) {
      data = await file.readAsBytes();
    }
    if (data == null && url.isNotEmpty) {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        data = response.bodyBytes;
      }
    }
    if (data == null || data.isEmpty) {
      if (url.isNotEmpty) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
      return;
    }
    final safeName = _safeDownloadName(name);
    final mime = _downloadMimeFromName(safeName);
    if (Platform.isAndroid &&
        (mime.startsWith('image/') || mime.startsWith('video/'))) {
      try {
        final exists =
            await _galleryChannel.invokeMethod<bool>('exists', {
              'name': safeName,
              'mime': mime,
            }) ??
            false;
        if (exists && context.mounted) {
          final overwrite = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Media deja enregistre'),
              content: const Text(
                'Ce media existe deja dans la galerie du telephone. Voulez-vous l enregistrer encore une fois ?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Enregistrer'),
                ),
              ],
            ),
          );
          if (overwrite != true) return;
        }
        await _galleryChannel.invokeMethod<String>('save', {
          'name': safeName,
          'mime': mime,
          'bytes': data,
        });
        if (!context.mounted) return;
        AppToast.show(
          context,
          'Media enregistre dans la galerie.',
          tone: AppToastTone.success,
        );
        return;
      } catch (_) {
        // Fallback below keeps older or restricted devices usable.
      }
    }
    final savedPath = await FilePicker.platform.saveFile(
      fileName: safeName,
      bytes: data,
    );
    if (!context.mounted || savedPath == null) return;
    AppToast.show(context, 'Fichier enregistre.', tone: AppToastTone.success);
  } catch (error) {
    if (!context.mounted) return;
    AppToast.show(
      context,
      AppToast.friendlyError(error, fallback: 'Telechargement impossible.'),
      tone: AppToastTone.error,
    );
  }
}

class MessagesScreen extends StatefulWidget {
  final int? initialUserId;
  final List<Map<String, dynamic>> initialSharedMedia;
  final Map<String, dynamic>? initialTicketShare;

  const MessagesScreen({
    super.key,
    this.initialUserId,
    this.initialSharedMedia = const [],
    this.initialTicketShare,
  });

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen>
    with WidgetsBindingObserver {
  final _searchController = TextEditingController();
  final _conversationScroll = ScrollController();
  final Set<int> _selected = {};
  List<Map<String, dynamic>> _conversations = [];
  List<Map<String, dynamic>> _archivedConversations = [];
  List<Map<String, dynamic>> _friendRequests = [];
  List<Map<String, dynamic>> _travelStories = [];
  final Map<int, _PendingStoryUpload> _pendingStoryUploads = {};
  Set<int> _contactAttentionIds = {};
  Timer? _refreshTimer;
  Timer? _storyReconnectTimer;
  StreamSubscription? _storySocketSub;
  WebSocketChannel? _storyChannel;
  final ValueNotifier<int> _storyStripDismissSignal = ValueNotifier<int>(0);
  bool _loading = true;
  bool _refreshing = false;
  int _conversationLoadGeneration = 0;
  bool _archived = false;
  bool _favorites = false;
  bool _openedInitialConversation = false;
  bool _shareHintShown = false;
  bool _ticketSharePrompted = false;
  bool _sharingMedia = false;
  bool _loadingStories = false;
  bool _storySocketClosedByUs = false;
  bool _storiesStripVisible = true;
  bool _redirectingToLogin = false;
  bool _conversationHorizontalSwipeActive = false;
  double _lastConversationScrollOffset = 0;
  DateTime? _lastContactDiscoverySync;
  DateTime? _lastConversationMetaSync;
  late List<Map<String, dynamic>> _pendingSharedMedia;

  bool get _selectionMode => _selected.isNotEmpty;
  List<Map<String, dynamic>> get _selectedConversations => _conversations
      .where((item) => _selected.contains(item['userId']))
      .toList();
  bool get _selectedAllPinned =>
      _selectedConversations.isNotEmpty &&
      _selectedConversations.every((item) => item['isPinned'] == true);
  bool get _selectedAllImportant =>
      _selectedConversations.isNotEmpty &&
      _selectedConversations.every((item) => item['isImportant'] == true);
  bool get _selectedAllMuted =>
      _selectedConversations.isNotEmpty &&
      _selectedConversations.every((item) => item['isMuted'] == true);
  bool get _travelerContactsEnabled =>
      ApiService.currentAgent == null &&
      ApiService.currentUser != null &&
      (ApiService.currentUser?['accountType']?.toString() == 'client' ||
          ApiService.currentUser?['accountType'] == null);
  Set<int> get _storyAuthorIds => _travelStories
      .map((item) => (item['authorId'] as num?)?.toInt())
      .whereType<int>()
      .toSet();

  List<Map<String, dynamic>> get _incomingFriendRequests => _friendRequests
      .where(
        (item) =>
            item['status']?.toString() == 'pending' &&
            item['direction']?.toString() == 'incoming',
      )
      .toList();

  String get _conversationMetaCacheSuffix {
    final user =
        ApiService.currentUser?['id'] ?? ApiService.currentUser?['userId'];
    return user?.toString() ?? 'anonymous';
  }

  String get _seenContactsCacheKey {
    final company = ApiService.companyId ?? ApiService.companySlug ?? 'global';
    return 'traveler_seen_contacts_${company}_$_conversationMetaCacheSuffix';
  }

  String get _travelerContactsCacheKey =>
      'traveler_contacts_$_conversationMetaCacheSuffix';

  String get _friendRequestsCacheKey =>
      'traveler_friend_requests_$_conversationMetaCacheSuffix';

  Set<int> _contactAttentionIdsFor(
    List<Map<String, dynamic>> contacts,
    List<Map<String, dynamic>> requests,
    List<Map<String, dynamic>> seenRows,
  ) {
    final seen = seenRows
        .map((item) => int.tryParse(item['id']?.toString() ?? ''))
        .whereType<int>()
        .toSet();
    final ids = requests
        .where(
          (item) =>
              item['status']?.toString() == 'pending' &&
              item['direction']?.toString() == 'incoming',
        )
        .map((item) => int.tryParse(item['userId']?.toString() ?? ''))
        .whereType<int>()
        .toSet();
    ids.addAll(
      contacts
          .where((item) => item['onTranviko'] != false)
          .map((item) => int.tryParse(item['userId']?.toString() ?? ''))
          .whereType<int>()
          .where((id) => !seen.contains(id)),
    );
    return ids;
  }

  List<Map<String, dynamic>> get _homeConversationRows {
    final rows = _visible
        .map((item) => <String, dynamic>{...item, '_rowKind': 'conversation'})
        .toList();
    if (_archivedConversations.isNotEmpty) {
      final latestArchive = _sortedConversations(_archivedConversations).first;
      rows.add({
        '_rowKind': 'archive',
        'name': appTC(context, 'archives'),
        'lastAt': latestArchive['lastAt'],
        'lastMessage': _archivedConversations
            .take(3)
            .map((item) => item['name']?.toString() ?? '')
            .where((name) => name.isNotEmpty)
            .join(', '),
        'unread': _archivedConversations.fold<int>(
          0,
          (sum, item) => sum + ((item['unread'] as num?)?.toInt() ?? 0),
        ),
      });
    }
    final incoming = _incomingFriendRequests;
    if (incoming.isNotEmpty) {
      incoming.sort(
        (a, b) => _messageDate(
          b['updatedAt'] ?? b['createdAt'],
        ).compareTo(_messageDate(a['updatedAt'] ?? a['createdAt'])),
      );
    }
    rows.add({
      '_rowKind': 'friendRequests',
      'name': appTC(context, 'friendRequestsReceived'),
      'lastAt': incoming.isEmpty
          ? null
          : incoming.first['updatedAt'] ?? incoming.first['createdAt'],
      'lastMessage': incoming.isEmpty
          ? appTC(context, 'noResult')
          : incoming
                .take(3)
                .map((item) => item['name']?.toString() ?? '')
                .where((name) => name.isNotEmpty)
                .join(', '),
      'unread': incoming.length,
    });
    rows.sort((a, b) {
      final pinned = (b['isPinned'] == true ? 1 : 0).compareTo(
        a['isPinned'] == true ? 1 : 0,
      );
      if (pinned != 0) return pinned;
      return _messageDate(b['lastAt']).compareTo(_messageDate(a['lastAt']));
    });
    return rows;
  }

  String get _storyCacheKey {
    final company = ApiService.companyId ?? ApiService.companySlug ?? 'global';
    final user =
        ApiService.currentUser?['id']?.toString() ??
        ApiService.currentUser?['userId']?.toString() ??
        'traveler';
    return 'travel_stories_${company}_$user';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pendingSharedMedia = List<Map<String, dynamic>>.from(
      widget.initialSharedMedia,
    );
    _conversationScroll.addListener(_syncStoriesStripVisibility);
    unawaited(_loadCachedTravelStories());
    _load();
    _connectStorySocket();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showShareHint());
    _refreshTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (ApiService.activeToken != null) unawaited(_load());
    });
  }

  void _showShareHint() {
    if (_shareHintShown ||
        _pendingSharedMedia.isEmpty ||
        _conversations.isEmpty ||
        !mounted) {
      return;
    }
    _shareHintShown = true;
    unawaited(_sharePendingMedia());
  }

  void _redirectToLoginIfNeeded() {
    if (_redirectingToLogin || ApiService.activeToken != null || !mounted) {
      return;
    }
    _redirectingToLogin = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ApiService.activeToken != null) return;
      Navigator.of(context).pushReplacementNamed('/login');
    });
  }

  void _syncStoriesStripVisibility() {
    if (!_conversationScroll.hasClients || !_travelerContactsEnabled) return;
    final offset = _conversationScroll.offset;
    final movingDown = offset > _lastConversationScrollOffset + 8;
    final movingUp = offset < _lastConversationScrollOffset - 10;
    final nextVisible = offset <= 18 || movingUp
        ? true
        : (movingDown ? false : _storiesStripVisible);
    _lastConversationScrollOffset = offset;
    if (nextVisible != _storiesStripVisible && mounted) {
      setState(() => _storiesStripVisible = nextVisible);
    }
  }

  bool _handleConversationScroll(ScrollNotification notification) {
    if (!_travelerContactsEnabled) return false;
    if (_conversationHorizontalSwipeActive) return false;
    if (notification.metrics.pixels <= 8 && !_storiesStripVisible && mounted) {
      setState(() => _storiesStripVisible = true);
      return false;
    }
    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      final dy = notification.dragDetails!.delta.dy;
      if (dy < -8 && _storiesStripVisible && mounted) {
        setState(() => _storiesStripVisible = false);
      } else if (dy > 8 && !_storiesStripVisible && mounted) {
        setState(() => _storiesStripVisible = true);
      }
    }
    return false;
  }

  void _handleConversationPointerMove(PointerMoveEvent event) {
    if (!_travelerContactsEnabled) return;
    if (_conversationHorizontalSwipeActive) return;
    final dx = event.delta.dx.abs();
    final dy = event.delta.dy;
    if (dy.abs() < 6 || dy.abs() < dx * 1.8) return;
    if (dy < -6 && _storiesStripVisible && mounted) {
      setState(() => _storiesStripVisible = false);
    } else if (dy > 6 && !_storiesStripVisible && mounted) {
      setState(() => _storiesStripVisible = true);
    }
  }

  void _dismissStorySelection() {
    _storyStripDismissSignal.value++;
  }

  List<Map<String, dynamic>> _consumePendingSharedMedia() {
    if (_pendingSharedMedia.isEmpty) return const [];
    final items = List<Map<String, dynamic>>.from(_pendingSharedMedia);
    _pendingSharedMedia = [];
    return items;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _closeStorySocket();
    _conversationScroll.dispose();
    _storyStripDismissSignal.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_load());
      _connectStorySocket();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _closeStorySocket();
    }
  }

  void _connectStorySocket() {
    if (!_travelerContactsEnabled ||
        ApiService.activeToken == null ||
        _storySocketSub != null) {
      return;
    }
    _storySocketClosedByUs = false;
    _storyReconnectTimer?.cancel();
    try {
      final channel = WebSocketChannel.connect(ApiService.chatWebSocketUri());
      _storyChannel = channel;
      _storySocketSub = channel.stream.listen(
        _handleStorySocketEvent,
        onDone: _scheduleStorySocketReconnect,
        onError: (_) => _scheduleStorySocketReconnect(),
      );
    } catch (_) {
      _scheduleStorySocketReconnect();
    }
  }

  void _handleStorySocketEvent(dynamic event) {
    try {
      final payload = jsonDecode(event.toString());
      if (payload is Map && payload['event'] == 'story_update') {
        unawaited(_loadTravelStories());
      } else if (payload is Map && payload['event'] == 'contact_update') {
        unawaited(_load());
        unawaited(_loadConversationMeta(force: true));
        unawaited(_syncKnownContactsSilently(force: true));
        unawaited(_loadTravelStories());
      }
    } catch (_) {
      // A regular chat event is irrelevant on this lightweight story channel.
    }
  }

  void _scheduleStorySocketReconnect() {
    _storySocketSub = null;
    _storyChannel = null;
    if (!mounted ||
        _storySocketClosedByUs ||
        !_travelerContactsEnabled ||
        ApiService.activeToken == null) {
      return;
    }
    _storyReconnectTimer?.cancel();
    _storyReconnectTimer = Timer(
      const Duration(seconds: 3),
      _connectStorySocket,
    );
  }

  void _closeStorySocket() {
    _storySocketClosedByUs = true;
    _storyReconnectTimer?.cancel();
    _storyReconnectTimer = null;
    _storySocketSub?.cancel();
    _storySocketSub = null;
    try {
      _storyChannel?.sink.close();
    } catch (_) {}
    _storyChannel = null;
  }

  Future<void> _load({bool force = false}) async {
    if (_refreshing && !force) return;
    final generation = ++_conversationLoadGeneration;
    final archivedMode = _archived;
    final favoritesMode = _favorites;
    _refreshing = true;
    if (ApiService.activeToken == null) {
      if (mounted) setState(() => _loading = false);
      _refreshing = false;
      return;
    }
    try {
      final cacheKey =
          'chat_conversations_${archivedMode
              ? 'archived'
              : favoritesMode
              ? 'favorites'
              : 'active'}';
      final cached = await LocalCacheService.readList(cacheKey);
      if (mounted && generation == _conversationLoadGeneration) {
        setState(() {
          if (cached.isNotEmpty && _conversations.isEmpty) {
            _conversations = _sortedConversations(cached);
          }
          _loading = false;
        });
        if (cached.isNotEmpty) {
          _openInitialConversationIfNeeded();
          _showShareHint();
        }
      }
      final items = await ApiService.fetchConversations(
        archived: archivedMode,
        favoritesOnly: favoritesMode,
      );
      await LocalCacheService.writeList(cacheKey, items);
      if (!mounted || generation != _conversationLoadGeneration) return;
      setState(() {
        _conversations = _sortedConversations(items);
        _loading = false;
        _selected.removeWhere(
          (id) => !items.any((item) => item['userId'] == id),
        );
      });
      _openInitialConversationIfNeeded();
      _showShareHint();
      _showInitialTicketShare();
      unawaited(_loadTravelStories());
      unawaited(_syncKnownContactsSilently());
      if (!archivedMode && !favoritesMode) {
        unawaited(_loadConversationMeta(force: force));
      }
    } catch (_) {
      if (mounted && generation == _conversationLoadGeneration) {
        setState(() => _loading = false);
      }
    } finally {
      if (generation == _conversationLoadGeneration) _refreshing = false;
    }
  }

  Future<void> _loadConversationMeta({bool force = false}) async {
    if (!_travelerContactsEnabled || ApiService.activeToken == null) return;
    final now = DateTime.now();
    if (!force &&
        _lastConversationMetaSync != null &&
        now.difference(_lastConversationMetaSync!) <
            const Duration(seconds: 30)) {
      return;
    }
    _lastConversationMetaSync = now;
    final archivedKey = 'chat_archived_summary_$_conversationMetaCacheSuffix';
    final requestsKey = _friendRequestsCacheKey;
    final cached = await Future.wait([
      LocalCacheService.readList(archivedKey),
      LocalCacheService.readList(requestsKey),
      LocalCacheService.readList(_travelerContactsCacheKey),
      LocalCacheService.readList(_seenContactsCacheKey),
    ]);
    if (mounted &&
        (cached[0].isNotEmpty ||
            cached[1].isNotEmpty ||
            cached[2].isNotEmpty)) {
      setState(() {
        _archivedConversations = _sortedConversations(cached[0]);
        _friendRequests = cached[1];
        _contactAttentionIds = _contactAttentionIdsFor(
          cached[2],
          cached[1],
          cached[3],
        );
      });
    }
    try {
      final results = await Future.wait([
        ApiService.fetchConversations(archived: true),
        ApiService.fetchFriendRequests(),
      ]);
      final archived = List<Map<String, dynamic>>.from(results[0]);
      final requests = List<Map<String, dynamic>>.from(results[1]);
      await Future.wait([
        LocalCacheService.writeList(archivedKey, archived),
        LocalCacheService.writeList(requestsKey, requests),
      ]);
      if (!mounted) return;
      setState(() {
        _archivedConversations = _sortedConversations(archived);
        _friendRequests = requests;
        _contactAttentionIds = _contactAttentionIdsFor(
          cached[2],
          requests,
          cached[3],
        );
      });
    } catch (_) {
      // Cached summaries keep these navigation rows usable offline.
    }
  }

  Future<void> _openReceivedFriendRequests() async {
    _dismissStorySelection();
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _ReceivedFriendRequestsScreen(
          initialRequests: _incomingFriendRequests,
        ),
      ),
    );
    if (!mounted) return;
    await _loadConversationMeta(force: true);
  }

  Future<void> _setConversationMode({
    required bool archived,
    required bool favorites,
  }) async {
    _dismissStorySelection();
    if (!mounted) return;
    setState(() {
      _archived = archived;
      _favorites = favorites;
      _conversations = [];
      _selected.clear();
      _loading = true;
    });
    await _load(force: true);
  }

  Future<void> _loadCachedTravelStories() async {
    if (!_travelerContactsEnabled) return;
    final cached = await LocalCacheService.readList(_storyCacheKey);
    final active = cached.where(_storyStillActive).toList();
    if (!mounted || active.isEmpty) return;
    setState(() => _travelStories = active);
  }

  Future<void> _loadTravelStories() async {
    if (!_travelerContactsEnabled || _loadingStories) return;
    _loadingStories = true;
    try {
      final items = await ApiService.fetchTravelStories();
      final activeStories = items
          .where(_storyStillActive)
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      final localPending = _travelStories
          .where(
            (story) =>
                ((story['id'] as num?)?.toInt() ?? 0) < 0 &&
                story['uploadState'] != 'sent',
          )
          .map((story) => Map<String, dynamic>.from(story))
          .toList();
      final mergedStories = [...localPending, ...activeStories];
      await LocalCacheService.writeList(_storyCacheKey, mergedStories);
      if (mounted) {
        setState(() => _travelStories = mergedStories);
      }
      unawaited(_prefetchTravelStoryMedia(activeStories));
    } catch (_) {
      await _loadCachedTravelStories();
    } finally {
      _loadingStories = false;
    }
  }

  Future<void> _prefetchTravelStoryMedia(
    List<Map<String, dynamic>> stories,
  ) async {
    if (stories.isEmpty) return;
    final cachedStories = <Map<String, dynamic>>[];
    for (var index = 0; index < stories.length; index++) {
      final story = await _attachCachedStoryMedia(stories[index]);
      cachedStories.add(
        index < 80 && !_storyMediaIsVideo(story)
            ? await _cacheTravelStoryMedia(story)
            : story,
      );
    }
    await LocalCacheService.writeList(_storyCacheKey, cachedStories);
    if (!mounted) return;
    setState(
      () => _travelStories = cachedStories.where(_storyStillActive).toList(),
    );
  }

  Future<Map<String, dynamic>> _cacheTravelStoryMedia(
    Map<String, dynamic> story,
  ) async {
    final next = Map<String, dynamic>.from(story);
    if (_storyCachedFileAvailable(next)) return next;
    final url = _storyMediaUrl(next);
    if (url.isEmpty) return next;
    try {
      final file = await _storyCacheFileFor(next, url);
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

  Future<Map<String, dynamic>> _attachPreparedStoryLocalMedia(
    Map<String, dynamic> story,
    _PreparedAttachment prepared,
  ) async {
    final next = Map<String, dynamic>.from(story);
    try {
      final dir = await getTemporaryDirectory();
      final storyId = (story['id'] ?? DateTime.now().microsecondsSinceEpoch)
          .toString();
      final extension = prepared.mime.startsWith('video/')
          ? 'mp4'
          : prepared.mime.contains('png')
          ? 'png'
          : prepared.mime.contains('webp')
          ? 'webp'
          : 'jpg';
      final file = File(
        '${dir.path}${Platform.pathSeparator}tranviko-story-$storyId.$extension',
      );
      await file.writeAsBytes(prepared.bytes, flush: true);
      next['cachedMediaPath'] = file.path;
    } catch (_) {}
    return next;
  }

  Future<void> _publishTravelStory() async {
    _dismissStorySelection();
    final type = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        Widget option({
          required String value,
          required IconData icon,
          required String title,
          required String subtitle,
        }) {
          return Material(
            color: scheme.primary.withValues(alpha: .07),
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => Navigator.pop(context, value),
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: scheme.onPrimary),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            subtitle,
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                  ],
                ),
              ),
            ),
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Nouvelle story',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 5),
                Text(
                  'Choisissez un media. Il restera visible pendant 24 heures.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 18),
                option(
                  value: 'image',
                  icon: Icons.photo_camera_back_rounded,
                  title: 'Photo',
                  subtitle: 'Recadrage et legende avant publication',
                ),
                const SizedBox(height: 10),
                option(
                  value: 'video',
                  icon: Icons.video_camera_back_rounded,
                  title: 'Video',
                  subtitle: 'Compression automatique avant l envoi',
                ),
              ],
            ),
          ),
        );
      },
    );
    if (type == null || !mounted) return;
    _PickedAttachment? picked;
    if (Platform.isAndroid) {
      picked = await _pickSingleStoryMedia(
        context,
        type == 'video' ? 'video' : 'image',
      );
      // Closing the Tranviko gallery is a cancellation, not a request to
      // unexpectedly open Android's native picker afterwards.
      if (picked == null) return;
    } else {
      final picker = ImagePicker();
      final XFile? systemPicked = type == 'video'
          ? await picker.pickVideo(source: ImageSource.gallery)
          : await picker.pickImage(
              source: ImageSource.gallery,
              imageQuality: 88,
            );
      if (systemPicked == null || !mounted) return;
      final bytes = await File(systemPicked.path).readAsBytes();
      picked = _PickedAttachment(
        bytes: bytes,
        name: systemPicked.name.isEmpty
            ? (type == 'video' ? 'story.mp4' : 'story.jpg')
            : systemPicked.name,
        mime: type == 'video' ? 'video/mp4' : 'image/jpeg',
        localPath: systemPicked.path,
      );
    }
    if (!mounted) return;
    final prepared = await Navigator.push<_PreparedAttachment>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _MediaPreparationScreen(
          bytes: picked!.bytes,
          name: picked.name,
          mime: picked.mime,
          localPath: picked.localPath,
        ),
      ),
    );
    if (prepared == null || !mounted) return;
    final options = await _showTravelStoryOptions(
      context,
      prepared.caption,
      friends: _conversations,
      currentUserId: int.tryParse(
        (ApiService.currentUser?['id'] ??
                ApiService.currentUser?['userId'] ??
                '')
            .toString(),
      ),
    );
    if (options == null || !mounted) return;
    await _queueTravelStoryUpload(prepared, options);
  }

  Future<void> _queueTravelStoryUpload(
    _PreparedAttachment prepared,
    _StoryPublishOptions options,
  ) async {
    final localId = -DateTime.now().microsecondsSinceEpoch;
    final now = DateTime.now();
    final currentUser = ApiService.currentUser ?? const <String, dynamic>{};
    final draft = await _attachPreparedStoryLocalMedia({
      'id': localId,
      'authorId': int.tryParse(
        (currentUser['id'] ?? currentUser['userId'] ?? '').toString(),
      ),
      'authorName': (currentUser['fullName'] ?? currentUser['name'] ?? 'Moi')
          .toString(),
      'authorPhotoBase64': currentUser['profilePhotoBase64'] ?? '',
      'authorPhotoUrl': currentUser['profilePhotoUrl'] ?? '',
      'mediaType': prepared.mime.startsWith('video/') ? 'video' : 'image',
      'caption': options.caption,
      'allowReshare': options.allowReshare,
      'audienceMode': options.audienceMode,
      'audienceUserIds': options.audienceUserIds,
      'uploadName': prepared.name,
      'uploadMime': prepared.mime,
      'createdAt': now.toIso8601String(),
      'expiresAt': now.add(const Duration(hours: 24)).toIso8601String(),
      'viewCount': 0,
      'likeCount': 0,
      'uploadState': 'uploading',
    }, prepared);
    _pendingStoryUploads[localId] = _PendingStoryUpload(prepared, options);
    if (!mounted) return;
    setState(() => _travelStories.insert(0, draft));
    await LocalCacheService.writeList(_storyCacheKey, _travelStories);
    unawaited(_performTravelStoryUpload(localId));
  }

  Future<bool> _performTravelStoryUpload(int localId) async {
    final pending = _pendingStoryUploads[localId];
    if (pending == null) return false;
    if (mounted) {
      setState(() {
        final index = _travelStories.indexWhere(
          (item) => item['id'] == localId,
        );
        if (index >= 0) {
          _travelStories[index] = {
            ..._travelStories[index],
            'uploadState': 'uploading',
          };
        }
      });
    }
    try {
      final created = await ApiService.createTravelStory(
        bytes: pending.prepared.bytes,
        name: pending.prepared.name,
        mimeType: pending.prepared.mime,
        caption: pending.options.caption,
        allowReshare: pending.options.allowReshare,
        audienceMode: pending.options.audienceMode,
        audienceUserIds: pending.options.audienceUserIds,
      );
      final localStory = await _attachPreparedStoryLocalMedia({
        ...created,
        'uploadState': 'sent',
      }, pending.prepared);
      _pendingStoryUploads.remove(localId);
      if (!mounted) return true;
      setState(() {
        final index = _travelStories.indexWhere(
          (item) => item['id'] == localId,
        );
        if (index >= 0) {
          _travelStories[index] = localStory;
        } else {
          _travelStories.insert(0, localStory);
        }
      });
      await LocalCacheService.writeList(_storyCacheKey, _travelStories);
      unawaited(_loadTravelStories());
      return true;
    } catch (error) {
      if (!mounted) return false;
      setState(() {
        final index = _travelStories.indexWhere(
          (item) => item['id'] == localId,
        );
        if (index >= 0) {
          _travelStories[index] = {
            ..._travelStories[index],
            'uploadState': 'failed',
            'uploadError': AppToast.friendlyError(
              error,
              fallback: 'Story non envoyee',
            ),
          };
        }
      });
      await LocalCacheService.writeList(_storyCacheKey, _travelStories);
      return false;
    }
  }

  Future<bool> _retryTravelStoryUpload(int localId) async {
    if (!_pendingStoryUploads.containsKey(localId)) {
      final story = _travelStories.cast<Map<String, dynamic>?>().firstWhere(
        (item) => item?['id'] == localId,
        orElse: () => null,
      );
      final path = story == null ? '' : _storyCachedMediaPath(story);
      if (story == null || path.isEmpty) return false;
      final file = File(path);
      if (!await file.exists()) return false;
      final bytes = await file.readAsBytes();
      _pendingStoryUploads[localId] = _PendingStoryUpload(
        _PreparedAttachment(
          bytes: bytes,
          name: story['uploadName']?.toString() ?? 'story-media',
          mime:
              story['uploadMime']?.toString() ??
              (story['mediaType'] == 'video' ? 'video/mp4' : 'image/jpeg'),
          localPath: path,
          caption: story['caption']?.toString() ?? '',
        ),
        _StoryPublishOptions(
          caption: story['caption']?.toString() ?? '',
          allowReshare: story['allowReshare'] == true,
          audienceMode: story['audienceMode']?.toString() ?? 'friends',
          audienceUserIds: ((story['audienceUserIds'] as List?) ?? const [])
              .map((item) => int.tryParse(item.toString()))
              .whereType<int>()
              .toList(),
        ),
      );
    }
    return _performTravelStoryUpload(localId);
  }

  Future<void> _deleteOwnTravelStory(Map<String, dynamic> story) async {
    final id = (story['id'] as num?)?.toInt() ?? 0;
    if (id > 0) await ApiService.deleteTravelStory(id);
    _pendingStoryUploads.remove(id);
    if (!mounted) return;
    setState(() => _travelStories.removeWhere((item) => item['id'] == id));
    await LocalCacheService.writeList(_storyCacheKey, _travelStories);
  }

  Future<void> _openTravelStory(int index) async {
    if (_travelStories.isEmpty) return;
    final activeStories = _travelStories.where(_storyStillActive).toList();
    if (activeStories.isEmpty) {
      setState(() => _travelStories = []);
      return;
    }
    List<Map<String, dynamic>> sortStoryGroup(
      List<Map<String, dynamic>> items,
    ) {
      return items..sort((a, b) {
        final aAt = DateTime.tryParse(a['createdAt']?.toString() ?? '');
        final bAt = DateTime.tryParse(b['createdAt']?.toString() ?? '');
        if (aAt != null && bAt != null) return aAt.compareTo(bAt);
        return 0;
      });
    }

    int newestFirst(
      List<Map<String, dynamic>> a,
      List<Map<String, dynamic>> b,
    ) {
      final aLatest = a.isEmpty
          ? null
          : DateTime.tryParse(a.last['createdAt']?.toString() ?? '');
      final bLatest = b.isEmpty
          ? null
          : DateTime.tryParse(b.last['createdAt']?.toString() ?? '');
      if (aLatest != null && bLatest != null) return bLatest.compareTo(aLatest);
      return 0;
    }

    final selectedFromOriginal = index >= 0 && index < _travelStories.length
        ? _travelStories[index]
        : null;
    final selected =
        selectedFromOriginal != null && _storyStillActive(selectedFromOriginal)
        ? selectedFromOriginal
        : activeStories[index.clamp(0, activeStories.length - 1).toInt()];
    final selectedAuthorId = (selected['authorId'] as num?)?.toInt();
    final grouped = <int, List<Map<String, dynamic>>>{};
    for (var i = 0; i < activeStories.length; i++) {
      final story = activeStories[i];
      final authorId = (story['authorId'] as num?)?.toInt() ?? -i - 1;
      grouped.putIfAbsent(authorId, () => []).add(story);
    }
    final groups = grouped.values.map(sortStoryGroup).toList();
    groups.sort((a, b) {
      final aUnseen = a.any((story) => story['isViewed'] != true);
      final bUnseen = b.any((story) => story['isViewed'] != true);
      if (aUnseen != bUnseen) return aUnseen ? -1 : 1;
      return newestFirst(a, b);
    });
    var groupIndex = groups.indexWhere(
      (group) => group.any(
        (story) => (story['authorId'] as num?)?.toInt() == selectedAuthorId,
      ),
    );
    if (groupIndex < 0) groupIndex = 0;
    while (mounted && groupIndex >= 0 && groupIndex < groups.length) {
      final rawGroup = groups[groupIndex];
      final viewerStories = <Map<String, dynamic>>[];
      for (final story in rawGroup) {
        viewerStories.add(await _attachCachedStoryMedia(story));
      }
      if (!mounted || viewerStories.isEmpty) break;
      final firstUnseenIndex = viewerStories.indexWhere(
        (story) => story['isViewed'] != true,
      );
      final initialIndex = firstUnseenIndex >= 0 ? firstUnseenIndex : 0;
      final result = await Navigator.push<Map<String, dynamic>?>(
        context,
        _storyViewerRoute(viewerStories, initialIndex),
      );
      if (result?['completed'] == true) {
        groupIndex += 1;
        continue;
      }
      break;
    }
    if (mounted) _loadTravelStories();
  }

  Route<Map<String, dynamic>?> _storyViewerRoute(
    List<Map<String, dynamic>> stories,
    int initialIndex,
  ) {
    return PageRouteBuilder<Map<String, dynamic>?>(
      opaque: false,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) =>
          _TravelStoryViewer(stories: stories, initialIndex: initialIndex),
      transitionsBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(.28, .04),
            end: Offset.zero,
          ).animate(curved),
          child: RotationTransition(
            turns: Tween<double>(begin: .018, end: 0).animate(curved),
            child: ScaleTransition(
              scale: Tween<double>(begin: .94, end: 1).animate(curved),
              child: child,
            ),
          ),
        );
      },
    );
  }

  Future<void> _openMyTravelStories() async {
    final currentUserId = int.tryParse(
      (ApiService.currentUser?['id'] ?? ApiService.currentUser?['userId'] ?? '')
          .toString(),
    );
    final ownStories =
        _travelStories
            .where(
              (story) =>
                  _storyStillActive(story) &&
                  (story['authorId'] as num?)?.toInt() == currentUserId,
            )
            .map((story) => Map<String, dynamic>.from(story))
            .toList()
          ..sort(
            (a, b) => _messageDate(
              b['createdAt'],
            ).compareTo(_messageDate(a['createdAt'])),
          );
    if (ownStories.isEmpty) {
      await _publishTravelStory();
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _MyTravelStoriesScreen(
          stories: ownStories,
          onAdd: _publishTravelStory,
          onOpen: (story) async {
            final index = _travelStories.indexWhere(
              (item) => item['id'] == story['id'],
            );
            if (index >= 0 && mounted) await _openTravelStory(index);
          },
          onDelete: _deleteOwnTravelStory,
          onRetry: (story) =>
              _retryTravelStoryUpload((story['id'] as num?)?.toInt() ?? 0),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _hideTravelStoryAuthorFromStrip(int index) async {
    if (index < 0 || index >= _travelStories.length) return;
    final story = _travelStories[index];
    final storyId = (story['id'] as num?)?.toInt();
    final authorId = (story['authorId'] as num?)?.toInt();
    final currentUserId = int.tryParse(
      (ApiService.currentUser?['id'] ?? ApiService.currentUser?['userId'] ?? '')
          .toString(),
    );
    if (storyId == null || authorId == null || authorId == currentUserId) {
      return;
    }
    try {
      await ApiService.hideTravelStory(storyId);
      if (!mounted) return;
      setState(() {
        _travelStories.removeWhere(
          (item) => (item['authorId'] as num?)?.toInt() == authorId,
        );
      });
      await LocalCacheService.writeList(_storyCacheKey, _travelStories);
      if (mounted) {
        AppToast.show(
          context,
          'Stories de ce contact masquees.',
          tone: AppToastTone.success,
        );
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(
          context,
          'Masquage impossible.',
          tone: AppToastTone.error,
        );
      }
    }
  }

  Future<void> _openHiddenTravelStories() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const _HiddenTravelStoriesScreen(),
      ),
    );
    if (changed == true && mounted) {
      unawaited(_loadTravelStories());
    }
  }

  void _openInitialConversationIfNeeded() {
    if (_openedInitialConversation || widget.initialUserId == null) return;
    Map<String, dynamic>? match;
    for (final item in _conversations) {
      if (item['userId'] == widget.initialUserId) {
        match = item;
        break;
      }
    }
    if (match == null) return;
    final conversation = match;
    _openedInitialConversation = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            other: conversation,
            initialSharedMedia: _consumePendingSharedMedia(),
          ),
        ),
      );
      if (mounted) _load();
      if (mounted) unawaited(_loadConversationMeta(force: true));
    });
  }

  Future<void> _bulkAction(String action) async {
    final ids = _selected.toList();
    setState(() => _selected.clear());
    for (final id in ids) {
      await ApiService.chatConversationAction(userId: id, action: action);
    }
    await _load();
  }

  void _showInitialTicketShare() {
    final ticket = widget.initialTicketShare;
    if (_ticketSharePrompted ||
        ticket == null ||
        _archived ||
        _favorites ||
        _conversations.isEmpty ||
        !mounted) {
      return;
    }
    _ticketSharePrompted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final recipients = await _pickRecipients(title: 'Partager ce billet');
      if (!mounted || recipients == null || recipients.isEmpty) return;
      try {
        final route = (ticket['route'] ?? 'Trajet').toString();
        final code = (ticket['reservationCode'] ?? '').toString();
        for (final userId in recipients) {
          await ApiService.sendChatMessage(
            userId: userId,
            body: 'Billet partage: $route${code.isEmpty ? '' : ' - $code'}',
            type: 'tool',
            toolAction: 'share_ticket',
            metadata: {
              'title': 'Billet partage',
              'icon': Icons.confirmation_number_outlined.codePoint,
              'actionType': 'share_ticket',
              'payload': {...ticket, 'travelTool': true, 'kind': 'ticket'},
            },
          );
        }
        if (mounted) {
          AppToast.show(
            context,
            'Billet envoye a ${recipients.length} ami(s).',
            tone: AppToastTone.success,
          );
        }
      } catch (error) {
        if (mounted) {
          AppToast.show(
            context,
            AppToast.friendlyError(
              error,
              fallback: 'Partage du billet impossible.',
            ),
            tone: AppToastTone.error,
          );
        }
      }
    });
  }

  Future<void> _conversationAction(int userId, String action) async {
    try {
      await ApiService.chatConversationAction(userId: userId, action: action);
      await _load(force: true);
    } catch (error) {
      if (mounted) {
        AppToast.show(
          context,
          AppToast.friendlyError(
            error,
            fallback: 'Action sur la discussion impossible.',
          ),
          tone: AppToastTone.error,
        );
      }
    }
  }

  Future<Set<int>?> _pickRecipients({
    required String title,
    int? excludedUserId,
    bool includeStoryTarget = false,
  }) {
    final choices = _sortedConversations(
      _conversations.where((item) => item['userId'] != excludedUserId).toList(),
    );
    return showModalBottomSheet<Set<int>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ConversationRecipientPicker(
        title: title,
        conversations: choices,
        includeStoryTarget: includeStoryTarget,
      ),
    );
  }

  String _sharedMimeFromName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.webm')) return 'video/webm';
    return 'application/octet-stream';
  }

  OverlayEntry _showShareProgress(ValueListenable<String> progress) {
    final entry = OverlayEntry(
      builder: (_) => Material(
        color: Colors.black54,
        child: Center(child: _MediaShareProgressDialog(progress: progress)),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(entry);
    return entry;
  }

  Future<List<_PreparedAttachment>?> _preparePendingSharedMedia() async {
    final loading = ValueNotifier<String>('Ouverture des medias...');
    final loadingOverlay = _showShareProgress(loading);
    var loadingClosed = false;
    try {
      final picked = <_PickedAttachment>[];
      for (final item in _pendingSharedMedia) {
        final uri = item['uri']?.toString() ?? '';
        if (uri.isEmpty) continue;
        final bytes = await _galleryChannel.invokeMethod<Uint8List>(
          'readMedia',
          {'uri': uri},
        );
        if (bytes == null || bytes.isEmpty) continue;
        final name = (item['name'] ?? '').toString().trim();
        final mime = (item['mime'] ?? '').toString().trim();
        picked.add(
          _PickedAttachment(
            bytes: bytes,
            name: name.isEmpty ? 'tranviko-media' : name,
            mime: mime.isEmpty ? _sharedMimeFromName(name) : mime,
            localPath: uri,
          ),
        );
      }
      loadingOverlay.remove();
      loading.dispose();
      loadingClosed = true;
      if (!mounted || picked.isEmpty) return null;
      if (picked.length > 1) {
        return Navigator.push<List<_PreparedAttachment>>(
          context,
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => _MediaBatchPreparationScreen(items: picked),
          ),
        );
      }
      final item = picked.first;
      final prepared = await Navigator.push<_PreparedAttachment>(
        context,
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => _MediaPreparationScreen(
            bytes: item.bytes,
            name: item.name,
            mime: item.mime,
            localPath: item.localPath,
          ),
        ),
      );
      return prepared == null ? null : [prepared];
    } catch (_) {
      if (!loadingClosed) {
        if (loadingOverlay.mounted) loadingOverlay.remove();
        loading.dispose();
      }
      rethrow;
    }
  }

  Future<void> _sharePendingMedia() async {
    if (_sharingMedia || _pendingSharedMedia.isEmpty || !mounted) return;
    final recipients = await _pickRecipients(
      title: 'Envoyer ${_pendingSharedMedia.length} media(s)',
      includeStoryTarget: _travelerContactsEnabled,
    );
    if (!mounted || recipients == null || recipients.isEmpty) return;
    if (recipients.contains(_shareToStoryTargetId)) {
      await _sharePendingMediaToStory();
      return;
    }
    _sharingMedia = true;
    try {
      final prepared = await _preparePendingSharedMedia();
      if (!mounted || prepared == null || prepared.isEmpty) return;
      final progress = ValueNotifier<String>('Preparation de l envoi...');
      final progressOverlay = _showShareProgress(progress);
      var progressDisposed = false;
      try {
        var completed = 0;
        final total = recipients.length * prepared.length;
        for (final userId in recipients) {
          final albumId = prepared.length > 1
              ? 'album-${DateTime.now().microsecondsSinceEpoch}-$userId'
              : null;
          for (var index = 0; index < prepared.length; index++) {
            final item = prepared[index];
            progress.value = 'Envoi ${completed + 1} sur $total...';
            await ApiService.sendChatMessage(
              userId: userId,
              body: item.caption.trim().isNotEmpty
                  ? item.caption.trim()
                  : item.mime.startsWith('image/')
                  ? 'Photo'
                  : item.name,
              type: 'file',
              metadata: {
                'mimeType': item.mime,
                'fileName': item.name,
                ...item.metadata,
                if (item.caption.trim().isNotEmpty)
                  'caption': item.caption.trim(),
                if (albumId != null) ...{
                  'albumId': albumId,
                  'albumIndex': index,
                  'albumTotal': prepared.length,
                },
              },
              fileBase64: base64Encode(item.bytes),
              fileName: item.name,
              attachmentType: item.mime,
              attachmentSize: item.bytes.length,
            );
            completed++;
          }
        }
        progressOverlay.remove();
        progress.dispose();
        progressDisposed = true;
        if (!mounted) return;
        setState(() => _pendingSharedMedia = []);
        AppToast.show(
          context,
          'Medias envoyes a ${recipients.length} discussion(s).',
          tone: AppToastTone.success,
        );
        unawaited(_load());
      } finally {
        if (progressOverlay.mounted) progressOverlay.remove();
        if (!progressDisposed) progress.dispose();
      }
    } catch (error) {
      if (!mounted) return;
      AppToast.show(
        context,
        AppToast.friendlyError(error, fallback: 'Envoi des medias impossible.'),
        tone: AppToastTone.error,
      );
    } finally {
      _sharingMedia = false;
    }
  }

  Future<void> _sharePendingMediaToStory() async {
    if (_sharingMedia || _pendingSharedMedia.isEmpty || !mounted) return;
    _sharingMedia = true;
    try {
      final prepared = await _preparePendingSharedMedia();
      if (!mounted || prepared == null || prepared.isEmpty) return;
      final options = await _showTravelStoryOptions(
        context,
        prepared.length == 1 ? prepared.first.caption : '',
        friends: _conversations,
        currentUserId: int.tryParse(
          (ApiService.currentUser?['id'] ??
                  ApiService.currentUser?['userId'] ??
                  '')
              .toString(),
        ),
      );
      if (!mounted || options == null) return;
      final progress = ValueNotifier<String>(
        prepared.length > 1
            ? 'Publication de ${prepared.length} stories...'
            : 'Publication du status...',
      );
      final progressOverlay = _showShareProgress(progress);
      var progressDisposed = false;
      try {
        for (var index = 0; index < prepared.length; index++) {
          final item = prepared[index];
          progress.value = prepared.length > 1
              ? 'Story ${index + 1} sur ${prepared.length}...'
              : 'Publication du status...';
          final story = await ApiService.createTravelStory(
            bytes: item.bytes,
            name: item.name,
            mimeType: item.mime,
            caption: item.caption.trim().isNotEmpty
                ? item.caption.trim()
                : options.caption,
            allowReshare: options.allowReshare,
            audienceMode: options.audienceMode,
            audienceUserIds: options.audienceUserIds,
          );
          _travelStories.insert(
            0,
            await _attachPreparedStoryLocalMedia(story, item),
          );
        }
        progressOverlay.remove();
        progress.dispose();
        progressDisposed = true;
        if (!mounted) return;
        setState(() => _pendingSharedMedia = []);
        await LocalCacheService.writeList(_storyCacheKey, _travelStories);
        AppToast.show(
          context,
          prepared.length > 1
              ? '${prepared.length} stories publiees.'
              : 'Status publie.',
          tone: AppToastTone.success,
        );
        unawaited(_loadTravelStories());
      } finally {
        if (progressOverlay.mounted) progressOverlay.remove();
        if (!progressDisposed) progress.dispose();
      }
    } catch (error) {
      if (!mounted) return;
      AppToast.show(
        context,
        AppToast.friendlyError(
          error,
          fallback: 'Publication du status impossible.',
        ),
        tone: AppToastTone.error,
      );
    } finally {
      _sharingMedia = false;
    }
  }

  Future<List<Map<String, dynamic>>> _readDeviceContacts({
    bool requestAccess = true,
  }) async {
    if (!Platform.isAndroid) {
      if (mounted) {
        AppToast.show(
          context,
          'La synchronisation des contacts est disponible sur Android.',
          tone: AppToastTone.warning,
        );
      }
      return [];
    }
    try {
      var allowed =
          await _contactsChannel.invokeMethod<bool>('hasContactsAccess') ??
          false;
      if (!allowed && requestAccess) {
        allowed =
            await _contactsChannel.invokeMethod<bool>(
              'requestContactsAccess',
            ) ??
            false;
      }
      if (!allowed) {
        if (!requestAccess) return [];
        if (mounted) {
          AppToast.show(
            context,
            'Autorisez les contacts pour trouver vos proches sur Tranviko.',
            tone: AppToastTone.warning,
          );
        }
        return [];
      }
      final raw =
          await _contactsChannel.invokeMethod<List<dynamic>>('listContacts') ??
          [];
      return raw
          .whereType<Map>()
          .map<Map<String, dynamic>>(
            (item) => <String, dynamic>{
              'name': item['name']?.toString() ?? '',
              'phones': List<String>.from(
                (item['phones'] as List?) ?? const [],
              ),
            },
          )
          .where((item) => (item['phones'] as List).isNotEmpty)
          .toList();
    } catch (error) {
      if (mounted) {
        AppToast.show(
          context,
          AppToast.friendlyError(
            error,
            fallback: 'Lecture des contacts impossible.',
          ),
          tone: AppToastTone.error,
        );
      }
      return [];
    }
  }

  Future<Map<String, List<Map<String, dynamic>>>> _loadTravelerNetwork({
    bool readContacts = true,
  }) async {
    final contacts = readContacts
        ? await _readDeviceContacts()
        : <Map<String, dynamic>>[];
    final synced = contacts.isEmpty
        ? <Map<String, dynamic>>[]
        : await ApiService.syncPhoneContacts(contacts);
    final requests = await ApiService.fetchFriendRequests();
    await Future.wait([
      LocalCacheService.writeList(_travelerContactsCacheKey, synced),
      LocalCacheService.writeList(_friendRequestsCacheKey, requests),
    ]);
    return {'contacts': synced, 'requests': requests};
  }

  Future<void> _syncKnownContactsSilently({bool force = false}) async {
    if (!_travelerContactsEnabled || ApiService.activeToken == null) return;
    final last = _lastContactDiscoverySync;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < const Duration(minutes: 10)) {
      return;
    }
    final contacts = await _readDeviceContacts(requestAccess: false);
    if (contacts.isEmpty) return;
    _lastContactDiscoverySync = DateTime.now();
    try {
      final synced = await ApiService.syncPhoneContacts(contacts);
      await LocalCacheService.writeList(_travelerContactsCacheKey, synced);
      unawaited(_loadConversationMeta(force: true));
    } catch (_) {
      // The explicit contacts screen remains available if the network is down.
    }
  }

  Future<void> _openTravelerContacts() async {
    _dismissStorySelection();
    if (ApiService.activeToken == null) return;
    try {
      final cached = await Future.wait([
        LocalCacheService.readList(_travelerContactsCacheKey),
        LocalCacheService.readList(_friendRequestsCacheKey),
      ]);
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => _TravelerContactsSheet(
            initialContacts: cached[0],
            initialRequests: cached[1],
            onRefresh: () => _loadTravelerNetwork(),
            onOpenChat: (contact) async {
              Navigator.pop(context);
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatScreen(
                    other: {
                      'userId': contact['userId'],
                      'name':
                          contact['name'] ?? contact['username'] ?? 'Contact',
                      'role': 'voyageur',
                      'lastMessage': '',
                      'lastAt': DateTime.now().toIso8601String(),
                    },
                    initialSharedMedia: const [],
                  ),
                ),
              );
              if (mounted) _load();
            },
          ),
        ),
      );
      if (mounted) {
        _load();
        unawaited(_loadConversationMeta(force: true));
      }
    } catch (error) {
      if (mounted) {
        AppToast.show(
          context,
          AppToast.friendlyError(error, fallback: 'Contacts indisponibles.'),
          tone: AppToastTone.error,
        );
      }
    }
  }

  Future<void> _openConversationItem(Map<String, dynamic> item) async {
    _dismissStorySelection();
    final id = item['userId'] as int?;
    if (id == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(other: item, initialSharedMedia: const []),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _openConversationSearch() async {
    _dismissStorySelection();
    final selected = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _ConversationSearchScreen(
          conversations: _sortedConversations(_conversations),
        ),
      ),
    );
    if (selected != null && mounted) {
      await _openConversationItem(selected);
    }
  }

  void _toggleSelection(int id) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  List<Map<String, dynamic>> get _visible {
    final scoped = _conversations.where((item) {
      final isArchived = item['isArchived'] == true;
      if (_archived) return isArchived;
      if (_favorites) return !isArchived && item['isImportant'] == true;
      return !isArchived;
    }).toList();
    return _sortedConversations(scoped);
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = int.tryParse(
      (ApiService.currentUser?['id'] ?? ApiService.currentUser?['userId'] ?? '')
          .toString(),
    );
    final conversationRows = !_archived && !_favorites
        ? _homeConversationRows
        : _visible
              .map(
                (item) => <String, dynamic>{
                  ...item,
                  '_rowKind': 'conversation',
                },
              )
              .toList();
    return PopScope(
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _selectionMode) setState(_selected.clear);
      },
      child: Scaffold(
        backgroundColor: _screenBg(context),
        appBar: AppBar(
          backgroundColor: _selectionMode
              ? Theme.of(
                  context,
                ).colorScheme.primaryContainer.withValues(alpha: .34)
              : _screenBg(context),
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              bottom: Radius.circular(_selectionMode ? 22 : 0),
            ),
          ),
          title: Text(
            _selectionMode
                ? '${_selected.length} ${appTC(context, 'messageSelectionCount')}'
                : _archived
                ? appTC(context, 'archives')
                : _favorites
                ? appTC(context, 'favorites')
                : appTC(context, 'messaging'),
          ),
          leading: _selectionMode
              ? IconButton(
                  onPressed: () => setState(_selected.clear),
                  icon: const Icon(Icons.close),
                )
              : _archived
              ? IconButton(
                  tooltip: appTC(context, 'backToConversations'),
                  onPressed: () => unawaited(
                    _setConversationMode(archived: false, favorites: false),
                  ),
                  icon: const Icon(Icons.arrow_back_rounded),
                )
              : _favorites
              ? IconButton(
                  tooltip: appTC(context, 'backToConversations'),
                  onPressed: () => unawaited(
                    _setConversationMode(archived: false, favorites: false),
                  ),
                  icon: const Icon(Icons.arrow_back_rounded),
                )
              : null,
          actions: _selectionMode
              ? [
                  IconButton.filledTonal(
                    tooltip: _selectedAllPinned
                        ? appTC(context, 'unpin')
                        : appTC(context, 'pin'),
                    onPressed: () =>
                        _bulkAction(_selectedAllPinned ? 'unpin' : 'pin'),
                    icon: Icon(
                      _selectedAllPinned
                          ? Icons.push_pin
                          : Icons.push_pin_outlined,
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: _selectedAllImportant
                        ? appTC(context, 'removeImportant')
                        : appTC(context, 'important'),
                    onPressed: () => _bulkAction(
                      _selectedAllImportant ? 'normal' : 'important',
                    ),
                    icon: Icon(
                      _selectedAllImportant ? Icons.star : Icons.star_border,
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: _selectedAllMuted
                        ? appTC(context, 'unmute')
                        : appTC(context, 'mute'),
                    onPressed: () =>
                        _bulkAction(_selectedAllMuted ? 'unmute' : 'mute'),
                    icon: Icon(
                      _selectedAllMuted
                          ? Icons.notifications_active_outlined
                          : Icons.notifications_off_outlined,
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: _archived
                        ? appTC(context, 'unarchive')
                        : appTC(context, 'archive'),
                    onPressed: () =>
                        _bulkAction(_archived ? 'restore' : 'archive'),
                    icon: Icon(
                      _archived ? Icons.unarchive : Icons.archive_outlined,
                    ),
                  ),
                ]
              : [
                  if (!_archived &&
                      !_favorites &&
                      _pendingSharedMedia.isNotEmpty)
                    IconButton(
                      tooltip: 'Choisir les destinataires',
                      onPressed: _sharePendingMedia,
                      icon: Badge(
                        label: Text('${_pendingSharedMedia.length}'),
                        child: const Icon(Icons.send_to_mobile_outlined),
                      ),
                    ),
                  if (!_archived && !_favorites && _travelerContactsEnabled)
                    IconButton(
                      tooltip: appTC(context, 'travelerContacts'),
                      onPressed: _openTravelerContacts,
                      icon: Badge(
                        isLabelVisible: _contactAttentionIds.isNotEmpty,
                        label: Text('${_contactAttentionIds.length}'),
                        child: const Icon(Icons.person_add_alt_1_rounded),
                      ),
                    ),
                  if (!_archived && !_favorites)
                    IconButton(
                      tooltip: appTC(context, 'favorites'),
                      onPressed: () => unawaited(
                        _setConversationMode(archived: false, favorites: true),
                      ),
                      icon: const Icon(Icons.star_outline_rounded),
                    ),
                  if (!_archived && !_favorites)
                    IconButton(
                      tooltip: appTC(context, 'search'),
                      onPressed: _openConversationSearch,
                      icon: const Icon(Icons.search_rounded),
                    ),
                ],
        ),
        body: ApiService.activeToken == null
            ? Builder(
                builder: (context) {
                  _redirectToLoginIfNeeded();
                  return const Center(child: CircularProgressIndicator());
                },
              )
            : _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: Listener(
                  onPointerMove: _handleConversationPointerMove,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _dismissStorySelection,
                    child: NotificationListener<ScrollNotification>(
                      onNotification: _handleConversationScroll,
                      child: ListView(
                        controller: _conversationScroll,
                        padding: const EdgeInsets.only(bottom: 24),
                        children: [
                          if (!_archived &&
                              !_favorites &&
                              _travelerContactsEnabled) ...[
                            AnimatedSize(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                              alignment: Alignment.topCenter,
                              child: _storiesStripVisible
                                  ? Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        12,
                                        10,
                                        12,
                                        2,
                                      ),
                                      child: _TravelStoryStrip(
                                        stories: _travelStories,
                                        currentUserId: currentUserId,
                                        dismissSignal: _storyStripDismissSignal,
                                        onAdd: _publishTravelStory,
                                        onOpen: _openTravelStory,
                                        onOpenMine: _openMyTravelStories,
                                        onHide: _hideTravelStoryAuthorFromStrip,
                                        onHidden: _openHiddenTravelStories,
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                          GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTap: _dismissStorySelection,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              child: conversationRows.isEmpty
                                  ? Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                      ),
                                      child: _EmptyState(
                                        archived: _archived,
                                        favorites: _favorites,
                                      ),
                                    )
                                  : Column(
                                      key: ValueKey(
                                        '${_archived}_${_favorites}_${conversationRows.length}',
                                      ),
                                      children: [
                                        for (
                                          var i = 0;
                                          i < conversationRows.length;
                                          i++
                                        ) ...[
                                          if (conversationRows[i]['_rowKind'] ==
                                              'archive')
                                            _ConversationHubTile(
                                              icon: Icons.archive_rounded,
                                              title: appTC(context, 'archives'),
                                              subtitle:
                                                  (conversationRows[i]['lastMessage'] ??
                                                          '')
                                                      .toString(),
                                              count:
                                                  (conversationRows[i]['unread']
                                                          as num?)
                                                      ?.toInt(),
                                              onTap: () => unawaited(
                                                _setConversationMode(
                                                  archived: true,
                                                  favorites: false,
                                                ),
                                              ),
                                            )
                                          else if (conversationRows[i]['_rowKind'] ==
                                              'friendRequests')
                                            _ConversationHubTile(
                                              icon: Icons
                                                  .person_add_alt_1_rounded,
                                              title: appTC(
                                                context,
                                                'friendRequestsReceived',
                                              ),
                                              subtitle:
                                                  (conversationRows[i]['lastMessage'] ??
                                                          '')
                                                      .toString(),
                                              count:
                                                  (conversationRows[i]['unread']
                                                          as num?)
                                                      ?.toInt(),
                                              accent: Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                              onTap:
                                                  _openReceivedFriendRequests,
                                            )
                                          else
                                            _SwipeConversationTile(
                                              key: ValueKey(
                                                'conversation-${conversationRows[i]['userId']}-${_archived}',
                                              ),
                                              item: conversationRows[i],
                                              archived: _archived,
                                              enabled: !_selectionMode,
                                              onSwipeActivityChanged: (active) {
                                                if (_conversationHorizontalSwipeActive ==
                                                    active) {
                                                  return;
                                                }
                                                _conversationHorizontalSwipeActive =
                                                    active;
                                              },
                                              onAction: (action) =>
                                                  _conversationAction(
                                                    conversationRows[i]['userId']
                                                        as int,
                                                    action,
                                                  ),
                                              child: _ConversationTile(
                                                item: conversationRows[i],
                                                hasStory: _storyAuthorIds.contains(
                                                  conversationRows[i]['userId'],
                                                ),
                                                storyUnseen: _travelStories.any(
                                                  (story) =>
                                                      story['authorId'] ==
                                                          conversationRows[i]['userId'] &&
                                                      story['isViewed'] != true,
                                                ),
                                                onStoryTap: () {
                                                  _dismissStorySelection();
                                                  final storyIndex =
                                                      _travelStories.indexWhere(
                                                        (story) =>
                                                            story['authorId'] ==
                                                            conversationRows[i]['userId'],
                                                      );
                                                  if (storyIndex >= 0) {
                                                    _openTravelStory(
                                                      storyIndex,
                                                    );
                                                  }
                                                },
                                                selected: _selected.contains(
                                                  conversationRows[i]['userId'],
                                                ),
                                                onLongPress: () =>
                                                    _toggleSelection(
                                                      conversationRows[i]['userId']
                                                          as int,
                                                    ),
                                                onTap: () async {
                                                  final id =
                                                      conversationRows[i]['userId']
                                                          as int;
                                                  if (_selectionMode) {
                                                    _toggleSelection(id);
                                                    return;
                                                  }
                                                  await _openConversationItem(
                                                    conversationRows[i],
                                                  );
                                                },
                                              ),
                                            ),
                                        ],
                                      ],
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _ConversationSearchScreen extends StatefulWidget {
  final List<Map<String, dynamic>> conversations;

  const _ConversationSearchScreen({required this.conversations});

  @override
  State<_ConversationSearchScreen> createState() =>
      _ConversationSearchScreenState();
}

class _ConversationSearchScreenState extends State<_ConversationSearchScreen> {
  final _search = TextEditingController();
  Timer? _messageDebounce;
  String _filter = 'all';
  bool _loadingMessages = false;
  int _messageSearchGeneration = 0;
  List<_ConversationMessageMatch> _messageMatches = [];

  static const _filters = [
    ('unread', 'unread', Icons.markunread_rounded),
    ('photo', 'photos', Icons.photo_rounded),
    ('video', 'videos', Icons.play_circle_rounded),
    ('link', 'links', Icons.link_rounded),
    ('document', 'documents', Icons.description_rounded),
    ('app_contact', 'appContacts', Icons.person_rounded),
    ('external_contact', 'externalContacts', Icons.contact_phone_rounded),
  ];

  @override
  void dispose() {
    _messageDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _setFilter(String value) {
    setState(() => _filter = _filter == value ? 'all' : value);
    _queueMessageSearch();
  }

  void _queueMessageSearch() {
    _messageDebounce?.cancel();
    final query = _search.text.trim();
    final generation = ++_messageSearchGeneration;
    final shouldSearchMessages = query.isNotEmpty || _filter != 'all';
    if (!shouldSearchMessages) {
      setState(() {
        _loadingMessages = false;
        _messageMatches = [];
      });
      return;
    }
    setState(() => _loadingMessages = true);
    _messageDebounce = Timer(const Duration(milliseconds: 280), () {
      unawaited(_loadMessageMatches(query, generation));
    });
  }

  Future<void> _loadMessageMatches(String query, int generation) async {
    final lowered = query.toLowerCase();
    final hasTextQuery = lowered.isNotEmpty;
    final matches = <_ConversationMessageMatch>[];
    final candidates = widget.conversations.take(30).toList();
    for (final conversation in candidates) {
      if (generation != _messageSearchGeneration) return;
      final userId = int.tryParse(conversation['userId']?.toString() ?? '');
      if (userId == null) continue;
      try {
        final cachedRows = await LocalCacheService.readList(
          'chat_messages_$userId',
        );
        var rows = List<Map<String, dynamic>>.from(cachedRows);
        final page = await ApiService.fetchMessagesPage(userId, limit: 80);
        final freshRows = List<Map<String, dynamic>>.from(
          page['results'] as List? ?? const [],
        );
        final seen = <String>{};
        rows =
            [...rows, ...freshRows].where((message) {
              final key =
                  '${message['id'] ?? message['clientId'] ?? message.hashCode}';
              return seen.add(key);
            }).toList()..sort(
              (a, b) => _messageDate(
                a['createdAt'],
              ).compareTo(_messageDate(b['createdAt'])),
            );
        if (freshRows.isNotEmpty) {
          await LocalCacheService.writeList('chat_messages_$userId', rows);
        }
        for (final message in rows) {
          if (matches.length >= 24) break;
          if (!_messageMatchesFilter(message)) continue;
          final haystack = [
            message['body'],
            message['attachmentName'],
            message['attachmentType'],
            message['attachmentUrl'],
            message['type'],
            if (message['metadata'] is Map)
              (message['metadata'] as Map).values.join(' '),
          ].join(' ').toLowerCase();
          if (!hasTextQuery || haystack.contains(lowered)) {
            matches.add(
              _ConversationMessageMatch(
                conversation: conversation,
                message: message,
              ),
            );
          }
        }
      } catch (_) {}
      if (matches.length >= 24) break;
    }
    if (!mounted || generation != _messageSearchGeneration) return;
    setState(() {
      _messageMatches = matches;
      _loadingMessages = false;
    });
  }

  bool _messageMatchesFilter(Map<String, dynamic> message) {
    final type = (message['type'] ?? '').toString().toLowerCase();
    final metadata = Map<String, dynamic>.from(
      (message['metadata'] as Map?) ?? const {},
    );
    final body = (message['body'] ?? '').toString().toLowerCase();
    final attachmentName = (message['attachmentName'] ?? '')
        .toString()
        .toLowerCase();
    final attachmentType =
        (message['attachmentType'] ??
                metadata['attachmentType'] ??
                metadata['mimeType'] ??
                '')
            .toString()
            .toLowerCase();
    final attachmentUrl =
        (message['attachmentUrl'] ??
                metadata['attachmentUrl'] ??
                metadata['mediaUrl'] ??
                '')
            .toString()
            .toLowerCase();
    bool hasExt(Iterable<String> extensions) => extensions.any(
      (ext) => attachmentName.endsWith(ext) || attachmentUrl.contains(ext),
    );
    switch (_filter) {
      case 'photo':
        return type.contains('image') ||
            type.contains('photo') ||
            attachmentType.startsWith('image/') ||
            hasExt(['.jpg', '.jpeg', '.png', '.webp', '.gif']);
      case 'video':
        return type.contains('video') ||
            attachmentType.startsWith('video/') ||
            hasExt(['.mp4', '.mov', '.m4v', '.webm']);
      case 'link':
        return body.contains('http://') || body.contains('https://');
      case 'document':
        final media =
            attachmentType.startsWith('image/') ||
            attachmentType.startsWith('video/') ||
            hasExt([
              '.jpg',
              '.jpeg',
              '.png',
              '.webp',
              '.gif',
              '.mp4',
              '.mov',
              '.m4v',
              '.webm',
            ]);
        return !media &&
            (type.contains('file') ||
                attachmentType.isNotEmpty ||
                hasExt([
                  '.pdf',
                  '.doc',
                  '.docx',
                  '.xls',
                  '.xlsx',
                  '.ppt',
                  '.pptx',
                  '.txt',
                ]));
      case 'app_contact':
        return metadata['contactUserId'] != null ||
            metadata['sharedContact'] is Map;
      case 'external_contact':
        return metadata['externalContact'] is Map ||
            body.contains('+') ||
            metadata['phone'] != null;
      default:
        return true;
    }
  }

  bool _matchesFilter(Map<String, dynamic> item) {
    final preview = _conversationPreview(item).toLowerCase();
    final role = (item['role'] ?? '').toString().toLowerCase();
    final type = (item['lastMessageType'] ?? item['type'] ?? '')
        .toString()
        .toLowerCase();
    switch (_filter) {
      case 'unread':
        return ((item['unread'] as num?)?.toInt() ?? 0) > 0;
      case 'photo':
        return type.contains('image') || preview.contains('photo');
      case 'video':
        return type.contains('video') || preview.contains('video');
      case 'link':
        return preview.contains('http://') || preview.contains('https://');
      case 'document':
        return type.contains('file') ||
            preview.contains('.pdf') ||
            preview.contains('document');
      case 'app_contact':
        return role.contains('voyageur') ||
            role.contains('agent') ||
            role.contains('directeur');
      case 'external_contact':
        return role.contains('externe') || preview.contains('+');
      default:
        return true;
    }
  }

  List<Map<String, dynamic>> get _results {
    final query = _search.text.trim().toLowerCase();
    return widget.conversations.where((item) {
      if (!_matchesFilter(item)) return false;
      if (query.isEmpty) return true;
      return (item['name'] ?? '').toString().toLowerCase().contains(query) ||
          (item['role'] ?? '').toString().toLowerCase().contains(query) ||
          _conversationPreview(item).toLowerCase().contains(query);
    }).toList();
  }

  String _selectedFilterLabel(BuildContext context) {
    for (final item in _filters) {
      if (item.$1 == _filter) return appTC(context, item.$2);
    }
    return '';
  }

  String _messageSnippet(Map<String, dynamic> message) {
    final body = (message['body'] ?? '').toString().trim();
    if (body.isNotEmpty) return body;
    final attachment = (message['attachmentName'] ?? '').toString().trim();
    if (attachment.isNotEmpty) return attachment;
    final type = (message['type'] ?? '').toString();
    final attachmentType = (message['attachmentType'] ?? '').toString();
    if (type.contains('video') || attachmentType.startsWith('video/')) {
      return appTC(context, 'videos');
    }
    if (type.contains('image') ||
        type.contains('photo') ||
        attachmentType.startsWith('image/')) {
      return appTC(context, 'photos');
    }
    if (type.contains('file') || attachmentType.isNotEmpty) {
      return appTC(context, 'documents');
    }
    return type.isEmpty ? appTC(context, 'messaging') : type;
  }

  Widget _sectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 16, 2, 8),
      child: Text(
        label,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final selectedLabel = _filter == 'all'
        ? null
        : _selectedFilterLabel(context);
    final results = _results;
    final query = _search.text.trim();
    final showMessageMatches = query.isNotEmpty || _filter != 'all';
    return Scaffold(
      backgroundColor: _screenBg(context),
      body: SafeArea(
        child: Column(
          children: [
            Material(
              color: _surfacePanel(context),
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Focus(
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.backspace &&
                        _search.text.isEmpty &&
                        _filter != 'all') {
                      setState(() => _filter = 'all');
                      _queueMessageSearch();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: dark ? const Color(0xFF12233A) : Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: scheme.outline.withValues(alpha: .14),
                      ),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: appTC(context, 'back'),
                          onPressed: () => Navigator.pop(context),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: scheme.onSurfaceVariant,
                          ),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                        if (selectedLabel != null)
                          Container(
                            margin: const EdgeInsets.only(right: 7),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: dark
                                  ? const Color(0xFF1B2C43)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: scheme.primary.withValues(alpha: .20),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  selectedLabel,
                                  style: TextStyle(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                GestureDetector(
                                  onTap: () {
                                    setState(() => _filter = 'all');
                                    _queueMessageSearch();
                                  },
                                  child: Icon(
                                    Icons.close_rounded,
                                    size: 16,
                                    color: scheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Expanded(
                          child: TextField(
                            controller: _search,
                            autofocus: true,
                            onChanged: (_) {
                              setState(() {});
                              _queueMessageSearch();
                            },
                            decoration: InputDecoration(
                              hintText: selectedLabel == null
                                  ? appTC(context, 'searchContactsMessages')
                                  : '',
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 15,
                              ),
                            ),
                          ),
                        ),
                        if (_search.text.isNotEmpty)
                          IconButton(
                            onPressed: () {
                              _search.clear();
                              setState(() => _messageMatches = []);
                              _queueMessageSearch();
                            },
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              foregroundColor: scheme.onSurfaceVariant,
                            ),
                            icon: const Icon(Icons.close_rounded),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                scrollDirection: Axis.horizontal,
                itemCount: _filters.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, index) {
                  final item = _filters[index];
                  final selected = _filter == item.$1;
                  return ChoiceChip(
                    selected: selected,
                    avatar: Icon(item.$3, size: 17),
                    label: Text(appTC(context, item.$2)),
                    showCheckmark: false,
                    backgroundColor: dark
                        ? const Color(0xFF12233A)
                        : Colors.white,
                    selectedColor: dark
                        ? const Color(0xFF1B2C43)
                        : Colors.white,
                    side: BorderSide(
                      color: selected
                          ? scheme.primary.withValues(alpha: .30)
                          : scheme.outline.withValues(alpha: .14),
                    ),
                    onSelected: (_) => _setFilter(item.$1),
                  );
                },
              ),
            ),
            Expanded(
              child:
                  results.isEmpty &&
                      _messageMatches.isEmpty &&
                      !_loadingMessages
                  ? Center(
                      child: Text(
                        appTC(context, 'noResult'),
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
                      children: [
                        if (results.isNotEmpty)
                          _sectionLabel(appTC(context, 'messaging')),
                        for (final item in results) ...[
                          Material(
                            color: _surfacePanel(context),
                            borderRadius: BorderRadius.circular(18),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(18),
                              onTap: () => Navigator.pop(context, item),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    _Avatar(
                                      name: (item['name'] ?? 'Contact')
                                          .toString(),
                                      size: 46,
                                      photoBase64: item['profilePhotoBase64']
                                          ?.toString(),
                                      photoUrl: item['profilePhotoUrl']
                                          ?.toString(),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            (item['name'] ?? 'Contact')
                                                .toString(),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _conversationPreview(item),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: scheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (((item['unread'] as num?)?.toInt() ??
                                            0) >
                                        0)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: scheme.primary,
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text(
                                          '${item['unread']}',
                                          style: TextStyle(
                                            color: scheme.onPrimary,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        if (showMessageMatches) ...[
                          _sectionLabel(appTC(context, 'foundMessages')),
                          if (_loadingMessages)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 18),
                              child: Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          for (final match in _messageMatches) ...[
                            _MessageSearchResultTile(
                              match: match,
                              snippet: _messageSnippet(match.message),
                              onTap: () =>
                                  Navigator.pop(context, match.conversation),
                            ),
                            const SizedBox(height: 8),
                          ],
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationMessageMatch {
  final Map<String, dynamic> conversation;
  final Map<String, dynamic> message;

  const _ConversationMessageMatch({
    required this.conversation,
    required this.message,
  });
}

class _MessageSearchResultTile extends StatelessWidget {
  final _ConversationMessageMatch match;
  final String snippet;
  final VoidCallback onTap;

  const _MessageSearchResultTile({
    required this.match,
    required this.snippet,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final conversation = match.conversation;
    final message = match.message;
    final time = _messageDayLabel(message['createdAt']);
    final metadata = Map<String, dynamic>.from(
      (message['metadata'] as Map?) ?? const {},
    );
    final rawMediaUrl =
        (message['attachmentUrl'] ?? metadata['attachmentUrl'] ?? '')
            .toString();
    final mediaUrl = rawMediaUrl.isEmpty
        ? ''
        : rawMediaUrl.startsWith('http')
        ? rawMediaUrl
        : '${ApiService.baseUrl.replaceFirst('/api', '')}$rawMediaUrl';
    final mediaType = (message['attachmentType'] ?? metadata['mimeType'] ?? '')
        .toString()
        .toLowerCase();
    final name = (message['attachmentName'] ?? message['body'] ?? '')
        .toString()
        .toLowerCase();
    final image =
        mediaType.startsWith('image/') ||
        RegExp(r'\.(png|jpe?g|webp|gif)$').hasMatch(name);
    final video =
        mediaType.startsWith('video/') ||
        RegExp(r'\.(mp4|mov|m4v|webm)$').hasMatch(name);
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: .48),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              if ((image || video) && mediaUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (video)
                          _InlineVideoPreview(
                            url: mediaUrl,
                            muted: true,
                            showPlayButton: true,
                            autoplay: false,
                            loop: false,
                          )
                        else
                          Image.network(
                            mediaUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => ColoredBox(
                              color: scheme.surfaceContainerHighest,
                              child: const Icon(Icons.image_rounded),
                            ),
                          ),
                        if (video)
                          const Center(
                            child: Icon(
                              Icons.play_circle_fill_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                      ],
                    ),
                  ),
                )
              else
                _Avatar(
                  name: (conversation['name'] ?? 'Contact').toString(),
                  size: 42,
                  photoBase64: conversation['profilePhotoBase64']?.toString(),
                  photoUrl: conversation['profilePhotoUrl']?.toString(),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            (conversation['name'] ?? 'Contact').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        if (time.isNotEmpty)
                          Text(
                            time,
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      snippet,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConversationRecipientPicker extends StatefulWidget {
  final String title;
  final List<Map<String, dynamic>> conversations;
  final Set<int> initialSelected;
  final bool includeStoryTarget;

  const _ConversationRecipientPicker({
    required this.title,
    required this.conversations,
    this.initialSelected = const {},
    this.includeStoryTarget = false,
  });

  @override
  State<_ConversationRecipientPicker> createState() =>
      _ConversationRecipientPickerState();
}

class _ConversationRecipientPickerState
    extends State<_ConversationRecipientPicker> {
  final _search = TextEditingController();
  final Set<int> _selected = {};

  @override
  void initState() {
    super.initState();
    _selected.addAll(widget.initialSelected);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _visible {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return widget.conversations;
    return widget.conversations.where((item) {
      return (item['name'] ?? '').toString().toLowerCase().contains(query) ||
          (item['role'] ?? '').toString().toLowerCase().contains(query);
    }).toList();
  }

  void _toggle(int id) {
    HapticFeedback.selectionClick();
    if (!_selected.contains(id) && _selected.length >= 5) {
      AppToast.show(
        context,
        'Maximum 5 discussions.',
        tone: AppToastTone.warning,
      );
      return;
    }
    setState(() {
      if (!_selected.remove(id)) {
        _selected.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return FractionallySizedBox(
      heightFactor: .84,
      child: Material(
        color: dark ? const Color(0xFF101923) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Container(
              width: 42,
              height: 4,
              margin: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                color: dark ? Colors.white24 : const Color(0xFFD5DEE8),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _selected.isEmpty
                              ? 'Selectionnez une ou plusieurs discussions'
                              : '${_selected.length}/5 destinataire(s)',
                          style: TextStyle(
                            color: dark ? Colors.white60 : Colors.blueGrey,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fermer',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: appTC(context, 'searchContactsMessages'),
                  prefixIcon: const Icon(Icons.search),
                ),
              ),
            ),
            if (widget.includeStoryTarget && _search.text.trim().isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Material(
                  color: dark
                      ? const Color(0xFF172332)
                      : const Color(0xFFF7FBFF),
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () =>
                        Navigator.pop(context, {_shareToStoryTargetId}),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 11,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [
                                  Theme.of(context).colorScheme.primary,
                                  const Color(0xFF00B8D9),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: const Icon(
                              Icons.auto_stories_rounded,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  appTC(context, 'shareToStatus'),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  appTC(context, 'shareToStatusSub'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: dark
                                        ? Colors.white60
                                        : Colors.blueGrey.shade600,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: _visible.isEmpty
                  ? const Center(child: Text('Aucune discussion disponible'))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                      itemCount: _visible.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        indent: 66,
                        color: dark ? Colors.white10 : const Color(0xFFE7EDF4),
                      ),
                      itemBuilder: (context, index) {
                        final item = _visible[index];
                        final id = item['userId'] as int;
                        final selected = _selected.contains(id);
                        return ListTile(
                          minTileHeight: 66,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          selected: selected,
                          selectedTileColor: _blue.withValues(alpha: .08),
                          onTap: () => _toggle(id),
                          leading: _Avatar(
                            name: (item['name'] ?? 'Contact').toString(),
                            photoBase64: item['profilePhotoBase64']?.toString(),
                            photoUrl: item['profilePhotoUrl']?.toString(),
                          ),
                          title: Text(
                            (item['name'] ?? 'Contact').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            _conversationPreview(item),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: selected ? _blue : Colors.transparent,
                              border: Border.all(
                                color: selected
                                    ? _blue
                                    : dark
                                    ? Colors.white30
                                    : const Color(0xFFB9C6D4),
                                width: 2,
                              ),
                            ),
                            child: selected
                                ? const Icon(
                                    Icons.check,
                                    size: 17,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                        );
                      },
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: _selected.isEmpty
                        ? null
                        : () =>
                              Navigator.pop(context, Set<int>.from(_selected)),
                    icon: const Icon(Icons.send_rounded),
                    label: Text(
                      _selected.isEmpty
                          ? 'Choisir un destinataire'
                          : 'Envoyer (${_selected.length})',
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaShareProgressDialog extends StatelessWidget {
  final ValueListenable<String> progress;

  const _MediaShareProgressDialog({required this.progress});

  @override
  Widget build(BuildContext context) {
    Widget content(String value) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      content: Row(
        children: [
          const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    return ValueListenableBuilder<String>(
      valueListenable: progress,
      builder: (_, value, _) => content(value),
    );
  }
}

typedef _TravelerNetworkRefresh =
    Future<Map<String, List<Map<String, dynamic>>>> Function();

class _TravelerContactsSheet extends StatefulWidget {
  final List<Map<String, dynamic>> initialContacts;
  final List<Map<String, dynamic>> initialRequests;
  final _TravelerNetworkRefresh onRefresh;
  final Future<void> Function(Map<String, dynamic> contact) onOpenChat;

  const _TravelerContactsSheet({
    required this.initialContacts,
    required this.initialRequests,
    required this.onRefresh,
    required this.onOpenChat,
  });

  @override
  State<_TravelerContactsSheet> createState() => _TravelerContactsSheetState();
}

class _TravelerContactsSheetState extends State<_TravelerContactsSheet> {
  final _search = TextEditingController();
  final _contactsScroll = ScrollController();
  final Map<String, GlobalKey> _externalLetterKeys = {};
  static const _alphabetIndex = <String>[
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'P',
    'Q',
    'R',
    'S',
    'T',
    'U',
    'V',
    'W',
    'X',
    'Y',
    'Z',
    '#',
  ];
  final Set<int> _busyUsers = {};
  List<Map<String, dynamic>> _contacts = [];
  List<Map<String, dynamic>> _remoteAppContacts = [];
  List<Map<String, dynamic>> _requests = [];
  Timer? _searchDebounce;
  bool _refreshing = false;
  bool _searchingAppContacts = false;
  int _searchGeneration = 0;
  Set<int> _seenContactIds = {};
  bool _seenLoaded = false;
  String? _activeExternalLetter;
  bool _letterJumpInProgress = false;

  @override
  void initState() {
    super.initState();
    _contacts = List<Map<String, dynamic>>.from(widget.initialContacts);
    _requests = List<Map<String, dynamic>>.from(widget.initialRequests);
    _search.addListener(_onSearchChanged);
    _contactsScroll.addListener(_syncActiveExternalLetter);
    unawaited(_loadSeenContacts());
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    _contactsScroll.removeListener(_syncActiveExternalLetter);
    _contactsScroll.dispose();
    super.dispose();
  }

  String _contactLetter(Map<String, dynamic> item) {
    final raw = (item['name'] ?? item['contactName'] ?? item['phone'] ?? '#')
        .toString()
        .trim()
        .toUpperCase();
    if (raw.isEmpty) return '#';
    const accents = {
      'À': 'A',
      'Á': 'A',
      'Â': 'A',
      'Ä': 'A',
      'Ã': 'A',
      'Å': 'A',
      'Ç': 'C',
      'È': 'E',
      'É': 'E',
      'Ê': 'E',
      'Ë': 'E',
      'Ì': 'I',
      'Í': 'I',
      'Î': 'I',
      'Ï': 'I',
      'Ñ': 'N',
      'Ò': 'O',
      'Ó': 'O',
      'Ô': 'O',
      'Ö': 'O',
      'Õ': 'O',
      'Ù': 'U',
      'Ú': 'U',
      'Û': 'U',
      'Ü': 'U',
      'Ý': 'Y',
      'Ÿ': 'Y',
    };
    final letter = accents[raw[0]] ?? raw[0];
    return RegExp(r'^[A-Z]$').hasMatch(letter) ? letter : '#';
  }

  List<String> get _availableExternalLetters {
    final letters = _visibleContacts
        .where(_isExternalContact)
        .map(_contactLetter)
        .toSet()
        .toList();
    letters.sort(
      (a, b) => a == '#'
          ? 1
          : b == '#'
          ? -1
          : a.compareTo(b),
    );
    return letters;
  }

  Future<void> _jumpToExternalLetter(String letter) async {
    if (!_availableExternalLetters.contains(letter)) return;
    setState(() => _activeExternalLetter = letter);
    _letterJumpInProgress = true;
    try {
      var target = _externalLetterKeys[letter]?.currentContext;
      if (target == null && _contactsScroll.hasClients) {
        final visible = _visibleContacts;
        final targetIndex = visible.indexWhere(
          (item) => _isExternalContact(item) && _contactLetter(item) == letter,
        );
        if (targetIndex >= 0 && visible.isNotEmpty) {
          final ratio = (targetIndex / visible.length).clamp(0.0, 1.0);
          await _contactsScroll.animateTo(
            _contactsScroll.position.maxScrollExtent * ratio,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          );
          await Future<void>.delayed(const Duration(milliseconds: 30));
          target = _externalLetterKeys[letter]?.currentContext;
        }
      }
      if (target != null) {
        await Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: .03,
        );
      }
    } finally {
      _letterJumpInProgress = false;
      _syncActiveExternalLetter();
    }
  }

  void _dragAlphabetRail(double localY, double height) {
    if (height <= 0 || _availableExternalLetters.isEmpty) return;
    final index =
        ((localY.clamp(0.0, height - .1) / height) * _alphabetIndex.length)
            .floor()
            .clamp(0, _alphabetIndex.length - 1);
    final requested = _alphabetIndex[index];
    final requestedIndex = _alphabetIndex.indexOf(requested);
    final candidates = _availableExternalLetters.toList()
      ..sort((left, right) {
        final leftDistance = (_alphabetIndex.indexOf(left) - requestedIndex)
            .abs();
        final rightDistance = (_alphabetIndex.indexOf(right) - requestedIndex)
            .abs();
        return leftDistance.compareTo(rightDistance);
      });
    final target = candidates.first;
    if (target == _activeExternalLetter || _letterJumpInProgress) return;
    unawaited(_jumpToExternalLetter(target));
  }

  void _syncActiveExternalLetter() {
    if (!mounted || _letterJumpInProgress) return;
    String? candidate;
    double? closestBelow;
    double? closestAbove;
    String? firstAbove;
    final threshold = MediaQuery.paddingOf(context).top + kToolbarHeight + 104;
    for (final letter in _availableExternalLetters) {
      final letterContext = _externalLetterKeys[letter]?.currentContext;
      final renderObject = letterContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.attached) continue;
      final top = renderObject.localToGlobal(Offset.zero).dy;
      if (top <= threshold && (closestBelow == null || top > closestBelow)) {
        closestBelow = top;
        candidate = letter;
      } else if (top > threshold &&
          (closestAbove == null || top < closestAbove)) {
        closestAbove = top;
        firstAbove = letter;
      }
    }
    candidate ??= firstAbove;
    if (candidate != null && candidate != _activeExternalLetter) {
      setState(() => _activeExternalLetter = candidate);
    }
  }

  String _statusOf(Map<String, dynamic> item) {
    final direct = (item['friendshipStatus'] ?? item['status'] ?? '')
        .toString();
    if (direct.isNotEmpty && direct != 'none') return direct;
    final friendship = item['friendship'];
    if (friendship is Map) {
      final nested = (friendship['status'] ?? '').toString();
      if (nested.isNotEmpty) return nested;
    }
    if (item['isFriend'] == true || item['accepted'] == true) return 'accepted';
    return direct.isEmpty ? 'none' : direct;
  }

  String _directionOf(Map<String, dynamic> item) {
    final direct = (item['friendshipDirection'] ?? item['direction'] ?? '')
        .toString();
    if (direct.isNotEmpty) return direct;
    final friendship = item['friendship'];
    if (friendship is Map) {
      return (friendship['direction'] ?? '').toString();
    }
    return '';
  }

  int? _requestIdOf(Map<String, dynamic> item) {
    final direct = int.tryParse(item['id']?.toString() ?? '');
    if (direct != null) return direct;
    final friendship = item['friendship'];
    if (friendship is Map) {
      return int.tryParse(friendship['id']?.toString() ?? '');
    }
    return null;
  }

  List<Map<String, dynamic>> get _visibleContacts {
    final query = _search.text.trim().toLowerCase();
    final items = List<Map<String, dynamic>>.from(_mergedContactItems);
    items.sort((left, right) {
      final leftExternal = _isExternalContact(left);
      final rightExternal = _isExternalContact(right);
      if (leftExternal != rightExternal) return leftExternal ? 1 : -1;
      final leftName = (left['name'] ?? left['contactName'] ?? '')
          .toString()
          .toLowerCase();
      final rightName = (right['name'] ?? right['contactName'] ?? '')
          .toString()
          .toLowerCase();
      return leftName.compareTo(rightName);
    });
    if (query.isEmpty) {
      return items;
    }
    return items.where((item) {
      final haystack = [
        item['name'],
        item['contactName'],
        item['phone'],
        item['username'],
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  List<Map<String, dynamic>> get _mergedContactItems {
    final byUser = <int, Map<String, dynamic>>{};
    final external = <Map<String, dynamic>>[];
    void addItem(Map<String, dynamic> item) {
      final id = _contactId(item);
      if (id == null) {
        external.add(item);
        return;
      }
      final existing = byUser[id];
      if (existing == null) {
        byUser[id] = item;
        return;
      }
      final existingStatus = _statusOf(existing);
      final nextStatus = _statusOf(item);
      final existingBetter =
          existingStatus == 'accepted' ||
          (existingStatus == 'pending' && nextStatus == 'none');
      byUser[id] = existingBetter ? existing : {...existing, ...item};
    }

    // Accepted friends and outgoing requests also belong in this page even if
    // their number is no longer present in the local address book.
    for (final item in _requests) {
      addItem(item);
    }
    for (final item in _contacts) {
      addItem(item);
    }
    for (final item in _remoteAppContacts) {
      addItem(item);
    }
    return [...byUser.values, ...external];
  }

  String get _seenCacheKey {
    final company = ApiService.companyId ?? ApiService.companySlug ?? 'global';
    final user = ApiService.currentUser?['id']?.toString() ?? 'traveler';
    return 'traveler_seen_contacts_${company}_$user';
  }

  int? _contactId(Map<String, dynamic> item) =>
      int.tryParse(item['userId']?.toString() ?? '');

  bool _isExternalContact(Map<String, dynamic> item) =>
      item['onTranviko'] == false ||
      _statusOf(item) == 'external' ||
      _contactId(item) == null;

  void _onSearchChanged() {
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final letters = _availableExternalLetters;
      if (letters.isEmpty) {
        if (_activeExternalLetter != null) {
          setState(() => _activeExternalLetter = null);
        }
      } else {
        _syncActiveExternalLetter();
      }
    });
    final query = _search.text.trim();
    _searchDebounce?.cancel();
    if (query.length < 2) {
      setState(() {
        _remoteAppContacts = [];
        _searchingAppContacts = false;
      });
      return;
    }
    final generation = ++_searchGeneration;
    setState(() => _searchingAppContacts = true);
    _searchDebounce = Timer(const Duration(milliseconds: 260), () {
      unawaited(_searchRemoteContacts(query, generation));
    });
  }

  Future<void> _searchRemoteContacts(String query, int generation) async {
    try {
      final results = await ApiService.searchTravelerContacts(query);
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _remoteAppContacts = results;
        _searchingAppContacts = false;
      });
    } catch (_) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() => _searchingAppContacts = false);
    }
  }

  Future<void> _loadSeenContacts() async {
    final rows = await LocalCacheService.readList(_seenCacheKey);
    final ids = rows
        .map((item) => int.tryParse(item['id']?.toString() ?? ''))
        .whereType<int>()
        .toSet();
    if (!mounted) return;
    setState(() {
      _seenContactIds = ids;
      _seenLoaded = true;
    });
    unawaited(_rememberCurrentContactsSeen());
  }

  Future<void> _rememberCurrentContactsSeen() async {
    await Future<void>.delayed(const Duration(milliseconds: 850));
    final ids = _contacts.map(_contactId).whereType<int>().toSet();
    if (ids.isEmpty) return;
    final next = {..._seenContactIds, ...ids}.toList()..sort();
    await LocalCacheService.writeList(
      _seenCacheKey,
      next.map((id) => {'id': id}).toList(),
    );
  }

  bool _isNewContact(Map<String, dynamic> item) {
    if (!_seenLoaded) return false;
    final id = _contactId(item);
    if (id == null || _seenContactIds.contains(id)) return false;
    final status = _statusOf(item);
    return status == 'none' || status == 'pending';
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final data = await widget.onRefresh();
      if (!mounted) return;
      setState(() {
        _contacts = data['contacts'] ?? <Map<String, dynamic>>[];
        _requests = data['requests'] ?? <Map<String, dynamic>>[];
      });
      unawaited(_rememberCurrentContactsSeen());
      final query = _search.text.trim();
      if (query.length >= 2) {
        final generation = ++_searchGeneration;
        unawaited(_searchRemoteContacts(query, generation));
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _patchFriendState(
    int userId, {
    required String status,
    required String direction,
    int? requestId,
  }) {
    Map<String, dynamic>? source;
    for (final item in [..._contacts, ..._requests]) {
      if (_contactId(item) == userId) {
        source = Map<String, dynamic>.from(item);
        break;
      }
    }
    Map<String, dynamic> patch(Map<String, dynamic> item) {
      if (int.tryParse(item['userId']?.toString() ?? '') != userId) {
        return item;
      }
      final friendship = Map<String, dynamic>.from(
        (item['friendship'] as Map?) ?? const {},
      );
      friendship['status'] = status;
      friendship['direction'] = direction;
      if (requestId != null) friendship['id'] = requestId;
      return {
        ...item,
        'friendship': friendship,
        'friendshipStatus': status,
        'friendshipDirection': direction,
        if (requestId != null) 'id': requestId,
        'isFriend': status == 'accepted',
        'accepted': status == 'accepted',
      };
    }

    setState(() {
      _contacts = _contacts.map(patch).toList();
      _remoteAppContacts = _remoteAppContacts.map(patch).toList();
      _requests = _requests
          .map(patch)
          .where(
            (item) =>
                (status != 'accepted' && status != 'none') ||
                _contactId(item) != userId,
          )
          .toList();
      if (status == 'accepted' &&
          source != null &&
          !_contacts.any((item) => _contactId(item) == userId)) {
        _contacts.insert(0, patch(source));
      }
    });
  }

  Future<void> _sendRequest(Map<String, dynamic> item) async {
    if (_statusOf(item) == 'accepted') {
      await widget.onOpenChat(item);
      return;
    }
    final userId = int.tryParse(item['userId']?.toString() ?? '');
    if (userId == null) return;
    setState(() => _busyUsers.add(userId));
    try {
      final response = await ApiService.sendFriendRequest(userId);
      final request = Map<String, dynamic>.from(
        (response['request'] as Map?) ?? const {},
      );
      final accepted =
          response['accepted'] == true || request['status'] == 'accepted';
      final requestDirection = request['direction']?.toString() ?? '';
      _patchFriendState(
        userId,
        status: accepted ? 'accepted' : 'pending',
        direction: accepted
            ? ''
            : (requestDirection.isNotEmpty ? requestDirection : 'outgoing'),
        requestId: int.tryParse(request['id']?.toString() ?? ''),
      );
      unawaited(_refresh());
    } finally {
      if (mounted) setState(() => _busyUsers.remove(userId));
    }
  }

  Future<void> _requestAction(Map<String, dynamic> item, String action) async {
    final userId = int.tryParse(item['userId']?.toString() ?? '');
    final requestId = _requestIdOf(item);
    if (requestId == null) return;
    if (userId != null) setState(() => _busyUsers.add(userId));
    try {
      final response = await ApiService.friendRequestAction(
        requestId: requestId,
        action: action,
      );
      if (userId != null) {
        final request = Map<String, dynamic>.from(
          (response['request'] as Map?) ?? const {},
        );
        _patchFriendState(
          userId,
          status: action == 'accept' ? 'accepted' : 'none',
          direction: request['direction']?.toString() ?? '',
          requestId: int.tryParse(request['id']?.toString() ?? ''),
        );
      }
      unawaited(_refresh());
    } finally {
      if (mounted && userId != null) setState(() => _busyUsers.remove(userId));
    }
  }

  Future<void> _inviteExternalContact(Map<String, dynamic> item) async {
    final phone = (item['phone'] ?? '').toString().trim();
    if (phone.isEmpty) return;
    final body = Uri.encodeComponent(appTC(context, 'inviteToTranvikoSms'));
    final uri = Uri.parse('sms:$phone?body=$body');
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      AppToast.show(
        context,
        appTC(context, 'inviteSmsUnavailable'),
        tone: AppToastTone.error,
      );
    }
  }

  Widget _trailingFor(Map<String, dynamic> item) {
    if (_isExternalContact(item)) {
      return Tooltip(
        message: appTC(context, 'inviteToTranviko'),
        child: IconButton.filledTonal(
          onPressed: () => _inviteExternalContact(item),
          icon: const Icon(Icons.send_to_mobile_rounded),
          style: IconButton.styleFrom(
            minimumSize: const Size(46, 46),
            shape: const CircleBorder(),
          ),
        ),
      );
    }
    final userId = int.tryParse(item['userId']?.toString() ?? '');
    final busy = userId != null && _busyUsers.contains(userId);
    if (busy) {
      return const SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    final status = _statusOf(item);
    final direction = _directionOf(item);
    if (status == 'accepted') {
      final scheme = Theme.of(context).colorScheme;
      return Tooltip(
        message: appTC(context, 'openDiscussion'),
        child: IconButton.filledTonal(
          onPressed: () => widget.onOpenChat(item),
          icon: const Icon(Icons.forum_rounded),
          style: IconButton.styleFrom(
            foregroundColor: scheme.primary,
            backgroundColor: scheme.primary.withValues(alpha: .10),
            minimumSize: const Size(44, 44),
            shape: const CircleBorder(),
          ),
        ),
      );
    }
    if (status == 'pending' && direction == 'incoming') {
      return Wrap(
        spacing: 6,
        children: [
          IconButton.filledTonal(
            tooltip: 'Refuser',
            onPressed: () => _requestAction(item, 'refuse'),
            icon: const Icon(Icons.close_rounded),
          ),
          IconButton.filled(
            tooltip: 'Accepter',
            onPressed: () => _requestAction(item, 'accept'),
            icon: const Icon(Icons.check_rounded),
          ),
        ],
      );
    }
    if (status == 'pending') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: .62),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.hourglass_top_rounded, size: 15),
            const SizedBox(width: 5),
            Text(
              appTC(context, 'requestSent'),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      );
    }
    return Tooltip(
      message: appTC(context, 'sendFriendRequest'),
      child: IconButton.filled(
        onPressed: () => _sendRequest(item),
        icon: const Icon(Icons.person_add_rounded),
        style: IconButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
          minimumSize: const Size(46, 46),
          shape: const CircleBorder(),
        ),
      ),
    );
  }

  Widget _sectionHeader(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .10),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _contactCard(
    BuildContext context,
    Map<String, dynamic> item, {
    bool highlighted = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final name = item['name']?.toString() ?? 'Contact';
    final subtitle = [
      if ((item['contactName'] ?? '').toString().isNotEmpty)
        item['contactName'],
      item['phone'] ?? item['username'] ?? '',
    ].where((value) => value.toString().isNotEmpty).join(' - ');
    return Material(
      color: highlighted
          ? scheme.primary.withValues(alpha: .055)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        minTileHeight: 72,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            _Avatar(
              name: name,
              photoBase64: item['profilePhotoBase64']?.toString(),
              photoUrl: item['profilePhotoUrl']?.toString(),
            ),
            if (highlighted)
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.surface, width: 2),
                  ),
                ),
              ),
          ],
        ),
        title: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        trailing: _trailingFor(item),
      ),
    );
  }

  List<Widget> _contactSectionWidgets(BuildContext context) {
    bool incoming(Map<String, dynamic> item) =>
        _statusOf(item) == 'pending' && _directionOf(item) == 'incoming';
    final visible = _visibleContacts;
    final incomingItems = visible.where(incoming).toList();
    final newItems = visible
        .where(
          (item) =>
              !incoming(item) &&
              !_isExternalContact(item) &&
              _isNewContact(item),
        )
        .toList();
    final knownItems = visible
        .where(
          (item) =>
              !incoming(item) &&
              !_isExternalContact(item) &&
              !_isNewContact(item),
        )
        .toList();
    final externalItems = visible
        .where((item) => _isExternalContact(item))
        .toList();
    final scheme = Theme.of(context).colorScheme;
    final children = <Widget>[];
    if (incomingItems.isNotEmpty) {
      children.add(
        _sectionHeader(
          context,
          title: appTC(context, 'friendRequestsReceived'),
          subtitle: appTC(context, 'friendRequestsReceivedSub'),
          icon: Icons.mark_email_unread_rounded,
          color: scheme.secondary,
        ),
      );
      children.addAll(
        incomingItems.map(
          (item) => _contactCard(context, item, highlighted: true),
        ),
      );
    }
    if (newItems.isNotEmpty) {
      children.add(
        _sectionHeader(
          context,
          title: appTC(context, 'newOnTranviko'),
          subtitle: appTC(context, 'newOnTranvikoSub'),
          icon: Icons.auto_awesome_rounded,
          color: scheme.primary,
        ),
      );
      children.addAll(
        newItems.map((item) => _contactCard(context, item, highlighted: true)),
      );
    }
    if (knownItems.isNotEmpty) {
      children.add(
        _sectionHeader(
          context,
          title: appTC(context, 'seenContacts'),
          subtitle: appTC(context, 'seenContactsSub'),
          icon: Icons.people_alt_rounded,
          color: scheme.tertiary,
        ),
      );
      children.addAll(knownItems.map((item) => _contactCard(context, item)));
    }
    if (externalItems.isNotEmpty) {
      children.add(
        _sectionHeader(
          context,
          title: appTC(context, 'externalContacts'),
          subtitle: appTC(context, 'externalContactsInviteSub'),
          icon: Icons.sms_rounded,
          color: scheme.primary,
        ),
      );
      final byLetter = <String, List<Map<String, dynamic>>>{};
      for (final item in externalItems) {
        byLetter.putIfAbsent(_contactLetter(item), () => []).add(item);
      }
      final letters = byLetter.keys.toList()
        ..sort(
          (a, b) => a == '#'
              ? 1
              : b == '#'
              ? -1
              : a.compareTo(b),
        );
      for (final letter in letters) {
        final key = _externalLetterKeys.putIfAbsent(letter, GlobalKey.new);
        children.add(
          KeyedSubtree(
            key: key,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
              child: Row(
                children: [
                  Text(
                    letter,
                    style: TextStyle(
                      color: scheme.primary,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Divider(
                      color: scheme.outline.withValues(alpha: .18),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        children.addAll(
          (byLetter[letter] ?? const <Map<String, dynamic>>[]).map(
            (item) => _contactCard(context, item),
          ),
        );
      }
    }
    return children;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final externalLetters = _availableExternalLetters;
    if (_activeExternalLetter == null && externalLetters.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _activeExternalLetter == null) {
          setState(() => _activeExternalLetter = externalLetters.first);
        }
      });
    }
    return Scaffold(
      backgroundColor: _screenBg(context),
      appBar: AppBar(
        backgroundColor: _screenBg(context),
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: Text(
          appTC(context, 'addFriendPage'),
          style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton.filledTonal(
            tooltip: appTC(context, 'refresh'),
            onPressed: _refreshing ? null : _refresh,
            icon: _refreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            style: IconButton.styleFrom(
              minimumSize: const Size(42, 42),
              shape: const CircleBorder(),
            ),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: .48),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: scheme.outline.withValues(alpha: .10),
                  ),
                ),
                child: TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: appTC(context, 'searchContact'),
                    prefixIcon: const Icon(Icons.person_search_rounded),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: appTC(context, 'close'),
                            onPressed: _search.clear,
                            icon: const Icon(Icons.close_rounded),
                          ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _searchingAppContacts
                  ? const LinearProgressIndicator(minHeight: 2)
                  : const SizedBox(height: 2),
            ),
            Expanded(
              child: _visibleContacts.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.fromLTRB(24, 18, 24, 34),
                      children: [
                        Icon(
                          Icons.person_search_rounded,
                          size: 58,
                          color: scheme.primary,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          appTC(context, 'noTranvikoContact'),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          appTC(context, 'noTranvikoContactSub'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    )
                  : Stack(
                      children: [
                        ListView(
                          controller: _contactsScroll,
                          padding: EdgeInsets.fromLTRB(
                            16,
                            0,
                            externalLetters.isEmpty ? 18 : 42,
                            28,
                          ),
                          children: _contactSectionWidgets(context),
                        ),
                        if (externalLetters.isNotEmpty)
                          Positioned(
                            right: 3,
                            top: 4,
                            bottom: 4,
                            child: LayoutBuilder(
                              builder: (context, constraints) => GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onVerticalDragDown: (details) =>
                                    _dragAlphabetRail(
                                      details.localPosition.dy,
                                      constraints.maxHeight,
                                    ),
                                onVerticalDragUpdate: (details) =>
                                    _dragAlphabetRail(
                                      details.localPosition.dy,
                                      constraints.maxHeight,
                                    ),
                                child: Container(
                                  width: 31,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: scheme.surface.withValues(
                                      alpha: .96,
                                    ),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: scheme.outline.withValues(
                                        alpha: .12,
                                      ),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: .06,
                                        ),
                                        blurRadius: 12,
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    children: [
                                      for (final letter in _alphabetIndex)
                                        Expanded(
                                          child: InkWell(
                                            customBorder: const CircleBorder(),
                                            onTap:
                                                externalLetters.contains(letter)
                                                ? () => _jumpToExternalLetter(
                                                    letter,
                                                  )
                                                : null,
                                            child: Center(
                                              child: AnimatedContainer(
                                                duration: const Duration(
                                                  milliseconds: 150,
                                                ),
                                                width: 20,
                                                height: 20,
                                                alignment: Alignment.center,
                                                decoration: BoxDecoration(
                                                  color:
                                                      _activeExternalLetter ==
                                                          letter
                                                      ? scheme.primary
                                                      : Colors.transparent,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  child: Text(
                                                    letter,
                                                    style: TextStyle(
                                                      color:
                                                          _activeExternalLetter ==
                                                              letter
                                                          ? Colors.white
                                                          : externalLetters
                                                                .contains(
                                                                  letter,
                                                                )
                                                          ? scheme
                                                                .onSurfaceVariant
                                                          : scheme.outline
                                                                .withValues(
                                                                  alpha: .35,
                                                                ),
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                      height: 1,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
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
          ],
        ),
      ),
    );
  }
}

class _ReservationPickerSheet extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Map<String, dynamic>> reservations;
  final String Function(Map<String, dynamic>) routeOf;
  final String Function(Map<String, dynamic>) codeOf;
  final String Function(Map<String, dynamic>) dateOf;

  const _ReservationPickerSheet({
    required this.title,
    required this.subtitle,
    required this.reservations,
    required this.routeOf,
    required this.codeOf,
    required this.dateOf,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: .72,
      minChildSize: .42,
      maxChildSize: .92,
      builder: (context, controller) => Container(
        decoration: BoxDecoration(
          color: _screenBg(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 30,
              offset: Offset(0, -12),
            ),
          ],
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: scheme.outline.withValues(alpha: .32),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: scheme.primary.withValues(alpha: .12),
                    child: Icon(
                      Icons.confirmation_number_outlined,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          subtitle,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
                itemCount: reservations.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final item = reservations[index];
                  final code = codeOf(item);
                  final route = routeOf(item);
                  final date = dateOf(item);
                  return Container(
                    decoration: BoxDecoration(
                      color: _surfacePanel(context),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: scheme.outline.withValues(alpha: .16),
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      title: Text(
                        route,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      subtitle: Text(
                        [
                          code,
                          date,
                        ].where((value) => value.isNotEmpty).join(' - '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.pop(context, item),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final Map<String, dynamic> other;
  final List<Map<String, dynamic>> initialSharedMedia;

  const ChatScreen({
    super.key,
    required this.other,
    this.initialSharedMedia = const [],
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _controller = TextEditingController();
  final _conversationSearchController = TextEditingController();
  final _scroll = ScrollController();
  final Set<int> _selected = {};
  final Set<int> _visibleReadAckedIds = {};
  final Map<String, GlobalKey> _messageKeys = {};
  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _messageArchive = [];
  final List<double> _voiceWaveformSamples = [];
  WebSocketChannel? _channel;
  StreamSubscription? _socketSub;
  Timer? _reconnectTimer;
  Timer? _presenceTimer;
  Timer? _voiceTimer;
  Timer? _liveLocationTimer;
  StreamSubscription<Amplitude>? _amplitudeSub;
  final AudioRecorder _recorder = AudioRecorder();
  Map<String, dynamic>? _replyTo;
  String? _voicePath;
  int _voiceSeconds = 0;
  double _voiceLevel = 0;
  bool _loading = true;
  bool _socketOnline = false;
  bool _recording = false;
  bool _voicePaused = false;
  bool _hasText = false;
  bool _isBlocked = false;
  String _composerPreviewUrl = '';
  String _dismissedComposerPreviewUrl = '';
  bool _showJumpToBottom = false;
  bool _mediaLoadingVisible = false;
  bool _handledInitialSharedMedia = false;
  bool _resumingQueuedUploads = false;
  bool _loadingOlderMessages = false;
  bool _loadingLatestMessages = false;
  bool _hasMoreMessages = false;
  bool _backendHasMoreMessages = false;
  bool _conversationSearchActive = false;
  _ComposerPanel _composerPanel = _ComposerPanel.none;
  List<Map<String, dynamic>> _favoriteGifs = [];
  List<Map<String, dynamic>> _favoriteStickers = [];
  bool _loadingGifFavorites = false;
  bool _loadingStickerFavorites = false;
  int _conversationSearchCursor = -1;
  List<int> _conversationSearchMatches = [];
  String? _nextMessagesBefore;
  int _visibleArchiveStart = 0;
  DateTime? _liveLocationUntil;

  static const int _networkMessagePageSize = 24;
  static const int _cacheMessageWaveSize = 64;

  bool get _selectionMode => _selected.isNotEmpty;
  bool get _travelerMode =>
      ApiService.currentAgent == null &&
      ApiService.currentUser != null &&
      (ApiService.currentUser?['accountType']?.toString() == 'client' ||
          ApiService.currentUser?['accountType'] == null);
  bool get _selectionOnlyMine => _messages
      .where((item) => _expandedSelectedMessageIds.contains(item['id']))
      .every((item) => item['fromMe'] == true);
  bool get _selectionHasDeleted => _messages
      .where((item) => _expandedSelectedMessageIds.contains(item['id']))
      .any(_isDeletedMessage);

  GlobalKey _keyForMessage(dynamic id) {
    final key = id?.toString() ?? '';
    return _messageKeys.putIfAbsent(key, GlobalKey.new);
  }

  String _albumId(Map<String, dynamic> message) {
    final metadata = Map<String, dynamic>.from(
      (message['metadata'] as Map?) ?? const {},
    );
    return metadata['albumId']?.toString() ?? '';
  }

  int _albumIndex(Map<String, dynamic> message) {
    final metadata = Map<String, dynamic>.from(
      (message['metadata'] as Map?) ?? const {},
    );
    final value = metadata['albumIndex'];
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _clientId(Map<String, dynamic> message) {
    final metadata = Map<String, dynamic>.from(
      (message['metadata'] as Map?) ?? const {},
    );
    return metadata['clientId']?.toString() ?? '';
  }

  bool _isImageMessage(Map<String, dynamic> message) {
    if (message['type'] != 'file') return false;
    if (_isDeletedMessage(message)) return false;
    final type =
        message['attachmentType']?.toString() ??
        (message['metadata'] as Map?)?['mimeType']?.toString() ??
        '';
    final name =
        message['attachmentName']?.toString() ??
        message['body']?.toString() ??
        '';
    return type.startsWith('image/') ||
        RegExp(r'\.(png|jpe?g|webp|gif)$', caseSensitive: false).hasMatch(name);
  }

  bool _isDeletedMessage(Map<String, dynamic> message) =>
      message['isDeleted'] == true || message['deletedForEveryone'] == true;

  bool _canMergeInAlbum(
    Map<String, dynamic> previous,
    Map<String, dynamic> current,
  ) {
    if (!_isImageMessage(previous) || !_isImageMessage(current)) return false;
    if (previous['fromMe'] != current['fromMe']) return false;
    if (!_sameMessageDay(previous['createdAt'], current['createdAt'])) {
      return false;
    }
    final previousAlbum = _albumId(previous);
    final currentAlbum = _albumId(current);
    if (previousAlbum.isNotEmpty && previousAlbum == currentAlbum) {
      return _albumIndex(current) == _albumIndex(previous) + 1;
    }
    final previousAt = _messageDate(previous['createdAt']);
    final currentAt = _messageDate(current['createdAt']);
    if (previousAt.millisecondsSinceEpoch == 0 ||
        currentAt.millisecondsSinceEpoch == 0) {
      return true;
    }
    return currentAt.difference(previousAt).inMinutes.abs() <= 10;
  }

  bool _isAlbumContinuation(int index) {
    if (index <= 0 || index >= _messages.length) return false;
    final current = _messages[index];
    final previous = _messages[index - 1];
    return _canMergeInAlbum(previous, current);
  }

  bool _startsMessageDay(int index) {
    if (index <= 0) return true;
    return !_sameMessageDay(
      _messages[index - 1]['createdAt'],
      _messages[index]['createdAt'],
    );
  }

  List<Map<String, dynamic>> _albumAt(int index) {
    if (index < 0 || index >= _messages.length) return const [];
    final first = _messages[index];
    if (!_isImageMessage(first)) return const [];
    final items = <Map<String, dynamic>>[];
    for (var i = index; i < _messages.length; i++) {
      final item = _messages[i];
      if (!_isImageMessage(item)) break;
      if (items.isNotEmpty && !_canMergeInAlbum(items.last, item)) break;
      items.add(item);
    }
    return items;
  }

  List<Map<String, dynamic>> _albumForMessage(Map<String, dynamic> message) {
    final index = _messages.indexWhere((item) => item['id'] == message['id']);
    if (index < 0 || !_isImageMessage(message)) return [message];
    var start = index;
    while (start > 0 &&
        _canMergeInAlbum(_messages[start - 1], _messages[start])) {
      start--;
    }
    final album = _albumAt(start);
    return album.isEmpty ? [message] : album;
  }

  Set<int> get _expandedSelectedMessageIds {
    final ids = <int>{};
    for (final message in _messages) {
      final id = (message['id'] as num?)?.toInt();
      if (id == null || !_selected.contains(id)) continue;
      for (final item in _albumForMessage(message)) {
        final itemId = (item['id'] as num?)?.toInt();
        if (itemId != null && itemId > 0) ids.add(itemId);
      }
    }
    return ids;
  }

  @override
  void initState() {
    super.initState();
    _isBlocked = widget.other['isBlocked'] == true;
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_syncComposerState);
    _conversationSearchController.addListener(_refreshConversationSearch);
    _scroll.addListener(_syncScrollButton);
    _scroll.addListener(_maybeLoadOlderMessages);
    unawaited(_loadFavoriteGifs());
    unawaited(_loadFavoriteStickers());
    _load();
    unawaited(_loadConversationStatus());
    _connectSocket();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _processInitialSharedMedia(),
    );
  }

  Future<void> _loadConversationStatus() async {
    try {
      final otherId = widget.other['userId'] as int;
      final info = await ApiService.fetchChatConversationInfo(otherId);
      if (mounted) setState(() => _isBlocked = info['isBlocked'] == true);
    } catch (_) {}
  }

  Future<void> _processInitialSharedMedia() async {
    if (_handledInitialSharedMedia ||
        widget.initialSharedMedia.isEmpty ||
        !mounted) {
      return;
    }
    _handledInitialSharedMedia = true;
    _showMediaLoadingOverlay(
      widget.initialSharedMedia.length > 1
          ? 'Preparation de ${widget.initialSharedMedia.length} medias...'
          : 'Preparation du media...',
    );
    try {
      final picked = <_PickedAttachment>[];
      for (final item in widget.initialSharedMedia) {
        final uri = item['uri']?.toString() ?? '';
        if (uri.isEmpty) continue;
        final bytes = await _galleryChannel.invokeMethod<Uint8List>(
          'readMedia',
          {'uri': uri},
        );
        if (bytes == null || bytes.isEmpty) continue;
        final name = (item['name'] ?? '').toString().trim();
        final mime = (item['mime'] ?? '').toString().trim();
        picked.add(
          _PickedAttachment(
            bytes: bytes,
            name: name.isEmpty ? 'tranviko-media' : name,
            mime: mime.isEmpty ? _mimeFromFileName(name) : mime,
            localPath: uri,
          ),
        );
      }
      _hideMediaLoadingOverlay();
      if (!mounted || picked.isEmpty) return;
      if (picked.length > 1) {
        final prepared = await Navigator.push<List<_PreparedAttachment>>(
          context,
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => _MediaBatchPreparationScreen(items: picked),
          ),
        );
        if (!mounted || prepared == null || prepared.isEmpty) return;
        final albumId = prepared.length > 1
            ? 'album-${DateTime.now().microsecondsSinceEpoch}'
            : null;
        for (var i = 0; i < prepared.length; i++) {
          await _sendPreparedAttachment(
            prepared[i],
            albumId: albumId,
            albumIndex: i,
            albumTotal: prepared.length,
          );
        }
        return;
      }
      final item = picked.first;
      final prepared = await Navigator.push<_PreparedAttachment>(
        context,
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => _MediaPreparationScreen(
            bytes: item.bytes,
            name: item.name,
            mime: item.mime,
            localPath: item.localPath,
          ),
        ),
      );
      if (!mounted || prepared == null) return;
      await _sendPreparedAttachment(prepared);
    } catch (error) {
      _hideMediaLoadingOverlay();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Partage impossible: $error')));
    }
  }

  void _syncScrollButton() {
    if (!_scroll.hasClients) return;
    final next =
        _scroll.position.maxScrollExtent - _scroll.position.pixels > 360;
    if (next != _showJumpToBottom && mounted) {
      setState(() => _showJumpToBottom = next);
    }
  }

  void _maybeLoadOlderMessages() {
    if (!_scroll.hasClients || _loadingOlderMessages || !_hasMoreMessages) {
      return;
    }
    final hasCachedOlder = _visibleArchiveStart > 0;
    if (!hasCachedOlder && (_nextMessagesBefore ?? '').isEmpty) return;
    if (_scroll.position.pixels <= 220) {
      unawaited(_loadOlderMessages());
    }
  }

  String _chatMessagesCacheKey(int otherId) => 'chat_messages_$otherId';

  String _chatMessagesMetaCacheKey(int otherId) =>
      'chat_messages_${otherId}_meta';

  String get _gifFavoritesCacheKey {
    final user =
        ApiService.currentUser?['id'] ??
        ApiService.currentAgent?['id'] ??
        ApiService.currentAgent?['userId'] ??
        'guest';
    return 'chat_gif_favorites_$user';
  }

  String get _stickerFavoritesCacheKey {
    final user =
        ApiService.currentUser?['id'] ??
        ApiService.currentAgent?['id'] ??
        ApiService.currentAgent?['userId'] ??
        'guest';
    return 'chat_sticker_favorites_$user';
  }

  Future<void> _loadFavoriteGifs() async {
    if (_loadingGifFavorites) return;
    _loadingGifFavorites = true;
    final items = await LocalCacheService.readList(_gifFavoritesCacheKey);
    if (mounted) setState(() => _favoriteGifs = items);
    _loadingGifFavorites = false;
  }

  Future<void> _saveFavoriteGifs() =>
      LocalCacheService.writeList(_gifFavoritesCacheKey, _favoriteGifs);

  Future<void> _loadFavoriteStickers() async {
    if (_loadingStickerFavorites) return;
    _loadingStickerFavorites = true;
    final items = await LocalCacheService.readList(_stickerFavoritesCacheKey);
    if (mounted) setState(() => _favoriteStickers = items);
    _loadingStickerFavorites = false;
  }

  Future<void> _saveFavoriteStickers() =>
      LocalCacheService.writeList(_stickerFavoritesCacheKey, _favoriteStickers);

  String _stableMessageKey(Map<String, dynamic> message) {
    final metadata = message['metadata'] as Map?;
    final clientId = (metadata?['clientId'] ?? message['clientId'] ?? '')
        .toString();
    if (clientId.isNotEmpty) return 'client:$clientId';
    final id = message['id']?.toString() ?? '';
    if (id.isNotEmpty) return 'id:$id';
    return 'local:${message['createdAt']}:${message['body']}';
  }

  List<Map<String, dynamic>> _mergeMessageCollections(
    Iterable<Map<String, dynamic>> current,
    Iterable<Map<String, dynamic>> updates,
  ) {
    final byKey = <String, Map<String, dynamic>>{};
    for (final raw in [...current, ...updates]) {
      final item = Map<String, dynamic>.from(raw);
      final key = _stableMessageKey(item);
      final previous = byKey[key];
      byKey[key] = previous == null
          ? item
          : _mergeServerMessage(previous, item);
    }
    final merged = byKey.values.toList()
      ..sort(
        (left, right) => _messageDate(
          left['createdAt'],
        ).compareTo(_messageDate(right['createdAt'])),
      );
    return merged;
  }

  void _refreshVisibleWindow({String? firstVisibleKey}) {
    if (_messageArchive.isEmpty) {
      _visibleArchiveStart = 0;
      _messages = [];
      return;
    }
    var start = -1;
    if (firstVisibleKey != null && firstVisibleKey.isNotEmpty) {
      start = _messageArchive.indexWhere(
        (item) => _stableMessageKey(item) == firstVisibleKey,
      );
    }
    if (start < 0) {
      start = math.max(0, _messageArchive.length - _cacheMessageWaveSize);
    }
    _visibleArchiveStart = start;
    _messages = _messageArchive.sublist(start);
    _hasMoreMessages = _visibleArchiveStart > 0 || _backendHasMoreMessages;
  }

  Future<void> _writeMessagesCache(
    int otherId,
    List<Map<String, dynamic>> messages, {
    bool? hasMore,
    String? nextBefore,
  }) async {
    _messageArchive = _mergeMessageCollections(_messageArchive, messages);
    await LocalCacheService.writeList(
      _chatMessagesCacheKey(otherId),
      _messageArchive,
    );
    if (hasMore != null) {
      await LocalCacheService.writeMap(_chatMessagesMetaCacheKey(otherId), {
        'hasMore': hasMore,
        'nextBefore': nextBefore ?? '',
        'savedAt': DateTime.now().toIso8601String(),
      });
    }
  }

  Future<void> _loadOlderMessages() async {
    if (_loadingOlderMessages || !_hasMoreMessages) return;
    final previousExtent = _scroll.hasClients
        ? _scroll.position.maxScrollExtent
        : 0.0;
    setState(() => _loadingOlderMessages = true);
    if (_visibleArchiveStart > 0) {
      final nextStart = math.max(
        0,
        _visibleArchiveStart - _cacheMessageWaveSize,
      );
      await Future<void>.delayed(const Duration(milliseconds: 70));
      if (!mounted) return;
      setState(() {
        _visibleArchiveStart = nextStart;
        _messages = _messageArchive.sublist(nextStart);
        _hasMoreMessages = nextStart > 0 || _backendHasMoreMessages;
        _loadingOlderMessages = false;
      });
      if (_conversationSearchActive) _refreshConversationSearch();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        final delta = _scroll.position.maxScrollExtent - previousExtent;
        if (delta > 0) _scroll.jumpTo(_scroll.position.pixels + delta);
      });
      return;
    }
    final before = _nextMessagesBefore;
    if (before == null || before.isEmpty) {
      setState(() {
        _hasMoreMessages = false;
        _loadingOlderMessages = false;
      });
      return;
    }
    try {
      final otherId = widget.other['userId'] as int;
      final page = await ApiService.fetchMessagesPage(
        otherId,
        limit: _networkMessagePageSize,
        before: before,
      );
      final older = _markIncomingReadLocally(
        List<Map<String, dynamic>>.from(page['results'] as List),
      );
      final merged = _mergeMessageCollections(_messageArchive, older);
      _messageArchive = merged;
      _backendHasMoreMessages = page['hasMore'] == true;
      _visibleArchiveStart = 0;
      await _writeMessagesCache(
        otherId,
        merged,
        hasMore: _backendHasMoreMessages,
        nextBefore: page['nextBefore']?.toString(),
      );
      if (!mounted) return;
      setState(() {
        _messages = merged;
        _hasMoreMessages = _backendHasMoreMessages;
        _nextMessagesBefore = page['nextBefore']?.toString();
        _loadingOlderMessages = false;
      });
      if (_conversationSearchActive) _refreshConversationSearch();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        final delta = _scroll.position.maxScrollExtent - previousExtent;
        if (delta > 0) _scroll.jumpTo(_scroll.position.pixels + delta);
      });
    } catch (_) {
      if (mounted) setState(() => _loadingOlderMessages = false);
    }
  }

  void _syncComposerState() {
    final next = _controller.text.trim().isNotEmpty;
    final match = RegExp(
      r'https?://[^\s<>]+',
      caseSensitive: false,
    ).firstMatch(_controller.text);
    final url = (match?.group(0) ?? '').replaceFirst(RegExp(r'[.,;:!?]+$'), '');
    final preview = url == _dismissedComposerPreviewUrl ? '' : url;
    if ((next != _hasText || preview != _composerPreviewUrl) && mounted) {
      setState(() {
        _hasText = next;
        _composerPreviewUrl = preview;
      });
    }
  }

  void _dismissComposerPreview() {
    if (_composerPreviewUrl.isEmpty) return;
    setState(() {
      _dismissedComposerPreviewUrl = _composerPreviewUrl;
      _composerPreviewUrl = '';
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _connectSocket();
      _load();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _closeChatSocket();
    }
  }

  List<Map<String, dynamic>> _markIncomingReadLocally(
    List<Map<String, dynamic>> items,
  ) {
    final otherId = widget.other['userId'];
    final now = DateTime.now().toIso8601String();
    return items.map((item) {
      if (item['fromMe'] == true ||
          item['isRead'] == true ||
          item['senderId'] != otherId) {
        return item;
      }
      final metadata = Map<String, dynamic>.from(
        (item['metadata'] as Map?) ?? {},
      );
      metadata['readAt'] ??= now;
      metadata['deliveredAt'] ??= item['deliveredAt'] ?? now;
      return {
        ...item,
        'isRead': true,
        'isDelivered': true,
        'deliveredAt': metadata['deliveredAt'],
        'metadata': metadata,
      };
    }).toList();
  }

  List<int> _incomingUnreadMessageIds(List<Map<String, dynamic>> items) {
    final otherId = widget.other['userId'];
    return items
        .where(
          (item) =>
              item['fromMe'] != true &&
              item['senderId'] == otherId &&
              item['isRead'] != true,
        )
        .map((item) => int.tryParse(item['id']?.toString() ?? '') ?? 0)
        .where((id) => id > 0 && !_visibleReadAckedIds.contains(id))
        .toSet()
        .toList();
  }

  void _ackVisibleMessagesRead(
    List<Map<String, dynamic>> items, {
    String source = 'chat_visible',
  }) {
    final ids = _incomingUnreadMessageIds(items);
    if (ids.isEmpty) return;
    _visibleReadAckedIds.addAll(ids);
    unawaited(() async {
      try {
        final updated = await ApiService.chatMessagesBatchAction(
          messageIds: ids,
          action: 'read',
        );
        if (!mounted || updated.isEmpty) return;
        setState(() {
          for (final message in updated) {
            final messageId = message['id'];
            final index = _messages.indexWhere(
              (item) => item['id'] == messageId,
            );
            if (index >= 0) {
              _messages[index] = _mergeServerMessage(
                Map<String, dynamic>.from(_messages[index]),
                message,
              );
            }
          }
        });
        await _writeMessagesCache(widget.other['userId'] as int, _messages);
      } catch (_) {
        _visibleReadAckedIds.removeAll(ids);
        await ApiService.ackChatDelivered(ids, source: source);
      }
    }());
  }

  Map<String, dynamic>? _initialConversationMessage() {
    final payload = widget.other['lastMessagePayload'];
    if (payload is! Map) return null;
    final message = Map<String, dynamic>.from(payload);
    final id = message['id']?.toString() ?? '';
    final otherId = widget.other['userId'];
    if (id.isEmpty) return null;
    if (message['senderId'] != otherId && message['recipientId'] != otherId) {
      return null;
    }
    return message;
  }

  List<Map<String, dynamic>> _mergeInitialConversationMessage(
    List<Map<String, dynamic>> cached,
  ) {
    final initial = _initialConversationMessage();
    if (initial == null) return cached;
    final initialId = initial['id']?.toString() ?? '';
    final hasInitial = cached.any(
      (item) => item['id']?.toString() == initialId,
    );
    final merged = hasInitial
        ? cached
              .map(
                (item) => item['id']?.toString() == initialId
                    ? _mergeServerMessage(
                        Map<String, dynamic>.from(item),
                        initial,
                      )
                    : item,
              )
              .toList()
        : [...cached, initial];
    merged.sort(
      (a, b) =>
          _messageDate(a['createdAt']).compareTo(_messageDate(b['createdAt'])),
    );
    return merged;
  }

  Future<void> _load() async {
    if (_loadingLatestMessages) return;
    _loadingLatestMessages = true;
    final otherId = widget.other['userId'] as int;
    final cacheKey = _chatMessagesCacheKey(otherId);
    final cached = _mergeInitialConversationMessage(
      await LocalCacheService.readList(cacheKey),
    );
    final cachedMeta = await LocalCacheService.readMap(
      _chatMessagesMetaCacheKey(otherId),
    );
    if (mounted && _messageArchive.isEmpty) {
      final archive = _markIncomingReadLocally(cached);
      _messageArchive = _mergeMessageCollections(const [], archive);
      _backendHasMoreMessages = cachedMeta?['hasMore'] == true;
      _nextMessagesBefore = cachedMeta?['nextBefore']?.toString();
      _refreshVisibleWindow();
      setState(() => _loading = false);
      _ackVisibleMessagesRead(_messages);
      if (_messages.isNotEmpty) _toBottom();
    }
    try {
      final archiveBeforeNetwork = List<Map<String, dynamic>>.from(
        _messageArchive,
      );
      final firstVisibleKey = _messages.isEmpty
          ? null
          : _stableMessageKey(_messages.first);
      final page = await ApiService.fetchMessagesPage(
        otherId,
        limit: _networkMessagePageSize,
      );
      final rawItems = List<Map<String, dynamic>>.from(page['results'] as List);
      _ackVisibleMessagesRead(rawItems);
      final items = _markIncomingReadLocally(rawItems);
      final withLocalMedia = _mergeLocalMedia(items, archiveBeforeNetwork);
      final merged = _mergeMessageCollections(
        archiveBeforeNetwork,
        withLocalMedia,
      );
      final cachedCursor = cachedMeta?['nextBefore']?.toString() ?? '';
      final preserveCachedCursor =
          archiveBeforeNetwork.isNotEmpty && cachedCursor.isNotEmpty;
      _messageArchive = merged;
      _backendHasMoreMessages = preserveCachedCursor
          ? (cachedMeta?['hasMore'] == true)
          : page['hasMore'] == true;
      _nextMessagesBefore = preserveCachedCursor
          ? cachedCursor
          : page['nextBefore']?.toString();
      _refreshVisibleWindow(firstVisibleKey: firstVisibleKey);
      await _writeMessagesCache(
        otherId,
        merged,
        hasMore: _backendHasMoreMessages,
        nextBefore: _nextMessagesBefore,
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
      if (firstVisibleKey == null) _toBottom();
      unawaited(_cacheRemoteMedia());
      unawaited(_resumeQueuedUploads());
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    } finally {
      _loadingLatestMessages = false;
    }
  }

  List<Map<String, dynamic>> _mergeLocalMedia(
    List<Map<String, dynamic>> fresh,
    List<Map<String, dynamic>> cached,
  ) {
    final cachedById = {
      for (final item in cached) item['id']?.toString(): item,
    };
    final merged = fresh.map((item) {
      final cachedItem = cachedById[item['id']?.toString()];
      if (cachedItem == null) return item;
      return {
        ...item,
        if (cachedItem['audioLocalPath'] != null)
          'audioLocalPath': cachedItem['audioLocalPath'],
        if (cachedItem['audioBase64'] != null)
          'audioBase64': cachedItem['audioBase64'],
        if (cachedItem['attachmentLocalPath'] != null)
          'attachmentLocalPath': cachedItem['attachmentLocalPath'],
        if (cachedItem['attachmentBase64'] != null)
          'attachmentBase64': cachedItem['attachmentBase64'],
      };
    }).toList();
    final knownClientIds = merged
        .map(
          (item) => ((item['metadata'] as Map?)?['clientId'] ?? '').toString(),
        )
        .where((value) => value.isNotEmpty)
        .toSet();
    for (final cachedItem in cached) {
      final pendingOrFailed =
          cachedItem['pending'] == true || cachedItem['failed'] == true;
      if (!pendingOrFailed || cachedItem['fromMe'] != true) continue;
      final cachedId = cachedItem['id']?.toString() ?? '';
      final clientId = ((cachedItem['metadata'] as Map?)?['clientId'] ?? '')
          .toString();
      final alreadyKnown =
          cachedId.isNotEmpty &&
          merged.any((item) => item['id']?.toString() == cachedId);
      if (!alreadyKnown &&
          (clientId.isEmpty || !knownClientIds.contains(clientId))) {
        merged.add(Map<String, dynamic>.from(cachedItem));
      }
    }
    merged.sort((left, right) {
      final leftAt =
          DateTime.tryParse(left['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final rightAt =
          DateTime.tryParse(right['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return leftAt.compareTo(rightAt);
    });
    return merged;
  }

  Future<void> _resumeQueuedUploads() async {
    if (_resumingQueuedUploads || !mounted) return;
    final queued = _messages
        .where(
          (message) =>
              message['fromMe'] == true &&
              (message['pending'] == true || message['failed'] == true) &&
              message['retryPayload'] is Map,
        )
        .map(Map<String, dynamic>.from)
        .toList();
    if (queued.isEmpty) return;
    _resumingQueuedUploads = true;
    try {
      for (final message in queued) {
        if (!mounted) return;
        await _retryFailedMessage(message);
      }
    } finally {
      _resumingQueuedUploads = false;
    }
  }

  Future<void> _cacheRemoteMedia() async {
    var changed = false;
    final next = _messages
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    for (final message in next.reversed.take(40)) {
      final id = message['id']?.toString();
      if (id == null || id.startsWith('-')) continue;
      final audioUrl = _absoluteMediaUrl(message['audioUrl']?.toString());
      if (audioUrl.isNotEmpty &&
          message['audioLocalPath'] == null &&
          message['audioBase64'] == null) {
        final path = await _downloadMediaToCache(audioUrl, 'audio-$id');
        if (path != null) {
          message['audioLocalPath'] = path;
          changed = true;
        }
      }
      final attachmentUrl = _absoluteMediaUrl(
        message['attachmentUrl']?.toString(),
      );
      final size = (message['attachmentSize'] as num?)?.toInt() ?? 0;
      if (attachmentUrl.isNotEmpty &&
          message['attachmentLocalPath'] == null &&
          message['attachmentBase64'] == null &&
          size <= 25 * 1024 * 1024) {
        final path = await _downloadMediaToCache(
          attachmentUrl,
          'file-$id-${message['attachmentName'] ?? 'attachment'}',
        );
        if (path != null) {
          message['attachmentLocalPath'] = path;
          changed = true;
        }
      }
    }
    if (!changed) return;
    if (mounted) setState(() => _messages = next);
    await _writeMessagesCache(widget.other['userId'] as int, next);
  }

  String _absoluteMediaUrl(String? value) {
    final raw = value ?? '';
    if (raw.isEmpty) return '';
    if (raw.startsWith('http')) return raw;
    return '${ApiService.baseUrl.replaceFirst('/api', '')}$raw';
  }

  Future<String?> _downloadMediaToCache(String url, String name) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          response.bodyBytes.isEmpty) {
        return null;
      }
      final dir = await getApplicationSupportDirectory();
      final mediaDir = Directory(
        '${dir.path}${Platform.pathSeparator}chat_media',
      );
      if (!await mediaDir.exists()) await mediaDir.create(recursive: true);
      final safeName = base64Url
          .encode(utf8.encode('$name-$url'))
          .replaceAll('=', '');
      final extension = Uri.parse(url).pathSegments.isNotEmpty
          ? Uri.parse(url).pathSegments.last.split('.').last
          : 'bin';
      final file = File(
        '${mediaDir.path}${Platform.pathSeparator}$safeName.$extension',
      );
      await file.writeAsBytes(response.bodyBytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  void _connectSocket() {
    _reconnectTimer?.cancel();
    _presenceTimer?.cancel();
    _socketSub?.cancel();
    _channel?.sink.close();
    try {
      final channel = WebSocketChannel.connect(ApiService.chatWebSocketUri());
      _channel = channel;
      setState(() => _socketOnline = true);
      _startPresenceHeartbeat();
      _socketSub = channel.stream.listen(
        _handleSocketEvent,
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _closeChatSocket() {
    _reconnectTimer?.cancel();
    _presenceTimer?.cancel();
    _socketSub?.cancel();
    _socketSub = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    if (mounted && _socketOnline) setState(() => _socketOnline = false);
  }

  void _scheduleReconnect() {
    if (!mounted) return;
    setState(() => _socketOnline = false);
    _presenceTimer?.cancel();
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), _connectSocket);
  }

  void _startPresenceHeartbeat() {
    _presenceTimer?.cancel();
    _sendPresencePing();
    _presenceTimer = Timer.periodic(
      const Duration(seconds: 25),
      (_) => _sendPresencePing(),
    );
  }

  void _sendPresencePing() {
    try {
      _channel?.sink.add(jsonEncode({'action': 'presence_ping'}));
    } catch (_) {}
  }

  bool _sameOutgoingPending(
    Map<String, dynamic> pending,
    Map<String, dynamic> message,
  ) {
    if (pending['pending'] != true || pending['fromMe'] != true) return false;
    final pendingClientId = _clientId(pending);
    final messageClientId = _clientId(message);
    if (pendingClientId.isNotEmpty && messageClientId.isNotEmpty) {
      return pendingClientId == messageClientId;
    }
    final pendingAlbum = _albumId(pending);
    final messageAlbum = _albumId(message);
    if (pendingAlbum.isNotEmpty && messageAlbum.isNotEmpty) {
      return pendingAlbum == messageAlbum &&
          _albumIndex(pending) == _albumIndex(message);
    }
    final sameBody =
        (pending['body'] ?? '').toString() ==
        (message['body'] ?? '').toString();
    final sameType =
        (pending['type'] ?? 'text').toString() ==
        (message['type'] ?? 'text').toString();
    if ((pending['type'] ?? message['type']) == 'file') {
      final pendingName =
          pending['attachmentName']?.toString() ??
          (pending['metadata'] as Map?)?['fileName']?.toString() ??
          '';
      final messageName =
          message['attachmentName']?.toString() ??
          (message['metadata'] as Map?)?['fileName']?.toString() ??
          '';
      return sameBody && sameType && pendingName == messageName;
    }
    return sameBody && sameType;
  }

  Map<String, dynamic> _mergeServerMessage(
    Map<String, dynamic> existing,
    Map<String, dynamic> incoming,
  ) {
    final existingMetadata = Map<String, dynamic>.from(
      existing['metadata'] is Map ? existing['metadata'] as Map : const {},
    );
    final incomingMetadata = Map<String, dynamic>.from(
      incoming['metadata'] is Map ? incoming['metadata'] as Map : const {},
    );
    final mergedMetadata = {...existingMetadata, ...incomingMetadata};
    final existingPayload = existingMetadata['payload'];
    final incomingPayload = incomingMetadata['payload'];
    if (existingPayload is Map && incomingPayload is Map) {
      mergedMetadata['payload'] = {
        ...Map<String, dynamic>.from(existingPayload),
        ...Map<String, dynamic>.from(incomingPayload),
      };
    } else if (existingPayload is Map &&
        (incomingPayload == null ||
            (incomingPayload is Map && incomingPayload.isEmpty))) {
      mergedMetadata['payload'] = existingPayload;
    }
    final existingDeliveredAt = () {
      final direct = existing['deliveredAt']?.toString() ?? '';
      if (direct.isNotEmpty) return direct;
      return existingMetadata['deliveredAt']?.toString() ?? '';
    }();
    final incomingDeliveredAt = () {
      final direct = incoming['deliveredAt']?.toString() ?? '';
      if (direct.isNotEmpty) return direct;
      return incomingMetadata['deliveredAt']?.toString() ?? '';
    }();
    if (incomingDeliveredAt.isEmpty && existingDeliveredAt.isNotEmpty) {
      mergedMetadata['deliveredAt'] = existingDeliveredAt;
    }
    final existingReadAt = existingMetadata['readAt']?.toString();
    final incomingReadAt = incomingMetadata['readAt']?.toString();
    if ((incomingReadAt == null || incomingReadAt.isEmpty) &&
        (existingReadAt ?? '').isNotEmpty) {
      mergedMetadata['readAt'] = existingReadAt;
    }
    final wasDelivered =
        existing['isDelivered'] == true || existingDeliveredAt.isNotEmpty;
    final wasRead =
        existing['isRead'] == true || (existingReadAt ?? '').isNotEmpty;
    final nextDelivered =
        incoming['isDelivered'] == true ||
        incomingDeliveredAt.isNotEmpty ||
        wasDelivered;
    final nextRead =
        incoming['isRead'] == true ||
        (incomingReadAt ?? '').isNotEmpty ||
        wasRead;
    return {
      ...existing,
      ...incoming,
      'isDelivered': nextDelivered,
      if ((mergedMetadata['deliveredAt'] ?? '').toString().isNotEmpty)
        'deliveredAt': mergedMetadata['deliveredAt'],
      'isRead': nextRead,
      if (mergedMetadata.isNotEmpty) 'metadata': mergedMetadata,
    };
  }

  void _handleSocketEvent(dynamic event) {
    final payload = jsonDecode(event.toString()) as Map<String, dynamic>;
    if (payload['event'] == 'conversation_cleared' &&
        payload['otherUserId'] == widget.other['userId']) {
      if (mounted) {
        setState(() {
          _messages.clear();
          _messageArchive.clear();
          _visibleArchiveStart = 0;
          _hasMoreMessages = false;
          _backendHasMoreMessages = false;
          _nextMessagesBefore = null;
        });
        LocalCacheService.writeList(
          _chatMessagesCacheKey(widget.other['userId'] as int),
          const <Map<String, dynamic>>[],
        );
      }
      return;
    }
    final message = payload['message'] as Map<String, dynamic>?;
    if (message == null) return;
    final otherId = widget.other['userId'];
    if (message['senderId'] != otherId && message['recipientId'] != otherId) {
      return;
    }
    final reason = (payload['reason'] ?? 'message').toString();
    final isFreshMessage = reason == 'message' && payload['silent'] != true;
    final id = message['id'];
    final fromMe = message['senderId'] != otherId;
    final shouldStickToBottom =
        isFreshMessage && (fromMe || _isNearConversationBottom());
    if (mounted) {
      setState(() {
        final existingIndex = _messages.indexWhere((item) => item['id'] == id);
        if (existingIndex >= 0) {
          _messages[existingIndex] = _mergeServerMessage(
            Map<String, dynamic>.from(_messages[existingIndex]),
            {...message, 'fromMe': fromMe, 'pending': false},
          );
          return;
        }
        if (fromMe) {
          final pendingIndex = _messages.indexWhere(
            (item) => _sameOutgoingPending(item, message),
          );
          if (pendingIndex >= 0) {
            _messages[pendingIndex] = _mergeServerMessage(
              Map<String, dynamic>.from(_messages[pendingIndex]),
              {...message, 'fromMe': true, 'pending': false},
            );
            return;
          }
        }
        _messages.add({...message, 'fromMe': fromMe});
      });
      unawaited(_writeMessagesCache(otherId as int, _messages));
      if (_conversationSearchActive) _refreshConversationSearch();
      if (!fromMe) _markIncomingSocketMessageRead(id);
    }
    if (!_conversationSearchActive && shouldStickToBottom) {
      _toBottom();
    } else if (isFreshMessage && !fromMe && mounted) {
      setState(() => _showJumpToBottom = true);
    }
  }

  void _markIncomingSocketMessageRead(dynamic rawId) {
    final messageId = int.tryParse(rawId?.toString() ?? '');
    if (messageId == null || messageId <= 0) return;
    unawaited(() async {
      try {
        final updated = await ApiService.chatMessageAction(
          messageId: messageId,
          action: 'read',
        );
        if (!mounted) return;
        setState(() {
          final index = _messages.indexWhere((item) => item['id'] == messageId);
          if (index >= 0) {
            _messages[index] = _mergeServerMessage(
              Map<String, dynamic>.from(_messages[index]),
              updated,
            );
          }
        });
        await _writeMessagesCache(widget.other['userId'] as int, _messages);
      } catch (_) {
        await ApiService.ackChatDelivered([messageId], source: 'chat_visible');
      }
    }());
  }

  Future<Map<String, String>?> _tryDirectChatUpload({
    required String fileBase64,
    required String fileName,
    required String mimeType,
    required int? attachmentSize,
  }) async {
    try {
      final encoded = fileBase64.contains(',')
          ? fileBase64.split(',').last
          : fileBase64;
      final bytes = base64Decode(encoded);
      if (bytes.isEmpty) return null;
      final intent = await ApiService.createChatUploadIntent(
        userId: widget.other['userId'] as int,
        fileName: fileName,
        mimeType: mimeType,
        size: attachmentSize ?? bytes.length,
      );
      final uploadUrl = intent['uploadUrl']?.toString() ?? '';
      if (uploadUrl.isEmpty) return null;
      await ApiService.uploadBytesToSignedUrl(
        uploadUrl: uploadUrl,
        bytes: bytes,
        mimeType: mimeType,
        headers: Map<String, dynamic>.from(
          (intent['headers'] as Map?) ?? const {},
        ),
      );
      final attachmentUrl = intent['attachmentUrl']?.toString() ?? '';
      final objectKey = intent['objectKey']?.toString() ?? '';
      final uploadToken = intent['uploadToken']?.toString() ?? '';
      if (attachmentUrl.isEmpty && objectKey.isEmpty) return null;
      return {
        if (attachmentUrl.isNotEmpty) 'attachmentUrl': attachmentUrl,
        if (objectKey.isNotEmpty) 'attachmentObjectKey': objectKey,
        if (uploadToken.isNotEmpty) 'uploadToken': uploadToken,
      };
    } catch (_) {
      return null;
    }
  }

  Future<void> _send({
    String? body,
    String type = 'text',
    Map<String, dynamic>? metadata,
    String? audioBase64,
    int? audioDurationSeconds,
    String? fileBase64,
    String? fileName,
    String? attachmentType,
    int? attachmentSize,
    String? attachmentLocalPath,
    String? toolAction,
  }) async {
    final text = (body ?? _controller.text).trim();
    if (text.isEmpty) return;
    unawaited(
      type == 'file' || type == 'voice'
          ? TranvikoInteractionFeedback.mediaSent()
          : TranvikoInteractionFeedback.messageSent(),
    );
    final enrichedMetadata = Map<String, dynamic>.from(metadata ?? const {});
    enrichedMetadata['clientId'] ??=
        'mobile-${DateTime.now().microsecondsSinceEpoch}-${math.Random().nextInt(1 << 32)}';
    final replyTo = _replyTo;
    if (replyTo != null) enrichedMetadata['replyTo'] = replyTo;
    _controller.clear();
    if (_hasText && mounted) setState(() => _hasText = false);
    final pendingId = -DateTime.now().microsecondsSinceEpoch;
    setState(() {
      _replyTo = null;
      _messages.add({
        'id': pendingId,
        'body': text,
        'fromMe': true,
        'senderName': 'Moi',
        'createdAt': DateTime.now().toIso8601String(),
        'type': type,
        'metadata': enrichedMetadata,
        'isImportant': false,
        'isDeleted': false,
        'pending': true,
        'failed': false,
        if (audioBase64 != null) 'audioBase64': audioBase64,
        if (attachmentLocalPath != null)
          'attachmentLocalPath': attachmentLocalPath,
        if (fileBase64 != null && attachmentLocalPath == null)
          'attachmentBase64': fileBase64,
        if (fileName != null) 'attachmentName': fileName,
        if (attachmentType != null) 'attachmentType': attachmentType,
        if (attachmentSize != null) 'attachmentSize': attachmentSize,
        'retryPayload': {
          'body': text,
          'type': type,
          'metadata': enrichedMetadata,
          'audioBase64': audioBase64,
          'audioDurationSeconds': audioDurationSeconds,
          'fileBase64': fileBase64,
          'fileName': fileName,
          'attachmentType': attachmentType,
          'attachmentSize': attachmentSize,
          'attachmentLocalPath': attachmentLocalPath,
          'toolAction': toolAction,
        },
      });
    });
    await _writeMessagesCache(widget.other['userId'] as int, _messages);
    _toBottom();
    try {
      var uploadFileBase64 = fileBase64;
      String? uploadedAttachmentUrl;
      String? uploadedAttachmentObjectKey;
      String? uploadToken;
      if (fileBase64 != null && type == 'file') {
        final directUpload = await _tryDirectChatUpload(
          fileBase64: fileBase64,
          fileName: fileName ?? 'media',
          mimeType: attachmentType ?? 'application/octet-stream',
          attachmentSize: attachmentSize,
        );
        if (directUpload != null) {
          uploadedAttachmentUrl = directUpload['attachmentUrl'];
          uploadedAttachmentObjectKey = directUpload['attachmentObjectKey'];
          uploadToken = directUpload['uploadToken'];
          uploadFileBase64 = null;
          enrichedMetadata['directUpload'] = true;
          if (uploadedAttachmentObjectKey != null) {
            enrichedMetadata['attachmentObjectKey'] =
                uploadedAttachmentObjectKey;
          }
        }
      }
      final saved = await ApiService.sendChatMessage(
        userId: widget.other['userId'] as int,
        body: text,
        type: type,
        metadata: enrichedMetadata.isEmpty ? null : enrichedMetadata,
        audioBase64: audioBase64,
        audioDurationSeconds: audioDurationSeconds,
        fileBase64: uploadFileBase64,
        fileName: fileName,
        attachmentType: attachmentType,
        attachmentSize: attachmentSize,
        attachmentUrl: uploadedAttachmentUrl,
        attachmentObjectKey: uploadedAttachmentObjectKey,
        uploadToken: uploadToken,
        toolAction: toolAction,
      );
      if (!mounted) return;
      setState(() {
        final savedId = saved['id'];
        final pendingIndex = _messages.indexWhere(
          (item) => item['id'] == pendingId,
        );
        _messages.removeWhere(
          (item) => item['id'] == savedId && item['id'] != pendingId,
        );
        if (pendingIndex >= 0 && pendingIndex < _messages.length) {
          _messages[pendingIndex] = _mergeServerMessage(
            Map<String, dynamic>.from(_messages[pendingIndex]),
            {
              ...saved,
              if (audioBase64 != null) 'audioBase64': audioBase64,
              if (attachmentLocalPath != null)
                'attachmentLocalPath': attachmentLocalPath,
              if (uploadFileBase64 != null && attachmentLocalPath == null)
                'attachmentBase64': uploadFileBase64,
              'fromMe': true,
              'pending': false,
            },
          );
        } else if (!_messages.any((item) => item['id'] == savedId)) {
          _messages.add({
            ...saved,
            if (audioBase64 != null) 'audioBase64': audioBase64,
            if (attachmentLocalPath != null)
              'attachmentLocalPath': attachmentLocalPath,
            if (uploadFileBase64 != null && attachmentLocalPath == null)
              'attachmentBase64': uploadFileBase64,
            'fromMe': true,
            'pending': false,
          });
        }
      });
      await _writeMessagesCache(widget.other['userId'] as int, _messages);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        final index = _messages.indexWhere((item) => item['id'] == pendingId);
        if (index >= 0) {
          _messages[index]['failed'] = true;
          _messages[index]['pending'] = false;
          _messages[index]['errorText'] = 'Non envoye. Verifiez la connexion.';
        }
      });
      await _writeMessagesCache(widget.other['userId'] as int, _messages);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  Future<void> _retryFailedMessage(Map<String, dynamic> message) async {
    final id = message['id'];
    final retryPayload = Map<String, dynamic>.from(
      (message['retryPayload'] as Map?) ?? const {},
    );
    final text = (retryPayload['body'] ?? message['body'] ?? '').toString();
    if (text.trim().isEmpty) return;
    setState(() {
      final index = _messages.indexWhere((item) => item['id'] == id);
      if (index >= 0) {
        _messages[index]['failed'] = false;
        _messages[index]['pending'] = true;
        _messages[index].remove('errorText');
      }
    });
    try {
      final retryFileBase64 = retryPayload['fileBase64']?.toString();
      final retryType = (retryPayload['type'] ?? message['type'] ?? 'text')
          .toString();
      var uploadFileBase64 = retryFileBase64;
      String? uploadedAttachmentUrl;
      String? uploadedAttachmentObjectKey;
      String? uploadToken;
      final retryMetadata = Map<String, dynamic>.from(
        (retryPayload['metadata'] as Map?) ?? const {},
      );
      if (retryFileBase64 != null && retryType == 'file') {
        final directUpload = await _tryDirectChatUpload(
          fileBase64: retryFileBase64,
          fileName: retryPayload['fileName']?.toString() ?? 'media',
          mimeType:
              retryPayload['attachmentType']?.toString() ??
              'application/octet-stream',
          attachmentSize: retryPayload['attachmentSize'] as int?,
        );
        if (directUpload != null) {
          uploadFileBase64 = null;
          uploadedAttachmentUrl = directUpload['attachmentUrl'];
          uploadedAttachmentObjectKey = directUpload['attachmentObjectKey'];
          uploadToken = directUpload['uploadToken'];
          retryMetadata['directUpload'] = true;
          if (uploadedAttachmentObjectKey != null) {
            retryMetadata['attachmentObjectKey'] = uploadedAttachmentObjectKey;
          }
        }
      }
      final saved = await ApiService.sendChatMessage(
        userId: widget.other['userId'] as int,
        body: text,
        type: retryType,
        metadata: retryMetadata,
        audioBase64: retryPayload['audioBase64']?.toString(),
        audioDurationSeconds: retryPayload['audioDurationSeconds'] as int?,
        fileBase64: uploadFileBase64,
        fileName: retryPayload['fileName']?.toString(),
        attachmentType: retryPayload['attachmentType']?.toString(),
        attachmentSize: retryPayload['attachmentSize'] as int?,
        attachmentUrl: uploadedAttachmentUrl,
        attachmentObjectKey: uploadedAttachmentObjectKey,
        uploadToken: uploadToken,
        toolAction: retryPayload['toolAction']?.toString(),
      );
      if (!mounted) return;
      setState(() {
        final index = _messages.indexWhere((item) => item['id'] == id);
        if (index >= 0) {
          _messages[index] = {
            ...saved,
            if (retryPayload['audioBase64'] != null)
              'audioBase64': retryPayload['audioBase64'],
            if (retryPayload['attachmentLocalPath'] != null)
              'attachmentLocalPath': retryPayload['attachmentLocalPath'],
            if (uploadFileBase64 != null &&
                retryPayload['attachmentLocalPath'] == null)
              'attachmentBase64': uploadFileBase64,
            'fromMe': true,
            'pending': false,
          };
        }
      });
      await _writeMessagesCache(widget.other['userId'] as int, _messages);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        final index = _messages.indexWhere((item) => item['id'] == id);
        if (index >= 0) {
          _messages[index]['failed'] = true;
          _messages[index]['pending'] = false;
          _messages[index]['errorText'] = 'Toujours non envoye.';
        }
      });
      await _writeMessagesCache(widget.other['userId'] as int, _messages);
    }
  }

  Future<void> _startVoice() async {
    if (!await _recorder.hasPermission()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Autorisation micro refusee.')),
      );
      return;
    }
    await TranvikoInteractionFeedback.voiceStart();
    await Future<void>.delayed(const Duration(milliseconds: 90));
    final dir = await getTemporaryDirectory();
    _voicePath =
        '${dir.path}/chat-${DateTime.now().microsecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: _voicePath!,
    );
    _amplitudeSub?.cancel();
    _voiceWaveformSamples.clear();
    _amplitudeSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 90))
        .listen((amplitude) {
          final db = amplitude.current.isFinite ? amplitude.current : -60.0;
          final level = ((db + 60) / 60).clamp(0.05, 1.0).toDouble();
          _captureVoiceSample(level);
          if (mounted && !_voicePaused) setState(() => _voiceLevel = level);
        });
    setState(() {
      _recording = true;
      _voicePaused = false;
      _voiceSeconds = 0;
      _voiceLevel = .08;
    });
    _voiceTimer?.cancel();
    _voiceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _voiceSeconds++);
    });
  }

  void _captureVoiceSample(double level) {
    _voiceWaveformSamples.add(level.clamp(.05, 1.0).toDouble());
    if (_voiceWaveformSamples.length <= 64) return;
    final source = List<double>.from(_voiceWaveformSamples);
    _voiceWaveformSamples
      ..clear()
      ..addAll(_compressWaveform(source, target: 64));
  }

  List<double> _compressWaveform(List<double> source, {int target = 42}) {
    if (source.isEmpty) return const [];
    if (source.length <= target) return List<double>.from(source);
    final result = <double>[];
    for (var i = 0; i < target; i++) {
      final start = (i * source.length / target).floor();
      final end = ((i + 1) * source.length / target).ceil();
      final slice = source.sublist(start, end.clamp(start + 1, source.length));
      result.add(slice.reduce((a, b) => a > b ? a : b));
    }
    return result;
  }

  Future<void> _toggleVoicePause() async {
    if (!_recording) return;
    if (_voicePaused) {
      await _recorder.resume();
      unawaited(TranvikoInteractionFeedback.voiceResume());
      if (!mounted) return;
      setState(() {
        _voicePaused = false;
        _voiceLevel = .08;
      });
      _voiceTimer?.cancel();
      _voiceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _voiceSeconds++);
      });
    } else {
      await _recorder.pause();
      unawaited(TranvikoInteractionFeedback.voicePause());
      _voiceTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _voicePaused = true;
        _voiceLevel = .05;
      });
    }
  }

  Future<void> _stopVoice({bool send = true}) async {
    _voiceTimer?.cancel();
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;
    final seconds = _voiceSeconds.clamp(1, 600).toInt();
    final waveform = _compressWaveform(_voiceWaveformSamples, target: 42);
    final path = await _recorder.stop();
    setState(() {
      _recording = false;
      _voicePaused = false;
      _voiceSeconds = 0;
      _voiceLevel = 0;
    });
    _voiceWaveformSamples.clear();
    if (!send) unawaited(TranvikoInteractionFeedback.voiceCancel());
    if (send && path != null) {
      final bytes = await File(path).readAsBytes();
      _send(
        body: 'Message vocal ${_duration(seconds)}',
        type: 'voice',
        metadata: {
          'durationSeconds': seconds,
          'mimeType': 'audio/mp4',
          if (waveform.isNotEmpty) 'waveform': waveform,
        },
        audioBase64: base64Encode(bytes),
        audioDurationSeconds: seconds,
      );
    }
  }

  Future<void> _sendPickedAttachment({
    required bool photo,
    bool video = false,
  }) async {
    Navigator.pop(context);
    await _sendSystemPickedAttachment(photo: photo, video: video);
  }

  Future<void> _sendSystemPickedAttachment({
    required bool photo,
    bool video = false,
  }) async {
    if (photo) {
      final pickedItems = await ImagePicker().pickMultiImage(imageQuality: 72);
      if (pickedItems.isEmpty) return;
      final picked = <_PickedAttachment>[];
      for (final item in pickedItems) {
        final bytes = await File(item.path).readAsBytes();
        picked.add(
          _PickedAttachment(
            bytes: bytes,
            name: item.name.isNotEmpty ? item.name : 'photo.jpg',
            mime: item.mimeType ?? 'image/jpeg',
            localPath: item.path,
          ),
        );
      }
      if (!mounted) return;
      final prepared = picked.length == 1
          ? await Navigator.push<List<_PreparedAttachment>>(
              context,
              MaterialPageRoute(
                fullscreenDialog: true,
                builder: (_) => _MediaBatchPreparationScreen(items: picked),
              ),
            )
          : await Navigator.push<List<_PreparedAttachment>>(
              context,
              MaterialPageRoute(
                fullscreenDialog: true,
                builder: (_) => _MediaBatchPreparationScreen(items: picked),
              ),
            );
      if (!mounted || prepared == null || prepared.isEmpty) return;
      final albumId = prepared.length > 1
          ? 'album-${DateTime.now().microsecondsSinceEpoch}'
          : null;
      for (var i = 0; i < prepared.length; i++) {
        await _sendPreparedAttachment(
          prepared[i],
          albumId: albumId,
          albumIndex: i,
          albumTotal: prepared.length,
        );
      }
      return;
    }
    String? name;
    String? mime;
    String? localPath;
    Uint8List? bytes;
    if (video) {
      final picked = await ImagePicker().pickVideo(source: ImageSource.gallery);
      if (picked == null) return;
      bytes = await File(picked.path).readAsBytes();
      name = picked.name.isNotEmpty ? picked.name : 'video.mp4';
      mime = picked.mimeType ?? _mimeFromFileName(name);
      localPath = picked.path;
    } else {
      final result = await FilePicker.platform.pickFiles(withData: true);
      final file = result?.files.single;
      if (file == null) return;
      bytes =
          file.bytes ??
          (file.path == null ? null : await File(file.path!).readAsBytes());
      if (bytes == null) return;
      name = file.name;
      mime = _mimeFromFileName(name);
      localPath = file.path;
    }
    if (!mounted) return;
    final prepared = await Navigator.push<_PreparedAttachment>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _MediaPreparationScreen(
          bytes: bytes!,
          name: name!,
          mime: mime!,
          localPath: localPath,
        ),
      ),
    );
    if (!mounted || prepared == null) return;
    await _sendPreparedAttachment(prepared);
  }

  Future<void> _sendGalleryAttachment({
    required bool photo,
    bool video = false,
  }) async {
    Navigator.pop(context);
    if (!Platform.isAndroid || (!photo && !video)) {
      await _sendSystemPickedAttachment(photo: photo, video: video);
      return;
    }
    _showMediaLoadingOverlay(
      photo ? 'Chargement de vos photos...' : 'Chargement de vos videos...',
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
    try {
      final hasAccess =
          await _galleryChannel.invokeMethod<bool>('hasMediaAccess') ?? false;
      final granted =
          hasAccess ||
          (await _galleryChannel.invokeMethod<bool>('requestMediaAccess') ??
              false);
      if (!granted) {
        _hideMediaLoadingOverlay();
        if (mounted) {
          AppToast.show(
            context,
            'Autorisez les medias pour afficher la galerie Tranviko.',
            tone: AppToastTone.warning,
          );
        }
        return;
      }
      final raw = await _galleryChannel.invokeMethod<List<dynamic>>(
        'listMedia',
        {'kind': photo ? 'image' : 'video', 'limit': 120},
      );
      final items = (raw ?? const [])
          .whereType<Map>()
          .map((item) => _GalleryMediaItem.fromNative(item))
          .where((item) => item.uri.isNotEmpty)
          .toList();
      if (items.isEmpty) {
        _hideMediaLoadingOverlay();
        if (mounted) {
          AppToast.show(
            context,
            'Aucun media disponible dans cette categorie.',
            tone: AppToastTone.info,
          );
        }
        return;
      }
      if (!mounted) {
        _hideMediaLoadingOverlay();
        return;
      }
      _hideMediaLoadingOverlay();
      final selected = await Navigator.push<List<_GalleryMediaItem>>(
        context,
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => _CustomMediaGalleryScreen(
            items: items,
            multiSelect: photo,
            title: photo ? 'Selectionner des photos' : 'Selectionner une video',
          ),
        ),
      );
      if (!mounted || selected == null || selected.isEmpty) return;
      _showMediaLoadingOverlay(
        selected.length > 1
            ? 'Preparation de ${selected.length} medias...'
            : 'Preparation du media...',
      );
      final picked = <_PickedAttachment>[];
      for (final item in selected) {
        final bytes = await _galleryChannel.invokeMethod<Uint8List>(
          'readMedia',
          {'uri': item.uri},
        );
        if (bytes == null || bytes.isEmpty) continue;
        picked.add(
          _PickedAttachment(
            bytes: bytes,
            name: item.name.isNotEmpty
                ? item.name
                : (item.isVideo ? 'video.mp4' : 'photo.jpg'),
            mime: item.mime.isNotEmpty
                ? item.mime
                : (item.isVideo ? 'video/mp4' : 'image/jpeg'),
            localPath: item.uri,
          ),
        );
      }
      _hideMediaLoadingOverlay();
      if (picked.isEmpty) return;
      if (photo) {
        final prepared = await Navigator.push<List<_PreparedAttachment>>(
          context,
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => _MediaBatchPreparationScreen(items: picked),
          ),
        );
        if (!mounted || prepared == null || prepared.isEmpty) return;
        final albumId = prepared.length > 1
            ? 'album-${DateTime.now().microsecondsSinceEpoch}'
            : null;
        for (var i = 0; i < prepared.length; i++) {
          await _sendPreparedAttachment(
            prepared[i],
            albumId: albumId,
            albumIndex: i,
            albumTotal: prepared.length,
          );
        }
        return;
      }
      final item = picked.first;
      final prepared = await Navigator.push<_PreparedAttachment>(
        context,
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => _MediaPreparationScreen(
            bytes: item.bytes,
            name: item.name,
            mime: item.mime,
            localPath: item.localPath,
          ),
        ),
      );
      if (!mounted || prepared == null) return;
      await _sendPreparedAttachment(prepared);
    } catch (error) {
      _hideMediaLoadingOverlay();
      if (mounted) {
        AppToast.show(
          context,
          AppToast.friendlyError(
            error,
            fallback: 'Impossible d ouvrir la galerie Tranviko.',
          ),
          tone: AppToastTone.error,
        );
      }
    }
  }

  void _showMediaLoadingOverlay(String label) {
    if (!mounted || _mediaLoadingVisible) return;
    _mediaLoadingVisible = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 260,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _surfacePanel(context),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: scheme.outline.withValues(alpha: .14),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 30,
                    offset: Offset(0, 16),
                  ),
                ],
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: _primaryText(context),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ).whenComplete(() => _mediaLoadingVisible = false);
  }

  void _hideMediaLoadingOverlay() {
    if (!_mediaLoadingVisible || !mounted) return;
    _mediaLoadingVisible = false;
    Navigator.of(context, rootNavigator: true).pop();
  }

  Future<void> _sendPreparedAttachment(
    _PreparedAttachment prepared, {
    String? albumId,
    int? albumIndex,
    int? albumTotal,
  }) async {
    final caption = prepared.caption.trim();
    await _send(
      body: caption.isNotEmpty
          ? caption
          : prepared.mime.startsWith('image/')
          ? 'Photo'
          : prepared.name,
      type: 'file',
      metadata: {
        'mimeType': prepared.mime,
        'fileName': prepared.name,
        ...prepared.metadata,
        if (caption.isNotEmpty) 'caption': caption,
        if (albumId != null) ...{
          'albumId': albumId,
          'albumIndex': albumIndex ?? 0,
          'albumTotal': albumTotal ?? 1,
        },
      },
      fileBase64: base64Encode(prepared.bytes),
      fileName: prepared.name,
      attachmentType: prepared.mime,
      attachmentSize: prepared.bytes.length,
      attachmentLocalPath: prepared.mime.startsWith('image/')
          ? null
          : prepared.localPath,
    );
  }

  String _mimeFromFileName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.webm')) return 'video/webm';
    return 'application/octet-stream';
  }

  Future<void> _bulkMessageAction(String action, {int? targetUserId}) async {
    final ids = _expandedSelectedMessageIds.where((id) => id > 0).toList();
    if (ids.isEmpty) return;
    try {
      final results = await ApiService.chatMessagesBatchAction(
        messageIds: ids,
        action: action,
        targetUserId: targetUserId,
      );
      if (!mounted) return;
      setState(() {
        _selected.clear();
        if (action == 'delete_for_me') {
          _messages.removeWhere((item) => ids.contains(item['id']));
          _messageArchive.removeWhere((item) => ids.contains(item['id']));
        } else if (action != 'forward') {
          for (final updated in results) {
            final id = updated['id'];
            final index = _messages.indexWhere((item) => item['id'] == id);
            if (index >= 0) _messages[index] = updated;
          }
        }
      });
      await _writeMessagesCache(widget.other['userId'] as int, _messages);
      if (!mounted) return;
      if (action == 'forward') {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Message transfere.')));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Action impossible pour cette selection.'),
        ),
      );
    }
  }

  Future<void> _reactToSelection() async {
    final ids = _expandedSelectedMessageIds.where((id) => id > 0).toList();
    if (ids.isEmpty) return;
    final currentUserId =
        (ApiService.currentUser?['id'] ??
                ApiService.currentUser?['userId'] ??
                '')
            .toString();
    final hasMyReaction = _messages.any((message) {
      if (!ids.contains(message['id'])) return false;
      final metadata = message['metadata'] as Map?;
      final reactions = metadata?['reactions'] as Map?;
      return reactions?[currentUserId]?.toString().isNotEmpty == true;
    });
    final emoji = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
          decoration: BoxDecoration(
            color: _surfacePanel(context),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.outline.withValues(alpha: .16),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x260F172A),
                blurRadius: 28,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: .12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.add_reaction_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Choisir une reaction',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          ids.length == 1
                              ? 'Appliquee au message selectionne'
                              : 'Appliquee aux ${ids.length} messages selectionnes',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  for (final value in const [
                    '👍',
                    '❤️',
                    '😂',
                    '😮',
                    '😢',
                    '🙏',
                  ])
                    IconButton.filledTonal(
                      tooltip: value,
                      onPressed: () => Navigator.pop(context, value),
                      icon: Text(value, style: const TextStyle(fontSize: 21)),
                    ),
                  if (hasMyReaction)
                    OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context, 'remove'),
                      icon: const Icon(Icons.remove_circle_outline_rounded),
                      label: const Text('Retirer ma reaction'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (emoji == null) return;
    try {
      final updated = <Map<String, dynamic>>[];
      for (final id in ids) {
        updated.add(
          await ApiService.reactToChatMessage(
            messageId: id,
            emoji: emoji == 'remove' ? null : emoji,
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        for (final item in updated) {
          final index = _messages.indexWhere(
            (message) => message['id'] == item['id'],
          );
          if (index >= 0) _messages[index] = item;
        }
        _selected.clear();
      });
      await _writeMessagesCache(widget.other['userId'] as int, _messages);
    } catch (_) {
      if (mounted) {
        AppToast.show(
          context,
          'Reaction impossible pour le moment.',
          tone: AppToastTone.error,
        );
      }
    }
  }

  Future<void> _openMessageReactions(Map<String, dynamic> message) async {
    final messageId = message['id'] as int? ?? 0;
    if (messageId <= 0) return;
    final metadata = message['metadata'] as Map?;
    final reactions = Map<String, dynamic>.from(
      metadata?['reactions'] as Map? ?? const <String, dynamic>{},
    );
    final currentUserId =
        (ApiService.currentUser?['id'] ??
                ApiService.currentUser?['userId'] ??
                '')
            .toString();
    final myReaction =
        (metadata?['myReaction'] ?? reactions[currentUserId] ?? '').toString();
    final counts = <String, int>{};
    for (final value in reactions.values) {
      final emoji = value.toString();
      if (emoji.isNotEmpty) counts[emoji] = (counts[emoji] ?? 0) + 1;
    }
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
          decoration: BoxDecoration(
            color: _surfacePanel(context),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.outline.withValues(alpha: .16),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x260F172A),
                blurRadius: 28,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Reactions',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
              ),
              const SizedBox(height: 4),
              Text(
                'Une reaction par personne sur ce message.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              if (counts.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (final entry in counts.entries)
                      Chip(
                        avatar: Text(entry.key),
                        label: Text('${entry.value}'),
                        side: BorderSide.none,
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 15),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final value in const [
                    '👍',
                    '❤️',
                    '😂',
                    '😮',
                    '😢',
                    '🙏',
                  ])
                    IconButton.filledTonal(
                      tooltip: value,
                      onPressed: () => Navigator.pop(context, value),
                      icon: Text(value, style: const TextStyle(fontSize: 21)),
                    ),
                  if (myReaction.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context, 'remove'),
                      icon: const Icon(Icons.remove_circle_outline_rounded),
                      label: const Text('Retirer ma reaction'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null) return;
    try {
      final updated = await ApiService.reactToChatMessage(
        messageId: messageId,
        emoji: choice == 'remove' ? null : choice,
      );
      if (!mounted) return;
      setState(() {
        final index = _messages.indexWhere((item) => item['id'] == messageId);
        if (index >= 0) _messages[index] = updated;
      });
      await _writeMessagesCache(widget.other['userId'] as int, _messages);
    } catch (_) {
      if (mounted) {
        AppToast.show(
          context,
          'Reaction impossible pour le moment.',
          tone: AppToastTone.error,
        );
      }
    }
  }

  Future<void> _confirmDeleteSelection() async {
    if (_selected.isEmpty) return;
    final onlyMine = _selectionOnlyMine;
    final hasDeleted = _selectionHasDeleted;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _panel,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Supprimer les messages',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, 'delete_for_me'),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Supprimer pour moi'),
              ),
              if (onlyMine && !hasDeleted) ...[
                const SizedBox(height: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () =>
                      Navigator.pop(context, 'delete_for_everyone'),
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: const Text('Supprimer pour tous les deux'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (action != null) await _bulkMessageAction(action);
  }

  Future<void> _forwardSelection() async {
    final conversations = await ApiService.fetchConversations();
    if (!mounted) return;
    final targets = await showModalBottomSheet<Set<int>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ConversationRecipientPicker(
        title: 'Transferer vers',
        conversations: conversations
            .where((item) => item['userId'] != widget.other['userId'])
            .toList(),
      ),
    );
    if (!mounted || targets == null || targets.isEmpty) return;
    final ids = _expandedSelectedMessageIds.where((id) => id > 0).toList();
    if (ids.isEmpty) return;
    try {
      for (final targetId in targets) {
        await ApiService.chatMessagesBatchAction(
          messageIds: ids,
          action: 'forward',
          targetUserId: targetId,
        );
      }
      if (!mounted) return;
      setState(() => _selected.clear());
      AppToast.show(
        context,
        'Message transfere a ${targets.length} discussion(s).',
        tone: AppToastTone.success,
      );
    } catch (error) {
      if (!mounted) return;
      AppToast.show(
        context,
        AppToast.friendlyError(error, fallback: 'Transfert impossible.'),
        tone: AppToastTone.error,
      );
    }
  }

  String _reservationCode(Map<String, dynamic> item) =>
      (item['qrData'] ??
              item['code'] ??
              item['trackingCode'] ??
              item['id'] ??
              '')
          .toString();

  String _reservationRoute(Map<String, dynamic> item) {
    final route = (item['ligne'] ?? item['route'] ?? '').toString().trim();
    if (route.isNotEmpty) return route;
    final departure = (item['departure'] ?? '').toString();
    final destination = (item['destination'] ?? '').toString();
    if (departure.isEmpty && destination.isEmpty) return 'Trajet';
    return '$departure -> $destination';
  }

  String _reservationDateLabel(Map<String, dynamic> item) {
    final bus = item['bus'] is Map ? item['bus'] as Map : const {};
    final date = (item['date'] ?? item['travelDate'] ?? '').toString();
    final time = (item['time'] ?? bus['time'] ?? item['departureTime'] ?? '')
        .toString();
    return [date, time].where((value) => value.isNotEmpty).join(' a ');
  }

  List<int> _reservationSeats(Map<String, dynamic> item) {
    final raw = item['selectedSeats'] ?? item['seats'];
    if (raw is! Iterable) return const [];
    return raw
        .map((seat) => seat is int ? seat : int.tryParse(seat.toString()))
        .whereType<int>()
        .toList();
  }

  Map<String, dynamic> _reservationPayload(Map<String, dynamic> item) {
    final code = _reservationCode(item);
    return {
      'reservationId': item['id']?.toString(),
      'reservationCode': code,
      'trackingCode': code,
      'route': _reservationRoute(item),
      'travelDate': item['date'] ?? item['travelDate'],
      'departureTime':
          item['time'] ??
          ((item['bus'] is Map) ? (item['bus'] as Map)['time'] : null) ??
          item['departureTime'],
      'seats': _reservationSeats(item),
      'status': item['status']?.toString() ?? '',
      'paymentMethod': item['paymentMethod']?.toString() ?? '',
      'passenger': item['passenger'] ?? item['client'],
    };
  }

  Future<List<Map<String, dynamic>>> _loadTravelReservations() async {
    final cached = await LocalCacheService.readList('reservations_cache');
    try {
      final fresh = await ApiService.fetchReservations();
      if (fresh.isNotEmpty || cached.isEmpty) {
        await LocalCacheService.writeList('reservations_cache', fresh);
        return fresh;
      }
    } catch (_) {
      // The cache keeps these tools useful during short network drops.
    }
    return cached;
  }

  Future<Map<String, dynamic>?> _pickReservation({
    required String title,
    String subtitle = 'Choisissez le billet concerne.',
    bool activeOnly = false,
  }) async {
    final reservations = await _loadTravelReservations();
    if (!mounted) return null;
    final items = reservations.where((item) {
      final status = (item['status'] ?? '').toString().toLowerCase();
      final cancelled =
          item['isCancelled'] == true ||
          status.startsWith('annul') ||
          status.contains('cancel');
      if (!activeOnly) return !cancelled;
      final canOpen = item['canOpenTripChat'] != false;
      return !cancelled && canOpen;
    }).toList();
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucune reservation disponible.')),
      );
      return null;
    }
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ReservationPickerSheet(
        title: title,
        subtitle: subtitle,
        reservations: items,
        routeOf: _reservationRoute,
        codeOf: _reservationCode,
        dateOf: _reservationDateLabel,
      ),
    );
  }

  Future<void> _shareTicket() async {
    _hideComposerPanel();
    final reservation = await _pickReservation(
      title: 'Partager un billet',
      subtitle: 'Le billet sera envoye comme carte dans cette discussion.',
    );
    if (reservation == null) return;
    final payload = _reservationPayload(reservation);
    _sendTool(
      'Billet partage',
      '${payload['route']} - ${payload['reservationCode']}',
      Icons.confirmation_number_outlined,
      'share_ticket',
      closeSheet: false,
      payload: {
        ...payload,
        'travelTool': true,
        'kind': 'ticket',
        'canOpenTripChat': reservation['canOpenTripChat'] != false,
      },
    );
  }

  Future<void> _shareTripTracking() async {
    _hideComposerPanel();
    final reservation = await _pickReservation(
      title: 'Partager un suivi de trajet',
      subtitle:
          'Le code de suivi permettra de suivre le bus si le GPS est actif.',
      activeOnly: true,
    );
    if (reservation == null) return;
    final payload = _reservationPayload(reservation);
    Map<String, dynamic> tracking = {};
    try {
      tracking = await ApiService.trackPackage(
        payload['trackingCode'].toString(),
      );
    } catch (_) {
      tracking = {'trackingAvailable': false};
    }
    _sendTool(
      'Suivi de trajet',
      '${payload['route']} - code ${payload['trackingCode']}',
      Icons.near_me_outlined,
      'share_trip_tracking',
      closeSheet: false,
      payload: {
        ...payload,
        'travelTool': true,
        'kind': 'tracking',
        'tracking': tracking,
        'trackingAvailable':
            tracking['trackingAvailable'] == true ||
            tracking['journey'] != null,
      },
    );
  }

  Future<bool> _ensureLocationPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Activez la localisation du telephone.')),
      );
      return false;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    final allowed =
        permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
    if (!allowed && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permission localisation refusee.')),
      );
    }
    return allowed;
  }

  Future<void> _sendTripPositionUpdate(
    Map<String, dynamic> reservation, {
    bool automatic = false,
  }) async {
    if (!await _ensureLocationPermission()) return;
    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    final payload = _reservationPayload(reservation);
    final until = _liveLocationUntil;
    _sendTool(
      automatic ? 'Position voyage' : 'Ma position',
      '${payload['route']} - position envoyee',
      Icons.my_location_outlined,
      automatic ? 'travel_location_update' : 'share_current_location',
      closeSheet: false,
      payload: {
        ...payload,
        'travelTool': true,
        'kind': automatic ? 'live_location_update' : 'location',
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracyMeters': position.accuracy,
        'speedKmh': sanitizedGpsSpeedKmh(position.speed),
        'recordedAt': DateTime.now().toIso8601String(),
        if (until != null) 'expiresAt': until.toIso8601String(),
      },
    );
  }

  Future<void> _startTripLocationShare() async {
    _hideComposerPanel();
    final reservation = await _pickReservation(
      title: 'Position automatique',
      subtitle: 'Votre position sera envoyee pendant le voyage choisi.',
      activeOnly: true,
    );
    if (reservation == null) return;
    final duration = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: _surfacePanel(context),
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Partager pendant',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              for (final minutes in [15, 30, 60])
                ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: Text('$minutes minutes'),
                  onTap: () => Navigator.pop(context, minutes),
                ),
            ],
          ),
        ),
      ),
    );
    if (duration == null) return;
    _liveLocationTimer?.cancel();
    _liveLocationUntil = DateTime.now().add(Duration(minutes: duration));
    await _sendTripPositionUpdate(reservation, automatic: true);
    _liveLocationTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      final until = _liveLocationUntil;
      if (until == null || DateTime.now().isAfter(until)) {
        timer.cancel();
        _liveLocationUntil = null;
        return;
      }
      unawaited(_sendTripPositionUpdate(reservation, automatic: true));
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Position partagee pendant $duration minutes.')),
    );
  }

  Future<void> _openTripAgentChat() async {
    _hideComposerPanel();
    final reservation = await _pickReservation(
      title: 'Contacter l agent du trajet',
      subtitle: 'Ouverture du salon voyage lie a votre reservation.',
      activeOnly: true,
    );
    final code = reservation == null ? '' : _reservationCode(reservation);
    if (!mounted || code.isEmpty) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TripChatScreen(reservationCode: code)),
    );
  }

  Future<void> _openLinkedConversationTool() async {
    _hideComposerPanel();
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _surfacePanel(context),
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ToolRow(
                icon: Icons.confirmation_number_outlined,
                title: 'Reservation',
                text: 'Lier cette discussion a un billet.',
                onTap: () => Navigator.pop(context, 'reservation'),
              ),
              _ToolRow(
                icon: Icons.inventory_2_outlined,
                title: 'Colis',
                text: 'Lier cette discussion a un code colis.',
                onTap: () => Navigator.pop(context, 'package'),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == 'reservation') {
      final reservation = await _pickReservation(
        title: 'Conversation liee',
        subtitle: 'Choisissez le billet qui donne le contexte.',
      );
      if (reservation == null) return;
      final payload = _reservationPayload(reservation);
      _sendTool(
        'Conversation liee',
        '${payload['route']} - ${payload['reservationCode']}',
        Icons.forum_outlined,
        'reservation_thread',
        closeSheet: false,
        payload: {...payload, 'travelTool': true, 'kind': 'reservation_thread'},
      );
      return;
    }
    if (choice == 'package') {
      final code = await _askTrackingCode();
      if (code == null || code.isEmpty) return;
      Map<String, dynamic> tracking = {};
      try {
        tracking = await ApiService.trackPackage(code);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Code colis introuvable.')),
          );
        }
        return;
      }
      _sendTool(
        'Conversation colis',
        '${tracking['departure'] ?? '-'} -> ${tracking['destination'] ?? '-'} - $code',
        Icons.inventory_2_outlined,
        'package_thread',
        closeSheet: false,
        payload: {
          'travelTool': true,
          'kind': 'package_thread',
          'trackingCode': code,
          'tracking': tracking,
          'route':
              '${tracking['departure'] ?? '-'} -> ${tracking['destination'] ?? '-'}',
          'status': tracking['status']?.toString() ?? '',
        },
      );
    }
  }

  Future<void> _openConversationInfo() async {
    final result = await Navigator.push<Object?>(
      context,
      MaterialPageRoute(
        builder: (_) => _ConversationInfoScreen(other: widget.other),
      ),
    );
    if (!mounted) return;
    if (result is Map && result['action'] == 'search') {
      _openConversationSearch();
      return;
    }
    if (mounted) {
      _load();
      _loadConversationStatus();
    }
  }

  Future<String?> _askTrackingCode() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Code colis'),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            hintText: 'Ex: COL-260713-ABC1234',
            prefixIcon: Icon(Icons.qr_code_rounded),
          ),
          onSubmitted: (_) =>
              Navigator.pop(context, controller.text.trim().toUpperCase()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, controller.text.trim().toUpperCase()),
            child: const Text('Valider'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  void _sendTool(
    String title,
    String body,
    IconData icon,
    String actionType, {
    Map<String, dynamic> payload = const {},
    String priority = 'normal',
    bool closeSheet = true,
  }) {
    if (closeSheet) _hideComposerPanel();
    _send(
      body: '$title: $body',
      type: 'tool',
      toolAction: actionType,
      metadata: {
        'title': title,
        'icon': icon.codePoint,
        'actionType': actionType,
        'priority': priority,
        'payload': payload,
      },
    );
  }

  void _showMediaImportSheet() {
    _hideComposerPanel();
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
          decoration: BoxDecoration(
            color: _surfacePanel(context),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: scheme.outline.withValues(alpha: .16)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 28,
                offset: Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.perm_media_rounded,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Importer un media',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          'Choisissez le type, puis preparez le media avant envoi.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: Colors.blueGrey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _MediaImportTile(
                icon: Icons.collections_rounded,
                title: appTC(context, 'photosAlbums'),
                subtitle: 'Selection multiple, miniatures et edition.',
                color: scheme.primary,
                onTap: () => _sendGalleryAttachment(photo: true),
              ),
              _MediaImportTile(
                icon: Icons.video_collection_rounded,
                title: 'Video',
                subtitle: 'Previsualisation et coupe avant envoi.',
                color: const Color(0xFF0EA5E9),
                onTap: () => _sendGalleryAttachment(photo: false, video: true),
              ),
              _MediaImportTile(
                icon: Icons.picture_as_pdf_rounded,
                title: 'Document / PDF',
                subtitle: 'Apercu pour PDF et fichiers utiles.',
                color: const Color(0xFFEF4444),
                onTap: () => _sendPickedAttachment(photo: false),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTools() {
    FocusScope.of(context).unfocus();
    setState(() {
      _composerPanel = _composerPanel == _ComposerPanel.actions
          ? _ComposerPanel.none
          : _ComposerPanel.actions;
    });
  }

  void _showGifs() {
    FocusScope.of(context).unfocus();
    setState(() => _composerPanel = _ComposerPanel.media);
  }

  void _hideComposerPanel() {
    if (!mounted || _composerPanel == _ComposerPanel.none) return;
    setState(() => _composerPanel = _ComposerPanel.none);
  }

  List<_ChatActionDefinition> get _chatActions => [
    _ChatActionDefinition(
      icon: Icons.photo_library_rounded,
      label: 'Photos',
      color: const Color(0xFF2563EB),
      onTap: _showMediaImportSheet,
    ),
    _ChatActionDefinition(
      icon: Icons.video_collection_rounded,
      label: 'Videos',
      color: const Color(0xFF7C3AED),
      onTap: _showMediaImportSheet,
    ),
    _ChatActionDefinition(
      icon: Icons.description_rounded,
      label: 'Document',
      color: const Color(0xFFEF4444),
      onTap: _showMediaImportSheet,
    ),
    _ChatActionDefinition(
      icon: Icons.gif_box_rounded,
      label: 'GIF',
      color: const Color(0xFFEC4899),
      onTap: _showGifs,
    ),
    if (_travelerMode) ...[
      _ChatActionDefinition(
        icon: Icons.confirmation_number_rounded,
        label: 'Billet',
        color: const Color(0xFF059669),
        onTap: _shareTicket,
      ),
      _ChatActionDefinition(
        icon: Icons.near_me_rounded,
        label: 'Trajet',
        color: const Color(0xFF0891B2),
        onTap: _shareTripTracking,
      ),
      _ChatActionDefinition(
        icon: Icons.my_location_rounded,
        label: 'Position',
        color: const Color(0xFFF59E0B),
        onTap: _startTripLocationShare,
      ),
      _ChatActionDefinition(
        icon: Icons.support_agent_rounded,
        label: 'Agent',
        color: const Color(0xFF0F766E),
        onTap: _openTripAgentChat,
      ),
      _ChatActionDefinition(
        icon: Icons.forum_rounded,
        label: 'Associer',
        color: const Color(0xFF6366F1),
        onTap: _openLinkedConversationTool,
      ),
    ] else ...[
      _ChatActionDefinition(
        icon: Icons.route_rounded,
        label: 'Alerte',
        color: const Color(0xFFF97316),
        onTap: () => _sendTool(
          'Alerte trajet',
          'Situation a confirmer sur le bus et le prochain point.',
          Icons.route_outlined,
          'route_alert',
          priority: 'high',
          payload: {'requiresReply': true, 'suggestedSlaMinutes': 10},
        ),
      ),
      _ChatActionDefinition(
        icon: Icons.inventory_2_rounded,
        label: 'Colis',
        color: const Color(0xFF0EA5E9),
        onTap: () => _sendTool(
          'Controle colis',
          'Merci de verifier le code colis et son emplacement.',
          Icons.inventory_2_outlined,
          'package_check',
          payload: {'requiresCode': true, 'createsAuditTrail': true},
        ),
      ),
      _ChatActionDefinition(
        icon: Icons.verified_rounded,
        label: 'Ticket',
        color: const Color(0xFF10B981),
        onTap: () => _sendTool(
          'Controle ticket',
          'Billet a verifier avant embarquement.',
          Icons.confirmation_number_outlined,
          'ticket_check',
          payload: {
            'requiresTicketCode': true,
            'createsValidationRequest': true,
          },
        ),
      ),
      _ChatActionDefinition(
        icon: Icons.report_problem_rounded,
        label: 'Incident',
        color: const Color(0xFFDC2626),
        onTap: _showIncidentForm,
      ),
    ],
  ];

  bool _isGifMessage(Map<String, dynamic> message) {
    final metadata = message['metadata'] as Map?;
    if (metadata?['isGif'] == true) return true;
    final mime =
        message['attachmentType']?.toString().toLowerCase() ??
        metadata?['mimeType']?.toString().toLowerCase() ??
        '';
    final name =
        message['attachmentName']?.toString().toLowerCase() ??
        message['body']?.toString().toLowerCase() ??
        '';
    return mime == 'image/gif' || name.endsWith('.gif');
  }

  bool _isStickerMessage(Map<String, dynamic> message) =>
      (message['metadata'] as Map?)?['isSticker'] == true;

  Map<String, dynamic> _stickerEntryFromMessage(Map<String, dynamic> message) {
    final metadata = Map<String, dynamic>.from(
      (message['metadata'] as Map?) ?? const {},
    );
    return {
      'id':
          metadata['stickerId'] ??
          'message-${message['id'] ?? DateTime.now().microsecondsSinceEpoch}',
      'kind': metadata['stickerKind'] ?? 'image',
      'emoji': metadata['stickerEmoji'] ?? '',
      'name': message['attachmentName'] ?? metadata['stickerName'] ?? 'sticker',
      'mime': message['attachmentType'] ?? metadata['mimeType'] ?? 'image/png',
      'url': _absoluteMediaUrl(message['attachmentUrl']?.toString()),
      'localPath': message['attachmentLocalPath']?.toString() ?? '',
      'base64': message['attachmentBase64']?.toString() ?? '',
      'animated': metadata['stickerAnimated'] == true,
    };
  }

  String _stickerIdentity(Map<String, dynamic> item) {
    final sourceIdentity = item['sourceIdentity']?.toString() ?? '';
    if (sourceIdentity.isNotEmpty) return sourceIdentity;
    final id = item['id']?.toString() ?? '';
    if (id.isNotEmpty) return 'id:$id';
    final emoji = item['emoji']?.toString() ?? '';
    if (emoji.isNotEmpty) return 'emoji:$emoji';
    final url = item['url']?.toString() ?? '';
    if (url.isNotEmpty) return 'url:$url';
    final path = item['localPath']?.toString() ?? '';
    return 'path:$path';
  }

  bool _isFavoriteSticker(Map<String, dynamic> item) {
    final identity = _stickerIdentity(item);
    return _favoriteStickers.any(
      (candidate) => _stickerIdentity(candidate) == identity,
    );
  }

  Future<String> _storeStickerFile(Uint8List bytes, String name) async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory('${documents.path}/tranviko_stickers');
    await directory.create(recursive: true);
    final safeName = name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final file = File(
      '${directory.path}/${DateTime.now().microsecondsSinceEpoch}_$safeName',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> _addStickerFavorite(Map<String, dynamic> raw) async {
    final item = Map<String, dynamic>.from(raw);
    final identity = _stickerIdentity(item);
    if (identity == 'path:' || _isFavoriteSticker(item)) return;
    item['sourceIdentity'] = identity;
    final kind = item['kind']?.toString() ?? 'image';
    if (kind != 'emoji' && (item['localPath']?.toString() ?? '').isEmpty) {
      final bytes = await _stickerBytes(item);
      if (bytes == null || bytes.isEmpty) return;
      final video =
          kind == 'video' ||
          (item['mime']?.toString() ?? '').startsWith('video/');
      final extension = video
          ? 'mp4'
          : (item['mime']?.toString() ?? '').contains('webp')
          ? 'webp'
          : 'png';
      item['localPath'] = await _storeStickerFile(
        bytes,
        'favori-${DateTime.now().millisecondsSinceEpoch}.$extension',
      );
      item.remove('base64');
    }
    if (!mounted) return;
    setState(
      () => _favoriteStickers = [item, ..._favoriteStickers].take(60).toList(),
    );
    await _saveFavoriteStickers();
  }

  Future<void> _removeStickerFavorite(Map<String, dynamic> item) async {
    final identity = _stickerIdentity(item);
    if (!mounted) return;
    setState(
      () => _favoriteStickers.removeWhere(
        (candidate) => _stickerIdentity(candidate) == identity,
      ),
    );
    await _saveFavoriteStickers();
  }

  Future<Uint8List?> _stickerBytes(Map<String, dynamic> item) async {
    final path = item['localPath']?.toString() ?? '';
    if (path.isNotEmpty && await File(path).exists()) {
      return File(path).readAsBytes();
    }
    final encoded = item['base64']?.toString() ?? '';
    if (encoded.isNotEmpty) {
      try {
        return base64Decode(encoded.split(',').last);
      } catch (_) {}
    }
    return _gifBytes(item);
  }

  Future<void> _sendSticker(Map<String, dynamic> item) async {
    final kind = item['kind']?.toString() ?? 'image';
    _hideComposerPanel();
    if (kind == 'emoji') {
      final emoji = item['emoji']?.toString() ?? '';
      if (emoji.isEmpty) return;
      await _send(
        body: emoji,
        metadata: {
          'isSticker': true,
          'stickerKind': 'emoji',
          'stickerEmoji': emoji,
          'stickerId': item['id'],
        },
      );
      return;
    }
    final bytes = await _stickerBytes(item);
    if (!mounted || bytes == null || bytes.isEmpty) {
      if (mounted) {
        AppToast.show(
          context,
          'Ce sticker n est plus disponible hors ligne.',
          tone: AppToastTone.warning,
        );
      }
      return;
    }
    final mime =
        item['mime']?.toString() ??
        (kind == 'video' ? 'video/mp4' : 'image/png');
    final video = kind == 'video' || mime.startsWith('video/');
    final animated = item['animated'] == true || video;
    await _sendPreparedAttachment(
      _PreparedAttachment(
        bytes: bytes,
        name:
            item['name']?.toString() ??
            (video
                ? 'tranviko-sticker.mp4'
                : mime.contains('webp')
                ? 'tranviko-sticker.webp'
                : 'tranviko-sticker.png'),
        mime: mime,
        localPath: item['localPath']?.toString(),
        caption: '',
        metadata: {
          'isSticker': true,
          'stickerKind': video ? 'video' : 'image',
          'stickerAnimated': animated,
          'stickerId': item['id'],
          'stickerName': item['name'],
        },
      ),
    );
  }

  Future<_PreparedAttachment?> _prepareStaticSticker(
    Uint8List bytes,
    String name,
  ) async {
    final source = img.decodeImage(bytes);
    if (source == null) return null;
    final longest = math.max(source.width, source.height);
    final target = longest > 512
        ? img.copyResize(
            source,
            width: source.width >= source.height ? 512 : null,
            height: source.height > source.width ? 512 : null,
            interpolation: img.Interpolation.cubic,
          )
        : source;
    final encoded = Uint8List.fromList(img.encodePng(target, level: 6));
    final path = await _storeStickerFile(encoded, 'sticker.png');
    final outputName = RegExp(r'\.[^.]+$').hasMatch(name)
        ? name.replaceFirst(RegExp(r'\.[^.]+$'), '.png')
        : '$name.png';
    return _PreparedAttachment(
      bytes: encoded,
      name: outputName,
      mime: 'image/png',
      localPath: path,
      caption: '',
      metadata: const {
        'isSticker': true,
        'stickerKind': 'image',
        'stickerAnimated': false,
      },
    );
  }

  Future<void> _createStickerFromGallery() async {
    List<_GalleryMediaItem> selected = const [];
    try {
      if (Platform.isAndroid) {
        final hasAccess =
            await _galleryChannel.invokeMethod<bool>('hasMediaAccess') ?? false;
        final allowed = hasAccess
            ? true
            : (await _galleryChannel.invokeMethod<bool>('requestMediaAccess') ??
                  false);
        if (!allowed && mounted) {
          AppToast.show(
            context,
            'Autorisez les photos ou choisissez un media avec le selecteur.',
            tone: AppToastTone.warning,
          );
        }
        if (allowed && mounted) {
          final raw = await _galleryChannel.invokeMethod<List<dynamic>>(
            'listMedia',
            {'kind': 'all', 'limit': 300},
          );
          final items = (raw ?? const [])
              .whereType<Map>()
              .map(_GalleryMediaItem.fromNative)
              .toList();
          if (items.isNotEmpty) {
            selected =
                await Navigator.push<List<_GalleryMediaItem>>(
                  context,
                  MaterialPageRoute(
                    fullscreenDialog: true,
                    builder: (_) => _CustomMediaGalleryScreen(
                      items: items,
                      multiSelect: false,
                      title: 'Creer un sticker',
                    ),
                  ),
                ) ??
                const [];
          }
        }
      } else {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'mp4', 'mov'],
          withData: true,
        );
        final file = result?.files.single;
        if (file != null) {
          selected = [
            _GalleryMediaItem(
              uri: file.path ?? '',
              name: file.name,
              mime: _mimeFromFileName(file.name),
              isVideo: RegExp(
                r'\.(mp4|mov|m4v|webm)$',
                caseSensitive: false,
              ).hasMatch(file.name),
              size: file.size,
              durationMs: 0,
            ),
          ];
        }
      }
      if (mounted && selected.isEmpty) {
        final picked = await ImagePicker().pickMedia();
        if (picked != null) {
          final name = picked.name;
          selected = [
            _GalleryMediaItem(
              uri: picked.path,
              name: name,
              mime: _mimeFromFileName(name),
              isVideo: RegExp(
                r'\.(mp4|mov|m4v|webm)$',
                caseSensitive: false,
              ).hasMatch(name),
              size: await picked.length(),
              durationMs: 0,
            ),
          ];
        }
      }
      if (!mounted || selected.isEmpty) return;
      final source = selected.first;
      Uint8List? bytes;
      if (Platform.isAndroid && source.uri.startsWith('content:')) {
        bytes = await _galleryChannel.invokeMethod<Uint8List>('readMedia', {
          'uri': source.uri,
        });
      } else if (source.uri.isNotEmpty && await File(source.uri).exists()) {
        bytes = await File(source.uri).readAsBytes();
      }
      if (!mounted || bytes == null || bytes.isEmpty) {
        if (mounted) {
          AppToast.show(
            context,
            'Impossible de lire ce media.',
            tone: AppToastTone.error,
          );
        }
        return;
      }
      _PreparedAttachment? prepared;
      if (source.isVideo) {
        prepared = await Navigator.push<_PreparedAttachment>(
          context,
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => _StickerVideoEditor(
              bytes: bytes!,
              name: source.name,
              localPath: source.uri.startsWith('content:') ? null : source.uri,
            ),
          ),
        );
      } else {
        prepared = await _prepareStaticSticker(bytes, source.name);
      }
      if (!mounted || prepared == null) return;
      final item = {
        'id': 'custom-${DateTime.now().microsecondsSinceEpoch}',
        'kind': prepared.metadata['stickerKind'] ?? 'image',
        'animated': prepared.metadata['stickerAnimated'] == true,
        'name': prepared.name,
        'mime': prepared.mime,
        'localPath': prepared.localPath,
        'url': '',
      };
      await _addStickerFavorite(item);
      if (mounted) {
        AppToast.show(
          context,
          'Sticker ajoute a vos favoris.',
          tone: AppToastTone.success,
        );
      }
    } catch (error) {
      if (mounted) {
        AppToast.show(
          context,
          'Creation du sticker impossible: $error',
          tone: AppToastTone.error,
        );
      }
    }
  }

  Future<void> _openStickerMessageActions(Map<String, dynamic> message) async {
    if (!_isStickerMessage(message)) return;
    final entry = _stickerEntryFromMessage(message);
    final favorite = _isFavoriteSticker(entry);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _StickerMessageActionsSheet(
        item: entry,
        favorite: favorite,
        onUse: () {
          Navigator.pop(sheetContext);
          unawaited(_sendSticker(entry));
        },
        onFavorite: () {
          Navigator.pop(sheetContext);
          unawaited(
            favorite
                ? _removeStickerFavorite(entry)
                : _addStickerFavorite(entry),
          );
        },
      ),
    );
  }

  Map<String, dynamic> _gifEntryFromMessage(Map<String, dynamic> message) => {
    'id': 'message-${message['id'] ?? DateTime.now().microsecondsSinceEpoch}',
    'name': message['attachmentName']?.toString().isNotEmpty == true
        ? message['attachmentName'].toString()
        : 'tranviko.gif',
    'url': _absoluteMediaUrl(message['attachmentUrl']?.toString()),
    'localPath': message['attachmentLocalPath']?.toString() ?? '',
    'base64': message['attachmentBase64']?.toString() ?? '',
  };

  String _gifIdentity(Map<String, dynamic> item) {
    final url = item['url']?.toString() ?? '';
    if (url.isNotEmpty) return 'url:$url';
    final path = item['localPath']?.toString() ?? '';
    if (path.isNotEmpty) return 'path:$path';
    return 'name:${item['name'] ?? ''}';
  }

  Future<void> _addGifFavorite(Map<String, dynamic> raw) async {
    final item = Map<String, dynamic>.from(raw);
    final encoded = item.remove('base64')?.toString() ?? '';
    if ((item['localPath'] ?? '').toString().isEmpty && encoded.isNotEmpty) {
      try {
        final bytes = base64Decode(encoded.split(',').last);
        item['localPath'] = await _storeFavoriteGif(
          bytes,
          item['name']?.toString() ?? 'tranviko.gif',
        );
      } catch (_) {}
    }
    if ((item['localPath'] ?? '').toString().isEmpty &&
        (item['url'] ?? '').toString().isNotEmpty) {
      final bytes = await _gifBytes(item);
      if (bytes != null && bytes.isNotEmpty) {
        item['localPath'] = await _storeFavoriteGif(
          bytes,
          item['name']?.toString() ?? 'tranviko.gif',
        );
      }
    }
    final identity = _gifIdentity(item);
    if (identity == 'name:' ||
        _favoriteGifs.any((entry) => _gifIdentity(entry) == identity)) {
      return;
    }
    if (!mounted) return;
    setState(() => _favoriteGifs = [item, ..._favoriteGifs].take(40).toList());
    await _saveFavoriteGifs();
  }

  Future<String> _storeFavoriteGif(Uint8List bytes, String name) async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory('${documents.path}/tranviko_gifs');
    await directory.create(recursive: true);
    final safeName = name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final file = File(
      '${directory.path}/${DateTime.now().microsecondsSinceEpoch}_$safeName',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> _pickFavoriteGif() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['gif'],
      withData: true,
    );
    final selected = result?.files.single;
    if (selected == null) return;
    final bytes =
        selected.bytes ??
        (selected.path == null
            ? null
            : await File(selected.path!).readAsBytes());
    if (bytes == null || bytes.isEmpty) return;
    if (bytes.length > 12 * 1024 * 1024) {
      if (mounted) {
        AppToast.show(
          context,
          appTC(context, 'gifTooLarge'),
          tone: AppToastTone.warning,
        );
      }
      return;
    }
    final localPath = await _storeFavoriteGif(bytes, selected.name);
    await _addGifFavorite({
      'id': 'local-${DateTime.now().microsecondsSinceEpoch}',
      'name': selected.name,
      'localPath': localPath,
      'url': '',
    });
  }

  Future<Uint8List?> _gifBytes(Map<String, dynamic> item) async {
    final path = item['localPath']?.toString() ?? '';
    if (path.isNotEmpty) {
      final file = File(path);
      if (await file.exists()) return file.readAsBytes();
    }
    final encoded = item['base64']?.toString() ?? '';
    if (encoded.isNotEmpty) {
      try {
        return base64Decode(encoded.split(',').last);
      } catch (_) {}
    }
    final url = item['url']?.toString() ?? '';
    if (url.isEmpty) return null;
    const maxBytes = 12 * 1024 * 1024;
    final client = http.Client();
    try {
      final response = await client
          .send(http.Request('GET', Uri.parse(url)))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      if ((response.contentLength ?? 0) > maxBytes) return null;
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.stream) {
        if (builder.length + chunk.length > maxBytes) return null;
        builder.add(chunk);
      }
      return builder.takeBytes();
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  Future<void> _sendFavoriteGif(Map<String, dynamic> item) async {
    final bytes = await _gifBytes(item);
    if (!mounted) return;
    if (bytes == null || bytes.isEmpty) {
      AppToast.show(
        context,
        appTC(context, 'gifOfflineUnavailable'),
        tone: AppToastTone.warning,
      );
      return;
    }
    _hideComposerPanel();
    final mime = item['mime']?.toString() ?? 'image/gif';
    var name = item['name']?.toString() ?? 'tranviko.gif';
    if (!name.contains('.'))
      name = '$name.${mime.contains('webp') ? 'webp' : 'gif'}';
    await _sendPreparedAttachment(
      _PreparedAttachment(
        bytes: bytes,
        name: name,
        mime: mime,
        localPath: item['localPath']?.toString(),
        caption: '',
        metadata: const {'isGif': true},
      ),
    );
  }

  Future<void> _removeGifFavorite(Map<String, dynamic> item) async {
    final identity = _gifIdentity(item);
    if (!mounted) return;
    setState(
      () => _favoriteGifs.removeWhere(
        (candidate) => _gifIdentity(candidate) == identity,
      ),
    );
    await _saveFavoriteGifs();
  }

  Future<void> _openGifMessageActions(Map<String, dynamic> message) async {
    if (!_isGifMessage(message)) return;
    final entry = _gifEntryFromMessage(message);
    final identity = _gifIdentity(entry);
    final favorite = _favoriteGifs.any(
      (candidate) => _gifIdentity(candidate) == identity,
    );
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _GifMessageActionsSheet(
        item: entry,
        favorite: favorite,
        onUse: () {
          Navigator.pop(sheetContext);
          unawaited(_sendFavoriteGif(entry));
        },
        onFavorite: () {
          Navigator.pop(sheetContext);
          unawaited(
            favorite ? _removeGifFavorite(entry) : _addGifFavorite(entry),
          );
        },
      ),
    );
  }

  Future<void> _showIncidentForm() async {
    _hideComposerPanel();
    String type = 'Panne';
    String severity = 'Moyenne';
    final busController = TextEditingController();
    XFile? photo;
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _panel,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            MediaQuery.of(context).viewInsets.bottom + 18,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Rapport d incident flash',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: type,
                items: const [
                  DropdownMenuItem(value: 'Panne', child: Text('Panne')),
                  DropdownMenuItem(
                    value: 'Colis suspect',
                    child: Text('Colis suspect'),
                  ),
                  DropdownMenuItem(value: 'Retard', child: Text('Retard')),
                  DropdownMenuItem(
                    value: 'Controle routier',
                    child: Text('Controle routier'),
                  ),
                ],
                onChanged: (value) => setModalState(() => type = value ?? type),
                decoration: const InputDecoration(labelText: 'Type incident'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: busController,
                decoration: const InputDecoration(labelText: 'N bus / ligne'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: severity,
                items: const [
                  DropdownMenuItem(value: 'Faible', child: Text('Faible')),
                  DropdownMenuItem(value: 'Moyenne', child: Text('Moyenne')),
                  DropdownMenuItem(value: 'Critique', child: Text('Critique')),
                ],
                onChanged: (value) =>
                    setModalState(() => severity = value ?? severity),
                decoration: const InputDecoration(labelText: 'Gravite'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await ImagePicker().pickImage(
                    source: ImageSource.camera,
                    imageQuality: 45,
                  );
                  setModalState(() => photo = picked);
                },
                icon: const Icon(Icons.camera_alt_outlined),
                label: Text(photo == null ? 'Ajouter photo' : 'Photo ajoutee'),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.send),
                  label: const Text('Envoyer rapport'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (sent != true) return;
    String? photoBase64;
    if (photo != null) {
      photoBase64 = base64Encode(await File(photo!.path).readAsBytes());
    }
    _sendTool(
      'Incident $type',
      '$severity - ${busController.text.trim().isEmpty ? 'Bus/ligne non precise' : busController.text.trim()}',
      Icons.report_problem_outlined,
      'incident',
      priority: severity == 'Critique' ? 'urgent' : 'high',
      payload: {
        'incidentType': type,
        'busLine': busController.text.trim(),
        'severity': severity,
        if (photoBase64 != null) 'photoBase64': photoBase64,
        'requiresManagerAttention': true,
        'opensIncidentTask': true,
      },
      closeSheet: false,
    );
  }

  void _toggleMessage(int id) {
    if (id <= 0) return;
    HapticFeedback.selectionClick();
    final message = _messages.cast<Map<String, dynamic>?>().firstWhere(
      (item) => (item?['id'] as num?)?.toInt() == id,
      orElse: () => null,
    );
    final targetIds =
        (message == null
                ? const <Map<String, dynamic>>[]
                : _albumForMessage(message))
            .map((item) => (item['id'] as num?)?.toInt())
            .whereType<int>()
            .where((value) => value > 0)
            .toSet();
    if (targetIds.isEmpty) targetIds.add(id);
    setState(() {
      final allSelected = targetIds.every(_selected.contains);
      if (allSelected) {
        _selected.removeAll(targetIds);
      } else {
        _selected.addAll(targetIds);
      }
    });
  }

  Map<String, dynamic> _replyPayload(Map<String, dynamic> message) {
    final metadata = Map<String, dynamic>.from(
      (message['metadata'] as Map?) ?? const {},
    );
    final label = message['type'] == 'voice'
        ? 'Message vocal'
        : message['type'] == 'file'
        ? (message['attachmentName']?.toString().isNotEmpty == true
              ? message['attachmentName'].toString()
              : 'Media')
        : message['body']?.toString() ?? '';
    return {
      'id': message['id'],
      'body': label,
      'type': message['type'] ?? 'text',
      'fromMe': message['fromMe'] == true,
      'senderName': message['fromMe'] == true
          ? 'Vous'
          : (message['senderName']?.toString() ??
                widget.other['name']?.toString() ??
                ''),
      if (metadata['caption'] != null) 'caption': metadata['caption'],
    };
  }

  void _startReply(Map<String, dynamic> message) {
    if (_isDeletedMessage(message)) return;
    setState(() => _replyTo = _replyPayload(message));
  }

  void _scrollToRepliedMessage(Map<String, dynamic> reply) {
    unawaited(_scrollToRepliedMessageAsync(reply));
  }

  Future<void> _scrollToRepliedMessageAsync(Map<String, dynamic> reply) async {
    final id = reply['id']?.toString();
    if (id == null || id.isEmpty) return;
    var targetIndex = _messages.indexWhere(
      (item) => item['id']?.toString() == id,
    );
    if (targetIndex < 0) {
      AppToast.show(
        context,
        'Message repondu introuvable dans cette discussion.',
        tone: AppToastTone.warning,
      );
      return;
    }
    while (targetIndex > 0 && _isAlbumContinuation(targetIndex)) {
      targetIndex--;
    }
    if (_scroll.hasClients && _messages.length > 1) {
      final ratio = targetIndex / (_messages.length - 1);
      final targetOffset = (_scroll.position.maxScrollExtent * ratio)
          .clamp(
            _scroll.position.minScrollExtent,
            _scroll.position.maxScrollExtent,
          )
          .toDouble();
      await _scroll.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
    final targetMessage = _messages[targetIndex];
    final key = _messageKeys[targetMessage['id']?.toString() ?? id];
    final targetContext = key?.currentContext;
    if (targetContext == null) return;
    Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      alignment: .35,
    );
  }

  String _conversationSearchHaystack(Map<String, dynamic> message) {
    final metadata = Map<String, dynamic>.from(
      (message['metadata'] as Map?) ?? const {},
    );
    return [
      message['body'],
      message['attachmentName'],
      message['attachmentType'],
      message['type'],
      message['createdAt'],
      metadata.values.join(' '),
    ].join(' ').toLowerCase();
  }

  void _refreshConversationSearch() {
    if (!_conversationSearchActive || !mounted) return;
    final query = _conversationSearchController.text.trim().toLowerCase();
    final matches = <int>[];
    if (query.isNotEmpty) {
      for (var index = 0; index < _messages.length; index++) {
        if (_conversationSearchHaystack(_messages[index]).contains(query)) {
          matches.add(index);
        }
      }
    }
    setState(() {
      _conversationSearchMatches = matches;
      if (matches.isEmpty) {
        _conversationSearchCursor = -1;
      } else if (_conversationSearchCursor < 0 ||
          _conversationSearchCursor >= matches.length) {
        _conversationSearchCursor = matches.length - 1;
      }
    });
    if (matches.isNotEmpty) _scrollToConversationSearchMatch();
  }

  void _openConversationSearch() {
    setState(() {
      if (_selectionMode) _selected.clear();
      _conversationSearchActive = true;
    });
    _refreshConversationSearch();
  }

  void _closeConversationSearch() {
    setState(() {
      _conversationSearchActive = false;
      _conversationSearchMatches = [];
      _conversationSearchCursor = -1;
    });
    _conversationSearchController.clear();
  }

  void _jumpConversationSearch(int delta) {
    if (_conversationSearchMatches.isEmpty) return;
    setState(() {
      _conversationSearchCursor =
          (_conversationSearchCursor + delta) %
          _conversationSearchMatches.length;
      if (_conversationSearchCursor < 0) {
        _conversationSearchCursor = _conversationSearchMatches.length - 1;
      }
    });
    _scrollToConversationSearchMatch();
  }

  void _scrollToConversationSearchMatch() {
    if (_conversationSearchCursor < 0 ||
        _conversationSearchCursor >= _conversationSearchMatches.length) {
      return;
    }
    final targetIndex = _conversationSearchMatches[_conversationSearchCursor];
    if (targetIndex < 0 || targetIndex >= _messages.length) return;
    if (_scroll.hasClients && _messages.length > 1) {
      final ratio = targetIndex / (_messages.length - 1);
      final targetOffset = (_scroll.position.maxScrollExtent * ratio)
          .clamp(
            _scroll.position.minScrollExtent,
            _scroll.position.maxScrollExtent,
          )
          .toDouble();
      unawaited(
        _scroll.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        ),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || targetIndex >= _messages.length) return;
      final targetMessage = _messages[targetIndex];
      final key = _messageKeys[targetMessage['id']?.toString() ?? ''];
      final targetContext = key?.currentContext;
      if (targetContext == null) return;
      Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: .35,
      );
    });
  }

  void _openMessageInfo(Map<String, dynamic> message) {
    if (message['fromMe'] != true) return;
    if (_isDeletedMessage(message)) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _MessageInfoScreen(
          message: Map<String, dynamic>.from(message),
          otherName: widget.other['name']?.toString() ?? 'Interlocuteur',
        ),
      ),
    );
  }

  bool _isNearConversationBottom() {
    if (!_scroll.hasClients) return true;
    final distance = _scroll.position.maxScrollExtent - _scroll.position.pixels;
    return distance < 140;
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  });

  void _jumpToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
    if (mounted) setState(() => _showJumpToBottom = false);
  }

  Map<String, dynamic> get _otherPresence {
    final value = widget.other['presence'];
    if (value is Map) return Map<String, dynamic>.from(value);
    return const {};
  }

  bool get _otherIsOnline => _otherPresence['isOnline'] == true;

  String get _otherPresenceLabel {
    final direct = _otherPresence['label']?.toString() ?? '';
    if (direct.isNotEmpty) return direct;
    final lastSeenRaw = _otherPresence['lastSeenAt']?.toString() ?? '';
    if (lastSeenRaw.isEmpty) return 'hors ligne';
    final lastSeen = DateTime.tryParse(lastSeenRaw);
    if (lastSeen == null) return 'hors ligne';
    final elapsed = DateTime.now().difference(lastSeen.toLocal());
    if (elapsed.inSeconds < 60) return "vu a l'instant";
    if (elapsed.inMinutes < 60) return 'vu il y a ${elapsed.inMinutes} min';
    if (elapsed.inHours < 24) return 'vu il y a ${elapsed.inHours} h';
    return 'vu il y a ${elapsed.inDays} j';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reconnectTimer?.cancel();
    _presenceTimer?.cancel();
    _voiceTimer?.cancel();
    _liveLocationTimer?.cancel();
    _recorder.dispose();
    _socketSub?.cancel();
    _channel?.sink.close();
    _controller.removeListener(_syncComposerState);
    _conversationSearchController.removeListener(_refreshConversationSearch);
    _scroll.removeListener(_syncScrollButton);
    _scroll.removeListener(_maybeLoadOlderMessages);
    _controller.dispose();
    _conversationSearchController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchPosition = _conversationSearchCursor >= 0
        ? _conversationSearchCursor + 1
        : 0;
    return PopScope(
      canPop: !_selectionMode && !_conversationSearchActive,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _conversationSearchActive) {
          _closeConversationSearch();
          return;
        }
        if (!didPop && _selectionMode) {
          setState(_selected.clear);
        }
      },
      child: Scaffold(
        backgroundColor: _screenBg(context),
        appBar: AppBar(
          backgroundColor: _selectionMode
              ? Theme.of(
                  context,
                ).colorScheme.primaryContainer.withValues(alpha: .34)
              : _screenBg(context),
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              bottom: Radius.circular(_selectionMode ? 22 : 0),
            ),
          ),
          titleSpacing: _conversationSearchActive ? 8 : 0,
          leading: _conversationSearchActive
              ? null
              : _selectionMode
              ? IconButton(
                  onPressed: () => setState(_selected.clear),
                  icon: const Icon(Icons.close),
                )
              : null,
          title: _conversationSearchActive
              ? Container(
                  height: 44,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: .72),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: appTC(context, 'back'),
                        onPressed: _closeConversationSearch,
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _conversationSearchController,
                          autofocus: true,
                          decoration: const InputDecoration(
                            hintText: 'Rechercher dans la discussion',
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          '${_conversationSearchMatches.isEmpty ? 0 : searchPosition}/${_conversationSearchMatches.length}',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Precedent',
                        onPressed: _conversationSearchMatches.isEmpty
                            ? null
                            : () => _jumpConversationSearch(-1),
                        icon: const Icon(Icons.keyboard_arrow_up_rounded),
                      ),
                      IconButton(
                        tooltip: 'Suivant',
                        onPressed: _conversationSearchMatches.isEmpty
                            ? null
                            : () => _jumpConversationSearch(1),
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      ),
                    ],
                  ),
                )
              : _selectionMode
              ? Text('${_selected.length} message(s)')
              : InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _openConversationInfo,
                  child: Row(
                    children: [
                      _Avatar(
                        name: widget.other['name'].toString(),
                        size: 36,
                        photoBase64: widget.other['profilePhotoBase64']
                            ?.toString(),
                        photoUrl: widget.other['profilePhotoUrl']?.toString(),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.other['name'].toString(),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Row(
                              children: [
                                Icon(
                                  _otherIsOnline
                                      ? Icons.circle
                                      : Icons.schedule_rounded,
                                  size: 8,
                                  color: _otherIsOnline
                                      ? Colors.greenAccent
                                      : Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  _otherPresenceLabel,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
          actions: _conversationSearchActive
              ? const []
              : _selectionMode
              ? [
                  IconButton.filledTonal(
                    tooltip: 'Ajouter une reaction',
                    onPressed: _reactToSelection,
                    icon: const Icon(Icons.add_reaction_outlined),
                  ),
                  const SizedBox(width: 6),
                  if (!_selectionHasDeleted) ...[
                    IconButton.filledTonal(
                      tooltip: 'Transferer',
                      onPressed: _forwardSelection,
                      icon: const Icon(Icons.forward_outlined),
                    ),
                    const SizedBox(width: 6),
                    IconButton.filledTonal(
                      tooltip: 'Important',
                      onPressed: () => _bulkMessageAction('important'),
                      icon: const Icon(Icons.star_border),
                    ),
                  ],
                  const SizedBox(width: 6),
                  IconButton.filledTonal(
                    tooltip: 'Supprimer',
                    onPressed: _confirmDeleteSelection,
                    style: IconButton.styleFrom(
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.errorContainer,
                      foregroundColor: Theme.of(
                        context,
                      ).colorScheme.onErrorContainer,
                    ),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                  const SizedBox(width: 8),
                ]
              : [
                  Tooltip(
                    message: _socketOnline
                        ? 'Connexion temps reel active'
                        : 'Reconnexion en cours',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Center(
                        child: Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _socketOnline
                                ? Colors.greenAccent
                                : Colors.orange,
                            boxShadow: [
                              BoxShadow(
                                color:
                                    (_socketOnline
                                            ? Colors.greenAccent
                                            : Colors.orange)
                                        .withValues(alpha: .35),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Appel audio',
                    onPressed: () {
                      final callId =
                          'call-${DateTime.now().microsecondsSinceEpoch}';
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          settings: RouteSettings(
                            name: AudioCallScreen.routeNameFor(callId),
                          ),
                          builder: (_) => AudioCallScreen(
                            targetId: widget.other['userId'] as int,
                            title: widget.other['name'].toString(),
                            initialCallId: callId,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.call),
                  ),
                  IconButton(
                    tooltip: 'Appel video',
                    onPressed: () {
                      final callId =
                          'call-${DateTime.now().microsecondsSinceEpoch}';
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          settings: RouteSettings(
                            name: AudioCallScreen.routeNameFor(callId),
                          ),
                          builder: (_) => AudioCallScreen(
                            targetId: widget.other['userId'] as int,
                            title: widget.other['name'].toString(),
                            initialCallId: callId,
                            videoCall: true,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.videocam_rounded),
                  ),
                ],
        ),
        body: Column(
          children: [
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : Stack(
                      children: [
                        const Positioned.fill(child: _ChatPatternBackground()),
                        ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                          itemCount: _messages.length,
                          itemBuilder: (_, index) {
                            if (_isAlbumContinuation(index)) {
                              return const SizedBox.shrink();
                            }
                            final message = _messages[index];
                            final id = message['id'] as int? ?? 0;
                            final album = _albumAt(index);
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (index == 0 && _loadingOlderMessages)
                                  const Padding(
                                    padding: EdgeInsets.only(bottom: 10),
                                    child: _OlderMessagesLoader(),
                                  ),
                                if (_startsMessageDay(index))
                                  _ChatDateSeparator(
                                    label: _messageDayLabel(
                                      message['createdAt'],
                                    ),
                                  ),
                                KeyedSubtree(
                                  key: _keyForMessage(message['id']),
                                  child: _MessageBubble(
                                    message: message,
                                    albumMessages: album.length > 1
                                        ? album
                                        : null,
                                    searchQuery: _conversationSearchActive
                                        ? _conversationSearchController.text
                                              .trim()
                                        : '',
                                    selected: _selected.contains(id),
                                    selectionMode: _selectionMode,
                                    onRetry: () => _retryFailedMessage(message),
                                    onInfo:
                                        message['fromMe'] == true &&
                                            !_isDeletedMessage(message)
                                        ? () => _openMessageInfo(message)
                                        : null,
                                    onReply: _isDeletedMessage(message)
                                        ? null
                                        : () => _startReply(message),
                                    onReplyQuoteTap: _scrollToRepliedMessage,
                                    onReactionsTap: _isDeletedMessage(message)
                                        ? null
                                        : () => _openMessageReactions(message),
                                    onGifTap: _isGifMessage(message)
                                        ? () => _openGifMessageActions(message)
                                        : null,
                                    onStickerTap: _isStickerMessage(message)
                                        ? () => _openStickerMessageActions(
                                            message,
                                          )
                                        : null,
                                    onTap: () {
                                      if (_selectionMode) _toggleMessage(id);
                                    },
                                    onLongPress: () => _toggleMessage(id),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        Positioned(
                          right: 18,
                          bottom: 16,
                          child: AnimatedScale(
                            scale: _showJumpToBottom ? 1 : .7,
                            duration: const Duration(milliseconds: 160),
                            child: AnimatedOpacity(
                              opacity: _showJumpToBottom ? 1 : 0,
                              duration: const Duration(milliseconds: 160),
                              child: IgnorePointer(
                                ignoring: !_showJumpToBottom,
                                child: FloatingActionButton.small(
                                  heroTag: 'chat-jump-bottom',
                                  onPressed: _jumpToBottom,
                                  child: const Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
            SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_replyTo != null)
                    _ReplyComposerBar(
                      reply: _replyTo!,
                      onClose: () => setState(() => _replyTo = null),
                    ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 240),
                    reverseDuration: const Duration(milliseconds: 180),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => SizeTransition(
                      sizeFactor: animation,
                      child: FadeTransition(opacity: animation, child: child),
                    ),
                    child: _recording
                        ? _RecordingBar(
                            seconds: _voiceSeconds,
                            level: _voiceLevel,
                            paused: _voicePaused,
                            onCancel: () {
                              _stopVoice(send: false);
                            },
                            onPauseToggle: _toggleVoicePause,
                            onSend: () {
                              _stopVoice();
                            },
                          )
                        : _isBlocked
                        ? Container(
                            key: const ValueKey('blocked'),
                            width: double.infinity,
                            margin: const EdgeInsets.fromLTRB(14, 4, 14, 10),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.errorContainer,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.block_rounded,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onErrorContainer,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Vous avez bloque ce contact. Debloquez-le depuis ses informations pour ecrire.',
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onErrorContainer,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : _composerPanel == _ComposerPanel.actions
                        ? _ChatActionPanel(
                            key: const ValueKey('actions'),
                            actions: _chatActions,
                            onClose: _hideComposerPanel,
                          )
                        : _composerPanel == _ComposerPanel.media
                        ? _ChatExpressionPanel(
                            key: const ValueKey('expressions'),
                            gifLibrary: _favoriteGifs,
                            stickerFavorites: _favoriteStickers,
                            loading:
                                _loadingGifFavorites ||
                                _loadingStickerFavorites,
                            onBack: () => setState(
                              () => _composerPanel = _ComposerPanel.actions,
                            ),
                            onClose: _hideComposerPanel,
                            onAddGif: _pickFavoriteGif,
                            onUseGif: _sendFavoriteGif,
                            onCreateSticker: _createStickerFromGallery,
                            onUseSticker: _sendSticker,
                            onToggleStickerFavorite: (item) =>
                                _isFavoriteSticker(item)
                                ? _removeStickerFavorite(item)
                                : _addStickerFavorite(item),
                          )
                        : _Composer(
                            key: const ValueKey('composer'),
                            controller: _controller,
                            onTool: _showTools,
                            hasText: _hasText,
                            previewUrl: _composerPreviewUrl,
                            onDismissPreview: _dismissComposerPreview,
                            onPrimary: () => _hasText ? _send() : _startVoice(),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatDateSeparator extends StatelessWidget {
  const _ChatDateSeparator({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox.shrink();
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: dark ? const Color(0xE62A3442) : const Color(0xF2FFFFFF),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: dark ? Colors.white12 : const Color(0xFFDDE6F0),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x140F172A),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
            child: Text(
              label,
              style: TextStyle(
                color: dark ? Colors.white70 : const Color(0xFF526477),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OlderMessagesLoader extends StatelessWidget {
  const _OlderMessagesLoader();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _surfacePanel(context),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: scheme.outline.withValues(alpha: .12)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Chargement du reste des messages',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatPatternBackground extends StatelessWidget {
  const _ChatPatternBackground();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return CustomPaint(
      painter: _ChatPatternPainter(
        color: Color.alphaBlend(
          scheme.primary.withValues(alpha: dark ? .18 : .10),
          dark ? Colors.white : scheme.primary,
        ),
        dark: dark,
      ),
    );
  }
}

class _ChatPatternPainter extends CustomPainter {
  final Color color;
  final bool dark;

  const _ChatPatternPainter({required this.color, required this.dark});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(
      dark ? const Color(0xFF0B1118) : Colors.white,
      BlendMode.src,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = color.withValues(alpha: dark ? .20 : .16);
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withValues(alpha: dark ? .055 : .045);
    for (var y = -24.0; y < size.height + 80; y += 118) {
      for (var x = -16.0; x < size.width + 80; x += 126) {
        final offset = ((y / 118).round().isEven ? 0.0 : 42.0);
        final center = Offset(x + offset, y);
        canvas.drawCircle(center, 17, fill);
        canvas.drawArc(
          Rect.fromCenter(center: center, width: 54, height: 42),
          .35,
          2.1,
          false,
          paint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(center.dx + 33, center.dy + 18, 31, 19),
            const Radius.circular(8),
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ChatPatternPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.dark != dark;
  }
}

class _SwipeConversationTile extends StatefulWidget {
  final Map<String, dynamic> item;
  final bool archived;
  final bool enabled;
  final Future<void> Function(String action) onAction;
  final ValueChanged<bool>? onSwipeActivityChanged;
  final Widget child;

  const _SwipeConversationTile({
    super.key,
    required this.item,
    required this.archived,
    required this.enabled,
    required this.onAction,
    this.onSwipeActivityChanged,
    required this.child,
  });

  @override
  State<_SwipeConversationTile> createState() => _SwipeConversationTileState();
}

class _SwipeConversationTileState extends State<_SwipeConversationTile> {
  static const _leftReveal = -176.0;
  static const _leftCommit = -184.0;
  static const _rightReveal = 112.0;
  static const _rightCommit = 130.0;
  double _offset = 0;
  double _dragDx = 0;
  double _dragDy = 0;
  bool _dragAccepted = false;
  bool _working = false;

  bool get _markRead => ((widget.item['unread'] as num?)?.toInt() ?? 0) > 0;

  @override
  void didUpdateWidget(covariant _SwipeConversationTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _offset != 0) _offset = 0;
  }

  Future<void> _runAction(String action) async {
    if (_working) return;
    widget.onSwipeActivityChanged?.call(false);
    setState(() => _working = true);
    HapticFeedback.mediumImpact();
    await widget.onAction(action);
    if (mounted) {
      setState(() {
        _working = false;
        _offset = 0;
      });
    }
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!widget.enabled || _working) return;
    _dragDx += details.delta.dx;
    _dragDy += details.delta.dy;
    if (!_dragAccepted) {
      final horizontal = _dragDx.abs();
      final vertical = _dragDy.abs();
      if (horizontal < 14 || horizontal < vertical * 1.35) return;
      _dragAccepted = true;
      widget.onSwipeActivityChanged?.call(true);
    }
    setState(() {
      _offset = (_offset + details.delta.dx).clamp(-236.0, 156.0);
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    if (!widget.enabled || _working) return;
    _dragDx = 0;
    _dragDy = 0;
    _dragAccepted = false;
    widget.onSwipeActivityChanged?.call(false);
    final velocity = details.primaryVelocity ?? 0;
    if (_offset <= _leftCommit || (velocity < -720 && _offset < -104)) {
      unawaited(_runAction(widget.archived ? 'restore' : 'archive'));
      return;
    }
    if (_offset >= _rightCommit || (velocity > 720 && _offset > 72)) {
      unawaited(_runAction(_markRead ? 'read' : 'unread'));
      return;
    }
    setState(
      () => _offset = _offset <= -36
          ? _leftReveal
          : (_offset >= 36 ? _rightReveal : 0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final revealReadAction = _offset > 0;
    final revealDangerActions = _offset < 0;
    final width = MediaQuery.sizeOf(context).width;
    final archiveExpansion = ((-_offset - 138) / 46).clamp(0.0, 1.0);
    final archiveWidth = 88 + (width - 88) * archiveExpansion;
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        if (revealReadAction)
          Positioned.fill(
            child: _ConversationSwipeBackground(
              alignment: Alignment.centerLeft,
              color: const Color(0xFFDDF6F0),
              foreground: const Color(0xFF0F766E),
              icon: _markRead
                  ? Icons.mark_chat_read_rounded
                  : Icons.markunread_rounded,
              label: _markRead
                  ? appTC(context, 'markRead')
                  : appTC(context, 'markUnread'),
              onTap: () => _runAction(_markRead ? 'read' : 'unread'),
            ),
          ),
        if (revealDangerActions)
          Positioned.fill(
            child: Row(
              children: [
                Expanded(
                  child: _ConversationSwipeAction(
                    color: const Color(0xFFFFE7EA),
                    foreground: const Color(0xFFBE123C),
                    icon: Icons.delete_outline_rounded,
                    label: appTC(context, 'delete'),
                    onTap: () => _runAction('delete'),
                  ),
                ),
                _ConversationSwipeAction(
                  width: archiveWidth,
                  color: widget.archived
                      ? const Color(0xFFDDF6F0)
                      : const Color(0xFFEDE9FE),
                  foreground: widget.archived
                      ? const Color(0xFF0F766E)
                      : const Color(0xFF6D28D9),
                  icon: widget.archived
                      ? Icons.unarchive_rounded
                      : Icons.archive_rounded,
                  label: widget.archived
                      ? appTC(context, 'unarchive')
                      : appTC(context, 'archive'),
                  onTap: () =>
                      _runAction(widget.archived ? 'restore' : 'archive'),
                ),
              ],
            ),
          ),
        AnimatedContainer(
          duration: _dragAccepted
              ? Duration.zero
              : const Duration(milliseconds: 190),
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(_offset, 0, 0),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_offset.abs() > 2 ? 22 : 0),
            boxShadow: _offset.abs() > 2
                ? const [
                    BoxShadow(
                      color: Color(0x160F172A),
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ]
                : const [],
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (_) {
              _dragDx = 0;
              _dragDy = 0;
              _dragAccepted = false;
            },
            onHorizontalDragUpdate: _handleDragUpdate,
            onHorizontalDragEnd: _handleDragEnd,
            onHorizontalDragCancel: () {
              _dragDx = 0;
              _dragDy = 0;
              _dragAccepted = false;
              widget.onSwipeActivityChanged?.call(false);
              if (mounted && _offset != 0) setState(() => _offset = 0);
            },
            child: widget.child,
          ),
        ),
      ],
    );
  }
}

class _ConversationSwipeBackground extends StatelessWidget {
  final Alignment alignment;
  final Color color;
  final Color foreground;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ConversationSwipeBackground({
    required this.alignment,
    required this.color,
    required this.foreground,
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: color,
    child: InkWell(
      onTap: onTap,
      child: Container(
        alignment: alignment,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: foreground),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: foreground,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ConversationSwipeAction extends StatelessWidget {
  final double? width;
  final Color color;
  final Color foreground;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ConversationSwipeAction({
    this.width,
    required this.color,
    required this.foreground,
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Material(
      color: color,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: foreground),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: foreground,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
    return width == null ? content : SizedBox(width: width, child: content);
  }
}

class _ConversationHubTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final int? count;
  final Color? accent;
  final VoidCallback onTap;

  const _ConversationHubTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.count,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = accent ?? scheme.primary;
    return Material(
      color: _surfacePanel(context),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .10),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withValues(alpha: .10)),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _primaryText(context),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle.isEmpty ? appTC(context, 'noResult') : subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(
                        alpha: .55,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      color: scheme.onSurfaceVariant,
                      size: 22,
                    ),
                  ),
                  if ((count ?? 0) > 0)
                    Positioned(
                      right: -3,
                      top: -5,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 19),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                            color: _surfacePanel(context),
                            width: 2,
                          ),
                        ),
                        child: Text(
                          '$count',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReceivedFriendRequestsScreen extends StatefulWidget {
  final List<Map<String, dynamic>> initialRequests;

  const _ReceivedFriendRequestsScreen({required this.initialRequests});

  @override
  State<_ReceivedFriendRequestsScreen> createState() =>
      _ReceivedFriendRequestsScreenState();
}

class _ReceivedFriendRequestsScreenState
    extends State<_ReceivedFriendRequestsScreen> {
  late List<Map<String, dynamic>> _requests;
  final Set<int> _busy = {};

  @override
  void initState() {
    super.initState();
    _requests = widget.initialRequests
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<void> _act(Map<String, dynamic> item, String action) async {
    final requestId = (item['id'] as num?)?.toInt();
    if (requestId == null) return;
    setState(() => _busy.add(requestId));
    try {
      await ApiService.friendRequestAction(
        requestId: requestId,
        action: action,
      );
      if (mounted) {
        setState(
          () => _requests.removeWhere((request) => request['id'] == requestId),
        );
      }
    } catch (error) {
      if (mounted) {
        AppToast.show(
          context,
          AppToast.friendlyError(error, fallback: 'Action impossible.'),
          tone: AppToastTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(requestId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: _screenBg(context),
      appBar: AppBar(title: Text(appTC(context, 'friendRequestsReceived'))),
      body: _requests.isEmpty
          ? Center(child: Text(appTC(context, 'noResult')))
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _requests.length,
              itemBuilder: (context, index) {
                final item = _requests[index];
                final id = (item['id'] as num?)?.toInt() ?? 0;
                final busy = _busy.contains(id);
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 7,
                  ),
                  child: Row(
                    children: [
                      _Avatar(
                        name: item['name']?.toString() ?? 'Contact',
                        photoBase64: item['profilePhotoBase64']?.toString(),
                        photoUrl: item['profilePhotoUrl']?.toString(),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          item['name']?.toString() ?? 'Contact',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Refuser',
                        onPressed: busy ? null : () => _act(item, 'refuse'),
                        style: IconButton.styleFrom(
                          foregroundColor: scheme.error,
                        ),
                        icon: const Icon(Icons.close_rounded),
                      ),
                      const SizedBox(width: 7),
                      IconButton.filled(
                        tooltip: 'Accepter',
                        onPressed: busy ? null : () => _act(item, 'accept'),
                        icon: busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check_rounded),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool selected;
  final bool hasStory;
  final bool storyUnseen;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onStoryTap;

  const _ConversationTile({
    required this.item,
    required this.selected,
    this.hasStory = false,
    this.storyUnseen = false,
    required this.onTap,
    required this.onLongPress,
    this.onStoryTap,
  });

  @override
  Widget build(BuildContext context) {
    final unread = item['unread'] as int? ?? 0;
    final pinned = item['isPinned'] == true;
    final important = item['isImportant'] == true;
    final blocked = item['isBlocked'] == true;
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: selected
            ? Color.alphaBlend(
                scheme.primary.withValues(alpha: .16),
                _surfacePanel(context),
              )
            : _surfacePanel(context),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            children: [
              selected
                  ? const CircleAvatar(
                      backgroundColor: _blue,
                      child: Icon(Icons.check, color: Colors.white),
                    )
                  : GestureDetector(
                      onTap: hasStory ? onStoryTap : null,
                      child: _StoryRingAvatar(
                        active: storyUnseen,
                        showInactive: hasStory,
                        child: _Avatar(
                          name: item['name'].toString(),
                          photoBase64: item['profilePhotoBase64']?.toString(),
                          photoUrl: item['profilePhotoUrl']?.toString(),
                        ),
                      ),
                    ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item['name'].toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: _primaryText(context),
                            ),
                          ),
                        ),
                        if (pinned)
                          const Icon(Icons.push_pin, size: 15, color: _blue),
                        if (important)
                          const Icon(
                            Icons.star,
                            size: 16,
                            color: Color(0xFFF59E0B),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      blocked
                          ? 'Vous avez bloque cette personne'
                          : _conversationPreview(item),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: blocked ? scheme.error : scheme.onSurfaceVariant,
                        fontWeight: blocked ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              if (unread > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _blue,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '$unread',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StoryRingAvatar extends StatelessWidget {
  final bool active;
  final bool showInactive;
  final Widget child;

  const _StoryRingAvatar({
    required this.active,
    this.showInactive = false,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!active && !showInactive) return child;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: active
              ? [scheme.primary, scheme.tertiary, scheme.secondary]
              : [scheme.outlineVariant, scheme.outlineVariant],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: _surfacePanel(context), width: 2),
        ),
        child: child,
      ),
    );
  }
}

class _StoryMediaAvatar extends StatelessWidget {
  final Map<String, dynamic>? story;
  final Widget fallback;
  final double size;
  final double? height;
  final bool circular;

  const _StoryMediaAvatar({
    required this.story,
    required this.fallback,
    this.size = 58,
    this.height,
    this.circular = true,
  });

  @override
  Widget build(BuildContext context) {
    final mediaHeight = circular ? size : (height ?? size);
    final currentStory = story;
    if (currentStory == null) return fallback;
    final url = _storyMediaUrl(currentStory);
    final cachedPath = _storyCachedMediaPath(currentStory);
    final thumbnailUrl =
        (currentStory['thumbnailUrl'] ??
                currentStory['previewUrl'] ??
                currentStory['thumbnail'])
            ?.toString()
            .trim() ??
        '';
    final isVideo = _storyMediaIsVideo(currentStory);
    Widget media = fallback;
    if (cachedPath.isNotEmpty && File(cachedPath).existsSync() && !isVideo) {
      media = Image.file(
        File(cachedPath),
        width: size,
        height: mediaHeight,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    } else if (!isVideo && url.isNotEmpty) {
      media = Image.network(
        url,
        width: size,
        height: mediaHeight,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => fallback,
      );
    } else if (thumbnailUrl.isNotEmpty) {
      media = Image.network(
        thumbnailUrl,
        width: size,
        height: mediaHeight,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => fallback,
      );
    }
    final content = Stack(
      fit: StackFit.expand,
      children: [
        media,
        if (isVideo)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: .02),
                  Colors.black.withValues(alpha: .34),
                ],
              ),
            ),
            child: const Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: EdgeInsets.all(5),
                child: Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
          ),
      ],
    );
    return SizedBox(
      width: size,
      height: mediaHeight,
      child: circular
          ? ClipOval(child: content)
          : ClipRRect(borderRadius: BorderRadius.circular(20), child: content),
    );
  }
}

class _HiddenTravelStoriesScreen extends StatefulWidget {
  const _HiddenTravelStoriesScreen();

  @override
  State<_HiddenTravelStoriesScreen> createState() =>
      _HiddenTravelStoriesScreenState();
}

class _HiddenTravelStoriesScreenState
    extends State<_HiddenTravelStoriesScreen> {
  bool _loading = true;
  bool _changed = false;
  int? _expandedAuthorId;
  final Set<int> _busyAuthors = {};
  List<Map<String, dynamic>> _groups = [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final groups = await ApiService.fetchHiddenTravelStories();
      final hydrated = <Map<String, dynamic>>[];
      for (final group in groups) {
        final next = Map<String, dynamic>.from(group);
        final stories = (next['stories'] as List? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .where(_storyStillActive)
            .toList();
        final cachedStories = <Map<String, dynamic>>[];
        for (final story in stories) {
          cachedStories.add(await _attachCachedStoryMedia(story));
        }
        next['stories'] = cachedStories;
        next['latestStory'] = cachedStories.isNotEmpty
            ? cachedStories.first
            : next['latestStory'];
        if (cachedStories.isNotEmpty) hydrated.add(next);
      }
      if (!mounted) return;
      setState(() => _groups = hydrated);
    } catch (_) {
      if (mounted) {
        AppToast.show(
          context,
          'Chargement des stories masquees impossible.',
          tone: AppToastTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _storiesFor(Map<String, dynamic> group) {
    return (group['stories'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .where(_storyStillActive)
        .toList();
  }

  Future<void> _openGroup(Map<String, dynamic> group) async {
    final stories = _storiesFor(group);
    if (stories.isEmpty) return;
    final hydrated = <Map<String, dynamic>>[];
    for (final story in stories) {
      hydrated.add(await _attachCachedStoryMedia(story));
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _TravelStoryViewer(stories: hydrated, initialIndex: 0),
      ),
    );
    if (mounted) unawaited(_load());
  }

  Future<void> _unhide(Map<String, dynamic> group) async {
    final authorId = (group['authorId'] as num?)?.toInt();
    if (authorId == null || _busyAuthors.contains(authorId)) return;
    setState(() => _busyAuthors.add(authorId));
    try {
      await ApiService.unhideTravelStoryAuthor(authorId);
      if (!mounted) return;
      setState(() {
        _changed = true;
        _expandedAuthorId = null;
        _groups.removeWhere(
          (item) => (item['authorId'] as num?)?.toInt() == authorId,
        );
      });
      AppToast.show(context, 'Stories demasquees.', tone: AppToastTone.success);
    } catch (_) {
      if (mounted) {
        AppToast.show(
          context,
          'Demasquage impossible.',
          tone: AppToastTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busyAuthors.remove(authorId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        backgroundColor: _screenBg(context),
        appBar: AppBar(
          backgroundColor: _screenBg(context),
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.pop(context, _changed),
          ),
          title: const Text('Stories masquees'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _groups.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 74,
                        height: 74,
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: .10),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.visibility_rounded,
                          color: scheme.primary,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Aucune story masquee',
                        style: TextStyle(
                          color: _primaryText(context),
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Les stories que vous masquez apparaissent ici tant qu elles sont actives.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemBuilder: (context, index) {
                  final group = _groups[index];
                  final authorId = (group['authorId'] as num?)?.toInt();
                  final expanded =
                      authorId != null && authorId == _expandedAuthorId;
                  final stories = _storiesFor(group);
                  final latest = stories.isNotEmpty
                      ? stories.first
                      : Map<String, dynamic>.from(
                          (group['latestStory'] as Map?) ?? const {},
                        );
                  final name = (group['authorName'] ?? 'Voyageur').toString();
                  final avatar = _StoryMediaAvatar(
                    story: latest,
                    size: expanded ? 78 : 58,
                    circular: !expanded,
                    fallback: _Avatar(
                      name: name,
                      photoBase64: group['authorPhotoBase64']?.toString(),
                      photoUrl: group['authorPhotoUrl']?.toString(),
                      size: expanded ? 78 : 58,
                    ),
                  );
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 190),
                    curve: Curves.easeOutCubic,
                    decoration: BoxDecoration(
                      color: _surfacePanel(context),
                      borderRadius: BorderRadius.circular(expanded ? 28 : 22),
                      border: Border.all(
                        color: expanded
                            ? scheme.primary.withValues(alpha: .25)
                            : scheme.outline.withValues(alpha: .08),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: expanded ? .10 : .04,
                          ),
                          blurRadius: expanded ? 26 : 14,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(expanded ? 28 : 22),
                      onTap: expanded
                          ? () => setState(() => _expandedAuthorId = null)
                          : () => _openGroup(group),
                      onLongPress: () {
                        HapticFeedback.mediumImpact();
                        setState(
                          () => _expandedAuthorId = expanded ? null : authorId,
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 190),
                              curve: Curves.easeOutCubic,
                              width: expanded ? 82 : 60,
                              height: expanded ? 82 : 60,
                              clipBehavior: Clip.antiAlias,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(
                                  expanded ? 24 : 999,
                                ),
                              ),
                              child: avatar,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: _primaryText(context),
                                      fontSize: 15,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${stories.length} story${stories.length > 1 ? 's' : ''} active${stories.length > 1 ? 's' : ''}',
                                    style: TextStyle(
                                      color: scheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              child: expanded
                                  ? FilledButton.icon(
                                      key: const ValueKey('unhide'),
                                      onPressed: _busyAuthors.contains(authorId)
                                          ? null
                                          : () => _unhide(group),
                                      icon: const Icon(
                                        Icons.visibility_rounded,
                                        size: 18,
                                      ),
                                      label: const Text('Demasquer'),
                                    )
                                  : Icon(
                                      Icons.chevron_right_rounded,
                                      key: const ValueKey('open'),
                                      color: scheme.onSurfaceVariant,
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemCount: _groups.length,
              ),
      ),
    );
  }
}

class _MyTravelStoriesScreen extends StatefulWidget {
  final List<Map<String, dynamic>> stories;
  final Future<void> Function() onAdd;
  final Future<void> Function(Map<String, dynamic>) onOpen;
  final Future<void> Function(Map<String, dynamic>) onDelete;
  final Future<bool> Function(Map<String, dynamic>) onRetry;

  const _MyTravelStoriesScreen({
    required this.stories,
    required this.onAdd,
    required this.onOpen,
    required this.onDelete,
    required this.onRetry,
  });

  @override
  State<_MyTravelStoriesScreen> createState() => _MyTravelStoriesScreenState();
}

class _MyTravelStoriesScreenState extends State<_MyTravelStoriesScreen> {
  late List<Map<String, dynamic>> _stories;
  final Set<int> _busy = {};

  @override
  void initState() {
    super.initState();
    _stories = widget.stories
        .map((story) => Map<String, dynamic>.from(story))
        .toList();
  }

  Future<void> _delete(Map<String, dynamic> story) async {
    final id = (story['id'] as num?)?.toInt() ?? 0;
    setState(() => _busy.add(id));
    try {
      await widget.onDelete(story);
      if (mounted)
        setState(() => _stories.removeWhere((item) => item['id'] == id));
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _retry(Map<String, dynamic> story) async {
    final id = (story['id'] as num?)?.toInt() ?? 0;
    setState(() {
      _busy.add(id);
      final index = _stories.indexWhere((item) => item['id'] == id);
      if (index >= 0) {
        _stories[index] = {..._stories[index], 'uploadState': 'uploading'};
      }
    });
    try {
      final sent = await widget.onRetry(story);
      if (!mounted) return;
      setState(() {
        if (sent) {
          _stories.removeWhere((item) => item['id'] == id);
        } else {
          final index = _stories.indexWhere((item) => item['id'] == id);
          if (index >= 0) {
            _stories[index] = {..._stories[index], 'uploadState': 'failed'};
          }
        }
      });
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: _screenBg(context),
      appBar: AppBar(
        title: Text(appTC(context, 'myStories')),
        actions: [
          IconButton.filledTonal(
            tooltip: appTC(context, 'publishStory'),
            onPressed: widget.onAdd,
            icon: const Icon(Icons.add_photo_alternate_rounded),
            style: IconButton.styleFrom(
              minimumSize: const Size(44, 44),
              shape: const CircleBorder(),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _stories.isEmpty
          ? Center(child: Text(appTC(context, 'noActiveStory')))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 30),
              itemCount: _stories.length,
              itemBuilder: (context, index) {
                final story = _stories[index];
                final id = (story['id'] as num?)?.toInt() ?? 0;
                final state = story['uploadState']?.toString() ?? 'sent';
                final busy = _busy.contains(id);
                final failed = state == 'failed';
                final uploading = state == 'uploading' || busy;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: _surfacePanel(context),
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => widget.onOpen(story),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(15),
                              child: SizedBox(
                                width: 66,
                                height: 82,
                                child: _StoryMediaAvatar(
                                  story: story,
                                  size: 66,
                                  height: 82,
                                  circular: false,
                                  fallback: ColoredBox(
                                    color: scheme.surfaceContainerHighest,
                                    child: const Icon(Icons.image_rounded),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 13),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _relativeStoryTime(story['createdAt']),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  if (uploading) ...[
                                    Text(
                                      'Publication en cours...',
                                      style: TextStyle(
                                        color: scheme.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 7),
                                    const LinearProgressIndicator(),
                                  ] else if (failed)
                                    Text(
                                      story['uploadError']?.toString() ??
                                          'Story non envoyee',
                                      style: TextStyle(
                                        color: scheme.error,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    )
                                  else
                                    Text(
                                      '${story['viewCount'] ?? 0} vues  -  ${story['likeCount'] ?? 0} j aime',
                                      style: TextStyle(
                                        color: scheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (failed)
                              IconButton(
                                tooltip: 'Renvoyer',
                                onPressed: busy ? null : () => _retry(story),
                                icon: const Icon(Icons.refresh_rounded),
                              ),
                            IconButton(
                              tooltip: appTC(context, 'delete'),
                              onPressed: busy ? null : () => _delete(story),
                              icon: Icon(
                                Icons.delete_outline_rounded,
                                color: scheme.error,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _TravelStoryStrip extends StatefulWidget {
  final List<Map<String, dynamic>> stories;
  final int? currentUserId;
  final ValueListenable<int> dismissSignal;
  final VoidCallback onAdd;
  final ValueChanged<int> onOpen;
  final VoidCallback onOpenMine;
  final ValueChanged<int> onHide;
  final VoidCallback onHidden;

  const _TravelStoryStrip({
    required this.stories,
    required this.currentUserId,
    required this.dismissSignal,
    required this.onAdd,
    required this.onOpen,
    required this.onOpenMine,
    required this.onHide,
    required this.onHidden,
  });

  @override
  State<_TravelStoryStrip> createState() => _TravelStoryStripState();
}

class _TravelStoryStripState extends State<_TravelStoryStrip> {
  int? _expandedStoryIndex;
  final Map<int, GlobalKey> _storyAnchorKeys = {};

  @override
  void initState() {
    super.initState();
    widget.dismissSignal.addListener(_dismissExpandedStory);
  }

  @override
  void didUpdateWidget(covariant _TravelStoryStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dismissSignal != widget.dismissSignal) {
      oldWidget.dismissSignal.removeListener(_dismissExpandedStory);
      widget.dismissSignal.addListener(_dismissExpandedStory);
    }
  }

  @override
  void dispose() {
    widget.dismissSignal.removeListener(_dismissExpandedStory);
    super.dispose();
  }

  void _dismissExpandedStory() {
    if (_expandedStoryIndex == null || !mounted) return;
    setState(() => _expandedStoryIndex = null);
  }

  Future<void> _openStorySelection(
    Map<String, dynamic> story,
    int index,
  ) async {
    if (!mounted) return;
    final anchorContext = _storyAnchorKeys[index]?.currentContext;
    final renderObject = anchorContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) return;
    final anchorOrigin = renderObject.localToGlobal(Offset.zero);
    final anchorRect = anchorOrigin & renderObject.size;
    final viewport = MediaQuery.sizeOf(context);
    const selectedWidth = 126.0;
    const selectedHeight = 174.0;
    final selectedLeft = (anchorRect.center.dx - selectedWidth / 2).clamp(
      10.0,
      viewport.width - selectedWidth - 10,
    );
    final selectedTop = (anchorRect.bottom - selectedHeight).clamp(
      MediaQuery.paddingOf(context).top + 8,
      viewport.height - selectedHeight - 12,
    );
    final name = (story['authorName'] ?? appTC(context, 'traveler')).toString();
    final hide = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: appTC(context, 'cancel'),
      barrierColor: Colors.white.withValues(alpha: .52),
      transitionDuration: const Duration(milliseconds: 210),
      pageBuilder: (dialogContext, _, __) => BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Material(
          color: Colors.white.withValues(alpha: .18),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.pop(dialogContext, false),
            child: Stack(
              children: [
                Positioned(
                  left: selectedLeft,
                  top: selectedTop,
                  width: selectedWidth,
                  height: selectedHeight,
                  child: GestureDetector(
                    onTap: () {},
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 28,
                            offset: Offset(0, 14),
                          ),
                        ],
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Column(
                            children: [
                              _StoryMediaAvatar(
                                story: story,
                                size: 110,
                                height: 125,
                                circular: false,
                                fallback: _Avatar(
                                  name: name,
                                  photoBase64: story['authorPhotoBase64']
                                      ?.toString(),
                                  photoUrl: story['authorPhotoUrl']?.toString(),
                                  size: 74,
                                ),
                              ),
                              const SizedBox(height: 7),
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF111827),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                          Positioned(
                            right: -4,
                            bottom: -4,
                            child: Material(
                              color: const Color(0xFF111827),
                              shape: const CircleBorder(),
                              elevation: 4,
                              child: IconButton(
                                tooltip: appTC(context, 'hide'),
                                onPressed: () =>
                                    Navigator.pop(dialogContext, true),
                                color: Colors.white,
                                iconSize: 19,
                                icon: const Icon(Icons.visibility_off_rounded),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      transitionBuilder: (_, animation, __, child) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: .88, end: 1).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
          ),
          alignment: Alignment.bottomCenter,
          child: child,
        ),
      ),
    );
    if (!mounted) return;
    if (hide == true) widget.onHide(index);
  }

  @override
  Widget build(BuildContext context) {
    int newestFirst(
      ({Map<String, dynamic> story, int index}) a,
      ({Map<String, dynamic> story, int index}) b,
    ) {
      final aAt = DateTime.tryParse(a.story['createdAt']?.toString() ?? '');
      final bAt = DateTime.tryParse(b.story['createdAt']?.toString() ?? '');
      if (aAt != null && bAt != null) return bAt.compareTo(aAt);
      return b.index.compareTo(a.index);
    }

    final byAuthor = <int, List<({Map<String, dynamic> story, int index})>>{};
    for (var index = 0; index < widget.stories.length; index++) {
      final story = widget.stories[index];
      if (!_storyStillActive(story)) continue;
      final authorId = (story['authorId'] as num?)?.toInt() ?? -index - 1;
      byAuthor.putIfAbsent(authorId, () => []).add((
        story: story,
        index: index,
      ));
    }
    final firstStories =
        <({Map<String, dynamic> story, int index, bool unseen})>[];
    for (final authorStories in byAuthor.values) {
      authorStories.sort(newestFirst);
      final unseenStories = authorStories
          .where((item) => item.story['isViewed'] != true)
          .toList();
      final first = unseenStories.isNotEmpty
          ? unseenStories.first
          : authorStories.first;
      firstStories.add((
        story: first.story,
        index: first.index,
        unseen: unseenStories.isNotEmpty,
      ));
    }
    firstStories.sort((a, b) {
      if (a.unseen != b.unseen) return a.unseen ? -1 : 1;
      return newestFirst(
        (story: a.story, index: a.index),
        (story: b.story, index: b.index),
      );
    });
    final scheme = Theme.of(context).colorScheme;
    final ownStories = firstStories
        .where(
          (item) =>
              (item.story['authorId'] as num?)?.toInt() == widget.currentUserId,
        )
        .toList();
    final friendStories = firstStories
        .where(
          (item) =>
              (item.story['authorId'] as num?)?.toInt() != widget.currentUserId,
        )
        .toList();
    final ownStory = ownStories.isEmpty ? null : ownStories.first;
    final hasExpandedStory = _expandedStoryIndex != null;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _expandedStoryIndex == null
          ? null
          : () => setState(() => _expandedStoryIndex = null),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 190),
        curve: Curves.easeOutCubic,
        height: hasExpandedStory ? 150 : 96,
        color: Colors.transparent,
        child: ListView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          children: [
            _StoryAvatarItem(
              label: appTC(context, 'myStories'),
              onTap: ownStory == null ? widget.onAdd : widget.onOpenMine,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  _StoryRingAvatar(
                    active: false,
                    showInactive: ownStory != null,
                    child: ownStory == null
                        ? Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              color:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? const Color(0xFF14202B)
                                  : Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(color: scheme.outlineVariant),
                            ),
                            child: Icon(
                              Icons.add_rounded,
                              color: scheme.primary,
                              size: 28,
                            ),
                          )
                        : _StoryMediaAvatar(
                            story: ownStory.story,
                            size: 58,
                            fallback: _Avatar(
                              name:
                                  ownStory.story['authorName']?.toString() ??
                                  appTC(context, 'me'),
                              photoBase64: ownStory.story['authorPhotoBase64']
                                  ?.toString(),
                              photoUrl: ownStory.story['authorPhotoUrl']
                                  ?.toString(),
                            ),
                          ),
                  ),
                  if (ownStory != null)
                    Positioned(
                      right: -3,
                      bottom: -2,
                      child: GestureDetector(
                        onTap: widget.onAdd,
                        child: Container(
                          width: 23,
                          height: 23,
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(
                            Icons.add_rounded,
                            color: Colors.white,
                            size: 15,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            for (final item in friendStories)
              Builder(
                builder: (context) {
                  final expanded = _expandedStoryIndex == item.index;
                  final fallback = _Avatar(
                    name: (item.story['authorName'] ?? 'Voyageur').toString(),
                    photoBase64: item.story['authorPhotoBase64']?.toString(),
                    photoUrl: item.story['authorPhotoUrl']?.toString(),
                    size: expanded ? 72 : 58,
                  );
                  final avatar = AnimatedContainer(
                    duration: const Duration(milliseconds: 190),
                    curve: Curves.easeOutCubic,
                    width: expanded ? 88 : 58,
                    height: expanded ? 112 : 58,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(expanded ? 26 : 999),
                      boxShadow: expanded
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: .18),
                                blurRadius: 24,
                                offset: const Offset(0, 12),
                              ),
                            ]
                          : const [],
                    ),
                    child: expanded
                        ? Stack(
                            clipBehavior: Clip.none,
                            children: [
                              _StoryMediaAvatar(
                                story: item.story,
                                size: 88,
                                height: 112,
                                circular: false,
                                fallback: fallback,
                              ),
                              Positioned(
                                right: -4,
                                bottom: -5,
                                child: Material(
                                  color: Colors.black.withValues(alpha: .72),
                                  shape: const CircleBorder(),
                                  child: InkWell(
                                    customBorder: const CircleBorder(),
                                    onTap: () {
                                      setState(
                                        () => _expandedStoryIndex = null,
                                      );
                                      widget.onHide(item.index);
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Icon(
                                        Icons.visibility_off_rounded,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : _StoryRingAvatar(
                            active: item.unseen,
                            showInactive: !item.unseen,
                            child: _StoryMediaAvatar(
                              story: item.story,
                              size: 58,
                              fallback: fallback,
                            ),
                          ),
                  );
                  return _StoryAvatarItem(
                    key: _storyAnchorKeys.putIfAbsent(
                      item.index,
                      GlobalKey.new,
                    ),
                    expanded: expanded,
                    label:
                        (item.story['authorName'] ?? appTC(context, 'traveler'))
                            .toString(),
                    onTap: () {
                      if (expanded) {
                        setState(() => _expandedStoryIndex = null);
                        return;
                      }
                      if (_expandedStoryIndex != null) {
                        setState(() => _expandedStoryIndex = null);
                        return;
                      }
                      widget.onOpen(item.index);
                    },
                    onLongPress: () {
                      HapticFeedback.mediumImpact();
                      unawaited(_openStorySelection(item.story, item.index));
                    },
                    child: avatar,
                  );
                },
              ),
            _StoryAvatarItem(
              label: appTC(context, 'hiddenStories'),
              onTap: widget.onHidden,
              child: Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: .7),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.visibility_off_rounded,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoryAvatarItem extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget child;
  final bool expanded;

  const _StoryAvatarItem({
    super.key,
    required this.label,
    required this.onTap,
    this.onLongPress,
    required this.child,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 190),
    curve: Curves.easeOutCubic,
    width: expanded ? 112 : 70,
    height: expanded ? 146 : 84,
    transform: Matrix4.translationValues(0, expanded ? -8 : 0, 0),
    child: InkWell(
      borderRadius: BorderRadius.circular(expanded ? 24 : 18),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            bottom: 22,
            child: AnimatedScale(
              duration: const Duration(milliseconds: 190),
              curve: Curves.easeOutCubic,
              scale: expanded ? 1.02 : 1,
              child: child,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _primaryText(context),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _TravelStoryViewer extends StatefulWidget {
  final List<Map<String, dynamic>> stories;
  final int initialIndex;

  const _TravelStoryViewer({required this.stories, required this.initialIndex});

  @override
  State<_TravelStoryViewer> createState() => _TravelStoryViewerState();
}

class _TravelStoryViewerState extends State<_TravelStoryViewer>
    with WidgetsBindingObserver {
  late final PageController _pages;
  final _reply = TextEditingController();
  final _replyFocus = FocusNode();
  Timer? _refreshTimer;
  Timer? _progressTimer;
  Timer? _heartBurstTimer;
  Timer? _socketReconnectTimer;
  WebSocketChannel? _storyChannel;
  StreamSubscription? _storySocketSub;
  final ValueNotifier<double> _progressValue = ValueNotifier<double>(0);
  late int _index;
  bool _sending = false;
  bool _showHeartBurst = false;
  bool _storySocketClosedByUs = false;
  bool _pressingStory = false;
  bool _closing = false;
  bool _currentVideoReady = true;
  DateTime? _storyPressStartedAt;
  Offset? _storyPressStart;
  bool _storyTapCancelled = false;
  bool _storyMenuOpen = false;
  DateTime? _progressStartedAt;
  double _dismissDrag = 0;

  Map<String, dynamic> get _story => widget.stories[_index];
  int get _storyId => (_story['id'] as num?)?.toInt() ?? 0;
  int? get _currentUserId => int.tryParse(
    (ApiService.currentUser?['id'] ?? ApiService.currentUser?['userId'] ?? '')
        .toString(),
  );
  bool get _isOwner => _currentUserId == (_story['authorId'] as num?)?.toInt();
  bool get _progressPaused =>
      _replyFocus.hasFocus ||
      _sending ||
      _pressingStory ||
      _storyMenuOpen ||
      _closing ||
      (_storyMediaIsVideo(_story) && !_currentVideoReady);
  Map<String, dynamic> _withCurrentLocalMedia(Map<String, dynamic> updated) {
    final cachedPath = _storyCachedMediaPath(_story);
    if (cachedPath.isEmpty) return updated;
    return {...updated, 'cachedMediaPath': cachedPath};
  }

  Duration get _storyDuration {
    final raw =
        (_story['durationMs'] as num?)?.toInt() ??
        (_story['mediaType'] == 'video' ? 15000 : 5000);
    return Duration(milliseconds: raw.clamp(2000, 60000));
  }

  @override
  void initState() {
    super.initState();
    unawaited(ScreenAwakeService.acquire('travel_story'));
    WidgetsBinding.instance.addObserver(this);
    _index = widget.initialIndex.clamp(0, widget.stories.length - 1).toInt();
    _currentVideoReady = !_storyMediaIsVideo(_story);
    _pages = PageController(initialPage: _index);
    _replyFocus.addListener(() {
      if (mounted) setState(() {});
    });
    _reply.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markViewed();
      unawaited(_showPendingOwnerLikes());
    });
    _connectStorySocket();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 6),
      (_) => _refreshCurrent(),
    );
    _restartProgress();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pages.dispose();
    _reply.dispose();
    _replyFocus.dispose();
    _refreshTimer?.cancel();
    _progressTimer?.cancel();
    _heartBurstTimer?.cancel();
    _progressValue.dispose();
    _closeStorySocket();
    unawaited(ScreenAwakeService.release('travel_story'));
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _cancelStoryPress();
      return;
    }
    if (state == AppLifecycleState.resumed && mounted) {
      _replyFocus.unfocus();
      setState(() {
        _pressingStory = false;
        _dismissDrag = 0;
      });
      _restartProgress();
      _connectStorySocket();
      unawaited(_refreshCurrent());
    }
  }

  void _connectStorySocket() {
    if (ApiService.activeToken == null || _storySocketSub != null) return;
    _storySocketClosedByUs = false;
    _socketReconnectTimer?.cancel();
    try {
      final channel = WebSocketChannel.connect(ApiService.chatWebSocketUri());
      _storyChannel = channel;
      _storySocketSub = channel.stream.listen(
        _handleStorySocketEvent,
        onDone: _scheduleStorySocketReconnect,
        onError: (_) => _scheduleStorySocketReconnect(),
      );
    } catch (_) {
      _scheduleStorySocketReconnect();
    }
  }

  void _handleStorySocketEvent(dynamic event) {
    try {
      final payload = jsonDecode(event.toString());
      if (payload is Map && payload['event'] == 'story_update') {
        final eventId = (payload['storyId'] as num?)?.toInt();
        if (eventId == null || eventId == _storyId) {
          unawaited(_refreshCurrent());
        }
      }
    } catch (_) {
      // Chat updates share the same authenticated socket and are ignored here.
    }
  }

  void _scheduleStorySocketReconnect() {
    _storySocketSub = null;
    _storyChannel = null;
    if (!mounted || _storySocketClosedByUs || ApiService.activeToken == null) {
      return;
    }
    _socketReconnectTimer?.cancel();
    _socketReconnectTimer = Timer(
      const Duration(seconds: 3),
      _connectStorySocket,
    );
  }

  void _closeStorySocket() {
    _storySocketClosedByUs = true;
    _socketReconnectTimer?.cancel();
    _socketReconnectTimer = null;
    _storySocketSub?.cancel();
    _storySocketSub = null;
    try {
      _storyChannel?.sink.close();
    } catch (_) {}
    _storyChannel = null;
  }

  Future<void> _markViewed() async {
    if (_isOwner || _storyId <= 0) return;
    try {
      final updated = await ApiService.reactToTravelStory(
        storyId: _storyId,
        action: 'view',
      );
      if (mounted) {
        setState(
          () => widget.stories[_index] = _withCurrentLocalMedia(updated),
        );
      }
    } catch (_) {}
  }

  void _restartProgress() {
    _progressTimer?.cancel();
    _progressValue.value = 0;
    _progressStartedAt = DateTime.now();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 60), (_) {
      if (!mounted || _progressStartedAt == null) return;
      if (_progressPaused) {
        final frozen = Duration(
          milliseconds: (_progressValue.value * _storyDuration.inMilliseconds)
              .round(),
        );
        _progressStartedAt = DateTime.now().subtract(frozen);
        return;
      }
      final elapsed = DateTime.now().difference(_progressStartedAt!);
      if (elapsed >= _storyDuration) {
        _advanceStory();
        return;
      }
      _progressValue.value =
          (elapsed.inMilliseconds / _storyDuration.inMilliseconds)
              .clamp(0.0, 1.0)
              .toDouble();
    });
  }

  Future<void> _closeStory({
    bool downward = false,
    bool completed = false,
  }) async {
    if (_closing) return;
    _progressTimer?.cancel();
    if (mounted) {
      setState(() {
        _closing = true;
        if (downward) _dismissDrag = MediaQuery.sizeOf(context).height;
      });
    }
    if (downward) {
      await Future<void>.delayed(const Duration(milliseconds: 180));
    }
    if (mounted) Navigator.of(context).pop({'completed': completed});
  }

  void _advanceStory() {
    if (_index >= widget.stories.length - 1) {
      unawaited(_closeStory(completed: true));
      return;
    }
    _pages.animateToPage(
      _index + 1,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  void _rewindStory() {
    if (_index <= 0) {
      _restartProgress();
      return;
    }
    _pages.animateToPage(
      _index - 1,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  void _onStoryTap(Offset position, Size size) {
    if (position.dx < size.width * .38) {
      _rewindStory();
    } else if (position.dx > size.width * .62) {
      _advanceStory();
    } else {
      if (_replyFocus.hasFocus) _replyFocus.unfocus();
      if (mounted) {
        if (!_progressPaused) _restartProgress();
      }
    }
  }

  void _startStoryPress(Offset position) {
    _storyPressStartedAt = DateTime.now();
    _storyPressStart = position;
    _storyTapCancelled = false;
    if (mounted) setState(() => _pressingStory = true);
  }

  bool _finishStoryPressAsTap(Offset position) {
    final startedAt = _storyPressStartedAt;
    final start = _storyPressStart;
    final hold = startedAt == null
        ? Duration.zero
        : DateTime.now().difference(startedAt);
    final moved = start == null ? 0.0 : (position - start).distance;
    final isTap =
        !_storyTapCancelled &&
        hold < const Duration(milliseconds: 260) &&
        moved < 18;
    _storyPressStartedAt = null;
    _storyPressStart = null;
    _storyTapCancelled = false;
    if (mounted) {
      setState(() => _pressingStory = false);
    }
    return isTap;
  }

  void _cancelStoryPress() {
    _storyPressStartedAt = null;
    _storyPressStart = null;
    _storyTapCancelled = false;
    if (mounted) {
      setState(() => _pressingStory = false);
    }
  }

  void _setVideoDuration(Duration duration) {
    if (duration.inMilliseconds <= 0 ||
        _storyDuration == duration ||
        !mounted) {
      return;
    }
    setState(() => _story['durationMs'] = duration.inMilliseconds);
    _restartProgress();
  }

  void _setCurrentMediaReady(int page, bool ready) {
    if (!mounted || page != _index || _currentVideoReady == ready) return;
    setState(() => _currentVideoReady = ready);
    if (ready) _restartProgress();
  }

  Future<void> _refreshCurrent() async {
    final id = _storyId;
    if (id <= 0) return;
    try {
      final nextStory = await ApiService.fetchTravelStory(id);
      if (!_storyStillActive(nextStory)) {
        if (mounted) unawaited(_closeStory(downward: true));
        return;
      }
      if (mounted) {
        final oldLikes = (_story['likeCount'] as num?)?.toInt() ?? 0;
        final newLikes = (nextStory['likeCount'] as num?)?.toInt() ?? 0;
        setState(
          () => widget.stories[_index] = _withCurrentLocalMedia(nextStory),
        );
        if (_isOwner && newLikes > oldLikes) {
          _triggerHeartBurst();
          unawaited(_showPendingOwnerLikes());
        }
      }
    } catch (_) {}
  }

  void _triggerHeartBurst() {
    _heartBurstTimer?.cancel();
    if (!mounted) return;
    setState(() => _showHeartBurst = true);
    _heartBurstTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _showHeartBurst = false);
    });
  }

  String get _ownerLikeCacheKey =>
      'story_owner_seen_likes_${_currentUserId ?? 'anonymous'}';

  Future<void> _showPendingOwnerLikes() async {
    if (!_isOwner || _storyId <= 0) return;
    final currentLikes = (_story['likeCount'] as num?)?.toInt() ?? 0;
    final seen =
        await LocalCacheService.readMap(_ownerLikeCacheKey) ??
        <String, dynamic>{};
    final previous = (seen['$_storyId'] as num?)?.toInt() ?? 0;
    if (!mounted || !_isOwner) return;
    if (currentLikes > previous) _triggerHeartBurst();
    if (currentLikes != previous) {
      seen['$_storyId'] = currentLikes;
      await LocalCacheService.writeMap(_ownerLikeCacheKey, seen);
    }
  }

  Future<void> _toggleLike() async {
    if (_isOwner || _storyId <= 0) return;
    try {
      final wasLiked = _story['isLiked'] == true;
      final updated = await ApiService.reactToTravelStory(
        storyId: _storyId,
        action: wasLiked ? 'unlike' : 'like',
      );
      if (mounted) {
        setState(
          () => widget.stories[_index] = _withCurrentLocalMedia(updated),
        );
      }
      if (!wasLiked) {
        _triggerHeartBurst();
      }
    } catch (error) {
      if (mounted) {
        AppToast.show(
          context,
          'Reaction impossible.',
          tone: AppToastTone.error,
        );
      }
    }
  }

  Future<void> _sendReply() async {
    final body = _reply.text.trim();
    if (body.isEmpty || _sending || _isOwner) return;
    setState(() => _sending = true);
    var sent = false;
    try {
      await ApiService.replyToTravelStory(storyId: _storyId, body: body);
      sent = true;
      _reply.clear();
      _replyFocus.unfocus();
      if (mounted) {
        AppToast.show(context, 'Reponse envoyee.', tone: AppToastTone.success);
      }
    } catch (error) {
      if (mounted) {
        AppToast.show(context, 'Reponse impossible.', tone: AppToastTone.error);
      }
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
        if (sent && !_progressPaused) _restartProgress();
      }
    }
  }

  Future<void> _reshare() async {
    if (_storyId <= 0) return;
    try {
      await ApiService.reshareTravelStory(_storyId);
      if (mounted) {
        AppToast.show(
          context,
          'Story repartagee pour 24 heures.',
          tone: AppToastTone.success,
        );
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(
          context,
          'Repartage indisponible.',
          tone: AppToastTone.warning,
        );
      }
    }
  }

  Future<void> _delete() async {
    if (_storyId <= 0) return;
    await ApiService.deleteTravelStory(_storyId);
    if (mounted) unawaited(_closeStory(downward: true));
  }

  Future<void> _hideAuthor() async {
    final authorId = (_story['authorId'] as num?)?.toInt();
    if (authorId == null || _isOwner || _storyId <= 0) return;
    try {
      await ApiService.hideTravelStory(_storyId);
      if (!mounted) return;
      widget.stories.removeWhere(
        (item) => (item['authorId'] as num?)?.toInt() == authorId,
      );
      if (widget.stories.isEmpty) {
        unawaited(_closeStory(downward: true));
        return;
      }
      _index = _index.clamp(0, widget.stories.length - 1).toInt();
      _pages.jumpToPage(_index);
      _restartProgress();
      AppToast.show(
        context,
        'Stories de ce contact masquees.',
        tone: AppToastTone.success,
      );
    } catch (_) {
      if (mounted) {
        AppToast.show(
          context,
          'Masquage impossible.',
          tone: AppToastTone.error,
        );
      }
    }
  }

  Future<void> _showAudience() async {
    final viewers = ((_story['viewers'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    setState(() => _storyMenuOpen = true);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(18, 2, 18, 24),
          children: [
            const Text(
              'Vues et reactions',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            if (viewers.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 22),
                child: Text('Personne n a encore vu cette story.'),
              ),
            for (final item in viewers)
              ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.person_outline_rounded),
                ),
                title: Text((item['name'] ?? 'Voyageur').toString()),
                subtitle: Text(
                  item['likedAt'] == null
                      ? 'A vu votre story'
                      : 'A vu et aime votre story',
                ),
                trailing: item['likedAt'] == null
                    ? null
                    : const Icon(
                        Icons.favorite_rounded,
                        color: Color(0xFFFF6B8A),
                      ),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _storyMenuOpen = false);
    _restartProgress();
  }

  @override
  Widget build(BuildContext context) {
    final storyCaption = (_story['caption'] ?? '').toString();
    // A viewer must never lose the reply/like controls after a hold, a send or
    // an app lifecycle transition. Focus only pauses playback.
    final showReplyControls = !_isOwner;
    final showBottomPanel =
        storyCaption.isNotEmpty || _isOwner || showReplyControls;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final bottomPanelOffset = keyboardInset > 0
        ? keyboardInset + 10
        : math.max(10.0, bottomInset + 8);
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Builder(
          builder: (context) {
            final height = math.max(MediaQuery.sizeOf(context).height, 1);
            final slide = _closing
                ? 1.12
                : math.max(0.0, _dismissDrag / height).clamp(0.0, .32);
            return AnimatedSlide(
              offset: Offset(0, slide.toDouble()),
              duration: _closing || _dismissDrag == 0
                  ? const Duration(milliseconds: 180)
                  : Duration.zero,
              curve: Curves.easeInOutCubic,
              child: Stack(
                children: [
                  PageView.builder(
                    controller: _pages,
                    itemCount: widget.stories.length,
                    onPageChanged: (next) {
                      setState(() {
                        _index = next;
                        _currentVideoReady = !_storyMediaIsVideo(
                          widget.stories[next],
                        );
                      });
                      _restartProgress();
                      _markViewed();
                      unawaited(_showPendingOwnerLikes());
                    },
                    itemBuilder: (context, index) => _TravelStoryMedia(
                      story: widget.stories[index],
                      active: index == _index,
                      paused: _progressPaused,
                      onVideoDuration: _setVideoDuration,
                      onReadyChanged: (ready) =>
                          _setCurrentMediaReady(index, ready),
                      onCompleted: _advanceStory,
                    ),
                  ),
                  const Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0xB3000000),
                              Color(0x12000000),
                              Color(0x22000000),
                              Color(0xD9000000),
                            ],
                            stops: [0, .34, .62, 1],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTapDown: (details) =>
                          _startStoryPress(details.localPosition),
                      onTapCancel: _cancelStoryPress,
                      onTapUp: (details) {
                        final shouldTap = _finishStoryPressAsTap(
                          details.localPosition,
                        );
                        if (!shouldTap) return;
                        _onStoryTap(
                          details.localPosition,
                          MediaQuery.sizeOf(context),
                        );
                      },
                      onHorizontalDragStart: (_) {
                        _storyTapCancelled = true;
                      },
                      onHorizontalDragEnd: (details) {
                        final velocity = details.primaryVelocity ?? 0;
                        if (velocity <= -180) _advanceStory();
                        if (velocity >= 180) _rewindStory();
                      },
                      onVerticalDragStart: (_) {
                        _storyTapCancelled = true;
                        setState(() {
                          _dismissDrag = 0;
                          _pressingStory = true;
                        });
                      },
                      onVerticalDragUpdate: (details) {
                        setState(() => _dismissDrag += details.delta.dy);
                      },
                      onVerticalDragEnd: (_) {
                        if (mounted) setState(() => _pressingStory = false);
                        if (_dismissDrag > 86) {
                          unawaited(_closeStory(downward: true));
                        } else if (_dismissDrag < -58) {
                          setState(() {
                            _dismissDrag = 0;
                          });
                          _replyFocus.requestFocus();
                        } else if (mounted) {
                          setState(() => _dismissDrag = 0);
                        }
                      },
                      onVerticalDragCancel: () {
                        if (mounted) {
                          setState(() {
                            _dismissDrag = 0;
                            _pressingStory = false;
                          });
                        }
                      },
                    ),
                  ),
                  if (_showHeartBurst)
                    const Positioned.fill(
                      child: IgnorePointer(child: _StoryHeartBurst()),
                    ),
                  Positioned(
                    top: 10,
                    left: 16,
                    right: 16,
                    child: Row(
                      children: [
                        for (
                          var index = 0;
                          index < widget.stories.length;
                          index++
                        )
                          Expanded(
                            child: Container(
                              height: 4,
                              margin: EdgeInsets.only(
                                right: index == widget.stories.length - 1
                                    ? 0
                                    : 5,
                              ),
                              clipBehavior: Clip.antiAlias,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: .28),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: ValueListenableBuilder<double>(
                                valueListenable: _progressValue,
                                builder: (_, progress, __) =>
                                    FractionallySizedBox(
                                      alignment: Alignment.centerLeft,
                                      widthFactor: index < _index
                                          ? 1
                                          : (index == _index ? progress : 0),
                                      child: const DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 24,
                    left: 14,
                    right: 14,
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => _closeStory(downward: true),
                          style: IconButton.styleFrom(
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                        const SizedBox(width: 8),
                        _StoryRingAvatar(
                          active: true,
                          child: _Avatar(
                            name:
                                (_story['authorName'] ??
                                        appTC(context, 'traveler'))
                                    .toString(),
                            photoBase64: _story['authorPhotoBase64']
                                ?.toString(),
                            photoUrl: _story['authorPhotoUrl']?.toString(),
                            size: 38,
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                (_story['authorName'] ??
                                        appTC(context, 'traveler'))
                                    .toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black54,
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                _story['isReshare'] == true
                                    ? '${appTC(context, 'reshareStory')} - ${_relativeStoryTime(_story['createdAt'])}'
                                    : _relativeStoryTime(_story['createdAt']),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: .78),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  shadows: const [
                                    Shadow(
                                      color: Colors.black54,
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_storyId > 0)
                          PopupMenuButton<String>(
                            iconColor: Colors.white,
                            color: Theme.of(context).colorScheme.surface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            onOpened: () =>
                                setState(() => _storyMenuOpen = true),
                            onCanceled: () {
                              setState(() => _storyMenuOpen = false);
                              _restartProgress();
                            },
                            onSelected: (action) {
                              setState(() => _storyMenuOpen = false);
                              if (action == 'reshare') _reshare();
                              if (action == 'hide') _hideAuthor();
                              if (action == 'delete') _delete();
                              if (mounted) _restartProgress();
                            },
                            itemBuilder: (_) => [
                              if (!_isOwner && _story['allowReshare'] == true)
                                PopupMenuItem(
                                  value: 'reshare',
                                  child: Text(appTC(context, 'reshareStory')),
                                ),
                              if (!_isOwner)
                                PopupMenuItem(
                                  value: 'hide',
                                  child: Text(appTC(context, 'hideStories')),
                                ),
                              if (_isOwner)
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text(appTC(context, 'deleteStory')),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  if (showBottomPanel)
                    Positioned(
                      left: 14,
                      right: 14,
                      bottom: bottomPanelOffset,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 160),
                        opacity: showBottomPanel ? 1 : 0,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (storyCaption.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                                child: Text(
                                  storyCaption,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black87,
                                        blurRadius: 12,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            if (_isOwner)
                              InkWell(
                                onTap: _showAudience,
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                    horizontal: 3,
                                  ),
                                  child: Text(
                                    '${_story['viewCount'] ?? 0} vues  •  ${_story['likeCount'] ?? 0} j aime',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              )
                            else if (showReplyControls)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  IconButton(
                                    onPressed: _toggleLike,
                                    style: IconButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      foregroundColor: _story['isLiked'] == true
                                          ? const Color(0xFFFF6B8A)
                                          : Colors.white.withValues(alpha: .86),
                                      fixedSize: const Size(40, 40),
                                      minimumSize: const Size(40, 40),
                                      padding: EdgeInsets.zero,
                                    ),
                                    icon: Icon(
                                      _story['isLiked'] == true
                                          ? Icons.favorite_rounded
                                          : Icons.favorite_border_rounded,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 180,
                                      ),
                                      constraints: const BoxConstraints(
                                        minHeight: 38,
                                        maxHeight: 78,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFF111827,
                                        ).withValues(alpha: .70),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        border: Border.all(
                                          color: _replyFocus.hasFocus
                                              ? Colors.white.withValues(
                                                  alpha: .52,
                                                )
                                              : Colors.white.withValues(
                                                  alpha: .12,
                                                ),
                                        ),
                                      ),
                                      child: TextField(
                                        controller: _reply,
                                        focusNode: _replyFocus,
                                        minLines: 1,
                                        maxLines: 2,
                                        textInputAction: TextInputAction.send,
                                        onSubmitted: (_) => _sendReply(),
                                        cursorColor: Colors.white,
                                        textAlignVertical:
                                            TextAlignVertical.center,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                          height: 1.12,
                                          decoration: TextDecoration.none,
                                          decorationThickness: 0,
                                        ),
                                        decoration: InputDecoration(
                                          hintText: 'Repondre',
                                          hintStyle: TextStyle(
                                            color: Colors.white.withValues(
                                              alpha: .66,
                                            ),
                                            fontWeight: FontWeight.w700,
                                          ),
                                          isDense: true,
                                          filled: true,
                                          fillColor: Colors.transparent,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 15,
                                                vertical: 9,
                                              ),
                                          border: InputBorder.none,
                                          enabledBorder: InputBorder.none,
                                          focusedBorder: InputBorder.none,
                                          disabledBorder: InputBorder.none,
                                          counterText: '',
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    onPressed: _sending ? null : _sendReply,
                                    style: IconButton.styleFrom(
                                      backgroundColor: Colors.black.withValues(
                                        alpha: .30,
                                      ),
                                      foregroundColor: Colors.white,
                                      fixedSize: const Size(40, 40),
                                      minimumSize: const Size(40, 40),
                                    ),
                                    icon: _sending
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.send_rounded,
                                            size: 20,
                                          ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TravelStoryMedia extends StatefulWidget {
  final Map<String, dynamic> story;
  final bool active;
  final bool paused;
  final ValueChanged<Duration> onVideoDuration;
  final ValueChanged<bool> onReadyChanged;
  final VoidCallback onCompleted;

  const _TravelStoryMedia({
    required this.story,
    required this.active,
    required this.paused,
    required this.onVideoDuration,
    required this.onReadyChanged,
    required this.onCompleted,
  });

  @override
  State<_TravelStoryMedia> createState() => _TravelStoryMediaState();
}

class _TravelStoryMediaState extends State<_TravelStoryMedia> {
  VideoPlayerController? _video;
  Timer? _retryTimer;
  bool _completionSent = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  bool get _isVideo => _storyMediaIsVideo(widget.story);

  void _initVideo() {
    _retryTimer?.cancel();
    _retryTimer = null;
    if (!_isVideo) {
      widget.onReadyChanged(true);
      return;
    }
    widget.onReadyChanged(false);
    final cachedPath = _storyCachedMediaPath(widget.story);
    final url = _storyMediaUrl(widget.story);
    if (!_storyCachedFileAvailable(widget.story) && url.isEmpty) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    final controller = _storyCachedFileAvailable(widget.story)
        ? VideoPlayerController.file(File(cachedPath))
        : VideoPlayerController.networkUrl(Uri.parse(url));
    _video = controller;
    controller
        .initialize()
        .timeout(const Duration(seconds: 18))
        .then((_) {
          if (!mounted || _video != controller) return;
          controller.setLooping(false);
          widget.onVideoDuration(controller.value.duration);
          controller.addListener(_watchVideo);
          widget.onReadyChanged(true);
          _syncPlayback();
          setState(() => _failed = false);
          if (widget.active && !_storyCachedFileAvailable(widget.story)) {
            unawaited(StoryCacheService.cacheStoryMedia(widget.story));
          }
        })
        .catchError((_) {
          if (!mounted || _video != controller) return;
          widget.onReadyChanged(false);
          setState(() => _failed = true);
          _scheduleRetry();
        });
  }

  void _scheduleRetry() {
    if (!widget.active) return;
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || !_isVideo) return;
      _disposeVideoController();
      setState(() => _failed = false);
      _initVideo();
    });
  }

  void _disposeVideoController() {
    final controller = _video;
    if (controller == null) return;
    controller.removeListener(_watchVideo);
    controller.dispose();
    _video = null;
  }

  @override
  void didUpdateWidget(covariant _TravelStoryMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    final storyChanged =
        oldWidget.story['id'] != widget.story['id'] ||
        _storyMediaUrl(oldWidget.story) != _storyMediaUrl(widget.story) ||
        _storyCachedMediaPath(oldWidget.story) !=
            _storyCachedMediaPath(widget.story);
    if (storyChanged) {
      _completionSent = false;
      _failed = false;
      _disposeVideoController();
      _initVideo();
      return;
    }
    if (oldWidget.active != widget.active ||
        oldWidget.paused != widget.paused) {
      _completionSent = false;
      _syncPlayback();
      if (widget.active && _failed) _scheduleRetry();
    }
  }

  void _syncPlayback() {
    final controller = _video;
    if (controller == null || !controller.value.isInitialized) return;
    if (widget.active && !widget.paused) {
      controller.play();
    } else {
      controller.pause();
      if (!widget.active) controller.seekTo(Duration.zero);
    }
  }

  void _watchVideo() {
    final controller = _video;
    if (!widget.active ||
        controller == null ||
        !controller.value.isInitialized) {
      return;
    }
    final duration = controller.value.duration;
    if (!_completionSent &&
        duration > Duration.zero &&
        controller.value.position >= duration) {
      _completionSent = true;
      widget.onCompleted();
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _disposeVideoController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final url = _storyMediaUrl(widget.story);
    final cachedPath = _storyCachedMediaPath(widget.story);
    if (widget.story['mediaType']?.toString() == 'video') {
      final video = _video;
      if (video == null || !video.value.isInitialized) {
        return _StoryVideoLoadingPreview(failed: _failed, story: widget.story);
      }
      final size = video.value.size;
      return SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: size.width <= 0 ? 720 : size.width,
            height: size.height <= 0 ? 1280 : size.height,
            child: VideoPlayer(video),
          ),
        ),
      );
    }
    if (_storyCachedFileAvailable(widget.story)) {
      return SizedBox.expand(
        child: Image.file(
          File(cachedPath),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(
            Icons.broken_image_rounded,
            color: Colors.white,
            size: 48,
          ),
        ),
      );
    }
    return SizedBox.expand(
      child: url.isEmpty
          ? const Center(
              child: Icon(
                Icons.broken_image_rounded,
                color: Colors.white,
                size: 48,
              ),
            )
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Center(
                child: Icon(
                  Icons.broken_image_rounded,
                  color: Colors.white,
                  size: 48,
                ),
              ),
            ),
    );
  }
}

class _StoryVideoLoadingPreview extends StatelessWidget {
  final bool failed;
  final Map<String, dynamic> story;

  const _StoryVideoLoadingPreview({required this.failed, required this.story});

  @override
  Widget build(BuildContext context) {
    final thumbnail =
        (story['thumbnailUrl'] ?? story['previewUrl'] ?? story['thumbnail'])
            ?.toString()
            .trim() ??
        '';
    return Stack(
      fit: StackFit.expand,
      children: [
        if (thumbnail.isNotEmpty)
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Image.network(
              thumbnail,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          )
        else
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF0F172A),
                    Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: .38),
                    const Color(0xFF111827),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .34),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: .14)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!failed)
                  const SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.4,
                    ),
                  )
                else
                  const Icon(
                    Icons.play_circle_outline_rounded,
                    color: Colors.white,
                    size: 34,
                  ),
                const SizedBox(height: 10),
                Text(
                  failed ? 'Video en attente de reseau' : 'Chargement video',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StoryHeartBurst extends StatelessWidget {
  const _StoryHeartBurst();

  @override
  Widget build(BuildContext context) {
    const hearts = [
      (dx: .18, delay: 0.00, size: 22.0),
      (dx: .34, delay: 0.12, size: 18.0),
      (dx: .50, delay: 0.04, size: 28.0),
      (dx: .67, delay: 0.18, size: 20.0),
      (dx: .82, delay: 0.08, size: 24.0),
    ];
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: [
          for (final heart in hearts)
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: Duration(
                milliseconds: 980 + (heart.delay * 1000).round(),
              ),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                final delayed = ((value - heart.delay) / (1 - heart.delay))
                    .clamp(0.0, 1.0)
                    .toDouble();
                return Positioned(
                  left: constraints.maxWidth * heart.dx - heart.size,
                  bottom: 92 + delayed * constraints.maxHeight * .32,
                  child: Opacity(
                    opacity: (1 - delayed).clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: .72 + delayed * .55,
                      child: Icon(
                        Icons.favorite_rounded,
                        color: const Color(0xFFFF6B8A).withValues(alpha: .92),
                        size: heart.size,
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _StoryPublishOptions {
  final String caption;
  final bool allowReshare;
  final String audienceMode;
  final List<int> audienceUserIds;

  const _StoryPublishOptions({
    required this.caption,
    required this.allowReshare,
    required this.audienceMode,
    required this.audienceUserIds,
  });
}

class _PendingStoryUpload {
  final _PreparedAttachment prepared;
  final _StoryPublishOptions options;

  const _PendingStoryUpload(this.prepared, this.options);
}

String _storyAudienceSummary(
  String mode,
  Set<int> selectedIds,
  int totalFriends,
) {
  if (mode == 'include') {
    return selectedIds.isEmpty
        ? 'Choisissez les amis autorises'
        : '${selectedIds.length} personne(s) selectionnee(s)';
  }
  if (mode == 'exclude') {
    return selectedIds.isEmpty
        ? 'Personne n est masque'
        : '${selectedIds.length} personne(s) masquee(s)';
  }
  return totalFriends == 0
      ? 'Visible quand vous aurez des amis'
      : 'Visible par tous vos amis';
}

Future<Set<int>?> _showStoryAudiencePicker(
  BuildContext context, {
  required String title,
  required List<Map<String, dynamic>> friends,
  required Set<int> selectedIds,
}) {
  return showModalBottomSheet<Set<int>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ConversationRecipientPicker(
      title: title,
      conversations: friends,
      initialSelected: selectedIds,
    ),
  );
}

Future<_StoryPublishOptions?> _showTravelStoryOptions(
  BuildContext context,
  String initialCaption, {
  required List<Map<String, dynamic>> friends,
  int? currentUserId,
}) async {
  final controller = TextEditingController(text: initialCaption);
  final cached = await LocalCacheService.readMap(_storyAudiencePrefsKey());
  var reshare = cached?['allowReshare'] == true;
  var audienceMode = (cached?['audienceMode'] ?? 'friends').toString();
  if (!{'friends', 'include', 'exclude'}.contains(audienceMode)) {
    audienceMode = 'friends';
  }
  final selectedIds = ((cached?['audienceUserIds'] as List?) ?? const [])
      .map((value) => int.tryParse(value.toString()))
      .whereType<int>()
      .toSet();
  final friendRows = friends
      .where((item) {
        final id = (item['userId'] as num?)?.toInt();
        return id != null && id > 0 && id != currentUserId;
      })
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
  final result = await showModalBottomSheet<_StoryPublishOptions>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF101826)
        : Colors.white,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) {
        final scheme = Theme.of(context).colorScheme;
        Widget audienceCard({
          required String mode,
          required IconData icon,
          required String title,
          required String subtitle,
          required VoidCallback onTap,
        }) {
          final selected = audienceMode == mode;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: selected
                  ? scheme.primary.withValues(alpha: .09)
                  : _surfacePanel(context),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected
                    ? scheme.primary.withValues(alpha: .35)
                    : scheme.outline.withValues(alpha: .14),
              ),
            ),
            child: ListTile(
              onTap: onTap,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 7,
              ),
              leading: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected
                      ? scheme.primary
                      : scheme.primary.withValues(alpha: .10),
                ),
                child: Icon(
                  selected ? Icons.check_rounded : icon,
                  color: selected ? Colors.white : scheme.primary,
                ),
              ),
              title: Text(
                title,
                style: TextStyle(
                  color: _primaryText(context),
                  fontWeight: FontWeight.w900,
                ),
              ),
              subtitle: Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
            ),
          );
        }

        return SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: 24),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              4,
              20,
              MediaQuery.viewInsetsOf(context).bottom +
                  math.max(MediaQuery.viewPaddingOf(context).bottom, 44) +
                  76,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Publier une story',
                  style: TextStyle(
                    color: _primaryText(context),
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  maxLength: 700,
                  decoration: const InputDecoration(
                    labelText: 'Legende de la story',
                    prefixIcon: Icon(Icons.edit_note_rounded),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Qui peut la voir ?',
                  style: TextStyle(
                    color: _primaryText(context),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 9),
                audienceCard(
                  mode: 'friends',
                  icon: Icons.public_rounded,
                  title: 'Tout',
                  subtitle: _storyAudienceSummary(
                    'friends',
                    selectedIds,
                    friendRows.length,
                  ),
                  onTap: () => setSheetState(() {
                    audienceMode = 'friends';
                    selectedIds.clear();
                  }),
                ),
                audienceCard(
                  mode: 'include',
                  icon: Icons.groups_2_rounded,
                  title: 'Gens qui peuvent voir',
                  subtitle: _storyAudienceSummary(
                    'include',
                    selectedIds,
                    friendRows.length,
                  ),
                  onTap: () async {
                    final picked = await _showStoryAudiencePicker(
                      context,
                      title: 'Qui peut voir ?',
                      friends: friendRows,
                      selectedIds: selectedIds,
                    );
                    if (picked == null) return;
                    setSheetState(() {
                      audienceMode = 'include';
                      selectedIds
                        ..clear()
                        ..addAll(picked);
                    });
                  },
                ),
                audienceCard(
                  mode: 'exclude',
                  icon: Icons.visibility_off_rounded,
                  title: 'Gens qui ne peuvent pas voir',
                  subtitle: _storyAudienceSummary(
                    'exclude',
                    selectedIds,
                    friendRows.length,
                  ),
                  onTap: () async {
                    final picked = await _showStoryAudiencePicker(
                      context,
                      title: 'Masquer a qui ?',
                      friends: friendRows,
                      selectedIds: selectedIds,
                    );
                    if (picked == null) return;
                    setSheetState(() {
                      audienceMode = 'exclude';
                      selectedIds
                        ..clear()
                        ..addAll(picked);
                    });
                  },
                ),
                SwitchListTile.adaptive(
                  value: reshare,
                  onChanged: (value) => setSheetState(() => reshare = value),
                  title: const Text('Autoriser le repartage'),
                  subtitle: const Text(
                    'Vos amis pourront republier cette story pendant 24 heures.',
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      if (audienceMode == 'include' && selectedIds.isEmpty) {
                        AppToast.show(
                          context,
                          'Choisissez au moins une personne.',
                          tone: AppToastTone.warning,
                        );
                        return;
                      }
                      await LocalCacheService.writeMap(
                        _storyAudiencePrefsKey(),
                        {
                          'allowReshare': reshare,
                          'audienceMode': audienceMode,
                          'audienceUserIds': selectedIds.toList(),
                        },
                      );
                      if (!sheetContext.mounted) return;
                      Navigator.pop(
                        sheetContext,
                        _StoryPublishOptions(
                          caption: controller.text.trim(),
                          allowReshare: reshare,
                          audienceMode: audienceMode,
                          audienceUserIds: selectedIds.toList(),
                        ),
                      );
                    },
                    child: const Text('Publier la story'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
  controller.dispose();
  return result;
}

class _ConversationInfoScreen extends StatefulWidget {
  final Map<String, dynamic> other;
  const _ConversationInfoScreen({required this.other});

  @override
  State<_ConversationInfoScreen> createState() =>
      _ConversationInfoScreenState();
}

class _ConversationInfoScreenState extends State<_ConversationInfoScreen> {
  Map<String, dynamic>? _info;
  bool _loading = true;
  bool _working = false;

  int get _userId => (widget.other['userId'] as num?)?.toInt() ?? 0;
  Map<String, dynamic> get _user =>
      Map<String, dynamic>.from((_info?['user'] as Map?) ?? widget.other);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final info = await ApiService.fetchChatConversationInfo(_userId);
      if (mounted) setState(() => _info = info);
    } catch (_) {
      // The lightweight local data still keeps this page usable offline.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _runAction(String action) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await ApiService.chatConversationAction(userId: _userId, action: action);
      if (!mounted) return;
      if (action == 'block' || action == 'delete') {
        Navigator.pop(context, true);
        return;
      }
      await _load();
    } catch (error) {
      if (mounted)
        AppToast.show(context, 'Action impossible.', tone: AppToastTone.error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _shareContact() async {
    if (_userId <= 0 || _working) return;
    try {
      final conversations = await ApiService.fetchConversations();
      if (!mounted) return;
      final targets = await showModalBottomSheet<Set<int>>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _ConversationRecipientPicker(
          title: 'Partager ce contact',
          conversations: conversations
              .where((item) => item['userId'] != _userId)
              .toList(),
        ),
      );
      if (!mounted || targets == null || targets.isEmpty) return;
      setState(() => _working = true);
      final name = (_user['name'] ?? widget.other['name'] ?? 'Contact')
          .toString();
      final payload = <String, dynamic>{
        'travelTool': true,
        'kind': 'contact',
        'contactUserId': _userId,
        'name': name,
        'phone': (_user['phone'] ?? '').toString(),
        'profilePhotoBase64': _user['profilePhotoBase64']?.toString() ?? '',
        'profilePhotoUrl': _user['profilePhotoUrl']?.toString() ?? '',
        'isAppUser': true,
      };
      for (final targetId in targets) {
        await ApiService.sendChatMessage(
          userId: targetId,
          body: 'Contact partage : $name',
          type: 'tool',
          metadata: {'title': 'Contact partage', 'payload': payload},
          toolAction: 'share_contact',
        );
      }
      if (mounted) {
        AppToast.show(
          context,
          'Contact partage avec ${targets.length} discussion(s).',
          tone: AppToastTone.success,
        );
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(
          context,
          'Partage du contact impossible.',
          tone: AppToastTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _confirm(String action, String title, String message) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continuer'),
          ),
        ],
      ),
    );
    if (ok == true) _runAction(action);
  }

  Future<void> _report() async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Signaler cette discussion'),
        content: TextField(
          controller: controller,
          maxLength: 800,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Expliquez brievement le probleme',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || _working) return;
    setState(() => _working = true);
    try {
      await ApiService.reportChatConversation(userId: _userId, reason: reason);
      if (mounted) {
        AppToast.show(
          context,
          'Signalement transmis aux responsables.',
          tone: AppToastTone.success,
        );
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(
          context,
          'Signalement impossible.',
          tone: AppToastTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final blocked = _info?['isBlocked'] == true;
    final muted = _info?['isMuted'] == true;
    final name = (_user['name'] ?? widget.other['name'] ?? 'Contact')
        .toString();
    final phone = (_user['phone'] ?? '').toString();
    return Scaffold(
      backgroundColor: _screenBg(context),
      appBar: AppBar(title: const Text('Informations de la discussion')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
        children: [
          Center(
            child: _Avatar(
              name: name,
              size: 96,
              photoBase64: _user['profilePhotoBase64']?.toString(),
              photoUrl: _user['profilePhotoUrl']?.toString(),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            name,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _primaryText(context),
              fontWeight: FontWeight.w900,
              fontSize: 22,
            ),
          ),
          if (phone.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              phone,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 28),
          SwitchListTile.adaptive(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            secondary: CircleAvatar(
              backgroundColor: scheme.primary.withValues(alpha: .13),
              foregroundColor: scheme.primary,
              child: Icon(
                muted
                    ? Icons.notifications_off_rounded
                    : Icons.notifications_active_rounded,
              ),
            ),
            title: Text(
              muted
                  ? appTC(context, 'notificationsMuted')
                  : appTC(context, 'notificationsEnabled'),
              style: TextStyle(
                color: _primaryText(context),
                fontWeight: FontWeight.w900,
              ),
            ),
            subtitle: Text(
              muted
                  ? appTC(context, 'conversationMuteSub')
                  : appTC(context, 'conversationNotificationsSub'),
            ),
            value: !muted,
            onChanged: _working
                ? null
                : (_) => _runAction(muted ? 'unmute' : 'mute'),
          ),
          _ConversationInfoAction(
            icon: Icons.search_rounded,
            title: 'Rechercher dans la discussion',
            subtitle: 'Retrouver un message, un lien ou un document',
            onTap: () => Navigator.pop(context, {'action': 'search'}),
          ),
          _ConversationInfoAction(
            icon: Icons.contact_page_outlined,
            title: 'Partager le contact',
            subtitle: 'Envoyer une carte de contact dans vos discussions',
            onTap: _shareContact,
          ),
          _ConversationInfoAction(
            icon: blocked ? Icons.lock_open_rounded : Icons.block_rounded,
            title: blocked ? 'Debloquer' : 'Bloquer',
            subtitle: blocked
                ? 'Autoriser de nouveau les messages'
                : 'Ne plus recevoir de messages de ce contact',
            onTap: () => _runAction(blocked ? 'unblock' : 'block'),
          ),
          _ConversationInfoAction(
            icon: Icons.flag_outlined,
            title: 'Signaler',
            subtitle: 'Signaler un comportement ou un contenu inapproprie',
            onTap: _report,
          ),
          const SizedBox(height: 14),
          _ConversationInfoAction(
            icon: Icons.delete_outline_rounded,
            title: 'Supprimer cette discussion',
            subtitle: 'Les messages disparaissent uniquement de votre appareil',
            destructive: true,
            onTap: () => _confirm(
              'delete',
              'Supprimer cette discussion ?',
              'Cette action masque les messages pour votre compte.',
            ),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 20),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

class _ConversationMessageSearchScreen extends StatefulWidget {
  final Map<String, dynamic> other;

  const _ConversationMessageSearchScreen({required this.other});

  @override
  State<_ConversationMessageSearchScreen> createState() =>
      _ConversationMessageSearchScreenState();
}

class _ConversationMessageSearchScreenState
    extends State<_ConversationMessageSearchScreen> {
  final _query = TextEditingController();
  List<Map<String, dynamic>> _messages = const [];
  bool _loading = true;

  int get _userId => (widget.other['userId'] as num?)?.toInt() ?? 0;

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
    _load();
  }

  Future<void> _load() async {
    try {
      final messages = await ApiService.fetchMessages(_userId);
      if (mounted) setState(() => _messages = messages);
    } catch (_) {
      if (mounted) {
        AppToast.show(
          context,
          'Recherche indisponible hors connexion.',
          tone: AppToastTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  String _label(Map<String, dynamic> message) {
    final type = message['type']?.toString();
    if (type == 'voice') return 'Message vocal';
    if (type == 'file') {
      return message['attachmentName']?.toString().isNotEmpty == true
          ? message['attachmentName'].toString()
          : 'Media ou document';
    }
    return message['body']?.toString() ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final needle = _query.text.trim().toLowerCase();
    final results = _messages
        .where((message) {
          if (needle.isEmpty) return false;
          final haystack = [
            _label(message),
            message['attachmentName']?.toString() ?? '',
            message['createdAt']?.toString() ?? '',
          ].join(' ').toLowerCase();
          return haystack.contains(needle);
        })
        .toList()
        .reversed
        .toList();
    return Scaffold(
      backgroundColor: _screenBg(context),
      appBar: AppBar(title: const Text('Recherche dans la discussion')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _query,
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: 'Message, lien, document...',
                suffixIcon: _query.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Effacer',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: _query.clear,
                      ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : needle.isEmpty
                ? const Center(
                    child: Text('Saisissez un mot ou un nom de document.'),
                  )
                : results.isEmpty
                ? const Center(child: Text('Aucun message correspondant.'))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: results.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 7),
                    itemBuilder: (_, index) {
                      final message = results[index];
                      final mine = message['fromMe'] == true;
                      final type = message['type']?.toString();
                      return ListTile(
                        tileColor: _surfacePanel(context),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: .12),
                          child: Icon(
                            type == 'file'
                                ? Icons.perm_media_rounded
                                : type == 'voice'
                                ? Icons.mic_rounded
                                : Icons.chat_bubble_outline_rounded,
                          ),
                        ),
                        title: Text(
                          _label(message),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _primaryText(context),
                          ),
                        ),
                        subtitle: Text(
                          '${mine ? 'Vous' : (widget.other['name'] ?? 'Contact')} - ${_time(message['createdAt']?.toString())}',
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ConversationInfoAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool destructive;

  const _ConversationInfoAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = destructive ? scheme.error : scheme.primary;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: .13),
        foregroundColor: color,
        child: Icon(icon),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w900,
          color: destructive ? color : _primaryText(context),
        ),
      ),
      subtitle: Text(subtitle),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: scheme.onSurfaceVariant,
      ),
      onTap: onTap,
    );
  }
}

class _LinkPreviewCard extends StatelessWidget {
  final Map<String, dynamic> preview;
  final bool mine;

  const _LinkPreviewCard({required this.preview, required this.mine});

  @override
  Widget build(BuildContext context) {
    final url = preview['url']?.toString() ?? '';
    final video = preview['kind']?.toString() == 'video';
    final thumbnail = preview['thumbnailUrl']?.toString() ?? '';
    final provider = preview['provider']?.toString() ?? '';
    final rawTitle = preview['title']?.toString().trim() ?? '';
    final rawAuthor = preview['author']?.toString().trim() ?? '';
    final title = rawTitle.isNotEmpty
        ? rawTitle
        : (rawAuthor.isNotEmpty ? '@$rawAuthor' : 'Ouvrir le lien');
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: url.isEmpty
          ? null
          : () {
              final uri = Uri.tryParse(url);
              if (uri != null) {
                launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: mine
              ? Colors.white.withValues(alpha: .16)
              : scheme.primaryContainer.withValues(alpha: .65),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: mine
                ? Colors.white.withValues(alpha: .25)
                : scheme.primary.withValues(alpha: .18),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 82,
              height: 52,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .22),
                borderRadius: BorderRadius.circular(11),
              ),
              child: thumbnail.isEmpty
                  ? Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          video
                              ? Icons.play_circle_fill_rounded
                              : Icons.link_rounded,
                          color: mine ? Colors.white : scheme.primary,
                          size: 28,
                        ),
                        if (provider.isNotEmpty)
                          Positioned(
                            bottom: 4,
                            left: 4,
                            right: 4,
                            child: Text(
                              provider,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: mine
                                    ? Colors.white70
                                    : scheme.onSurfaceVariant,
                                fontSize: 8,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                      ],
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          thumbnail,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Icon(
                            Icons.play_circle_fill_rounded,
                            color: mine ? Colors.white : scheme.primary,
                            size: 28,
                          ),
                        ),
                        if (video)
                          const Center(
                            child: Icon(
                              Icons.play_circle_fill_rounded,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                      ],
                    ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video
                        ? (provider.isEmpty
                              ? 'Video externe'
                              : '$provider video')
                        : (preview['host'] ?? 'Lien').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: mine ? Colors.white : _primaryText(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: mine ? Colors.white70 : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedEmojiText extends StatefulWidget {
  final String text;
  final double fontSize;
  final bool animate;

  const _AnimatedEmojiText({
    required this.text,
    required this.fontSize,
    required this.animate,
  });

  @override
  State<_AnimatedEmojiText> createState() => _AnimatedEmojiTextState();
}

class _AnimatedEmojiTextState extends State<_AnimatedEmojiText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1450),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant _AnimatedEmojiText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate == oldWidget.animate) return;
    widget.animate ? _controller.repeat() : _controller.stop();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Text(
      widget.text,
      style: TextStyle(fontSize: widget.fontSize, height: 1.08),
    );
    if (!widget.animate) return text;
    return AnimatedBuilder(
      animation: _controller,
      child: text,
      builder: (context, child) {
        final wave = math.sin(_controller.value * math.pi * 2);
        final animatedEmoji = Transform.rotate(
          angle: wave * .035,
          child: Transform.scale(
            scale: 1 + math.max(0, wave) * .07,
            child: child,
          ),
        );
        final crying =
            widget.text.trim() == '\u{1F622}' ||
            widget.text.trim() == '\u{1F62D}';
        if (!crying) return animatedEmoji;
        final fall = _controller.value;
        return SizedBox(
          width: widget.fontSize * 1.18,
          height: widget.fontSize * 1.42,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              animatedEmoji,
              Positioned(
                left: widget.fontSize * .26,
                top: widget.fontSize * (.55 + fall * .62),
                child: Opacity(
                  opacity: math.sin(fall * math.pi).clamp(0.0, 1.0),
                  child: Icon(
                    Icons.water_drop_rounded,
                    color: const Color(0xFF38BDF8),
                    size: widget.fontSize * .20,
                  ),
                ),
              ),
              if (widget.text.trim() == '\u{1F62D}')
                Positioned(
                  right: widget.fontSize * .23,
                  top: widget.fontSize * (.51 + ((fall + .28) % 1) * .67),
                  child: Opacity(
                    opacity: math
                        .sin(((fall + .28) % 1) * math.pi)
                        .clamp(0.0, 1.0),
                    child: Icon(
                      Icons.water_drop_rounded,
                      color: const Color(0xFF38BDF8),
                      size: widget.fontSize * .18,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SmartMessageText extends StatelessWidget {
  final String body;
  final Color color;
  final Color linkColor;
  final bool selectable;
  final String highlight;

  const _SmartMessageText({
    required this.body,
    required this.color,
    required this.linkColor,
    required this.selectable,
    this.highlight = '',
  });

  static final _token = RegExp(
    r'(https?://[^\s<>]+|\+?\d[\d\s().-]{7,}\d|[\w.+-]+@[\w-]+\.[\w.-]+|\b\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\b)',
    caseSensitive: false,
  );

  Future<void> _open(BuildContext context, String value) async {
    final text = value.trim();
    if (text.contains('@') && !text.startsWith('http')) {
      await launchUrl(Uri(scheme: 'mailto', path: text));
      return;
    }
    if (text.startsWith('http')) {
      final uri = Uri.tryParse(text);
      if (uri != null)
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    if (RegExp(r'^\+?\d').hasMatch(text)) {
      final phone = text.replaceAll(RegExp(r'[^+\d]'), '');
      await launchUrl(Uri(scheme: 'tel', path: phone));
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted)
      AppToast.show(context, 'Date copiee.', tone: AppToastTone.success);
  }

  @override
  Widget build(BuildContext context) {
    final compact = body.replaceAll(RegExp(r'\s+'), '');
    final emojiOnly =
        compact.isNotEmpty &&
        RegExp(
          r'^(?:[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}\u{200D}\u{1F3FB}-\u{1F3FF}])+$',
          unicode: true,
        ).hasMatch(compact);
    final emojiCount = compact.characters.length;
    if (emojiOnly && emojiCount <= 3) {
      const animated = <String>{'❤️', '😂', '🔥', '👏', '😍', '🎉', '💪', '👍'};
      return _AnimatedEmojiText(
        text: body,
        fontSize: emojiCount == 1 ? 48 : 34,
        animate:
            emojiCount == 1 &&
            (animated.contains(compact) ||
                compact == '\u{1F622}' ||
                compact == '\u{1F62D}'),
      );
    }
    final spans = <InlineSpan>[];
    final query = highlight.trim().toLowerCase();
    void appendText(String text, TextStyle style) {
      if (text.isEmpty) return;
      if (query.isEmpty) {
        spans.add(TextSpan(text: text, style: style));
        return;
      }
      final lower = text.toLowerCase();
      var cursor = 0;
      while (cursor < text.length) {
        final index = lower.indexOf(query, cursor);
        if (index < 0) {
          spans.add(TextSpan(text: text.substring(cursor), style: style));
          break;
        }
        if (index > cursor) {
          spans.add(
            TextSpan(text: text.substring(cursor, index), style: style),
          );
        }
        spans.add(
          TextSpan(
            text: text.substring(index, index + query.length),
            style: style.copyWith(
              backgroundColor: Colors.amberAccent.withValues(alpha: .55),
              color: Colors.black,
              fontWeight: FontWeight.w900,
            ),
          ),
        );
        cursor = index + query.length;
      }
    }

    var cursor = 0;
    for (final match in _token.allMatches(body)) {
      if (match.start > cursor) {
        appendText(body.substring(cursor, match.start), const TextStyle());
      }
      final value = match.group(0) ?? '';
      spans.add(
        TextSpan(
          text: value,
          style: TextStyle(
            color: linkColor,
            fontWeight: FontWeight.w800,
            decoration: TextDecoration.underline,
            decorationColor: linkColor.withValues(alpha: .45),
          ),
          recognizer: selectable
              ? (TapGestureRecognizer()..onTap = () => _open(context, value))
              : null,
        ),
      );
      cursor = match.end;
    }
    if (cursor < body.length) {
      appendText(body.substring(cursor), const TextStyle());
    }
    return RichText(
      text: TextSpan(
        style: TextStyle(color: color, height: 1.35),
        children: spans,
      ),
    );
  }
}

enum _ComposerPanel { none, actions, media }

class _ChatActionDefinition {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ChatActionDefinition({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
}

class _ChatActionPanel extends StatelessWidget {
  final List<_ChatActionDefinition> actions;
  final VoidCallback onClose;

  const _ChatActionPanel({
    super.key,
    required this.actions,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: _screenBg(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    appTC(context, 'shareInDiscussion'),
                    style: TextStyle(
                      color: _primaryText(context),
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: appTC(context, 'close'),
                  onPressed: onClose,
                  style: IconButton.styleFrom(
                    backgroundColor: scheme.surfaceContainerHighest.withValues(
                      alpha: .55,
                    ),
                  ),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Directionality(
              textDirection: TextDirection.rtl,
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisExtent: 84,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 6,
                ),
                itemCount: actions.length,
                itemBuilder: (context, index) {
                  final action = actions[index];
                  return InkWell(
                    onTap: action.onTap,
                    borderRadius: BorderRadius.circular(20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: action.color.withValues(alpha: .12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            action.icon,
                            color: action.color,
                            size: 24,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          action.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.ltr,
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatExpressionPanel extends StatefulWidget {
  final List<Map<String, dynamic>> gifLibrary;
  final List<Map<String, dynamic>> stickerFavorites;
  final bool loading;
  final VoidCallback onBack;
  final VoidCallback onClose;
  final Future<void> Function() onAddGif;
  final Future<void> Function(Map<String, dynamic>) onUseGif;
  final Future<void> Function() onCreateSticker;
  final Future<void> Function(Map<String, dynamic>) onUseSticker;
  final Future<void> Function(Map<String, dynamic>) onToggleStickerFavorite;

  const _ChatExpressionPanel({
    super.key,
    required this.gifLibrary,
    required this.stickerFavorites,
    required this.loading,
    required this.onBack,
    required this.onClose,
    required this.onAddGif,
    required this.onUseGif,
    required this.onCreateSticker,
    required this.onUseSticker,
    required this.onToggleStickerFavorite,
  });

  @override
  State<_ChatExpressionPanel> createState() => _ChatExpressionPanelState();
}

class _ChatExpressionPanelState extends State<_ChatExpressionPanel> {
  final TextEditingController _search = TextEditingController();
  String _tab = 'gif';
  String _query = '';
  Timer? _searchDebounce;
  List<Map<String, dynamic>> _remoteGifs = const [];
  List<Map<String, dynamic>> _remoteStickers = const [];
  bool _remoteLoading = false;
  bool _remoteConfigured = false;
  bool _remoteHasMore = false;
  int _remoteOffset = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadRemote(reset: true));
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadRemote({required bool reset}) async {
    if (_remoteLoading) return;
    setState(() => _remoteLoading = true);
    final offset = reset ? 0 : _remoteOffset;
    try {
      final payload = await ApiService.fetchChatMedia(
        kind: _tab == 'gif' ? 'gif' : 'sticker',
        query: _query,
        offset: offset,
      );
      if (!mounted) return;
      final incoming = List<Map<String, dynamic>>.from(
        payload['results'] as List? ?? const [],
      );
      setState(() {
        _remoteConfigured = payload['configured'] == true;
        _remoteHasMore = payload['hasMore'] == true;
        _remoteOffset =
            (payload['nextOffset'] as num?)?.toInt() ??
            offset + incoming.length;
        if (_tab == 'gif') {
          _remoteGifs = reset ? incoming : [..._remoteGifs, ...incoming];
        } else {
          _remoteStickers = reset
              ? incoming
              : [..._remoteStickers, ...incoming];
        }
      });
    } catch (_) {
      if (mounted) setState(() => _remoteHasMore = false);
    } finally {
      if (mounted) setState(() => _remoteLoading = false);
    }
  }

  void _selectTab(String tab) {
    if (_tab == tab) return;
    setState(() {
      _tab = tab;
      _remoteOffset = tab == 'gif'
          ? _remoteGifs.length
          : _remoteStickers.length;
      _remoteHasMore = true;
    });
    if ((tab == 'gif' ? _remoteGifs : _remoteStickers).isEmpty) {
      unawaited(_loadRemote(reset: true));
    }
  }

  void _onSearchChanged(String value) {
    setState(() => _query = value);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 380),
      () => unawaited(_loadRemote(reset: true)),
    );
  }

  List<Map<String, dynamic>> get _gifs {
    final byId = <String, Map<String, dynamic>>{};
    for (final raw in [
      ..._remoteGifs,
      ...widget.gifLibrary,
      ..._defaultGifCatalog.map((item) => Map<String, dynamic>.from(item)),
    ]) {
      final item = Map<String, dynamic>.from(raw);
      final key = (item['id'] ?? item['url'] ?? item['localPath'] ?? '')
          .toString();
      if (key.isNotEmpty) byId[key] = item;
    }
    final query = _query.trim().toLowerCase();
    final items = byId.values.toList();
    if (query.isEmpty) return items;
    return items.where((item) {
      return '${item['name'] ?? ''} ${item['tags'] ?? ''}'
          .toLowerCase()
          .contains(query);
    }).toList();
  }

  List<Map<String, dynamic>> get _stickers {
    final byId = <String, Map<String, dynamic>>{};
    for (final raw in [
      ..._remoteStickers,
      ...widget.stickerFavorites,
      ..._defaultStickerCatalog.map(
        (item) => <String, dynamic>{...item, 'kind': 'emoji'},
      ),
    ]) {
      final item = Map<String, dynamic>.from(raw);
      final key = (item['id'] ?? item['emoji'] ?? item['localPath'] ?? '')
          .toString();
      if (key.isNotEmpty) byId[key] = item;
    }
    final query = _query.trim().toLowerCase();
    final items = byId.values.toList();
    if (query.isEmpty) return items;
    return items.where((item) {
      return '${item['emoji'] ?? ''} ${item['name'] ?? ''} ${item['tags'] ?? ''}'
          .toLowerCase()
          .contains(query);
    }).toList();
  }

  bool _favorite(Map<String, dynamic> item) {
    final id = item['id']?.toString() ?? '';
    final emoji = item['emoji']?.toString() ?? '';
    final path = item['localPath']?.toString() ?? '';
    return widget.stickerFavorites.any((favorite) {
      return (id.isNotEmpty && favorite['id']?.toString() == id) ||
          (emoji.isNotEmpty && favorite['emoji']?.toString() == emoji) ||
          (path.isNotEmpty && favorite['localPath']?.toString() == path);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: _screenBg(context),
      elevation: 12,
      shadowColor: const Color(0x330F172A),
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SizedBox(
        height: 420,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outline.withValues(alpha: .24),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 7, 8, 2),
              child: Row(
                children: [
                  IconButton(
                    tooltip: appTC(context, 'back'),
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  Expanded(
                    child: Text(
                      _tab == 'gif' ? 'GIF' : 'Stickers',
                      style: TextStyle(
                        color: _primaryText(context),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: _tab == 'gif'
                        ? appTC(context, 'addGif')
                        : 'Creer un sticker',
                    onPressed: () => unawaited(
                      _tab == 'gif'
                          ? widget.onAddGif()
                          : widget.onCreateSticker(),
                    ),
                    icon: Icon(
                      _tab == 'gif'
                          ? Icons.add_photo_alternate_rounded
                          : Icons.auto_fix_high_rounded,
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: appTC(context, 'close'),
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 3, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: _ExpressionTab(
                      label: 'GIF',
                      icon: Icons.gif_box_rounded,
                      selected: _tab == 'gif',
                      onTap: () => _selectTab('gif'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ExpressionTab(
                      label: 'Stickers',
                      icon: Icons.sticky_note_2_rounded,
                      selected: _tab == 'stickers',
                      onTap: () => _selectTab('stickers'),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: TextField(
                controller: _search,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: _tab == 'gif'
                      ? 'Rechercher un GIF'
                      : 'Rechercher un sticker',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _search.clear();
                            _onSearchChanged('');
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                  isDense: true,
                  filled: true,
                  fillColor: Theme.of(context).brightness == Brightness.dark
                      ? scheme.surfaceContainerHighest.withValues(alpha: .55)
                      : Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: BorderSide(
                      color: scheme.outline.withValues(alpha: .12),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: BorderSide(
                      color: scheme.outline.withValues(alpha: .12),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: BorderSide(
                      color: scheme.outline.withValues(alpha: .12),
                    ),
                  ),
                ),
              ),
            ),
            if (_remoteLoading) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: widget.loading
                  ? const Center(child: CircularProgressIndicator())
                  : _tab == 'gif'
                  ? _gifGrid()
                  : _stickerGrid(),
            ),
            if (_remoteConfigured)
              const Padding(
                padding: EdgeInsets.only(bottom: 5),
                child: Text(
                  'Propulse par GIPHY',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _gifGrid() {
    final gifs = _gifs;
    if (gifs.isEmpty) {
      return Center(child: Text(appTC(context, 'noResult')));
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 14),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 5,
        mainAxisSpacing: 5,
        childAspectRatio: 1.08,
      ),
      itemCount: gifs.length + (_remoteHasMore && !_remoteLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == gifs.length) {
          return InkWell(
            onTap: () => unawaited(_loadRemote(reset: false)),
            borderRadius: BorderRadius.circular(16),
            child: const Center(
              child: Icon(Icons.add_circle_outline_rounded, size: 30),
            ),
          );
        }
        final item = gifs[index];
        return InkWell(
          onTap: () => unawaited(widget.onUseGif(item)),
          borderRadius: BorderRadius.circular(13),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _GifImage(item: item),
                Positioned(
                  left: 5,
                  bottom: 5,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      item['name']?.toString() ?? 'GIF',
                      maxLines: 1,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _stickerGrid() {
    final stickers = _stickers;
    if (stickers.isEmpty) {
      return Center(child: Text(appTC(context, 'noResult')));
    }
    final favorites = stickers.where(_favorite).toList();
    return CustomScrollView(
      slivers: [
        if (favorites.isNotEmpty) ...[
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(14, 3, 14, 7),
              child: Row(
                children: [
                  Icon(Icons.star_rounded, size: 17, color: Color(0xFFF59E0B)),
                  SizedBox(width: 6),
                  Text(
                    'Favoris',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 78,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: favorites.length,
                separatorBuilder: (_, __) => const SizedBox(width: 7),
                itemBuilder: (context, index) {
                  final item = favorites[index];
                  return InkWell(
                    onTap: () => unawaited(widget.onUseSticker(item)),
                    onLongPress: () =>
                        unawaited(widget.onToggleStickerFavorite(item)),
                    borderRadius: BorderRadius.circular(18),
                    child: SizedBox(
                      width: 72,
                      child: _StickerPreview(item: item),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(14, 10, 14, 7),
            child: Text(
              'Tous les stickers',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 14),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
            ),
            itemCount: stickers.length,
            itemBuilder: (context, index) {
              final item = stickers[index];
              final favorite = _favorite(item);
              return InkWell(
                onTap: () => unawaited(widget.onUseSticker(item)),
                onLongPress: () =>
                    unawaited(widget.onToggleStickerFavorite(item)),
                borderRadius: BorderRadius.circular(18),
                child: Stack(
                  children: [
                    Positioned.fill(child: _StickerPreview(item: item)),
                    if (favorite)
                      const Positioned(
                        right: 3,
                        top: 3,
                        child: Icon(
                          Icons.star_rounded,
                          color: Color(0xFFF59E0B),
                          size: 16,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        if (_remoteHasMore && !_remoteLoading)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
              child: OutlinedButton.icon(
                onPressed: () => unawaited(_loadRemote(reset: false)),
                icon: const Icon(Icons.add_circle_outline_rounded),
                label: const Text('Afficher plus'),
              ),
            ),
          ),
      ],
    );
  }
}

class _ExpressionTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ExpressionTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: .12)
          : scheme.surfaceContainerHighest.withValues(alpha: .45),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 19, color: selected ? scheme.primary : null),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StickerPreview extends StatelessWidget {
  final Map<String, dynamic> item;

  const _StickerPreview({required this.item});

  @override
  Widget build(BuildContext context) {
    final kind = item['kind']?.toString() ?? 'emoji';
    if (kind == 'emoji') {
      return Center(
        child: Text(
          item['emoji']?.toString() ?? '',
          style: const TextStyle(fontSize: 40, height: 1),
        ),
      );
    }
    final path = item['localPath']?.toString() ?? '';
    final url = item['url']?.toString() ?? '';
    final mime = item['mime']?.toString() ?? '';
    final video = kind == 'video' || mime.startsWith('video/');
    if (video) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: _InlineVideoPreview(
          url: url,
          localPath: path.isEmpty ? null : path,
          muted: true,
          showPlayButton: false,
          autoplay: true,
          loop: true,
        ),
      );
    }
    final fallback = Center(
      child: Icon(
        Icons.sticky_note_2_rounded,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
    if (path.isNotEmpty && File(path).existsSync()) {
      return Image.file(File(path), fit: BoxFit.contain);
    }
    if (url.isNotEmpty) {
      return Image.network(
        url,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => fallback,
      );
    }
    return fallback;
  }
}

class _GifImage extends StatelessWidget {
  final Map<String, dynamic> item;

  const _GifImage({required this.item});

  @override
  Widget build(BuildContext context) {
    final path = item['localPath']?.toString() ?? '';
    final url = item['url']?.toString() ?? '';
    final fallback = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(child: Icon(Icons.gif_box_rounded, size: 34)),
    );
    if (path.isNotEmpty && File(path).existsSync()) {
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => fallback,
      );
    }
    if (url.isNotEmpty) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => fallback,
      );
    }
    return fallback;
  }
}

class _GifMessageActionsSheet extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool favorite;
  final VoidCallback onUse;
  final VoidCallback onFavorite;

  const _GifMessageActionsSheet({
    required this.item,
    required this.favorite,
    required this.onUse,
    required this.onFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _surfacePanel(context),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                height: 190,
                width: double.infinity,
                child: _GifImage(item: item),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onUse,
                    icon: const Icon(Icons.send_rounded),
                    label: Text(appTC(context, 'useGif')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: onFavorite,
                    icon: Icon(
                      favorite
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_add_outlined,
                    ),
                    label: Text(
                      favorite ? 'Retirer de mes GIF' : 'Enregistrer',
                    ),
                    style: FilledButton.styleFrom(
                      foregroundColor: favorite
                          ? scheme.primary
                          : scheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StickerMessageActionsSheet extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool favorite;
  final VoidCallback onUse;
  final VoidCallback onFavorite;

  const _StickerMessageActionsSheet({
    required this.item,
    required this.favorite,
    required this.onUse,
    required this.onFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _surfacePanel(context),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 188,
              width: 188,
              child: _StickerPreview(item: item),
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onUse,
                    icon: const Icon(Icons.send_rounded),
                    label: const Text('Utiliser'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: onFavorite,
                    icon: Icon(
                      favorite
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                    ),
                    label: Text(
                      favorite ? 'Retirer' : appTC(context, 'favorites'),
                    ),
                    style: FilledButton.styleFrom(
                      foregroundColor: favorite
                          ? const Color(0xFFF59E0B)
                          : scheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onTool;
  final bool hasText;
  final String previewUrl;
  final VoidCallback onDismissPreview;
  final VoidCallback onPrimary;

  const _Composer({
    super.key,
    required this.controller,
    required this.onTool,
    required this.hasText,
    required this.previewUrl,
    required this.onDismissPreview,
    required this.onPrimary,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final uri = Uri.tryParse(previewUrl);
    final host = uri?.host.replaceFirst('www.', '') ?? '';
    final video =
        host.contains('tiktok.') ||
        host.contains('youtube.') ||
        host.contains('youtu.be') ||
        host.contains('instagram.');
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      color: _screenBg(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (previewUrl.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 8, left: 44),
              padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: .72),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: scheme.primary.withValues(alpha: .2)),
              ),
              child: Row(
                children: [
                  Icon(
                    video ? Icons.play_circle_fill_rounded : Icons.link_rounded,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          video ? 'Apercu video externe' : 'Apercu du lien',
                          style: TextStyle(
                            color: scheme.onPrimaryContainer,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          host.isEmpty ? previewUrl : host,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: scheme.onPrimaryContainer.withValues(
                              alpha: .74,
                            ),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Retirer l apercu',
                    onPressed: onDismissPreview,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _RoundIcon(icon: Icons.add, onTap: onTool),
              const SizedBox(width: 8),
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: 44,
                    maxHeight: 108,
                  ),
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 4,
                    style: TextStyle(color: scheme.onSurface),
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: 'Message',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      filled: true,
                      fillColor: _surfacePanel(context),
                      hintStyle: TextStyle(color: scheme.onSurfaceVariant),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide(
                          color: scheme.outline.withValues(alpha: .22),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide(
                          color: scheme.outline.withValues(alpha: .22),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide(
                          color: scheme.primary,
                          width: 1.4,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _RoundIcon(
                icon: hasText ? Icons.send : Icons.mic_none,
                filled: true,
                onTap: onPrimary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReplyComposerBar extends StatelessWidget {
  final Map<String, dynamic> reply;
  final VoidCallback onClose;

  const _ReplyComposerBar({required this.reply, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          scheme.primary.withValues(alpha: .10),
          _surfacePanel(context),
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.primary.withValues(alpha: .18)),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 34,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  reply['senderName']?.toString() ?? 'Message',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
                Text(
                  reply['body']?.toString() ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _primaryText(context),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _ReplyQuote extends StatelessWidget {
  final Map<String, dynamic> reply;
  final bool mine;
  final ValueChanged<Map<String, dynamic>>? onTap;

  const _ReplyQuote({required this.reply, required this.mine, this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = mine ? scheme.onPrimary : scheme.primary;
    final content = Container(
      constraints: const BoxConstraints(minWidth: 180),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: mine
            ? Colors.white.withValues(alpha: .16)
            : scheme.primary.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            reply['senderName']?.toString() ?? 'Message',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            reply['body']?.toString() ?? '',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: mine
                  ? scheme.onPrimary.withValues(alpha: .78)
                  : scheme.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(
      onTap: () => onTap!(reply),
      borderRadius: BorderRadius.circular(14),
      child: content,
    );
  }
}

Future<void> _openStoryReplyPreview(
  BuildContext context,
  Map<String, dynamic> preview,
) async {
  final storyId = (preview['storyId'] as num?)?.toInt();
  if (storyId == null || storyId <= 0) return;
  final expires = DateTime.tryParse(preview['expiresAt']?.toString() ?? '');
  if (expires != null && expires.isBefore(DateTime.now())) {
    if (context.mounted) {
      AppToast.show(
        context,
        'Cette story n est plus disponible.',
        tone: AppToastTone.info,
      );
    }
    return;
  }
  try {
    List<Map<String, dynamic>> stories;
    try {
      stories = await ApiService.fetchTravelStories();
    } catch (_) {
      stories = await StoryCacheService.readCachedStories();
    }
    final activeStories = stories.where(_storyStillActive).toList();
    var selectedIndex = activeStories.indexWhere(
      (story) => story['id'] == storyId,
    );
    Map<String, dynamic>? directStory;
    if (selectedIndex < 0) {
      try {
        directStory = await ApiService.fetchTravelStory(storyId);
      } catch (_) {
        final cachedStories = await StoryCacheService.readCachedStories();
        final cachedIndex = cachedStories.indexWhere(
          (story) => story['id'] == storyId && _storyStillActive(story),
        );
        if (cachedIndex >= 0) directStory = cachedStories[cachedIndex];
      }
      directStory ??= {
        ...preview,
        'id': storyId,
        'authorName': preview['authorName'] ?? 'Story',
        'createdAt': preview['createdAt'] ?? DateTime.now().toIso8601String(),
      };
      if (!_storyStillActive(directStory)) {
        if (context.mounted) {
          AppToast.show(
            context,
            'Cette story n est plus disponible.',
            tone: AppToastTone.info,
          );
        }
        return;
      }
      activeStories.insert(0, directStory);
      selectedIndex = 0;
    }
    final selected = activeStories[selectedIndex];
    final authorId = (selected['authorId'] as num?)?.toInt();
    final authorStories = authorId == null
        ? <Map<String, dynamic>>[selected]
        : activeStories
              .where(
                (story) => (story['authorId'] as num?)?.toInt() == authorId,
              )
              .toList();
    for (var index = 0; index < authorStories.length; index++) {
      authorStories[index] = await _attachCachedStoryMedia(
        authorStories[index],
      );
    }
    final index = authorStories.indexWhere((story) => story['id'] == storyId);
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _TravelStoryViewer(
          stories: authorStories,
          initialIndex: index < 0 ? 0 : index,
        ),
      ),
    );
  } catch (_) {
    if (context.mounted) {
      AppToast.show(
        context,
        'Ouverture de la story impossible.',
        tone: AppToastTone.error,
      );
    }
  }
}

class _StoryReplyPreview extends StatelessWidget {
  final Map<String, dynamic> story;
  final bool mine;

  const _StoryReplyPreview({required this.story, required this.mine});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = story['mediaUrl']?.toString() ?? '';
    final video = story['mediaType']?.toString() == 'video';
    final label = story['caption']?.toString().trim();
    final expires = DateTime.tryParse(story['expiresAt']?.toString() ?? '');
    final expired = expires != null && expires.isBefore(DateTime.now());
    final content = Container(
      constraints: const BoxConstraints(minWidth: 180),
      height: 62,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: mine
            ? Colors.white.withValues(alpha: .16)
            : scheme.primary.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
        border: Border(
          left: BorderSide(
            color: mine ? scheme.onPrimary : scheme.primary,
            width: 3,
          ),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 62,
            height: 62,
            child: url.isEmpty
                ? ColoredBox(
                    color: Colors.black26,
                    child: Icon(
                      video
                          ? Icons.play_circle_fill_rounded
                          : Icons.photo_outlined,
                      color: Colors.white,
                    ),
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      if (video)
                        _InlineVideoPreview(
                          url: url,
                          muted: true,
                          showPlayButton: false,
                        )
                      else
                        Image.network(
                          url,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => ColoredBox(
                            color: Colors.black12,
                            child: Icon(
                              video
                                  ? Icons.play_circle_fill_rounded
                                  : Icons.photo_outlined,
                            ),
                          ),
                        ),
                      if (video)
                        const Center(
                          child: Icon(
                            Icons.play_circle_fill_rounded,
                            color: Colors.white,
                            size: 27,
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  expired ? 'Story expiree' : 'Reponse a une story',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: expired
                        ? (mine ? Colors.white60 : scheme.onSurfaceVariant)
                        : (mine ? scheme.onPrimary : scheme.primary),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (label?.isNotEmpty == true)
                  Text(
                    label!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: mine ? Colors.white70 : scheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
    return InkWell(
      onTap: expired
          ? null
          : () => unawaited(_openStoryReplyPreview(context, story)),
      borderRadius: BorderRadius.circular(14),
      child: content,
    );
  }
}

class _MessageReactionBar extends StatelessWidget {
  final Map<String, dynamic> reactions;
  final bool mine;
  final VoidCallback? onTap;

  const _MessageReactionBar({
    required this.reactions,
    required this.mine,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final value in reactions.values) {
      final emoji = value.toString();
      if (emoji.isEmpty) continue;
      counts[emoji] = (counts[emoji] ?? 0) + 1;
    }
    if (counts.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final content = Material(
      color: mine
          ? scheme.primaryContainer
          : Theme.of(context).brightness == Brightness.dark
          ? scheme.surfaceContainerHighest
          : Colors.white,
      elevation: Theme.of(context).brightness == Brightness.dark ? 0 : 2,
      shadowColor: const Color(0x260F172A),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final entry in counts.entries)
                Text(
                  '${entry.key} ${entry.value}',
                  style: TextStyle(
                    color: scheme.onPrimaryContainer,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    return Transform.translate(offset: const Offset(0, -5), child: content);
  }
}

class _RoundIcon extends StatelessWidget {
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;

  const _RoundIcon({
    required this.icon,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: filled ? scheme.primary : _surfacePanel(context),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(
            icon,
            color: filled ? scheme.onPrimary : scheme.primary,
            size: 21,
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final List<Map<String, dynamic>>? albumMessages;
  final String searchQuery;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onRetry;
  final VoidCallback? onInfo;
  final VoidCallback? onReply;
  final ValueChanged<Map<String, dynamic>>? onReplyQuoteTap;
  final VoidCallback? onReactionsTap;
  final VoidCallback? onGifTap;
  final VoidCallback? onStickerTap;

  const _MessageBubble({
    required this.message,
    this.albumMessages,
    this.searchQuery = '',
    required this.selected,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
    this.onRetry,
    this.onInfo,
    this.onReply,
    this.onReplyQuoteTap,
    this.onReactionsTap,
    this.onGifTap,
    this.onStickerTap,
  });

  @override
  Widget build(BuildContext context) {
    final mine = message['fromMe'] == true;
    final rawType = message['type']?.toString();
    final isVoice = rawType == 'voice';
    final isFile = rawType == 'file';
    final toolTask = (message['toolTask'] as Map?) ?? (message['task'] as Map?);
    final metadata = message['metadata'] as Map?;
    final callMeta = metadata?['call'] as Map?;
    final isSticker = metadata?['isSticker'] == true;
    final storyReply = metadata?['storyReply'] is Map
        ? Map<String, dynamic>.from(metadata?['storyReply'] as Map)
        : null;
    final reactions = metadata?['reactions'] is Map
        ? Map<String, dynamic>.from(metadata?['reactions'] as Map)
        : const <String, dynamic>{};
    final isCall = callMeta != null;
    final framelessMedia = isCall || isSticker;
    final payload =
        (metadata?['payload'] as Map?) ?? (toolTask?['payload'] as Map?) ?? {};
    final isTravelTool =
        payload['travelTool'] == true ||
        {
          'ticket',
          'tracking',
          'location',
          'live_location_update',
          'reservation_thread',
          'package_thread',
          'contact',
        }.contains(payload['kind']?.toString());
    final isTool = rawType == 'tool' || toolTask != null || isTravelTool;
    final deleted =
        message['isDeleted'] == true || message['deletedForEveryone'] == true;
    final failed = message['failed'] == true;
    final pending = message['pending'] == true;
    final read = message['isRead'] == true;
    final delivered = message['isDelivered'] == true || read;
    final scheme = Theme.of(context).colorScheme;
    final color = mine ? scheme.primary : _surfacePanel(context);
    final toolColor = Color.alphaBlend(
      scheme.primary.withValues(alpha: .10),
      _surfacePanel(context),
    );
    final textColor = framelessMedia
        ? _primaryText(context)
        : mine
        ? scheme.onPrimary
        : _primaryText(context);
    return Dismissible(
      key: ValueKey('msg-${message['id'] ?? message.hashCode}'),
      direction: deleted ? DismissDirection.none : DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onReply?.call();
        } else if (direction == DismissDirection.endToStart) {
          onInfo?.call();
        }
        return false;
      },
      background: _SwipeHint(
        alignment: Alignment.centerLeft,
        icon: Icons.reply_rounded,
        label: 'Repondre',
        color: scheme.primary,
      ),
      secondaryBackground: _SwipeHint(
        alignment: Alignment.centerRight,
        icon: Icons.info_outline_rounded,
        label: 'Infos',
        color: const Color(0xFF0EA5E9),
      ),
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: AbsorbPointer(
          absorbing: selectionMode,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            color: selected ? const Color(0x223B82F6) : Colors.transparent,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Align(
              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 310),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: mine
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    _ChatBubbleShell(
                      mine: mine,
                      frameless: framelessMedia,
                      color: isTool && !mine ? toolColor : color,
                      borderColor: selected
                          ? scheme.primary
                          : mine
                          ? scheme.primary.withValues(alpha: .10)
                          : scheme.outline.withValues(alpha: .18),
                      child: Padding(
                        padding: framelessMedia
                            ? EdgeInsets.zero
                            : const EdgeInsets.symmetric(
                                horizontal: 13,
                                vertical: 9,
                              ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (metadata?['replyTo'] is Map) ...[
                              _ReplyQuote(
                                reply: Map<String, dynamic>.from(
                                  metadata?['replyTo'] as Map,
                                ),
                                mine: mine,
                                onTap: onReplyQuoteTap,
                              ),
                              const SizedBox(height: 7),
                            ],
                            if (storyReply != null) ...[
                              _StoryReplyPreview(story: storyReply, mine: mine),
                              const SizedBox(height: 7),
                            ],
                            if (deleted)
                              Text(
                                'Message supprime',
                                style: TextStyle(
                                  color: textColor,
                                  fontStyle: FontStyle.italic,
                                ),
                              )
                            else if (isTool)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.auto_awesome,
                                        size: 15,
                                        color: textColor,
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        (message['metadata'] as Map?)?['title']
                                                ?.toString() ??
                                            'Outil',
                                        style: TextStyle(
                                          color: textColor,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (isTravelTool) ...[
                                    const SizedBox(height: 8),
                                    _TravelToolCard(
                                      payload: Map<String, dynamic>.from(
                                        payload,
                                      ),
                                      mine: mine,
                                      textColor: textColor,
                                    ),
                                  ],
                                  if (toolTask != null) ...[
                                    const SizedBox(height: 6),
                                    if (payload.isNotEmpty)
                                      Text(
                                        [
                                          if (payload['incidentType'] != null)
                                            'Type: ${payload['incidentType']}',
                                          if (payload['busLine'] != null &&
                                              payload['busLine']
                                                  .toString()
                                                  .isNotEmpty)
                                            'Bus/Ligne: ${payload['busLine']}',
                                          if (payload['severity'] != null)
                                            'Gravite: ${payload['severity']}',
                                        ].join('\\n'),
                                        style: TextStyle(
                                          color: textColor,
                                          fontSize: 12,
                                        ),
                                      ),
                                    if (payload['photoBase64'] != null &&
                                        payload['photoBase64']
                                            .toString()
                                            .isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: Image.memory(
                                          base64Decode(
                                            payload['photoBase64']
                                                .toString()
                                                .split(',')
                                                .last,
                                          ),
                                          height: 150,
                                          width: 240,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ],
                                    if (payload.isNotEmpty)
                                      const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: mine
                                            ? Colors.white.withValues(
                                                alpha: .18,
                                              )
                                            : scheme.primaryContainer
                                                  .withValues(
                                                    alpha:
                                                        Theme.of(
                                                              context,
                                                            ).brightness ==
                                                            Brightness.dark
                                                        ? .32
                                                        : 1,
                                                  ),
                                        borderRadius: BorderRadius.circular(99),
                                      ),
                                      child: Text(
                                        'Tache #${toolTask['id']} - ${toolTask['status']} - ${toolTask['priority']}',
                                        style: TextStyle(
                                          color: textColor,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    if (toolTask['actionType'] == 'incident' &&
                                        toolTask['status'] != 'done') ...[
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: [
                                          _TaskButton(
                                            taskId: toolTask['id'] as int,
                                            action: 'unlock_funds',
                                            label: 'Debloquer fonds',
                                          ),
                                          _TaskButton(
                                            taskId: toolTask['id'] as int,
                                            action: 'replacement_bus',
                                            label: 'Bus remplacement',
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ],
                              )
                            else if (isSticker)
                              _StickerMessageBubble(
                                message: message,
                                onTap: selectionMode ? onTap : onStickerTap,
                              )
                            else if (isCall)
                              _CallBubble(call: callMeta, mine: mine)
                            else if (isVoice)
                              _VoiceBubblePlayer(
                                audioUrl: message['audioUrl']?.toString(),
                                audioLocalPath: message['audioLocalPath']
                                    ?.toString(),
                                audioBase64: message['audioBase64']?.toString(),
                                duration:
                                    (((message['audioDurationSeconds']
                                                as num?) ??
                                            ((message['metadata']
                                                    as Map?)?['durationSeconds']
                                                as num?) ??
                                            1)
                                        .toInt()),
                                waveform: _waveformFromMetadata(metadata),
                                textColor: textColor,
                                mine: mine,
                                read: read,
                                onPlayed: mine || message['id'] is! int
                                    ? null
                                    : () => ApiService.chatMessageAction(
                                        messageId: message['id'] as int,
                                        action: 'read',
                                      ),
                              )
                            else if (isFile && (albumMessages?.length ?? 0) > 1)
                              _ImageAlbumBubble(
                                messages: albumMessages!,
                                textColor: textColor,
                                mine: mine,
                                selectionMode: selectionMode,
                                onSelectionTap: onTap,
                              )
                            else if (isFile)
                              _FileBubble(
                                message: message,
                                textColor: textColor,
                                mine: mine,
                                selectionMode: selectionMode,
                                onSelectionTap: onTap,
                                onGifTap: onGifTap,
                              )
                            else
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (metadata?['linkPreview'] is Map) ...[
                                    _LinkPreviewCard(
                                      preview: Map<String, dynamic>.from(
                                        metadata?['linkPreview'] as Map,
                                      ),
                                      mine: mine,
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                  _SmartMessageText(
                                    body: message['body'].toString(),
                                    color: textColor,
                                    linkColor: mine
                                        ? Colors.white
                                        : Theme.of(context).colorScheme.primary,
                                    selectable: !selectionMode,
                                    highlight: searchQuery,
                                  ),
                                ],
                              ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (message['isImportant'] == true)
                                  Icon(
                                    Icons.star,
                                    size: 13,
                                    color: mine
                                        ? Colors.amber.shade100
                                        : Colors.amber,
                                  ),
                                if (message['isImportant'] == true)
                                  const SizedBox(width: 4),
                                if (mine) ...[
                                  Icon(
                                    failed
                                        ? Icons.error_outline
                                        : pending
                                        ? Icons.schedule
                                        : read || delivered
                                        ? Icons.done_all
                                        : Icons.done,
                                    size: 13,
                                    color: failed
                                        ? Colors.redAccent
                                        : read
                                        ? const Color(0xFF7DD3FC)
                                        : mine && !framelessMedia
                                        ? Colors.white70
                                        : scheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Text(
                                  failed
                                      ? (message['errorText']?.toString() ??
                                            'non envoye')
                                      : pending
                                      ? 'envoi...'
                                      : _time(message['createdAt'] as String?),
                                  style: TextStyle(
                                    color: failed
                                        ? Colors.redAccent
                                        : mine && !framelessMedia
                                        ? Colors.white70
                                        : Colors.blueGrey,
                                    fontSize: 10,
                                    fontWeight: failed
                                        ? FontWeight.w800
                                        : FontWeight.w400,
                                  ),
                                ),
                                if (failed && onRetry != null) ...[
                                  const SizedBox(width: 6),
                                  InkWell(
                                    onTap: onRetry,
                                    borderRadius: BorderRadius.circular(999),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: mine
                                            ? Colors.white
                                            : const Color(0xFFFFE2E2),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: const Text(
                                        'Envoyer',
                                        style: TextStyle(
                                          color: Colors.redAccent,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (!deleted && reactions.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      _MessageReactionBar(
                        reactions: reactions,
                        mine: mine,
                        onTap: onReactionsTap,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatBubbleShell extends StatelessWidget {
  final bool mine;
  final bool frameless;
  final Color color;
  final Color borderColor;
  final Widget child;

  const _ChatBubbleShell({
    required this.mine,
    required this.frameless,
    required this.color,
    required this.borderColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (frameless) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: 0,
          left: mine ? null : -5,
          right: mine ? -5 : null,
          child: CustomPaint(
            size: const Size(11, 14),
            painter: _ChatBubbleTailPainter(
              color: color,
              borderColor: borderColor,
              mine: mine,
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(mine ? 18 : 5),
              topRight: Radius.circular(mine ? 5 : 18),
              bottomLeft: const Radius.circular(18),
              bottomRight: const Radius.circular(18),
            ),
            border: Border.all(color: borderColor),
          ),
          child: child,
        ),
      ],
    );
  }
}

class _ChatBubbleTailPainter extends CustomPainter {
  final Color color;
  final Color borderColor;
  final bool mine;

  const _ChatBubbleTailPainter({
    required this.color,
    required this.borderColor,
    required this.mine,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    if (mine) {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..quadraticBezierTo(
          size.width * .86,
          size.height * .30,
          size.width * .42,
          size.height * .58,
        )
        ..lineTo(0, size.height);
    } else {
      path
        ..moveTo(size.width, 0)
        ..lineTo(0, 0)
        ..quadraticBezierTo(
          size.width * .14,
          size.height * .30,
          size.width * .58,
          size.height * .58,
        )
        ..lineTo(size.width, size.height);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _ChatBubbleTailPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.borderColor != borderColor ||
      oldDelegate.mine != mine;
}

class _SwipeHint extends StatelessWidget {
  final Alignment alignment;
  final IconData icon;
  final String label;
  final Color color;

  const _SwipeHint({
    required this.alignment,
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final left = alignment == Alignment.centerLeft;
    return Container(
      alignment: alignment,
      padding: EdgeInsets.only(left: left ? 18 : 0, right: left ? 0 : 18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: .22)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageInfoScreen extends StatelessWidget {
  final Map<String, dynamic> message;
  final String otherName;

  const _MessageInfoScreen({required this.message, required this.otherName});

  Map<String, dynamic> get _metadata =>
      Map<String, dynamic>.from((message['metadata'] as Map?) ?? const {});

  String get _preview {
    if (message['type'] == 'voice') return 'Message vocal';
    if (message['type'] == 'file') {
      return message['attachmentName']?.toString().isNotEmpty == true
          ? message['attachmentName'].toString()
          : (message['body']?.toString() ?? 'Media');
    }
    final body = message['body']?.toString().trim() ?? '';
    return body.isEmpty ? 'Message' : body;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final metadata = _metadata;
    final createdAt = message['createdAt']?.toString();
    final deliveredAt =
        message['deliveredAt']?.toString() ??
        metadata['deliveredAt']?.toString();
    final readAt = metadata['readAt']?.toString();
    final isRead = message['isRead'] == true || (readAt ?? '').isNotEmpty;
    final isDelivered =
        message['isDelivered'] == true || (deliveredAt ?? '').isNotEmpty;
    final isVoice = message['type'] == 'voice';
    final title = isVoice ? 'Infos vocal' : 'Infos message';
    return Scaffold(
      backgroundColor: _screenBg(context),
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                scheme.primary.withValues(alpha: .10),
                _surfacePanel(context),
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: scheme.primary.withValues(alpha: .16)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                      child: Icon(
                        isVoice
                            ? Icons.graphic_eq_rounded
                            : message['type'] == 'file'
                            ? Icons.attach_file_rounded
                            : Icons.chat_bubble_rounded,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            otherName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _primaryText(context),
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            'Destinataire',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  _preview,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _primaryText(context),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _InfoStatusTile(
            icon: Icons.done_rounded,
            title: 'Envoye',
            detail: _dateTimeLabel(createdAt),
            active: true,
            tone: scheme.primary,
          ),
          _InfoStatusTile(
            icon: Icons.done_all_rounded,
            title: 'Recu sur un appareil',
            detail: isDelivered
                ? _dateTimeLabel(deliveredAt)
                : 'Pas encore confirme',
            active: isDelivered,
            tone: const Color(0xFF0EA5E9),
          ),
          _InfoStatusTile(
            icon: isVoice
                ? Icons.headphones_rounded
                : Icons.mark_chat_read_rounded,
            title: isVoice ? 'Ecoute' : 'Lu',
            detail: isRead ? _dateTimeLabel(readAt) : 'Pas encore consulte',
            active: isRead,
            tone: const Color(0xFF10B981),
          ),
          const SizedBox(height: 12),
          Text(
            'Les confirmations sont mises a jour en temps reel quand le destinataire recoit, ouvre ou lit le message.',
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoStatusTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final bool active;
  final Color tone;

  const _InfoStatusTile({
    required this.icon,
    required this.title,
    required this.detail,
    required this.active,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surfacePanel(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: active
              ? tone.withValues(alpha: .35)
              : scheme.outline.withValues(alpha: .16),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: active
                  ? tone.withValues(alpha: .14)
                  : scheme.surfaceContainerHighest.withValues(alpha: .45),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: active ? tone : scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: _primaryText(context),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CallBubble extends StatelessWidget {
  final Map call;
  final bool mine;

  const _CallBubble({required this.call, required this.mine});

  String _duration(num? seconds) {
    final value = (seconds ?? 0).toInt().clamp(0, 24 * 60 * 60).toInt();
    final minutes = value ~/ 60;
    final remaining = value % 60;
    return '$minutes:${remaining.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = (call['status'] ?? '').toString().toLowerCase();
    final seconds = call['durationSeconds'] is num
        ? call['durationSeconds'] as num
        : num.tryParse(call['durationSeconds']?.toString() ?? '') ?? 0;
    final bool service = call['service'] == true;
    late final IconData icon;
    late final String title;
    late final String detail;
    late final Color tone;
    if (status == 'answered') {
      icon = Icons.phone_in_talk_rounded;
      title = 'Appel decroche';
      detail = 'Duree ${_duration(seconds)}';
      tone = const Color(0xFF059669);
    } else if (status == 'accepted') {
      icon = Icons.phone_in_talk_rounded;
      title = 'Appel en cours';
      detail = 'Connexion active';
      tone = const Color(0xFF059669);
    } else if (status == 'rejected') {
      icon = Icons.call_end_rounded;
      title = 'Appel refuse';
      detail = 'Refuse par le destinataire';
      tone = const Color(0xFFD97706);
    } else if (status == 'missed') {
      icon = Icons.phone_missed_rounded;
      title = 'Appel non decroche';
      detail = 'Aucune reponse';
      tone = const Color(0xFFE11D48);
    } else {
      icon = Icons.call_rounded;
      title = 'Appel lance';
      detail = 'En attente de reponse';
      tone = const Color(0xFF0284C7);
    }
    final surface = Color.alphaBlend(
      tone.withValues(
        alpha: Theme.of(context).brightness == Brightness.dark ? .22 : .13,
      ),
      _surfacePanel(context),
    );
    final textColor = _primaryText(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 215),
      padding: const EdgeInsets.fromLTRB(12, 11, 14, 11),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(mine ? 20 : 7),
          bottomRight: Radius.circular(mine ? 7 : 20),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: .14),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: tone, size: 22),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${mine ? 'Sortant' : 'Entrant'}${service ? ' service' : ''} - $detail',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StickerMessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final VoidCallback? onTap;

  const _StickerMessageBubble({required this.message, this.onTap});

  @override
  Widget build(BuildContext context) {
    final metadata = Map<String, dynamic>.from(
      (message['metadata'] as Map?) ?? const {},
    );
    final kind = metadata['stickerKind']?.toString() ?? 'image';
    Widget child;
    if (kind == 'emoji') {
      child = _AnimatedEmojiText(
        text:
            metadata['stickerEmoji']?.toString() ??
            message['body']?.toString() ??
            '',
        fontSize: 94,
        animate: true,
      );
    } else {
      final path = message['attachmentLocalPath']?.toString() ?? '';
      final rawUrl = message['attachmentUrl']?.toString() ?? '';
      final url = rawUrl.isEmpty
          ? ''
          : rawUrl.startsWith('http')
          ? rawUrl
          : '${ApiService.baseUrl.replaceFirst('/api', '')}$rawUrl';
      final encoded = message['attachmentBase64']?.toString() ?? '';
      Uint8List? bytes;
      if (encoded.isNotEmpty) {
        try {
          bytes = base64Decode(encoded.split(',').last);
        } catch (_) {}
      }
      final mime = (message['attachmentType'] ?? metadata['mimeType'] ?? '')
          .toString();
      final video = kind == 'video' || mime.startsWith('video/');
      if (video) {
        child = _InlineVideoPreview(
          url: url,
          bytes: bytes,
          localPath: path.isEmpty ? null : path,
          muted: true,
          showPlayButton: false,
          autoplay: true,
          loop: true,
        );
      } else if (path.isNotEmpty && File(path).existsSync()) {
        child = Image.file(File(path), fit: BoxFit.contain);
      } else if (bytes != null) {
        child = Image.memory(bytes, fit: BoxFit.contain);
      } else {
        child = Image.network(
          url,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Icon(
            Icons.sticky_note_2_rounded,
            color: Colors.white70,
            size: 62,
          ),
        );
      }
    }
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(width: 170, height: 170, child: child),
    );
  }
}

class _FileBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final Color textColor;
  final bool mine;
  final bool selectionMode;
  final VoidCallback? onSelectionTap;
  final VoidCallback? onGifTap;

  const _FileBubble({
    required this.message,
    required this.textColor,
    required this.mine,
    this.selectionMode = false,
    this.onSelectionTap,
    this.onGifTap,
  });

  String get _url {
    final value = message['attachmentUrl']?.toString() ?? '';
    if (value.isEmpty) return '';
    if (value.startsWith('http')) return value;
    return '${ApiService.baseUrl.replaceFirst('/api', '')}$value';
  }

  String get _base64 =>
      message['attachmentBase64']?.toString() ??
      message['fileBase64']?.toString() ??
      '';

  String get _localPath => message['attachmentLocalPath']?.toString() ?? '';

  File? get _localFile {
    if (_localPath.isEmpty) return null;
    final file = File(_localPath);
    return file.existsSync() ? file : null;
  }

  Uint8List? get _localBytes {
    final file = _localFile;
    if (file != null && !_isVideo) {
      try {
        return file.readAsBytesSync();
      } catch (_) {}
    }
    if (_base64.isEmpty) return null;
    try {
      return base64Decode(_base64.split(',').last);
    } catch (_) {
      return null;
    }
  }

  String get _name => message['attachmentName']?.toString().isNotEmpty == true
      ? message['attachmentName'].toString()
      : message['body'].toString();

  String get _caption {
    final metadata = message['metadata'] as Map?;
    final value = metadata?['caption']?.toString() ?? '';
    return value.trim();
  }

  String get _type => message['attachmentType']?.toString() ?? '';

  bool get _isImage =>
      _type.startsWith('image/') ||
      RegExp(
        r'\.(png|jpe?g|webp|gif)(\?|$)',
        caseSensitive: false,
      ).hasMatch(_url) ||
      RegExp(r'\.(png|jpe?g|webp|gif)$', caseSensitive: false).hasMatch(_name);
  bool get _isGif =>
      _type.toLowerCase() == 'image/gif' ||
      RegExp(r'\.gif(\?|$)', caseSensitive: false).hasMatch(_url) ||
      RegExp(r'\.gif$', caseSensitive: false).hasMatch(_name);
  bool get _isVideo =>
      _type.startsWith('video/') ||
      RegExp(
        r'\.(mp4|mov|m4v|webm)(\?|$)',
        caseSensitive: false,
      ).hasMatch(_url) ||
      RegExp(r'\.(mp4|mov|m4v|webm)$', caseSensitive: false).hasMatch(_name);
  bool get _isPdf =>
      _type.contains('pdf') ||
      RegExp(r'\.pdf(\?|$)', caseSensitive: false).hasMatch(_url) ||
      RegExp(r'\.pdf$', caseSensitive: false).hasMatch(_name);

  Future<void> _open(BuildContext context) async {
    if (_url.isEmpty && _localBytes == null && _localFile == null) return;
    await showDialog(
      context: context,
      builder: (_) => _AttachmentPreviewDialog(
        url: _url,
        bytes: _localBytes,
        localPath: _localFile?.path,
        name: _name,
        isImage: _isImage,
        isVideo: _isVideo,
        isPdf: _isPdf,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localBytes = _localBytes;
    final localFile = _localFile;
    if (_isVideo &&
        (_url.isNotEmpty || localFile != null || localBytes != null)) {
      return InkWell(
        onTap: selectionMode ? onSelectionTap : () => _open(context),
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 178,
                width: 246,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: Colors.black,
                      child: _InlineVideoPreview(
                        url: _url,
                        bytes: localBytes,
                        localPath: localFile?.path,
                        muted: true,
                        showPlayButton: false,
                      ),
                    ),
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .58),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 17,
                            ),
                            SizedBox(width: 3),
                            Text(
                              'Video',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_caption.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(_caption, style: TextStyle(color: textColor)),
            ],
          ],
        ),
      );
    }
    if (_isImage &&
        (_url.isNotEmpty || localBytes != null || localFile != null)) {
      return InkWell(
        onTap: selectionMode
            ? onSelectionTap
            : _isGif && onGifTap != null
            ? onGifTap
            : () => _open(context),
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(_isGif ? 16 : 12),
              child: localBytes != null
                  ? Image.memory(
                      localBytes,
                      height: _isGif ? 190 : 170,
                      width: _isGif ? 250 : 240,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    )
                  : localFile != null
                  ? Image.file(
                      localFile,
                      height: _isGif ? 190 : 170,
                      width: _isGif ? 250 : 240,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    )
                  : Image.network(
                      _url,
                      height: _isGif ? 190 : 170,
                      width: _isGif ? 250 : 240,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
            ),
            if (!_isGif) ...[
              const SizedBox(height: 6),
              Text(
                _name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
              ),
            ],
            if (_caption.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(_caption, style: TextStyle(color: textColor)),
            ],
          ],
        ),
      );
    }
    return InkWell(
      onTap: selectionMode ? onSelectionTap : () => _open(context),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        constraints: const BoxConstraints(minWidth: 210),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: mine
              ? Colors.white.withValues(alpha: .16)
              : Color.alphaBlend(
                  Theme.of(context).colorScheme.primary.withValues(alpha: .09),
                  _surfacePanel(context),
                ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: .12),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isPdf
                  ? Icons.picture_as_pdf
                  : _isVideo
                  ? Icons.play_circle_outline
                  : Icons.insert_drive_file,
              color: textColor,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    appTC(context, 'preview'),
                    style: TextStyle(
                      color: textColor.withValues(alpha: .75),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageAlbumBubble extends StatelessWidget {
  final List<Map<String, dynamic>> messages;
  final Color textColor;
  final bool mine;
  final bool selectionMode;
  final VoidCallback? onSelectionTap;

  const _ImageAlbumBubble({
    required this.messages,
    required this.textColor,
    required this.mine,
    this.selectionMode = false,
    this.onSelectionTap,
  });

  String _url(Map<String, dynamic> message) {
    final value = message['attachmentUrl']?.toString() ?? '';
    if (value.isEmpty) return '';
    if (value.startsWith('http')) return value;
    return '${ApiService.baseUrl.replaceFirst('/api', '')}$value';
  }

  Uint8List? _bytes(Map<String, dynamic> message) {
    final base64Value =
        message['attachmentBase64']?.toString() ??
        message['fileBase64']?.toString() ??
        '';
    if (base64Value.isNotEmpty) {
      try {
        return base64Decode(base64Value.split(',').last);
      } catch (_) {}
    }
    final path = message['attachmentLocalPath']?.toString() ?? '';
    if (path.isNotEmpty && File(path).existsSync()) {
      try {
        return File(path).readAsBytesSync();
      } catch (_) {}
    }
    return null;
  }

  Widget _thumb(BuildContext context, Map<String, dynamic> message, int index) {
    final url = _url(message);
    final bytes = _bytes(message);
    final remaining = messages.length - 4;
    final showMore = index == 3 && remaining > 0;
    return InkWell(
      onTap: selectionMode ? onSelectionTap : () => _openAlbum(context, index),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: bytes != null
                ? Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true)
                : Image.network(url, fit: BoxFit.cover, gaplessPlayback: true),
          ),
          if (showMore)
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .56),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Center(
                child: Text(
                  '+$remaining',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 24,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _openAlbum(BuildContext context, int startIndex) {
    showDialog(
      context: context,
      builder: (_) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: SafeArea(
          child: GestureDetector(
            onVerticalDragEnd: (details) {
              if ((details.primaryVelocity ?? 0) > 420) {
                Navigator.pop(context);
              }
            },
            child: PageView.builder(
              controller: PageController(initialPage: startIndex),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final bytes = _bytes(messages[index]);
                final url = _url(messages[index]);
                return Stack(
                  children: [
                    Center(
                      child: InteractiveViewer(
                        minScale: .8,
                        maxScale: 4,
                        child: bytes != null
                            ? Image.memory(
                                bytes,
                                fit: BoxFit.contain,
                                gaplessPlayback: true,
                              )
                            : Image.network(
                                url,
                                fit: BoxFit.contain,
                                gaplessPlayback: true,
                              ),
                      ),
                    ),
                    Positioned(
                      left: 8,
                      right: 8,
                      top: 6,
                      child: Row(
                        children: [
                          IconButton(
                            color: Colors.white,
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded),
                          ),
                          Expanded(
                            child: Text(
                              '${index + 1}/${messages.length}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          IconButton(
                            color: Colors.white,
                            tooltip: 'Telecharger',
                            onPressed: () => _saveMediaToDevice(
                              context,
                              name:
                                  messages[index]['attachmentName']
                                      ?.toString() ??
                                  'photo-${index + 1}.jpg',
                              url: url,
                              bytes: bytes,
                              localPath: messages[index]['attachmentLocalPath']
                                  ?.toString(),
                            ),
                            icon: const Icon(Icons.download_rounded),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shown = messages.take(4).toList();
    final caption = messages
        .map(
          (item) => ((item['metadata'] as Map?)?['caption'] ?? '').toString(),
        )
        .firstWhere((value) => value.trim().isNotEmpty, orElse: () => '');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 246,
          height: messages.length == 2 ? 126 : 246,
          child: GridView.count(
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: messages.length == 2 ? 2 : 2,
            mainAxisSpacing: 5,
            crossAxisSpacing: 5,
            childAspectRatio: messages.length == 2 ? .86 : 1,
            children: [
              for (var i = 0; i < shown.length; i++)
                _thumb(context, shown[i], i),
            ],
          ),
        ),
        if (caption.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(caption.trim(), style: TextStyle(color: textColor)),
        ],
      ],
    );
  }
}

class _AttachmentPreviewDialog extends StatelessWidget {
  final String url;
  final Uint8List? bytes;
  final String? localPath;
  final String name;
  final bool isImage;
  final bool isVideo;
  final bool isPdf;

  const _AttachmentPreviewDialog({
    required this.url,
    required this.bytes,
    required this.localPath,
    required this.name,
    required this.isImage,
    required this.isVideo,
    required this.isPdf,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: SafeArea(
        child: GestureDetector(
          onVerticalDragEnd: (details) {
            if ((details.primaryVelocity ?? 0) > 420) {
              Navigator.pop(context);
            }
          },
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    IconButton(
                      color: Colors.white,
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      color: Colors.white,
                      tooltip: 'Telecharger',
                      onPressed: () => _saveMediaToDevice(
                        context,
                        name: name,
                        url: url,
                        bytes: bytes,
                        localPath: localPath,
                      ),
                      icon: const Icon(Icons.download_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(child: _buildContent()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (isImage) {
      return InteractiveViewer(
        minScale: .8,
        maxScale: 4,
        child: Center(
          child: bytes != null
              ? Image.memory(bytes!, fit: BoxFit.contain)
              : localPath != null && File(localPath!).existsSync()
              ? Image.file(File(localPath!), fit: BoxFit.contain)
              : Image.network(url, fit: BoxFit.contain),
        ),
      );
    }
    if (isVideo) {
      return _VideoAttachmentViewer(
        url: url,
        bytes: bytes,
        localPath: localPath,
      );
    }
    if (isPdf) {
      return PdfPreview(
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
        allowPrinting: false,
        allowSharing: false,
        build: (_) async {
          if (bytes != null) return bytes!;
          final path = localPath;
          if (path != null && File(path).existsSync()) {
            return File(path).readAsBytes();
          }
          return (await http.get(Uri.parse(url))).bodyBytes;
        },
      );
    }
    return Center(
      child: FilledButton.icon(
        onPressed: () =>
            launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        icon: const Icon(Icons.open_in_new),
        label: const Text('Ouvrir ce fichier'),
      ),
    );
  }
}

class _GalleryMediaItem {
  final String uri;
  final String name;
  final String mime;
  final bool isVideo;
  final int size;
  final int durationMs;
  final Uint8List? thumbnail;
  final String album;
  final bool favorite;

  const _GalleryMediaItem({
    required this.uri,
    required this.name,
    required this.mime,
    required this.isVideo,
    required this.size,
    required this.durationMs,
    this.thumbnail,
    this.album = 'Galerie',
    this.favorite = false,
  });

  factory _GalleryMediaItem.fromNative(Map<dynamic, dynamic> item) {
    final thumbnail = item['thumbnail'];
    return _GalleryMediaItem(
      uri: item['uri']?.toString() ?? '',
      name: item['name']?.toString() ?? '',
      mime: item['mime']?.toString() ?? '',
      isVideo: item['isVideo'] == true,
      size: (item['size'] as num?)?.toInt() ?? 0,
      durationMs: (item['durationMs'] as num?)?.toInt() ?? 0,
      thumbnail: thumbnail is Uint8List ? thumbnail : null,
      album: item['album']?.toString().trim().isNotEmpty == true
          ? item['album'].toString()
          : 'Galerie',
      favorite: item['favorite'] == true,
    );
  }
}

class _CustomMediaGalleryScreen extends StatefulWidget {
  final List<_GalleryMediaItem> items;
  final bool multiSelect;
  final String title;

  const _CustomMediaGalleryScreen({
    required this.items,
    required this.multiSelect,
    required this.title,
  });

  @override
  State<_CustomMediaGalleryScreen> createState() =>
      _CustomMediaGalleryScreenState();
}

class _CustomMediaGalleryScreenState extends State<_CustomMediaGalleryScreen> {
  final TextEditingController _searchController = TextEditingController();
  final Set<int> _selected = {};
  String _query = '';
  String _album = 'Recents';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<_GalleryMediaItem> get _filtered {
    final q = _query.trim().toLowerCase();
    return widget.items.where((item) {
      final albumMatches =
          _album == 'Recents' ||
          (_album == 'Favoris' ? item.favorite : item.album == _album);
      if (!albumMatches) return false;
      return q.isEmpty ||
          item.name.toLowerCase().contains(q) ||
          item.mime.toLowerCase().contains(q) ||
          item.album.toLowerCase().contains(q);
    }).toList();
  }

  List<String> get _albums {
    final values =
        widget.items
            .map((item) => item.album)
            .where((value) => value.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort(
            (left, right) => left.toLowerCase().compareTo(right.toLowerCase()),
          );
    return ['Recents', 'Favoris', ...values];
  }

  void _toggle(_GalleryMediaItem item) {
    final index = widget.items.indexOf(item);
    if (index < 0) return;
    setState(() {
      if (widget.multiSelect) {
        if (!_selected.remove(index)) _selected.add(index);
      } else {
        _selected
          ..clear()
          ..add(index);
      }
    });
  }

  void _submit() {
    if (_selected.isEmpty) return;
    Navigator.pop(
      context,
      _selected
          .map((index) => widget.items[index])
          .where((item) => item.uri.isNotEmpty)
          .toList(),
    );
  }

  String _duration(int milliseconds) {
    final seconds = (milliseconds / 1000).round();
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return '$minutes:${rest.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final items = _filtered;
    return Scaffold(
      backgroundColor: dark ? const Color(0xFF070B11) : Colors.white,
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: FilledButton.icon(
              onPressed: _selected.isEmpty ? null : _submit,
              icon: const Icon(Icons.check_rounded),
              label: Text(
                _selected.isEmpty ? 'Choisir' : '${_selected.length}',
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: 'Rechercher dans la galerie',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: dark
                      ? Colors.white.withValues(alpha: .08)
                      : Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide(
                      color: scheme.outline.withValues(alpha: .12),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide(
                      color: scheme.outline.withValues(alpha: .12),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                itemCount: _albums.length,
                separatorBuilder: (_, __) => const SizedBox(width: 7),
                itemBuilder: (context, index) {
                  final album = _albums[index];
                  final selected = album == _album;
                  return FilterChip(
                    selected: selected,
                    showCheckmark: false,
                    avatar: Icon(
                      album == 'Recents'
                          ? Icons.schedule_rounded
                          : album == 'Favoris'
                          ? Icons.favorite_rounded
                          : Icons.photo_album_rounded,
                      size: 16,
                      color: selected ? scheme.onPrimary : scheme.primary,
                    ),
                    label: Text(album),
                    labelStyle: TextStyle(
                      color: selected ? scheme.onPrimary : scheme.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                    selectedColor: scheme.primary,
                    backgroundColor: scheme.surfaceContainerHighest.withValues(
                      alpha: .5,
                    ),
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                    onSelected: (_) => setState(() => _album = album),
                  );
                },
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final sourceIndex = widget.items.indexOf(item);
                  final selected = _selected.contains(sourceIndex);
                  return InkWell(
                    onTap: () => _toggle(item),
                    borderRadius: BorderRadius.circular(18),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: selected
                                  ? scheme.primary
                                  : scheme.outline.withValues(alpha: .10),
                              width: selected ? 3 : 1,
                            ),
                            color: dark
                                ? Colors.white.withValues(alpha: .06)
                                : Colors.white,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: item.thumbnail == null
                              ? Icon(
                                  item.isVideo
                                      ? Icons.movie_rounded
                                      : Icons.image_rounded,
                                  color: scheme.primary,
                                  size: 34,
                                )
                              : Image.memory(
                                  item.thumbnail!,
                                  fit: BoxFit.cover,
                                ),
                        ),
                        if (item.isVideo)
                          Positioned(
                            left: 8,
                            bottom: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: .62),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.play_arrow_rounded,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                  if (item.durationMs > 0) ...[
                                    const SizedBox(width: 2),
                                    Text(
                                      _duration(item.durationMs),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        Positioned(
                          right: 8,
                          top: 8,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: selected
                                  ? scheme.primary
                                  : Colors.black.withValues(alpha: .38),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: selected
                                ? Icon(
                                    Icons.check_rounded,
                                    color: scheme.onPrimary,
                                    size: 17,
                                  )
                                : null,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreparedAttachment {
  final Uint8List bytes;
  final String name;
  final String mime;
  final String? localPath;
  final String caption;
  final Map<String, dynamic> metadata;

  const _PreparedAttachment({
    required this.bytes,
    required this.name,
    required this.mime,
    required this.localPath,
    required this.caption,
    this.metadata = const {},
  });
}

class _PickedAttachment {
  final Uint8List bytes;
  final String name;
  final String mime;
  final String? localPath;

  const _PickedAttachment({
    required this.bytes,
    required this.name,
    required this.mime,
    this.localPath,
  });

  _PreparedAttachment toPrepared() => _PreparedAttachment(
    bytes: bytes,
    name: name,
    mime: mime,
    localPath: localPath,
    caption: '',
  );
}

class _MediaBatchPreparationScreen extends StatefulWidget {
  final List<_PickedAttachment> items;

  const _MediaBatchPreparationScreen({required this.items});

  @override
  State<_MediaBatchPreparationScreen> createState() =>
      _MediaBatchPreparationScreenState();
}

class _MediaBatchPreparationScreenState
    extends State<_MediaBatchPreparationScreen> {
  late final List<_PreparedAttachment> _prepared = widget.items
      .map((item) => item.toPrepared())
      .toList();
  late final List<TextEditingController> _captions = widget.items
      .map((_) => TextEditingController())
      .toList();
  int _index = 0;
  bool _sending = false;

  @override
  void dispose() {
    for (final controller in _captions) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _editCurrent() async {
    final item = _prepared[_index];
    final edited = await Navigator.push<_PreparedAttachment>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _MediaPreparationScreen(
          bytes: item.bytes,
          name: item.name,
          mime: item.mime,
          localPath: item.localPath,
          batchEdit: true,
        ),
      ),
    );
    if (!mounted || edited == null) return;
    setState(() {
      _prepared[_index] = edited;
      if (edited.caption.trim().isNotEmpty) {
        _captions[_index].text = edited.caption;
      }
    });
  }

  void _submit() {
    if (_sending) return;
    setState(() => _sending = true);
    final result = <_PreparedAttachment>[];
    for (var i = 0; i < _prepared.length; i++) {
      final item = _prepared[i];
      result.add(
        _PreparedAttachment(
          bytes: item.bytes,
          name: item.name,
          mime: item.mime,
          localPath: item.localPath,
          caption: _captions[i].text,
          metadata: item.metadata,
        ),
      );
    }
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = dark ? Colors.white : const Color(0xFF0F172A);
    return Scaffold(
      backgroundColor: dark ? Colors.black : Colors.white,
      appBar: AppBar(
        title: Text('${_index + 1}/${_prepared.length} medias'),
        actions: [
          TextButton.icon(
            onPressed: _sending ? null : _submit,
            icon: _sending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded),
            label: const Text('Envoyer tout'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 86,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                scrollDirection: Axis.horizontal,
                itemBuilder: (context, i) {
                  final selected = i == _index;
                  return InkWell(
                    onTap: () => setState(() => _index = i),
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 70,
                          height: 70,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: selected
                                  ? scheme.primary
                                  : scheme.outline.withValues(alpha: .18),
                              width: selected ? 3 : 1,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(13),
                            child: Image.memory(
                              _prepared[i].bytes,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        if (selected)
                          Positioned(
                            right: 5,
                            top: 5,
                            child: CircleAvatar(
                              radius: 11,
                              backgroundColor: scheme.primary,
                              child: Icon(
                                Icons.check_rounded,
                                size: 14,
                                color: scheme.onPrimary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemCount: _prepared.length,
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(26),
                    child: Image.memory(
                      _prepared[_index].bytes,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Row(
                children: [
                  FilledButton.icon(
                    onPressed: _editCurrent,
                    icon: const Icon(Icons.tune_rounded),
                    label: const Text('Modifier'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _captions[_index],
                      style: TextStyle(color: fg),
                      decoration: InputDecoration(
                        hintText: 'Legende',
                        filled: true,
                        fillColor: dark
                            ? Colors.white.withValues(alpha: .10)
                            : Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawStroke {
  final List<Offset> points;
  final Color color;
  final double width;

  const _DrawStroke({
    required this.points,
    required this.color,
    required this.width,
  });
}

class _MediaPreparationScreen extends StatefulWidget {
  final Uint8List bytes;
  final String name;
  final String mime;
  final String? localPath;
  final bool batchEdit;

  const _MediaPreparationScreen({
    required this.bytes,
    required this.name,
    required this.mime,
    required this.localPath,
    this.batchEdit = false,
  });

  @override
  State<_MediaPreparationScreen> createState() =>
      _MediaPreparationScreenState();
}

class _MediaPreparationScreenState extends State<_MediaPreparationScreen> {
  final TextEditingController _captionController = TextEditingController();
  final List<_DrawStroke> _strokes = [];
  int _turns = 0;
  String _filter = 'original';
  String? _activeTool;
  bool _drawMode = false;
  bool _videoMuted = false;
  Color _drawColor = Colors.white;
  double _drawWidth = 7;
  double _videoStart = 0;
  double _videoEnd = 1;
  Rect _cropRect = const Rect.fromLTWH(0, 0, 1, 1);
  bool _sending = false;
  Size? _imageSize;

  bool get _isImage => widget.mime.startsWith('image/');
  bool get _isVideo => widget.mime.startsWith('video/');
  bool get _isPdf => widget.mime.contains('pdf');

  Color _editorBg(BuildContext context) => Colors.black;

  Color _editorFg(BuildContext context) => Colors.white;

  Color _editorPanel(BuildContext context) =>
      Colors.black.withValues(alpha: .74);

  @override
  void initState() {
    super.initState();
    if (_isImage) {
      final decoded = img.decodeImage(widget.bytes);
      if (decoded != null) {
        _imageSize = Size(decoded.width.toDouble(), decoded.height.toDouble());
      }
    }
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  String _title(BuildContext context) {
    if (_isImage) return appTC(context, 'photoEditor');
    if (_isVideo) return appTC(context, 'videoPreview');
    if (_isPdf) return appTC(context, 'pdfPreview');
    return appTC(context, 'mediaEditor');
  }

  String _filterLabel(BuildContext context, String value) {
    return switch (value) {
      'mono' => appTC(context, 'blackWhite'),
      'warm' => appTC(context, 'warmFilter'),
      'bright' => appTC(context, 'brightFilter'),
      _ => appTC(context, 'reset'),
    };
  }

  Widget _filterPreview(Widget child) {
    return switch (_filter) {
      'mono' => ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          .2126,
          .7152,
          .0722,
          0,
          0,
          .2126,
          .7152,
          .0722,
          0,
          0,
          .2126,
          .7152,
          .0722,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ]),
        child: child,
      ),
      'warm' => ColorFiltered(
        colorFilter: ColorFilter.mode(
          Colors.orange.withValues(alpha: .16),
          BlendMode.softLight,
        ),
        child: child,
      ),
      'bright' => ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          1.08,
          0,
          0,
          0,
          8,
          0,
          1.08,
          0,
          0,
          8,
          0,
          0,
          1.08,
          0,
          8,
          0,
          0,
          0,
          1,
          0,
        ]),
        child: child,
      ),
      _ => child,
    };
  }

  Offset _normalPoint(Offset local, Size size) => Offset(
    (local.dx / size.width).clamp(0.0, 1.0),
    (local.dy / size.height).clamp(0.0, 1.0),
  );

  void _startStroke(DragStartDetails details, Size size) {
    if (!_drawMode) return;
    setState(() {
      _strokes.add(
        _DrawStroke(
          points: [_normalPoint(details.localPosition, size)],
          color: _drawColor,
          width: _drawWidth,
        ),
      );
    });
  }

  void _appendStroke(DragUpdateDetails details, Size size) {
    if (!_drawMode || _strokes.isEmpty) return;
    setState(() {
      _strokes.last.points.add(_normalPoint(details.localPosition, size));
    });
  }

  double get _imageAspect {
    final size = _imageSize;
    if (size == null || size.height == 0) return 1;
    final rotated = (_turns % 2) != 0;
    return rotated ? size.height / size.width : size.width / size.height;
  }

  // Every outgoing video is normalised once. This keeps albums and stories
  // predictable on low-bandwidth routes instead of sending the raw gallery
  // file when the user did not trim it.
  bool get _videoNeedsTranscode => _isVideo;

  bool get _cropChanged =>
      _cropRect.left > .001 ||
      _cropRect.top > .001 ||
      _cropRect.right < .999 ||
      _cropRect.bottom < .999;

  Future<double> _probeVideoDurationSeconds(String inputPath) async {
    final session = await FFprobeKit.getMediaInformation(inputPath);
    final information = session.getMediaInformation();
    final raw = information?.getDuration();
    final duration = double.tryParse(raw ?? '') ?? 0;
    if (duration > 0) return duration;
    final output = await session.getOutput();
    final parsed = RegExp(
      r'"duration"\s*:\s*"([^"]+)"',
    ).firstMatch(output ?? '')?.group(1);
    return double.tryParse(parsed ?? '') ?? 0;
  }

  Future<String> _videoInputPath() async {
    final existing = widget.localPath;
    if (existing != null &&
        existing.isNotEmpty &&
        File(existing).existsSync()) {
      return existing;
    }
    final dir = await getTemporaryDirectory();
    final name = base64Url
        .encode(utf8.encode('${widget.name}-${widget.bytes.length}'))
        .replaceAll('=', '');
    final file = File(
      '${dir.path}${Platform.pathSeparator}ffmpeg-in-$name.mp4',
    );
    await file.writeAsBytes(widget.bytes, flush: true);
    return file.path;
  }

  Future<_PreparedAttachment> _prepareVideoAttachment() async {
    if (!_videoNeedsTranscode) {
      return _PreparedAttachment(
        bytes: widget.bytes,
        name: widget.name,
        mime: widget.mime,
        localPath: widget.localPath,
        caption: _captionController.text,
      );
    }
    final inputPath = await _videoInputPath();
    final duration = await _probeVideoDurationSeconds(inputPath);
    if (duration <= 0) {
      throw Exception('Impossible de lire la duree de la video.');
    }
    final startSeconds = (duration * _videoStart).clamp(0.0, duration);
    final endSeconds = (duration * _videoEnd).clamp(
      startSeconds + .2,
      duration,
    );
    final segmentSeconds = (endSeconds - startSeconds).clamp(.2, duration);
    final dir = await getTemporaryDirectory();
    final safeName = base64Url
        .encode(
          utf8.encode(
            '${widget.name}-${DateTime.now().microsecondsSinceEpoch}',
          ),
        )
        .replaceAll('=', '');
    final outputPath =
        '${dir.path}${Platform.pathSeparator}tranviko-video-$safeName.mp4';
    final args = [
      '-y',
      '-ss',
      startSeconds.toStringAsFixed(3),
      '-t',
      segmentSeconds.toStringAsFixed(3),
      '-i',
      inputPath,
      '-map',
      '0:v:0',
      if (!_videoMuted) ...['-map', '0:a?'],
      '-c:v',
      'libx264',
      '-preset',
      'veryfast',
      '-crf',
      '24',
      '-vf',
      'scale=-2:min(720\\,ih)',
      '-pix_fmt',
      'yuv420p',
      if (_videoMuted) '-an' else ...['-c:a', 'aac', '-b:a', '128k'],
      '-movflags',
      '+faststart',
      outputPath,
    ];
    final session = await FFmpegKit.executeWithArguments(args);
    final returnCode = await session.getReturnCode();
    if (!ReturnCode.isSuccess(returnCode)) {
      final logs = await session.getAllLogsAsString();
      throw Exception(
        'Traitement video impossible${logs == null || logs.isEmpty ? '' : ': ${logs.split('\n').take(2).join(' ')}'}',
      );
    }
    final output = File(outputPath);
    if (!output.existsSync() || output.lengthSync() == 0) {
      throw Exception('La video traitee est vide.');
    }
    final lower = widget.name.toLowerCase();
    final outputName = lower.endsWith('.mp4')
        ? widget.name
        : widget.name.replaceFirst(RegExp(r'\.[^.]+$'), '.mp4');
    return _PreparedAttachment(
      bytes: await output.readAsBytes(),
      name: outputName == widget.name && !lower.endsWith('.mp4')
          ? '${widget.name}.mp4'
          : outputName,
      mime: 'video/mp4',
      localPath: output.path,
      caption: _captionController.text,
      metadata: {
        'trimStartSeconds': startSeconds,
        'trimEndSeconds': endSeconds,
        'trimDurationSeconds': segmentSeconds,
        'muted': _videoMuted,
        'editedWith': 'ffmpeg',
      },
    );
  }

  void _drawSmoothStroke(
    img.Image target,
    _DrawStroke stroke,
    img.Color color,
    double width,
  ) {
    if (stroke.points.isEmpty) return;
    final radius = math.max(1, (width / 2).round());

    void stamp(Offset point) {
      final x = (point.dx * (target.width - 1))
          .round()
          .clamp(0, target.width - 1)
          .toInt();
      final y = (point.dy * (target.height - 1))
          .round()
          .clamp(0, target.height - 1)
          .toInt();
      img.fillCircle(
        target,
        x: x,
        y: y,
        radius: radius,
        color: color,
        antialias: true,
      );
    }

    stamp(stroke.points.first);
    for (var i = 1; i < stroke.points.length; i++) {
      final a = stroke.points[i - 1];
      final b = stroke.points[i];
      final dx = (b.dx - a.dx) * target.width;
      final dy = (b.dy - a.dy) * target.height;
      final distance = math.sqrt(dx * dx + dy * dy);
      final steps = math.max(1, (distance / math.max(1, radius * .65)).ceil());
      for (var step = 1; step <= steps; step++) {
        final t = step / steps;
        stamp(Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t));
      }
    }
  }

  Future<_PreparedAttachment> _prepareAttachment() async {
    if (_isVideo) return _prepareVideoAttachment();
    var outputBytes = widget.bytes;
    var outputName = widget.name;
    var outputMime = widget.mime;
    final changed =
        _isImage &&
        ((_turns % 4) != 0 ||
            _filter != 'original' ||
            _strokes.isNotEmpty ||
            _cropChanged);
    if (changed) {
      final decoded = img.decodeImage(widget.bytes);
      if (decoded != null) {
        var edited = img.Image.from(decoded);
        if (_cropChanged) {
          final x = (_cropRect.left * edited.width).round().clamp(
            0,
            edited.width - 1,
          );
          final y = (_cropRect.top * edited.height).round().clamp(
            0,
            edited.height - 1,
          );
          final right = (_cropRect.right * edited.width).round().clamp(
            x + 1,
            edited.width,
          );
          final bottom = (_cropRect.bottom * edited.height).round().clamp(
            y + 1,
            edited.height,
          );
          edited = img.copyCrop(
            edited,
            x: x,
            y: y,
            width: right - x,
            height: bottom - y,
          );
        }
        if ((_turns % 4) != 0) {
          edited = img.copyRotate(edited, angle: (_turns % 4) * 90);
        }
        edited = switch (_filter) {
          'mono' => img.grayscale(edited),
          'warm' => img.adjustColor(edited, saturation: 1.14, brightness: 1.04),
          'bright' => img.adjustColor(edited, brightness: 1.12, contrast: 1.05),
          _ => edited,
        };
        for (final stroke in _strokes) {
          if (stroke.points.isEmpty) continue;
          final argb = stroke.color.toARGB32();
          final drawColor = img.ColorRgba8(
            (argb >> 16) & 0xff,
            (argb >> 8) & 0xff,
            argb & 0xff,
            (argb >> 24) & 0xff,
          );
          final thickness = (stroke.width * edited.width / 360)
              .clamp(2, 28)
              .toDouble();
          _drawSmoothStroke(edited, stroke, drawColor, thickness);
        }
        final lower = outputName.toLowerCase();
        if (lower.endsWith('.png')) {
          outputBytes = img.encodePng(edited);
          outputMime = 'image/png';
        } else {
          outputBytes = img.encodeJpg(edited, quality: 88);
          outputMime = 'image/jpeg';
          if (!lower.endsWith('.jpg') && !lower.endsWith('.jpeg')) {
            outputName = outputName.replaceFirst(RegExp(r'\.[^.]+$'), '.jpg');
            if (outputName == widget.name) outputName = '${widget.name}.jpg';
          }
        }
      }
    }
    return _PreparedAttachment(
      bytes: outputBytes,
      name: outputName,
      mime: outputMime,
      localPath: changed ? null : widget.localPath,
      caption: _captionController.text,
      metadata: {
        if (_isVideo && (_videoStart > 0 || _videoEnd < 1)) ...{
          'trimStartFraction': _videoStart,
          'trimEndFraction': _videoEnd,
        },
        if (_isVideo && _videoMuted) 'mutedPreview': true,
      },
    );
  }

  Future<void> _submit() async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      final prepared = await _prepareAttachment();
      if (mounted) Navigator.pop(context, prepared);
    } catch (error) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = _editorBg(context);
    final fg = _editorFg(context);
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        foregroundColor: fg,
        title: Text(_title(context)),
        actions: [
          TextButton.icon(
            onPressed: _sending ? null : _submit,
            icon: _sending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    widget.batchEdit ? Icons.check_rounded : Icons.send_rounded,
                  ),
            label: Text(
              widget.batchEdit ? 'Valider' : appTC(context, 'sendMedia'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _buildPreview(context)),
            if (_isPdf)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Text(
                  appTC(context, 'previewOnlyPdf'),
                  style: TextStyle(color: fg.withValues(alpha: .72)),
                ),
              ),
            _buildCaption(context),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(BuildContext context) {
    if (_isImage) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: AspectRatio(
            aspectRatio: _imageAspect,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final canvasSize = Size(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );
                return GestureDetector(
                  onPanStart: _drawMode
                      ? (details) => _startStroke(details, canvasSize)
                      : null,
                  onPanUpdate: _drawMode
                      ? (details) => _appendStroke(details, canvasSize)
                      : null,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        const ColoredBox(color: Colors.black),
                        RotatedBox(
                          quarterTurns: _turns % 4,
                          child: _filterPreview(
                            Image.memory(widget.bytes, fit: BoxFit.contain),
                          ),
                        ),
                        CustomPaint(
                          painter: _DrawPreviewPainter(strokes: _strokes),
                        ),
                        if (_activeTool == 'crop')
                          _CropOverlay(
                            rect: _cropRect,
                            onChanged: (value) =>
                                setState(() => _cropRect = value),
                          ),
                        Positioned(
                          left: 12,
                          top: 12,
                          child: _buildImageToolbar(context),
                        ),
                        if (_activeTool != null)
                          Positioned(
                            left: 72,
                            right: 12,
                            bottom: 12,
                            child: _buildActiveImagePanel(context),
                          ),
                        if (_drawMode)
                          Positioned(
                            left: 12,
                            top: 12,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: .45),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.draw_rounded,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      'Crayon actif',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    }
    if (_isVideo) {
      return Stack(
        children: [
          Positioned.fill(
            child: _InlineVideoPreview(
              url: '',
              bytes: widget.bytes,
              localPath: widget.localPath,
              muted: _videoMuted,
              startFraction: _videoStart,
              endFraction: _videoEnd,
            ),
          ),
          Positioned(
            left: 12,
            right: 70,
            top: 12,
            child: _VideoFragmentStrip(
              start: _videoStart,
              end: _videoEnd,
              bytes: widget.bytes,
              localPath: widget.localPath,
              color: Theme.of(context).colorScheme.primary,
              onChanged: (start, end) => setState(() {
                _videoStart = start;
                _videoEnd = end;
              }),
            ),
          ),
          Positioned(right: 12, top: 12, child: _buildVideoToolbar(context)),
          if (_activeTool != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: _buildActiveVideoPanel(context),
            ),
        ],
      );
    }
    if (_isPdf) {
      return PdfPreview(
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
        allowPrinting: false,
        allowSharing: false,
        build: (_) async => widget.bytes,
      );
    }
    return Center(
      child: Icon(
        Icons.insert_drive_file_rounded,
        color: _editorFg(context).withValues(alpha: .72),
        size: 78,
      ),
    );
  }

  void _selectImageTool(String tool) {
    setState(() {
      _activeTool = _activeTool == tool ? null : tool;
      _drawMode = _activeTool == 'draw';
    });
  }

  void _selectVideoTool(String tool) {
    setState(() => _activeTool = _activeTool == tool ? null : tool);
  }

  Widget _toolCircle({
    required IconData icon,
    required String tooltip,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 8),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: active
              ? Theme.of(context).colorScheme.primary
              : Colors.black.withValues(alpha: .72),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 46,
              height: 46,
              child: Icon(
                icon,
                color: active
                    ? Theme.of(context).colorScheme.onPrimary
                    : Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImageToolbar(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _toolCircle(
          icon: Icons.crop_rounded,
          tooltip: 'Recadrer',
          active: _activeTool == 'crop',
          onTap: () => _selectImageTool('crop'),
        ),
        _toolCircle(
          icon: Icons.rotate_90_degrees_ccw_rounded,
          tooltip: 'Rotation',
          active: _activeTool == 'transform',
          onTap: () => _selectImageTool('transform'),
        ),
        _toolCircle(
          icon: Icons.draw_rounded,
          tooltip: 'Crayon',
          active: _activeTool == 'draw',
          onTap: () => _selectImageTool('draw'),
        ),
        _toolCircle(
          icon: Icons.auto_fix_high_rounded,
          tooltip: 'Filtres',
          active: _activeTool == 'filter',
          onTap: () => _selectImageTool('filter'),
        ),
        _toolCircle(
          icon: Icons.restart_alt_rounded,
          tooltip: 'Reinitialiser',
          active: false,
          onTap: () => setState(() {
            _turns = 0;
            _filter = 'original';
            _strokes.clear();
            _cropRect = const Rect.fromLTWH(0, 0, 1, 1);
            _drawMode = false;
            _activeTool = null;
          }),
        ),
      ],
    );
  }

  Widget _buildVideoToolbar(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _toolCircle(
          icon: _videoMuted
              ? Icons.volume_off_rounded
              : Icons.volume_up_rounded,
          tooltip: 'Audio',
          active: _activeTool == 'audio' || _videoMuted,
          onTap: () => _selectVideoTool('audio'),
        ),
        _toolCircle(
          icon: Icons.restart_alt_rounded,
          tooltip: 'Reinitialiser',
          active: false,
          onTap: () => setState(() {
            _videoStart = 0;
            _videoEnd = 1;
            _videoMuted = false;
            _activeTool = null;
          }),
        ),
      ],
    );
  }

  Widget _panelShell({required Widget child}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.black.withValues(alpha: .62)
            : Colors.white.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _editorFg(context).withValues(alpha: .16)),
      ),
      child: Padding(padding: const EdgeInsets.all(12), child: child),
    );
  }

  Widget _buildActiveImagePanel(BuildContext context) {
    if (_activeTool == 'crop') {
      return _panelShell(
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Glissez les bords du cadre pour recadrer.',
                style: TextStyle(
                  color: _editorFg(context),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton(
              onPressed: () =>
                  setState(() => _cropRect = const Rect.fromLTWH(0, 0, 1, 1)),
              icon: Icon(Icons.restart_alt_rounded, color: _editorFg(context)),
            ),
          ],
        ),
      );
    }
    if (_activeTool == 'transform') {
      return _panelShell(
        child: Row(
          children: [
            Expanded(
              child: _EditorToolButton(
                icon: Icons.rotate_left_rounded,
                label: appTC(context, 'rotateLeft'),
                onTap: () => setState(() => _turns = (_turns + 3) % 4),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _EditorToolButton(
                icon: Icons.rotate_right_rounded,
                label: appTC(context, 'rotateRight'),
                onTap: () => setState(() => _turns = (_turns + 1) % 4),
              ),
            ),
          ],
        ),
      );
    }
    if (_activeTool == 'draw') {
      return _panelShell(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                for (final color in const [
                  Colors.white,
                  Color(0xFF22C55E),
                  Color(0xFF38BDF8),
                  Color(0xFFF97316),
                  Color(0xFFEF4444),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      onTap: () => setState(() => _drawColor = color),
                      borderRadius: BorderRadius.circular(99),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color,
                          border: Border.all(
                            color: _drawColor == color
                                ? Colors.white
                                : Colors.white.withValues(alpha: .22),
                            width: _drawColor == color ? 3 : 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                IconButton(
                  color: Colors.white,
                  onPressed: _strokes.isEmpty
                      ? null
                      : () => setState(() => _strokes.removeLast()),
                  icon: const Icon(Icons.undo_rounded),
                ),
                IconButton(
                  color: Colors.white,
                  onPressed: _strokes.isEmpty
                      ? null
                      : () => setState(_strokes.clear),
                  icon: const Icon(Icons.cleaning_services_rounded),
                ),
              ],
            ),
            Slider(
              value: _drawWidth,
              min: 3,
              max: 16,
              onChanged: (value) => setState(() => _drawWidth = value),
            ),
          ],
        ),
      );
    }
    return _panelShell(
      child: SizedBox(
        height: 42,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final filter in const ['original', 'mono', 'warm', 'bright'])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(_filterLabel(context, filter)),
                  selected: _filter == filter,
                  onSelected: (_) => setState(() => _filter = filter),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveVideoPanel(BuildContext context) {
    return _panelShell(
      child: SwitchListTile(
        value: _videoMuted,
        onChanged: (value) => setState(() => _videoMuted = value),
        title: Text('Audio', style: TextStyle(color: _editorFg(context))),
        secondary: Icon(
          _videoMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
          color: _editorFg(context),
        ),
      ),
    );
  }

  Widget _buildCaption(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: TextField(
        controller: _captionController,
        minLines: 1,
        maxLines: 3,
        style: TextStyle(color: _editorFg(context)),
        decoration: InputDecoration(
          hintText: appTC(context, 'caption'),
          hintStyle: TextStyle(
            color: _editorFg(context).withValues(alpha: .56),
          ),
          filled: true,
          fillColor: _editorPanel(context),
          prefixIcon: Icon(Icons.short_text_rounded, color: _editorFg(context)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(
              color: _editorFg(context).withValues(alpha: .18),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: _editorFg(context)),
          ),
        ),
      ),
    );
  }
}

class _DrawPreviewPainter extends CustomPainter {
  final List<_DrawStroke> strokes;

  const _DrawPreviewPainter({required this.strokes});

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final path = Path();
      final first = stroke.points.first;
      path.moveTo(first.dx * size.width, first.dy * size.height);
      if (stroke.points.length == 1) {
        canvas.drawCircle(
          Offset(first.dx * size.width, first.dy * size.height),
          stroke.width / 2,
          paint..style = PaintingStyle.fill,
        );
        continue;
      }
      for (var i = 1; i < stroke.points.length - 1; i++) {
        final point = stroke.points[i];
        final next = stroke.points[i + 1];
        final mid = Offset(
          ((point.dx + next.dx) / 2) * size.width,
          ((point.dy + next.dy) / 2) * size.height,
        );
        path.quadraticBezierTo(
          point.dx * size.width,
          point.dy * size.height,
          mid.dx,
          mid.dy,
        );
      }
      final last = stroke.points.last;
      path.lineTo(last.dx * size.width, last.dy * size.height);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DrawPreviewPainter oldDelegate) => true;
}

enum _CropDragMode {
  move,
  left,
  right,
  top,
  bottom,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

class _CropOverlay extends StatefulWidget {
  final Rect rect;
  final ValueChanged<Rect> onChanged;

  const _CropOverlay({required this.rect, required this.onChanged});

  @override
  State<_CropOverlay> createState() => _CropOverlayState();
}

class _CropOverlayState extends State<_CropOverlay> {
  _CropDragMode? _mode;

  _CropDragMode _modeFor(Offset position, Size size) {
    final rect = Rect.fromLTRB(
      widget.rect.left * size.width,
      widget.rect.top * size.height,
      widget.rect.right * size.width,
      widget.rect.bottom * size.height,
    );
    const hit = 28.0;
    final nearLeft = (position.dx - rect.left).abs() < hit;
    final nearRight = (position.dx - rect.right).abs() < hit;
    final nearTop = (position.dy - rect.top).abs() < hit;
    final nearBottom = (position.dy - rect.bottom).abs() < hit;
    if (nearLeft && nearTop) return _CropDragMode.topLeft;
    if (nearRight && nearTop) return _CropDragMode.topRight;
    if (nearLeft && nearBottom) return _CropDragMode.bottomLeft;
    if (nearRight && nearBottom) return _CropDragMode.bottomRight;
    if (nearLeft) return _CropDragMode.left;
    if (nearRight) return _CropDragMode.right;
    if (nearTop) return _CropDragMode.top;
    if (nearBottom) return _CropDragMode.bottom;
    return _CropDragMode.move;
  }

  Rect _normalize(Rect rect) {
    const minSize = .12;
    var left = rect.left.clamp(0.0, 1.0).toDouble();
    var top = rect.top.clamp(0.0, 1.0).toDouble();
    var right = rect.right.clamp(0.0, 1.0).toDouble();
    var bottom = rect.bottom.clamp(0.0, 1.0).toDouble();
    if (right - left < minSize) {
      final center = ((left + right) / 2)
          .clamp(minSize / 2, 1 - minSize / 2)
          .toDouble();
      left = center - minSize / 2;
      right = center + minSize / 2;
    }
    if (bottom - top < minSize) {
      final center = ((top + bottom) / 2)
          .clamp(minSize / 2, 1 - minSize / 2)
          .toDouble();
      top = center - minSize / 2;
      bottom = center + minSize / 2;
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  void _drag(DragUpdateDetails details, Size size) {
    final mode = _mode ?? _CropDragMode.move;
    final dx = details.delta.dx / size.width;
    final dy = details.delta.dy / size.height;
    var rect = widget.rect;
    if (mode == _CropDragMode.move) {
      final width = rect.width;
      final height = rect.height;
      final left = (rect.left + dx).clamp(0.0, 1.0 - width).toDouble();
      final top = (rect.top + dy).clamp(0.0, 1.0 - height).toDouble();
      rect = Rect.fromLTWH(left, top, width, height);
    } else {
      var left = rect.left;
      var top = rect.top;
      var right = rect.right;
      var bottom = rect.bottom;
      if (mode == _CropDragMode.left ||
          mode == _CropDragMode.topLeft ||
          mode == _CropDragMode.bottomLeft) {
        left += dx;
      }
      if (mode == _CropDragMode.right ||
          mode == _CropDragMode.topRight ||
          mode == _CropDragMode.bottomRight) {
        right += dx;
      }
      if (mode == _CropDragMode.top ||
          mode == _CropDragMode.topLeft ||
          mode == _CropDragMode.topRight) {
        top += dy;
      }
      if (mode == _CropDragMode.bottom ||
          mode == _CropDragMode.bottomLeft ||
          mode == _CropDragMode.bottomRight) {
        bottom += dy;
      }
      rect = Rect.fromLTRB(left, top, right, bottom);
    }
    widget.onChanged(_normalize(rect));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final rect = Rect.fromLTRB(
          widget.rect.left * size.width,
          widget.rect.top * size.height,
          widget.rect.right * size.width,
          widget.rect.bottom * size.height,
        );
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (details) =>
              _mode = _modeFor(details.localPosition, size),
          onPanUpdate: (details) => _drag(details, size),
          onPanEnd: (_) => _mode = null,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: _CropShadePainter(rect: rect)),
              ),
              Positioned.fromRect(
                rect: rect,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .24),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                ),
              ),
              for (final point in [
                rect.topLeft,
                rect.topRight,
                rect.bottomLeft,
                rect.bottomRight,
              ])
                Positioned(
                  left: point.dx - 8,
                  top: point.dy - 8,
                  child: const _CropHandle(),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _CropShadePainter extends CustomPainter {
  final Rect rect;

  const _CropShadePainter({required this.rect});

  @override
  void paint(Canvas canvas, Size size) {
    final overlay = Paint()..color = Colors.black.withValues(alpha: .48);
    final path = Path()
      ..addRect(Offset.zero & size)
      ..addRect(rect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, overlay);
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: .42)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = rect.left + rect.width * i / 3;
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), grid);
      final y = rect.top + rect.height * i / 3;
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), grid);
    }
  }

  @override
  bool shouldRepaint(covariant _CropShadePainter oldDelegate) =>
      oldDelegate.rect != rect;
}

class _CropHandle extends StatelessWidget {
  const _CropHandle();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black.withValues(alpha: .25)),
      ),
      child: const SizedBox(width: 16, height: 16),
    );
  }
}

class _EditorToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _EditorToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = dark ? Colors.white : const Color(0xFF0F172A);
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        foregroundColor: fg,
        side: BorderSide(color: fg.withValues(alpha: .22)),
        backgroundColor: dark
            ? Colors.white.withValues(alpha: .08)
            : Colors.black.withValues(alpha: .04),
      ),
    );
  }
}

class _InlineVideoPreview extends StatefulWidget {
  final String url;
  final Uint8List? bytes;
  final String? localPath;
  final bool muted;
  final bool showPlayButton;
  final bool autoplay;
  final bool loop;
  final double startFraction;
  final double endFraction;

  const _InlineVideoPreview({
    required this.url,
    this.bytes,
    this.localPath,
    this.muted = false,
    this.showPlayButton = true,
    this.autoplay = false,
    this.loop = false,
    this.startFraction = 0,
    this.endFraction = 1,
  });

  @override
  State<_InlineVideoPreview> createState() => _InlineVideoPreviewState();
}

class _VideoAttachmentViewer extends StatefulWidget {
  final String url;
  final Uint8List? bytes;
  final String? localPath;

  const _VideoAttachmentViewer({required this.url, this.bytes, this.localPath});

  @override
  State<_VideoAttachmentViewer> createState() => _VideoAttachmentViewerState();
}

class _VideoAttachmentViewerState extends State<_VideoAttachmentViewer> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _muted = false;
  String? _tempPath;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final localPath = widget.localPath;
    final bytes = widget.bytes;
    if (localPath != null && File(localPath).existsSync()) {
      _controller = VideoPlayerController.file(File(localPath));
    } else if (bytes != null) {
      final dir = await getTemporaryDirectory();
      final name = base64Url
          .encode(utf8.encode('${widget.url}-${bytes.length}'))
          .replaceAll('=', '');
      final file = File('${dir.path}${Platform.pathSeparator}viewer-$name.mp4');
      await file.writeAsBytes(bytes, flush: true);
      _tempPath = file.path;
      _controller = VideoPlayerController.file(file);
    } else {
      _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    }
    await _controller!.initialize();
    _controller!.addListener(() {
      if (mounted) setState(() {});
    });
    if (mounted) setState(() => _ready = true);
  }

  @override
  void dispose() {
    _controller?.dispose();
    final tempPath = _tempPath;
    if (tempPath != null) {
      try {
        File(tempPath).deleteSync();
      } catch (_) {}
    }
    super.dispose();
  }

  String _label(Duration value) {
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = value.inHours;
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (!_ready || controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final duration = controller.value.duration;
    final position = controller.value.position;
    final maxMs = math.max(1, duration.inMilliseconds);
    final currentMs = position.inMilliseconds.clamp(0, maxMs);
    return Column(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(14, 8, 14, 16),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: .14)),
          ),
          child: Row(
            children: [
              IconButton.filled(
                onPressed: () {
                  controller.value.isPlaying
                      ? unawaited(controller.pause())
                      : unawaited(controller.play());
                },
                icon: Icon(
                  controller.value.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
              ),
              Text(
                _label(position),
                style: const TextStyle(
                  color: Colors.white,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              Expanded(
                child: Slider(
                  value: currentMs.toDouble(),
                  max: maxMs.toDouble(),
                  onChanged: (value) => unawaited(
                    controller.seekTo(Duration(milliseconds: value.round())),
                  ),
                ),
              ),
              Text(
                _label(duration),
                style: const TextStyle(
                  color: Colors.white,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              IconButton(
                color: Colors.white,
                onPressed: () {
                  _muted = !_muted;
                  unawaited(controller.setVolume(_muted ? 0 : 1));
                  setState(() {});
                },
                icon: Icon(
                  _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StickerVideoEditor extends StatefulWidget {
  final Uint8List bytes;
  final String name;
  final String? localPath;

  const _StickerVideoEditor({
    required this.bytes,
    required this.name,
    required this.localPath,
  });

  @override
  State<_StickerVideoEditor> createState() => _StickerVideoEditorState();
}

class _StickerVideoEditorState extends State<_StickerVideoEditor> {
  double _start = 0;
  double _end = 1;
  double _duration = 0;
  bool _loading = true;
  bool _creating = false;
  String? _inputPath;

  @override
  void initState() {
    super.initState();
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    try {
      final existing = widget.localPath;
      if (existing != null &&
          existing.isNotEmpty &&
          File(existing).existsSync()) {
        _inputPath = existing;
      } else {
        final directory = await getTemporaryDirectory();
        final file = File(
          '${directory.path}${Platform.pathSeparator}sticker-source-${DateTime.now().microsecondsSinceEpoch}.mp4',
        );
        await file.writeAsBytes(widget.bytes, flush: true);
        _inputPath = file.path;
      }
      final session = await FFprobeKit.getMediaInformation(_inputPath!);
      _duration =
          double.tryParse(session.getMediaInformation()?.getDuration() ?? '') ??
          0;
      if (_duration > 5) _end = 5 / _duration;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _updateRange(double start, double end) {
    if (_duration <= 0) {
      setState(() {
        _start = start;
        _end = end;
      });
      return;
    }
    final maxFraction = math.min(1.0, 5 / _duration);
    var nextStart = start;
    var nextEnd = end;
    if (nextEnd - nextStart > maxFraction) {
      final startMoved = (start - _start).abs() > (end - _end).abs();
      if (startMoved) {
        nextEnd = math.min(1.0, nextStart + maxFraction);
      } else {
        nextStart = math.max(0.0, nextEnd - maxFraction);
      }
    }
    setState(() {
      _start = nextStart;
      _end = nextEnd;
    });
  }

  String get _selectionLabel {
    if (_duration <= 0) return '5,0 s maximum';
    final seconds = ((_end - _start) * _duration).clamp(.0, 5.0);
    return '${seconds.toStringAsFixed(1)} s / 5,0 s';
  }

  Future<void> _create() async {
    if (_creating || _inputPath == null || _duration <= 0) return;
    setState(() => _creating = true);
    try {
      final startSeconds = (_start * _duration).clamp(0.0, _duration);
      final endSeconds = (_end * _duration).clamp(
        startSeconds + .2,
        math.min(_duration, startSeconds + 5),
      );
      final segmentSeconds = (endSeconds - startSeconds).clamp(.2, 5.0);
      final directory = await getApplicationDocumentsDirectory();
      final stickerDirectory = Directory('${directory.path}/tranviko_stickers');
      await stickerDirectory.create(recursive: true);
      final output = File(
        '${stickerDirectory.path}/${DateTime.now().microsecondsSinceEpoch}_animated_sticker.mp4',
      );
      final session = await FFmpegKit.executeWithArguments([
        '-y',
        '-ss',
        startSeconds.toStringAsFixed(3),
        '-t',
        segmentSeconds.toStringAsFixed(3),
        '-i',
        _inputPath!,
        '-an',
        '-vf',
        'scale=384:384:force_original_aspect_ratio=increase,crop=384:384',
        '-c:v',
        'libx264',
        '-preset',
        'veryfast',
        '-crf',
        '25',
        '-pix_fmt',
        'yuv420p',
        '-movflags',
        '+faststart',
        output.path,
      ]);
      final code = await session.getReturnCode();
      if (!ReturnCode.isSuccess(code) || !await output.exists()) {
        throw Exception('Conversion video impossible.');
      }
      final bytes = await output.readAsBytes();
      if (!mounted) return;
      Navigator.pop(
        context,
        _PreparedAttachment(
          bytes: bytes,
          name: 'tranviko-sticker.mp4',
          mime: 'video/mp4',
          localPath: output.path,
          caption: '',
          metadata: {
            'isSticker': true,
            'stickerKind': 'video',
            'stickerAnimated': true,
            'trimStartSeconds': startSeconds,
            'trimEndSeconds': endSeconds,
            'trimDurationSeconds': segmentSeconds,
            'muted': true,
          },
        ),
      );
    } catch (error) {
      if (mounted) {
        AppToast.show(
          context,
          'Sticker anime impossible: $error',
          tone: AppToastTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Sticker anime'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: FilledButton.icon(
              onPressed: _loading || _creating ? null : _create,
              icon: _creating
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: const Text('Creer'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: ColoredBox(
                          color: const Color(0xFF111827),
                          child: _InlineVideoPreview(
                            url: '',
                            bytes: widget.bytes,
                            localPath: _inputPath,
                            muted: true,
                            showPlayButton: false,
                            autoplay: true,
                            loop: true,
                            startFraction: _start,
                            endFraction: _end,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
                    decoration: const BoxDecoration(
                      color: Color(0xFF0B0B0D),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.content_cut_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Choisissez un extrait continu',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            Text(
                              _selectionLabel,
                              style: TextStyle(
                                color: scheme.primaryContainer,
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _VideoFragmentStrip(
                          start: _start,
                          end: _end,
                          bytes: widget.bytes,
                          localPath: _inputPath,
                          color: scheme.primary,
                          onChanged: _updateRange,
                        ),
                        const SizedBox(height: 10),
                        const Row(
                          children: [
                            Icon(
                              Icons.volume_off_rounded,
                              color: Colors.white54,
                              size: 17,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Le son est retire automatiquement.',
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _VideoFragmentStrip extends StatefulWidget {
  final double start;
  final double end;
  final Uint8List bytes;
  final String? localPath;
  final Color color;
  final void Function(double start, double end) onChanged;

  const _VideoFragmentStrip({
    required this.start,
    required this.end,
    required this.bytes,
    required this.localPath,
    required this.color,
    required this.onChanged,
  });

  @override
  State<_VideoFragmentStrip> createState() => _VideoFragmentStripState();
}

class _VideoFragmentStripState extends State<_VideoFragmentStrip> {
  final List<String> _frames = [];
  bool _loading = false;
  bool _dragStart = true;

  @override
  void initState() {
    super.initState();
    _generateFrames();
  }

  Future<String> _inputPath() async {
    final localPath = widget.localPath;
    if (localPath != null && File(localPath).existsSync()) return localPath;
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}${Platform.pathSeparator}strip-${widget.bytes.length}-${widget.hashCode}.mp4',
    );
    if (!await file.exists()) {
      await file.writeAsBytes(widget.bytes, flush: true);
    }
    return file.path;
  }

  Future<double> _duration(String path) async {
    final session = await FFprobeKit.getMediaInformation(path);
    final raw = session.getMediaInformation()?.getDuration();
    return double.tryParse(raw ?? '') ?? 0;
  }

  Future<void> _generateFrames() async {
    if (_loading) return;
    _loading = true;
    try {
      final input = await _inputPath();
      final duration = await _duration(input);
      final dir = await getTemporaryDirectory();
      final next = <String>[];
      for (var i = 0; i < 8; i++) {
        final at = duration <= 0 ? i.toDouble() : duration * ((i + .5) / 8);
        final output =
            '${dir.path}${Platform.pathSeparator}video-strip-${widget.hashCode}-$i.jpg';
        final session = await FFmpegKit.executeWithArguments([
          '-y',
          '-ss',
          at.toStringAsFixed(3),
          '-i',
          input,
          '-vframes',
          '1',
          '-q:v',
          '5',
          '-vf',
          'scale=160:-1',
          output,
        ]);
        final code = await session.getReturnCode();
        if (ReturnCode.isSuccess(code) && File(output).existsSync()) {
          next.add(output);
        }
      }
      if (mounted && next.isNotEmpty) {
        setState(() {
          _frames
            ..clear()
            ..addAll(next);
        });
      }
    } catch (_) {
      // Decorative only: the trim handles still work if thumbnails fail.
    } finally {
      _loading = false;
    }
  }

  void _beginDrag(Offset local, double width) {
    final startX = width * widget.start;
    final endX = width * widget.end;
    _dragStart = (local.dx - startX).abs() <= (local.dx - endX).abs();
  }

  void _updateDrag(Offset local, double width) {
    if (width <= 0) return;
    final value = (local.dx / width).clamp(0.0, 1.0).toDouble();
    if (_dragStart) {
      widget.onChanged(
        value.clamp(0.0, widget.end - .04).toDouble(),
        widget.end,
      );
    } else {
      widget.onChanged(
        widget.start,
        value.clamp(widget.start + .04, 1.0).toDouble(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 54,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: dark
            ? Colors.black.withValues(alpha: .58)
            : Colors.white.withValues(alpha: .90),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: (dark ? Colors.white : Colors.black).withValues(alpha: .14),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final left = width * widget.start.clamp(0.0, 1.0);
          final right = width * (1 - widget.end.clamp(0.0, 1.0));
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (details) => _beginDrag(details.localPosition, width),
            onPanUpdate: (details) => _updateDrag(details.localPosition, width),
            onTapDown: (details) {
              _beginDrag(details.localPosition, width);
              _updateDrag(details.localPosition, width);
            },
            child: Stack(
              children: [
                Row(
                  children: [
                    for (var i = 0; i < 8; i++)
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Color.lerp(widget.color, Colors.white, .08)!,
                                Color.lerp(widget.color, Colors.black, .28)!,
                              ],
                            ),
                          ),
                          child: _frames.length > i
                              ? Image.file(File(_frames[i]), fit: BoxFit.cover)
                              : null,
                        ),
                      ),
                  ],
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: left,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .48),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: right,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .48),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                Positioned(
                  left: (left - 8).clamp(0, width - 16).toDouble(),
                  top: 0,
                  bottom: 0,
                  child: const _TrimHandle(),
                ),
                Positioned(
                  right: (right - 8).clamp(0, width - 16).toDouble(),
                  top: 0,
                  bottom: 0,
                  child: const _TrimHandle(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TrimHandle extends StatelessWidget {
  const _TrimHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 16,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .22),
              blurRadius: 8,
            ),
          ],
        ),
        child: const Center(
          child: Icon(Icons.drag_indicator_rounded, size: 13),
        ),
      ),
    );
  }
}

class _InlineVideoPreviewState extends State<_InlineVideoPreview> {
  VideoPlayerController? _controller;
  bool _ready = false;
  String? _tempPath;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final bytes = widget.bytes;
    final localPath = widget.localPath;
    if (localPath != null && File(localPath).existsSync()) {
      _controller = VideoPlayerController.file(File(localPath));
    } else if (bytes != null) {
      final dir = await getTemporaryDirectory();
      final safeName = base64Url
          .encode(
            utf8.encode(
              widget.url.isEmpty ? widget.hashCode.toString() : widget.url,
            ),
          )
          .replaceAll('=', '');
      final file = File(
        '${dir.path}${Platform.pathSeparator}preview-$safeName.mp4',
      );
      await file.writeAsBytes(bytes, flush: true);
      _tempPath = file.path;
      _controller = VideoPlayerController.file(file);
    } else {
      _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    }
    await _controller!.initialize();
    await _controller!.setVolume(widget.muted ? 0 : 1);
    await _controller!.setLooping(widget.loop);
    _controller!.addListener(_enforceTrimPreview);
    await _seekToTrimStart();
    if (widget.autoplay) await _controller!.play();
    if (mounted) setState(() => _ready = true);
  }

  @override
  void didUpdateWidget(covariant _InlineVideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controller = _controller;
    if (controller == null) return;
    if (oldWidget.muted != widget.muted) {
      unawaited(controller.setVolume(widget.muted ? 0 : 1));
    }
    if (oldWidget.loop != widget.loop) {
      unawaited(controller.setLooping(widget.loop));
    }
    if (oldWidget.startFraction != widget.startFraction ||
        oldWidget.endFraction != widget.endFraction) {
      unawaited(_seekToTrimStart());
    }
  }

  Duration _fractionDuration(double value) {
    final controller = _controller;
    final duration = controller?.value.duration ?? Duration.zero;
    if (duration.inMilliseconds <= 0) return Duration.zero;
    return Duration(
      milliseconds: (duration.inMilliseconds * value.clamp(0.0, 1.0)).round(),
    );
  }

  Future<void> _seekToTrimStart() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    await controller.seekTo(_fractionDuration(widget.startFraction));
  }

  void _enforceTrimPreview() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final end = _fractionDuration(widget.endFraction);
    if (end == Duration.zero || !controller.value.isPlaying) return;
    if (controller.value.position >= end) {
      unawaited(controller.seekTo(_fractionDuration(widget.startFraction)));
      if (widget.loop || widget.autoplay) {
        unawaited(controller.play());
      } else {
        unawaited(controller.pause());
      }
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_enforceTrimPreview);
    _controller?.dispose();
    final tempPath = _tempPath;
    if (tempPath != null) {
      try {
        File(tempPath).deleteSync();
      } catch (_) {}
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (!_ready || controller == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: VideoPlayer(controller),
          ),
          if (widget.showPlayButton)
            IconButton.filled(
              iconSize: 44,
              onPressed: () {
                if (controller.value.isPlaying) {
                  unawaited(controller.pause());
                } else {
                  final end = _fractionDuration(widget.endFraction);
                  if (end != Duration.zero &&
                      controller.value.position >= end) {
                    unawaited(
                      controller.seekTo(
                        _fractionDuration(widget.startFraction),
                      ),
                    );
                  }
                  unawaited(controller.play());
                }
                setState(() {});
              },
              icon: Icon(
                controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
              ),
            ),
        ],
      ),
    );
  }
}

class _VoiceBubblePlayer extends StatefulWidget {
  final String? audioUrl;
  final String? audioLocalPath;
  final String? audioBase64;
  final int duration;
  final List<double> waveform;
  final Color textColor;
  final bool mine;
  final bool read;
  final Future<void> Function()? onPlayed;

  const _VoiceBubblePlayer({
    required this.audioUrl,
    required this.audioLocalPath,
    required this.audioBase64,
    required this.duration,
    required this.waveform,
    required this.textColor,
    required this.mine,
    required this.read,
    this.onPlayed,
  });

  @override
  State<_VoiceBubblePlayer> createState() => _VoiceBubblePlayerState();
}

class _VoiceBubblePlayerState extends State<_VoiceBubblePlayer> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<void>? _completeSub;
  bool _playing = false;
  bool _reportedPlayed = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _duration = Duration(seconds: widget.duration.clamp(1, 3600));
    _positionSub = _player.onPositionChanged.listen((value) {
      if (mounted) setState(() => _position = value);
    });
    _durationSub = _player.onDurationChanged.listen((value) {
      if (mounted && value.inMilliseconds > 0) {
        setState(() => _duration = value);
      }
    });
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playing = false;
          _position = Duration.zero;
        });
      }
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _completeSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final url = widget.audioUrl;
    final localPath = widget.audioLocalPath;
    final cachedAudio = widget.audioBase64;
    if ((localPath == null ||
            localPath.isEmpty ||
            !File(localPath).existsSync()) &&
        (url == null || url.isEmpty) &&
        (cachedAudio == null || cachedAudio.isEmpty)) {
      return;
    }
    if (_playing) {
      await _player.pause();
      if (mounted) setState(() => _playing = false);
      return;
    }
    final fullUrl = url == null || url.isEmpty
        ? null
        : (url.startsWith('http')
              ? url
              : '${ApiService.baseUrl.replaceFirst('/api', '')}$url');
    try {
      await _player.setReleaseMode(ReleaseMode.stop);
      if (_position > Duration.zero) {
        await _player.resume();
      } else if (localPath != null &&
          localPath.isNotEmpty &&
          File(localPath).existsSync()) {
        await _player.play(DeviceFileSource(localPath));
      } else if (cachedAudio != null && cachedAudio.isNotEmpty) {
        await _player.play(
          BytesSource(base64Decode(cachedAudio.split(',').last)),
        );
      } else if (fullUrl != null) {
        await _player.play(UrlSource(fullUrl));
      }
      if (!_reportedPlayed) {
        _reportedPlayed = true;
        final onPlayed = widget.onPlayed;
        if (onPlayed != null) unawaited(onPlayed());
      }
      if (mounted) setState(() => _playing = true);
    } catch (_) {
      if (mounted) setState(() => _playing = false);
    }
  }

  Future<void> _seekFraction(double value) async {
    final maxMs = _duration.inMilliseconds <= 0 ? 1 : _duration.inMilliseconds;
    final target = Duration(
      milliseconds: (maxMs * value.clamp(0.0, 1.0)).round(),
    );
    await _player.seek(target);
    if (mounted) setState(() => _position = target);
  }

  @override
  Widget build(BuildContext context) {
    final maxMs = _duration.inMilliseconds <= 0
        ? 1.0
        : _duration.inMilliseconds.toDouble();
    final progress =
        _position.inMilliseconds.clamp(0, maxMs.toInt()).toDouble() / maxMs;
    final readForColor = widget.mine ? widget.read : true;
    final activeColor = readForColor
        ? Colors.lightGreenAccent.shade400
        : (widget.mine ? Colors.white : Theme.of(context).colorScheme.primary);
    final inactiveColor = widget.mine
        ? Colors.white38
        : Theme.of(context).colorScheme.primaryContainer.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark ? .42 : 1,
          );
    return SizedBox(
      width: 236,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: _toggle,
            icon: Icon(
              _playing ? Icons.pause : Icons.play_arrow,
              color: activeColor,
            ),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _VoicePlaybackBars(
                  waveform: widget.waveform,
                  progress: progress,
                  activeColor: activeColor,
                  inactiveColor: inactiveColor,
                  onSeek: _seekFraction,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _durationLabel(_position),
                        style: TextStyle(
                          color: widget.textColor.withValues(alpha: .75),
                          fontSize: 10,
                        ),
                      ),
                      Text(
                        _durationLabel(_duration),
                        style: TextStyle(
                          color: widget.textColor.withValues(alpha: .75),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _durationLabel(Duration duration) {
    final seconds = duration.inSeconds;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}

class _VoicePlaybackBars extends StatelessWidget {
  final List<double> waveform;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;
  final ValueChanged<double> onSeek;

  const _VoicePlaybackBars({
    required this.waveform,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
    required this.onSeek,
  });

  List<double> get _samples {
    if (waveform.isNotEmpty) return waveform;
    return const [
      .28,
      .62,
      .42,
      .88,
      .55,
      .74,
      .36,
      .68,
      .94,
      .48,
      .78,
      .32,
      .58,
      .86,
      .44,
      .72,
      .38,
      .66,
      .9,
      .52,
      .8,
      .35,
      .61,
      .76,
      .46,
      .84,
      .4,
      .7,
      .92,
      .5,
      .64,
      .3,
      .82,
      .56,
      .73,
      .41,
      .69,
      .87,
      .45,
      .75,
      .34,
      .6,
    ];
  }

  void _seekFromPosition(BoxConstraints constraints, Offset position) {
    if (constraints.maxWidth <= 0) return;
    onSeek((position.dx / constraints.maxWidth).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final samples = _samples;
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) =>
              _seekFromPosition(constraints, details.localPosition),
          onHorizontalDragUpdate: (details) =>
              _seekFromPosition(constraints, details.localPosition),
          child: SizedBox(
            height: 34,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                for (var i = 0; i < samples.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.4),
                      child: FractionallySizedBox(
                        heightFactor: (.18 + samples[i].clamp(.05, 1.0) * .72)
                            .clamp(.18, .9)
                            .toDouble(),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: i / samples.length <= progress
                                ? activeColor
                                : inactiveColor,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RecordingBar extends StatelessWidget {
  final int seconds;
  final double level;
  final bool paused;
  final VoidCallback onCancel;
  final VoidCallback onPauseToggle;
  final VoidCallback onSend;

  const _RecordingBar({
    required this.seconds,
    required this.level,
    required this.paused,
    required this.onCancel,
    required this.onPauseToggle,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final safeLevel = paused ? .05 : level.clamp(.05, 1.0).toDouble();
    return Container(
      key: const ValueKey('recording'),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      color: _screenBg(context),
      child: Row(
        children: [
          _RoundIcon(icon: Icons.close, onTap: onCancel),
          const SizedBox(width: 10),
          _RoundIcon(
            icon: paused ? Icons.play_arrow : Icons.pause,
            onTap: onPauseToggle,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: _surfacePanel(context),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: .18),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    _duration(seconds),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: _VoiceLevelBars(level: safeLevel)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          _RoundIcon(icon: Icons.send, filled: true, onTap: onSend),
        ],
      ),
    );
  }
}

class _VoiceLevelBars extends StatelessWidget {
  final double level;

  const _VoiceLevelBars({required this.level});

  @override
  Widget build(BuildContext context) {
    const pattern = [.35, .75, .5, .95, .42, .82, .58, .7, .38, .88, .48, .64];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 0; i < pattern.length; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            curve: Curves.easeOutCubic,
            width: 4,
            height: 8 + (24 * (level * pattern[i])).clamp(0, 24).toDouble(),
            decoration: BoxDecoration(
              color: i.isEven ? _blue : const Color(0xFF60A5FA),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
      ],
    );
  }
}

class _TaskButton extends StatefulWidget {
  final int taskId;
  final String action;
  final String label;

  const _TaskButton({
    required this.taskId,
    required this.action,
    required this.label,
  });

  @override
  State<_TaskButton> createState() => _TaskButtonState();
}

class _TaskButtonState extends State<_TaskButton> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: _blue,
        side: const BorderSide(color: Color(0xFFBFDBFE)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
      ),
      onPressed: _loading
          ? null
          : () async {
              setState(() => _loading = true);
              try {
                await ApiService.chatToolTaskAction(
                  taskId: widget.taskId,
                  action: widget.action,
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Decision envoyee.')),
                  );
                }
              } finally {
                if (mounted) setState(() => _loading = false);
              }
            },
      child: Text(widget.label),
    );
  }
}

class _MediaImportTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _MediaImportTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: _primaryText(context),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: Colors.blueGrey),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final VoidCallback onTap;

  const _ToolRow({
    required this.icon,
    required this.title,
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: _softBlue,
        child: Icon(icon, color: _blue),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w900, color: _ink),
      ),
      subtitle: Text(text),
      onTap: onTap,
    );
  }
}

class _TravelToolCard extends StatelessWidget {
  final Map<String, dynamic> payload;
  final bool mine;
  final Color textColor;

  const _TravelToolCard({
    required this.payload,
    required this.mine,
    required this.textColor,
  });

  String get _kind => payload['kind']?.toString() ?? '';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final config = _config(scheme);
    final cardColor = Color.alphaBlend(
      config.color.withValues(alpha: mine ? .22 : .10),
      mine ? Colors.white.withValues(alpha: .09) : _surfacePanel(context),
    );
    final borderColor = config.color.withValues(alpha: mine ? .34 : .24);
    final code = payload['trackingCode']?.toString().isNotEmpty == true
        ? payload['trackingCode'].toString()
        : payload['reservationCode']?.toString() ?? '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: config.color.withValues(alpha: mine ? .28 : .14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(config.icon, size: 20, color: textColor),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      config.title,
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      config.subtitle,
                      style: TextStyle(
                        color: textColor.withValues(alpha: .72),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          switch (_kind) {
            'ticket' => _ticketBody(context, code),
            'tracking' => _trackingBody(context, code, config.color),
            'location' ||
            'live_location_update' => _locationBody(context, config.color),
            'package_thread' => _threadBody(
              context,
              code,
              'Colis',
              Icons.inventory_2_outlined,
              () => Navigator.pushNamed(
                context,
                '/package_tracking',
                arguments: {'trackingCode': code},
              ),
            ),
            'reservation_thread' => _threadBody(
              context,
              code,
              'Reservation',
              Icons.confirmation_number_outlined,
              () => _openTripChat(context, code),
            ),
            'contact' => _contactBody(context),
            _ => _genericBody(context, code),
          },
        ],
      ),
    );
  }

  _ToolCardConfig _config(ColorScheme scheme) {
    return switch (_kind) {
      'ticket' => const _ToolCardConfig(
        Icons.confirmation_number_outlined,
        'Billet partage',
        'Ticket verifiable et salon voyage',
        Color(0xFF2563EB),
      ),
      'tracking' => const _ToolCardConfig(
        Icons.route_outlined,
        'Suivi du trajet',
        'Position du bus et statut GPS',
        Color(0xFF0D9488),
      ),
      'location' => const _ToolCardConfig(
        Icons.my_location_outlined,
        'Position partagee',
        'Point GPS envoye manuellement',
        Color(0xFF16A34A),
      ),
      'live_location_update' => const _ToolCardConfig(
        Icons.sensors_rounded,
        'Position automatique',
        'Mise a jour pendant le voyage',
        Color(0xFF7C3AED),
      ),
      'package_thread' => const _ToolCardConfig(
        Icons.inventory_2_outlined,
        'Conversation colis',
        'Suivi et preuves de livraison',
        Color(0xFFEA580C),
      ),
      'reservation_thread' => const _ToolCardConfig(
        Icons.forum_outlined,
        'Salon reservation',
        'Discussion liee au billet',
        Color(0xFF0891B2),
      ),
      'contact' => const _ToolCardConfig(
        Icons.person_add_alt_1_rounded,
        'Contact partage',
        'Profil Tranviko verifie',
        Color(0xFF7C3AED),
      ),
      _ => _ToolCardConfig(
        Icons.travel_explore_rounded,
        'Contexte voyage',
        'Action liee a Tranviko',
        scheme.primary,
      ),
    };
  }

  Widget _ticketBody(BuildContext context, String code) {
    final route = payload['route']?.toString() ?? '';
    final seats = payload['seats'];
    final seatItems = seats is Iterable ? seats.toList() : const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _routeLine(route),
        if (_dateLabel.isNotEmpty) _mutedLine(_dateLabel),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: textColor.withValues(alpha: .22)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  code.isEmpty ? 'Code indisponible' : code,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .6,
                  ),
                ),
              ),
              Icon(Icons.qr_code_2_rounded, color: textColor),
            ],
          ),
        ),
        if (seatItems.isNotEmpty) ...[
          const SizedBox(height: 9),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final seat in seatItems.take(8))
                _chip('Siege $seat', Icons.event_seat_outlined),
            ],
          ),
        ],
        const SizedBox(height: 10),
        _actions(context, [
          _ToolAction(
            'Copier',
            Icons.copy_rounded,
            () => _copyCode(context, code),
          ),
          _ToolAction(
            'Salon',
            Icons.forum_outlined,
            () => _openTripChat(context, code),
          ),
          _ToolAction(
            'Historique',
            Icons.history_rounded,
            () => Navigator.pushNamed(context, '/history'),
          ),
        ]),
      ],
    );
  }

  Widget _trackingBody(BuildContext context, String code, Color accent) {
    final route = payload['route']?.toString() ?? '';
    final available = payload['trackingAvailable'] == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _routeLine(route),
        const SizedBox(height: 10),
        Row(
          children: [
            _stepDot(true, accent),
            Expanded(child: _stepLine(accent)),
            _stepDot(available, accent),
            Expanded(child: _stepLine(accent.withValues(alpha: .45))),
            _stepDot(false, accent),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _tiny('Billet'),
            _tiny(available ? 'GPS actif' : 'GPS attente'),
            _tiny('Arrivee'),
          ],
        ),
        const SizedBox(height: 10),
        _actions(context, [
          _ToolAction('Suivre', Icons.map_outlined, () {
            if (code.isEmpty) {
              _snack(context, 'Code de suivi indisponible.');
              return;
            }
            Navigator.pushNamed(
              context,
              '/package_tracking',
              arguments: {'trackingCode': code},
            );
          }),
          _ToolAction(
            'Salon',
            Icons.forum_outlined,
            () => _openTripChat(context, code),
          ),
          if (code.isNotEmpty)
            _ToolAction(
              'Copier',
              Icons.copy_rounded,
              () => _copyCode(context, code),
            ),
        ]),
      ],
    );
  }

  Widget _locationBody(BuildContext context, Color accent) {
    final lat = _coord(payload['latitude']);
    final lng = _coord(payload['longitude']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 92,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [
                accent.withValues(alpha: .24),
                accent.withValues(alpha: .08),
              ],
            ),
            border: Border.all(color: textColor.withValues(alpha: .18)),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _MiniMapPatternPainter(color: textColor),
                ),
              ),
              Center(
                child: Icon(Icons.location_pin, color: textColor, size: 36),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _mutedLine('GPS: ${_formatCoord(lat)}, ${_formatCoord(lng)}'),
        if ((payload['expiresAt'] ?? '').toString().isNotEmpty)
          _mutedLine('Actif jusqu a ${payload['expiresAt']}'),
        const SizedBox(height: 10),
        _actions(context, [
          _ToolAction(
            'Ouvrir carte',
            Icons.map_outlined,
            () => _openMap(context),
          ),
          _ToolAction('Copier GPS', Icons.copy_rounded, () {
            if (lat == null || lng == null) {
              _snack(context, 'Position GPS indisponible.');
              return;
            }
            Clipboard.setData(ClipboardData(text: '$lat,$lng'));
            _snack(context, 'Coordonnees copiees.');
          }),
        ]),
      ],
    );
  }

  Widget _threadBody(
    BuildContext context,
    String code,
    String label,
    IconData icon,
    VoidCallback open,
  ) {
    final route = payload['route']?.toString() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _routeLine(route.isEmpty ? '$label $code' : route),
        if (code.isNotEmpty) _mutedLine('Reference: $code'),
        const SizedBox(height: 10),
        _actions(context, [
          _ToolAction('Ouvrir', icon, open),
          if (code.isNotEmpty)
            _ToolAction(
              'Copier',
              Icons.copy_rounded,
              () => _copyCode(context, code),
            ),
        ]),
      ],
    );
  }

  Widget _contactBody(BuildContext context) {
    final userId =
        (payload['contactUserId'] as num?)?.toInt() ??
        int.tryParse(payload['contactUserId']?.toString() ?? '') ??
        0;
    final name = (payload['name'] ?? 'Contact Tranviko').toString();
    final phone = payload['phone']?.toString() ?? '';
    final isAppUser = payload['isAppUser'] == true && userId > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _Avatar(
              name: name,
              size: 42,
              photoBase64: payload['profilePhotoBase64']?.toString(),
              photoUrl: payload['profilePhotoUrl']?.toString(),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    isAppUser
                        ? 'Disponible sur Tranviko'
                        : 'Compte Tranviko indisponible',
                    style: TextStyle(
                      color: textColor.withValues(alpha: .72),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (phone.isNotEmpty) ...[const SizedBox(height: 7), _mutedLine(phone)],
        const SizedBox(height: 10),
        _actions(context, [
          if (isAppUser)
            _ToolAction('Ajouter', Icons.person_add_alt_1_rounded, () {
              unawaited(_addSharedContact(context, userId));
            }),
          if (isAppUser)
            _ToolAction('Message', Icons.chat_bubble_outline_rounded, () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatScreen(
                    other: {
                      'userId': userId,
                      'name': name,
                      'phone': phone,
                      'profilePhotoBase64': payload['profilePhotoBase64'],
                      'profilePhotoUrl': payload['profilePhotoUrl'],
                    },
                    initialSharedMedia: const [],
                  ),
                ),
              );
            }),
        ]),
      ],
    );
  }

  Future<void> _addSharedContact(BuildContext context, int userId) async {
    try {
      final response = await ApiService.sendFriendRequest(userId);
      final accepted = response['accepted'] == true;
      if (context.mounted) {
        _snack(
          context,
          accepted ? 'Contact ajoute.' : 'Demande d ami envoyee.',
        );
      }
    } catch (_) {
      if (context.mounted) {
        _snack(context, 'Ce contact ne peut pas etre ajoute pour le moment.');
      }
    }
  }

  Widget _genericBody(BuildContext context, String code) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if ((payload['route'] ?? '').toString().isNotEmpty)
        _routeLine(payload['route'].toString()),
      if (code.isNotEmpty) _mutedLine('Reference: $code'),
      if (code.isNotEmpty) ...[
        const SizedBox(height: 8),
        _actions(context, [
          _ToolAction(
            'Copier',
            Icons.copy_rounded,
            () => _copyCode(context, code),
          ),
        ]),
      ],
    ],
  );

  String get _dateLabel {
    final date = payload['travelDate']?.toString() ?? '';
    final time = payload['departureTime']?.toString() ?? '';
    return [date, time].where((value) => value.isNotEmpty).join(' a ');
  }

  Widget _routeLine(String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Text(
      value,
      style: TextStyle(color: textColor, fontWeight: FontWeight.w900),
    );
  }

  Widget _mutedLine(String value) => Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Text(
      value,
      style: TextStyle(color: textColor.withValues(alpha: .74), fontSize: 12),
    ),
  );

  Widget _chip(String label, IconData icon) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: textColor.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: textColor),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: textColor, fontSize: 11)),
      ],
    ),
  );

  Widget _actions(BuildContext context, List<_ToolAction> actions) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final action in actions)
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: textColor,
            side: BorderSide(color: textColor.withValues(alpha: .24)),
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          ),
          onPressed: action.onTap,
          icon: Icon(action.icon, size: 15),
          label: Text(action.label),
        ),
    ],
  );

  Widget _stepDot(bool active, Color accent) => Container(
    width: 16,
    height: 16,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: active ? accent : textColor.withValues(alpha: .18),
      border: Border.all(color: textColor.withValues(alpha: .28)),
    ),
  );

  Widget _stepLine(Color color) => Container(
    height: 3,
    margin: const EdgeInsets.symmetric(horizontal: 4),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(999),
    ),
  );

  Widget _tiny(String value) => Text(
    value,
    style: TextStyle(
      color: textColor.withValues(alpha: .70),
      fontSize: 10,
      fontWeight: FontWeight.w800,
    ),
  );

  void _copyCode(BuildContext context, String code) {
    if (code.isEmpty) return;
    Clipboard.setData(ClipboardData(text: code));
    _snack(context, 'Code copie.');
  }

  void _openTripChat(BuildContext context, String code) {
    if (code.isEmpty) {
      Navigator.pushNamed(context, '/history');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TripChatScreen(reservationCode: code)),
    );
  }

  Future<void> _openMap(BuildContext context) async {
    final lat = _coord(payload['latitude']);
    final lng = _coord(payload['longitude']);
    if (lat == null || lng == null) {
      _snack(context, 'Position GPS indisponible.');
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _SharedLocationMapScreen(
          latitude: lat,
          longitude: lng,
          title: payload['title']?.toString() ?? 'Position partagee',
          subtitle: payload['route']?.toString() ?? payload['note']?.toString(),
        ),
      ),
    );
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  double? _coord(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  String _formatCoord(dynamic value) {
    if (value is num) return value.toStringAsFixed(5);
    final parsed = double.tryParse(value?.toString() ?? '');
    return parsed == null ? '-' : parsed.toStringAsFixed(5);
  }
}

class _SharedLocationMapScreen extends StatelessWidget {
  final double latitude;
  final double longitude;
  final String title;
  final String? subtitle;

  const _SharedLocationMapScreen({
    required this.latitude,
    required this.longitude,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final point = latlng.LatLng(latitude, longitude);
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(initialCenter: point, initialZoom: 15),
            children: [
              TranvikoMapTiles(dark: isDark),
              MarkerLayer(
                markers: [
                  Marker(
                    point: point,
                    width: 64,
                    height: 64,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: scheme.primary.withValues(alpha: .18),
                        border: Border.all(color: scheme.primary, width: 2),
                      ),
                      child: Icon(
                        Icons.location_on_rounded,
                        color: scheme.primary,
                        size: 34,
                      ),
                    ),
                  ),
                ],
              ),
              const RichAttributionWidget(
                attributions: [TextSourceAttribution('OpenStreetMap')],
              ),
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16 + MediaQuery.paddingOf(context).bottom,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: scheme.outlineVariant),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? .28 : .10),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subtitle?.isNotEmpty == true
                        ? subtitle!
                        : 'Position Tranviko',
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolCardConfig {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  const _ToolCardConfig(this.icon, this.title, this.subtitle, this.color);
}

class _ToolAction {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _ToolAction(this.label, this.icon, this.onTap);
}

class _MiniMapPatternPainter extends CustomPainter {
  final Color color;

  const _MiniMapPatternPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: .16)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < 4; i++) {
      final y = size.height * (.18 + i * .22);
      final path = Path()
        ..moveTo(0, y)
        ..quadraticBezierTo(size.width * .32, y - 18, size.width * .62, y + 4)
        ..quadraticBezierTo(size.width * .86, y + 20, size.width, y - 6);
      canvas.drawPath(path, paint);
    }
    for (var i = 0; i < 3; i++) {
      final x = size.width * (.22 + i * .27);
      canvas.drawLine(Offset(x, 0), Offset(x - 18, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MiniMapPatternPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _Avatar extends StatefulWidget {
  final String name;
  final double size;
  final String? photoBase64;
  final String? photoUrl;

  const _Avatar({
    required this.name,
    this.size = 44,
    this.photoBase64,
    this.photoUrl,
  });

  @override
  State<_Avatar> createState() => _AvatarState();
}

class _AvatarState extends State<_Avatar> {
  ImageProvider? _imageProvider;
  String? _lastPhotoBase64;
  String? _lastPhotoUrl;

  @override
  void initState() {
    super.initState();
    _refreshImageProvider();
  }

  @override
  void didUpdateWidget(covariant _Avatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photoBase64 != widget.photoBase64 ||
        oldWidget.photoUrl != widget.photoUrl) {
      _refreshImageProvider();
    }
  }

  void _refreshImageProvider() {
    _lastPhotoBase64 = widget.photoBase64;
    _lastPhotoUrl = widget.photoUrl;
    _imageProvider = _buildImageProvider();
  }

  ImageProvider? _buildImageProvider() {
    final raw = _lastPhotoBase64 ?? '';
    if (raw.isNotEmpty) {
      try {
        final encoded = raw.contains(',') ? raw.split(',').last : raw;
        return MemoryImage(base64Decode(encoded));
      } catch (_) {
        return null;
      }
    }
    final url = _lastPhotoUrl ?? '';
    return url.isNotEmpty ? NetworkImage(url) : null;
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.name.trim().isEmpty
        ? '?'
        : widget.name.trim()[0].toUpperCase();
    final scheme = Theme.of(context).colorScheme;
    final bg = Color.alphaBlend(
      scheme.primary.withValues(alpha: .14),
      _surfacePanel(context),
    );
    return Container(
      width: widget.size,
      height: widget.size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(color: scheme.primary.withValues(alpha: .22)),
        image: _imageProvider == null
            ? null
            : DecorationImage(image: _imageProvider!, fit: BoxFit.cover),
      ),
      child: _imageProvider == null
          ? Text(
              initial,
              style: TextStyle(
                color: scheme.primary,
                fontWeight: FontWeight.w900,
                fontSize: widget.size * .42,
              ),
            )
          : null,
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool archived;
  final bool favorites;

  const _EmptyState({required this.archived, this.favorites = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      key: const ValueKey('empty'),
      padding: const EdgeInsets.fromLTRB(24, 54, 24, 24),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: .08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              archived
                  ? Icons.archive_outlined
                  : favorites
                  ? Icons.star_border_rounded
                  : Icons.forum_outlined,
              size: 30,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            archived
                ? 'Aucune discussion archivee'
                : favorites
                ? 'Ajoutez une etoile aux discussions importantes.'
                : 'Aucune discussion active',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _primaryText(context),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

String _duration(int seconds) {
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  return '$minutes:${rest.toString().padLeft(2, '0')}';
}

List<double> _waveformFromMetadata(Map? metadata) {
  final raw = metadata?['waveform'];
  if (raw is! List) return const [];
  return raw
      .map(
        (item) =>
            item is num ? item.toDouble().clamp(.05, 1.0).toDouble() : null,
      )
      .whereType<double>()
      .toList(growable: false);
}

String _time(String? value) {
  final date = DateTime.tryParse(value ?? '')?.toLocal();
  if (date == null) return '';
  return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

String _dateTimeLabel(String? value) {
  final date = DateTime.tryParse(value ?? '')?.toLocal();
  if (date == null) return 'Indisponible';
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final year = date.year.toString();
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$day/$month/$year a $hour:$minute';
}
