import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'api_service.dart';
import 'native_call_service.dart';
import 'story_cache_service.dart';

const String _messageReplyActionId = 'reply_message';

@pragma('vm:entry-point')
void tranvikoNotificationResponseBackground(NotificationResponse response) {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  PushNotificationService.handleNotificationResponse(
    response,
    background: true,
  );
}

class PushNotificationService {
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static const int _ongoingCallNotificationId = 72040;
  static StreamSubscription<String>? _tokenRefreshSubscription;
  static StreamSubscription<RemoteMessage>? _foregroundSubscription;
  static StreamSubscription<RemoteMessage>? _openedSubscription;
  static bool _localReady = false;
  static bool _timezoneReady = false;
  static void Function(Map<String, dynamic> data)? onNotificationTap;

  static Future<void> configure() async {
    if (ApiService.activeToken == null) return;
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getBool('onboarding_seen') != true) return;

    try {
      await _configureLocalNotifications();
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      unawaited(NativeCallService.requestPermissions());
      unawaited(NativeCallService.warmUp());
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
            alert: true,
            badge: true,
            sound: true,
          );
      await _registerCurrentToken(messaging);

      _tokenRefreshSubscription ??= messaging.onTokenRefresh.listen((token) {
        unawaited(_registerToken(token));
      });
      _foregroundSubscription ??= FirebaseMessaging.onMessage.listen(
        _showForegroundNotification,
      );
      _openedSubscription ??= FirebaseMessaging.onMessageOpenedApp.listen(
        _handleRemoteMessageTap,
      );
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        scheduleMicrotask(() => _handleRemoteMessageTap(initialMessage));
      }
    } catch (error) {
      debugPrint('Push notification setup failed: $error');
    }
  }

  static Future<void> _configureLocalNotifications() async {
    if (_localReady || kIsWeb) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const settings = InitializationSettings(android: android, iOS: ios);
    await _localNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: handleNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
          tranvikoNotificationResponseBackground,
    );
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'transport_high_importance',
        'Notifications Transport',
        description: 'Messages et alertes prioritaires',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'transport_ongoing_calls',
        'Appels en cours',
        description: 'Indicateur permanent pendant un appel audio',
        importance: Importance.high,
        playSound: false,
        enableVibration: false,
        showBadge: false,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'ticket_departure_reminders',
        'Rappels de depart',
        description: 'Alertes locales avant le depart du bus',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'driver_gps_alerts',
        'Alertes GPS conducteur',
        description:
            'Alertes locales quand la connexion du suivi GPS devient instable',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      ),
    );
    _localReady = true;
  }

  static Future<void> scheduleTicketDepartureReminders(
    List<Map<String, dynamic>> reservations,
  ) async {
    if (kIsWeb) return;
    await _configureLocalNotifications();
    _ensureTimezoneReady();
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('ticket_reminders') ?? true;
    await _cancelStoredTicketReminders(prefs);
    if (!enabled) return;
    final now = DateTime.now();
    final scheduledIds = <String>[];
    for (final reservation in reservations) {
      if (_isCancelledReservation(reservation)) continue;
      final departure = _reservationDeparture(reservation);
      if (departure == null || !departure.isAfter(now)) continue;
      final code = _reservationCode(reservation);
      if (code.isEmpty) continue;
      for (final minutes in const [30, 5]) {
        final target = departure.subtract(Duration(minutes: minutes));
        if (!target.isAfter(now.add(const Duration(seconds: 8)))) continue;
        final id = _stableReminderId('$code-$minutes');
        await _localNotifications.zonedSchedule(
          id,
          'Depart dans $minutes minutes',
          _reminderBody(reservation, departure),
          tz.TZDateTime.from(target, tz.local),
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'ticket_departure_reminders',
              'Rappels de depart',
              channelDescription: 'Alertes locales avant le depart du bus',
              importance: Importance.max,
              priority: Priority.high,
              category: AndroidNotificationCategory.reminder,
              visibility: NotificationVisibility.public,
              playSound: true,
              enableVibration: true,
            ),
            iOS: DarwinNotificationDetails(
              presentAlert: true,
              presentBadge: true,
              presentSound: true,
            ),
          ),
          payload: jsonEncode({
            'type': 'ticket_reminder',
            'reservationCode': code,
            'minutes': minutes.toString(),
          }),
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
        scheduledIds.add(id.toString());
      }
    }
    await prefs.setStringList('ticket_reminder_ids', scheduledIds);
  }

  static Future<void> cancelTicketDepartureReminders() async {
    if (kIsWeb) return;
    await _configureLocalNotifications();
    final prefs = await SharedPreferences.getInstance();
    await _cancelStoredTicketReminders(prefs);
  }

  static Future<void> _cancelStoredTicketReminders(
    SharedPreferences prefs,
  ) async {
    final ids = prefs.getStringList('ticket_reminder_ids') ?? const <String>[];
    for (final raw in ids) {
      final id = int.tryParse(raw);
      if (id != null) await _localNotifications.cancel(id);
    }
    await prefs.remove('ticket_reminder_ids');
  }

  static void _ensureTimezoneReady() {
    if (_timezoneReady) return;
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Africa/Bamako'));
    } catch (_) {}
    _timezoneReady = true;
  }

  static bool _isCancelledReservation(Map<String, dynamic> reservation) {
    final status = (reservation['status'] ?? '').toString().toLowerCase();
    return reservation['isCancelled'] == true ||
        status.contains('annul') ||
        status.contains('cancel');
  }

  static String _reservationCode(Map<String, dynamic> reservation) =>
      (reservation['qrData'] ??
              reservation['code'] ??
              reservation['reservationCode'] ??
              reservation['id'] ??
              '')
          .toString();

  static DateTime? _reservationDeparture(Map<String, dynamic> reservation) {
    final bus = reservation['bus'] is Map ? reservation['bus'] as Map : null;
    final date = (reservation['date'] ?? reservation['travelDate'] ?? '')
        .toString()
        .trim();
    final time =
        (reservation['time'] ??
                reservation['departureTime'] ??
                bus?['time'] ??
                '')
            .toString()
            .trim();
    if (date.isEmpty || time.isEmpty) return null;
    return DateTime.tryParse('$date ${time.length == 5 ? '$time:00' : time}');
  }

  static String _reminderBody(
    Map<String, dynamic> reservation,
    DateTime departure,
  ) {
    final departureCity = (reservation['departure'] ?? '').toString();
    final destination = (reservation['destination'] ?? '').toString();
    final route = [
      departureCity,
      destination,
    ].where((value) => value.trim().isNotEmpty).join(' -> ');
    final seats = reservation['seats'] ?? reservation['selectedSeats'];
    final seatsLabel = seats is Iterable && seats.isNotEmpty
        ? 'Sieges ${seats.join(', ')}'
        : 'Verifiez votre billet';
    final time =
        '${departure.hour.toString().padLeft(2, '0')}:${departure.minute.toString().padLeft(2, '0')}';
    return [
      if (route.isNotEmpty) route,
      '$seatsLabel - depart $time',
    ].join('\n');
  }

  static int _stableReminderId(String value) {
    var hash = 0;
    for (final unit in value.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return 810000 + (hash % 1000000);
  }

  static Future<void> showOngoingCallNotification({
    required String title,
    required String status,
    required String routeName,
  }) async {
    if (kIsWeb) return;
    await _configureLocalNotifications();
    final androidDetails = AndroidNotificationDetails(
      'transport_ongoing_calls',
      'Appels en cours',
      channelDescription: 'Indicateur permanent pendant un appel audio',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.call,
      visibility: NotificationVisibility.public,
      ticker: title,
      ongoing: true,
      autoCancel: false,
      playSound: false,
      enableVibration: false,
      usesChronometer: true,
      showWhen: true,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: false,
      presentBadge: false,
      presentSound: false,
    );
    await _localNotifications.show(
      _ongoingCallNotificationId,
      title,
      status,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: jsonEncode({
        'type': 'ongoing_audio_call',
        'routeName': routeName,
      }),
    );
  }

  static Future<void> clearOngoingCallNotification() async {
    if (kIsWeb) return;
    await _configureLocalNotifications();
    await _localNotifications.cancel(_ongoingCallNotificationId);
  }

  static Future<void> showDriverGpsConnectionAlert({
    required String title,
    required String body,
    String? journeyId,
  }) async {
    if (kIsWeb) return;
    await _configureLocalNotifications();
    final androidDetails = AndroidNotificationDetails(
      'driver_gps_alerts',
      'Alertes GPS conducteur',
      channelDescription:
          'Alertes locales quand la connexion du suivi GPS devient instable',
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.status,
      visibility: NotificationVisibility.public,
      playSound: true,
      enableVibration: true,
      styleInformation: BigTextStyleInformation(body),
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    await _localNotifications.show(
      73040,
      title,
      body,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: jsonEncode({
        'type': 'driver_gps_connection_alert',
        if (journeyId != null) 'journeyId': journeyId,
      }),
    );
  }

  static Future<void> _showForegroundNotification(RemoteMessage message) async {
    unawaited(
      acknowledgeMessageDelivery(message.data, source: 'firebase_foreground'),
    );
    final pushType = message.data['type']?.toString().toLowerCase() ?? '';
    if (pushType == 'story_update') {
      if (!kIsWeb) {
        unawaited(
          StoryCacheService.fetchAndCacheStories().catchError(
            (_) => <Map<String, dynamic>>[],
          ),
        );
      }
      return;
    }
    if (kIsWeb || !_localReady) return;
    final notification = message.notification;
    final isCall = message.data['type'] == 'incoming_audio_call';
    if (message.data['type'] == 'call_closed') {
      final acceptedDeviceId = message.data['acceptedDeviceId']?.toString();
      if (acceptedDeviceId != null && acceptedDeviceId.isNotEmpty) {
        final localDeviceId = await ApiService.callDeviceId();
        if (acceptedDeviceId == localDeviceId) return;
      }
      final callId = message.data['callId']?.toString() ?? '';
      if (callId.isNotEmpty) await NativeCallService.endCall(callId);
      return;
    }
    if (isCall) {
      await NativeCallService.showIncomingCall(
        Map<String, dynamic>.from(message.data),
      );
      return;
    }
    final title =
        notification?.title ??
        message.data['title'] ??
        (isCall ? 'Appel entrant' : 'Notification');
    final body =
        notification?.body ??
        message.data['body'] ??
        message.data['message'] ??
        (isCall ? 'Touchez pour repondre' : '');
    final androidDetails = AndroidNotificationDetails(
      isCall ? 'transport_calls' : 'transport_high_importance',
      isCall ? 'Appels Transport' : 'Notifications Transport',
      channelDescription: isCall
          ? 'Notifications prioritaires pour les appels entrants'
          : 'Notifications importantes de transport',
      importance: Importance.max,
      priority: Priority.high,
      category: isCall
          ? AndroidNotificationCategory.call
          : AndroidNotificationCategory.message,
      visibility: NotificationVisibility.public,
      ticker: title.toString(),
      fullScreenIntent: isCall,
      playSound: true,
      enableVibration: true,
      styleInformation: BigTextStyleInformation(body.toString()),
      actions: _messageNotificationActions(message.data),
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title.toString(),
      body.toString(),
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: jsonEncode(message.data),
    );
  }

  static Future<void> showMessageNotificationFromData(
    Map<dynamic, dynamic> rawData, {
    String source = 'firebase_background',
  }) async {
    final data = Map<String, dynamic>.from(rawData);
    if (!_isChatMessageData(data)) return;
    await acknowledgeMessageDelivery(data, source: source);
    if (kIsWeb) return;
    await _configureLocalNotifications();
    if (!_localReady) return;
    final title = data['title']?.toString().trim().isNotEmpty == true
        ? data['title'].toString()
        : 'Nouveau message';
    final body = data['body']?.toString().trim().isNotEmpty == true
        ? data['body'].toString()
        : data['message']?.toString() ?? 'Message recu';
    final androidDetails = AndroidNotificationDetails(
      'transport_high_importance',
      'Notifications Transport',
      channelDescription: 'Messages et alertes prioritaires',
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.message,
      visibility: NotificationVisibility.public,
      ticker: title,
      playSound: true,
      enableVibration: true,
      styleInformation: BigTextStyleInformation(body),
      actions: _messageNotificationActions(data),
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: jsonEncode(data),
    );
  }

  static void _handleRemoteMessageTap(RemoteMessage message) {
    unawaited(acknowledgeMessageDelivery(message.data, source: 'firebase_tap'));
    _dispatchTap(Map<String, dynamic>.from(message.data));
  }

  static void handleNotificationResponse(
    NotificationResponse response, {
    bool background = false,
  }) {
    if (response.actionId == _messageReplyActionId) {
      unawaited(_sendInlineMessageReply(response));
      return;
    }
    _handleNotificationTapPayload(response.payload);
  }

  static List<AndroidNotificationAction>? _messageNotificationActions(
    Map<String, dynamic> data,
  ) {
    if (!_isChatMessageData(data)) return null;
    return const [
      AndroidNotificationAction(
        _messageReplyActionId,
        'Repondre',
        showsUserInterface: false,
        allowGeneratedReplies: true,
        inputs: [AndroidNotificationActionInput(label: 'Votre reponse')],
      ),
      AndroidNotificationAction(
        'open_message',
        'Ouvrir',
        showsUserInterface: true,
      ),
    ];
  }

  static Future<void> _restoreSessionForBackgroundAction() async {
    final preferences = await SharedPreferences.getInstance();
    await ApiService.loadStoredCompany();
    ApiService.userToken = preferences.getString('user_token');
    ApiService.agentToken = preferences.getString('agent_token');
    final agentJson = preferences.getString('current_agent');
    final userJson = preferences.getString('current_user');
    if (agentJson != null && ApiService.agentToken != null) {
      try {
        ApiService.currentAgent = jsonDecode(agentJson) as Map<String, dynamic>;
      } catch (_) {
        ApiService.currentAgent = null;
      }
      ApiService.currentUser = null;
      ApiService.userToken = null;
      return;
    }
    ApiService.currentAgent = null;
    if (userJson != null) {
      try {
        ApiService.currentUser = jsonDecode(userJson) as Map<String, dynamic>;
      } catch (_) {
        ApiService.currentUser = null;
      }
    }
  }

  static Future<void> _sendInlineMessageReply(
    NotificationResponse response,
  ) async {
    final text = response.input?.trim() ?? '';
    if (text.isEmpty) return;
    Map<String, dynamic> data = const <String, dynamic>{};
    try {
      final decoded = jsonDecode(response.payload ?? '{}');
      if (decoded is! Map) return;
      data = Map<String, dynamic>.from(decoded);
      final targetId = int.tryParse(
        data['senderId']?.toString() ??
            data['sender_id']?.toString() ??
            data['fromId']?.toString() ??
            data['conversationId']?.toString() ??
            '',
      );
      if (targetId == null || targetId <= 0) return;
      await _restoreSessionForBackgroundAction();
      final companyId =
          data['companyId']?.toString() ?? data['company_id']?.toString();
      final companySlug =
          data['companySlug']?.toString() ?? data['company_slug']?.toString();
      if (companyId != null && companyId.trim().isNotEmpty) {
        ApiService.companyId = companyId.trim();
      }
      if (companySlug != null && companySlug.trim().isNotEmpty) {
        ApiService.companySlug = companySlug.trim();
      }
      await ApiService.sendChatMessage(
        userId: targetId,
        body: text,
        metadata: {'quickReply': true, 'source': 'notification_reply'},
      );
      await _showInlineReplyStatus(
        'Reponse envoyee',
        'Votre message a bien ete transmis.',
        success: true,
      );
    } catch (error) {
      debugPrint('Inline notification reply failed: $error');
      await _showInlineReplyStatus(
        'Reponse non envoyee',
        'Ouvrez Tranviko pour renvoyer ce message.',
        success: false,
      );
    }
  }

  static Future<void> _showInlineReplyStatus(
    String title,
    String body, {
    required bool success,
  }) async {
    if (kIsWeb) return;
    await _configureLocalNotifications();
    if (!_localReady) return;
    final androidDetails = AndroidNotificationDetails(
      'transport_status',
      'Statut Tranviko',
      channelDescription: 'Confirmations rapides de Tranviko',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.status,
      playSound: false,
      enableVibration: !success,
      color: success ? const Color(0xFF10B981) : const Color(0xFFEF4444),
      styleInformation: BigTextStyleInformation(body),
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: false,
    );
    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }

  static void _handleNotificationTapPayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        unawaited(
          acknowledgeMessageDelivery(decoded, source: 'local_notification_tap'),
        );
        _dispatchTap(decoded);
      }
    } catch (error) {
      debugPrint('Notification payload decode failed: $error');
    }
  }

  static void _dispatchTap(Map<String, dynamic> data) {
    onNotificationTap?.call(data);
  }

  static Future<void> acknowledgeMessageDelivery(
    Map<dynamic, dynamic> data, {
    String source = 'push_received',
  }) async {
    if (!_isChatMessageData(data)) return;
    final messageId = int.tryParse(
      data['messageId']?.toString() ??
          data['message_id']?.toString() ??
          data['id']?.toString() ??
          '',
    );
    if (messageId == null || messageId <= 0) return;
    try {
      await ApiService.ackChatDelivered([messageId], source: source);
    } catch (error) {
      debugPrint('Chat delivery ack failed: $error');
    }
  }

  static bool _isChatMessageData(Map<dynamic, dynamic> data) {
    final type = data['type']?.toString().toLowerCase() ?? '';
    final category = data['category']?.toString().toLowerCase() ?? '';
    final hasMessageId =
        (data['messageId']?.toString().isNotEmpty ?? false) ||
        (data['message_id']?.toString().isNotEmpty ?? false);
    return type == 'message' ||
        type == 'chat' ||
        type == 'chat_message' ||
        (category == 'message' && hasMessageId);
  }

  static Future<void> _registerCurrentToken(FirebaseMessaging messaging) async {
    final token = await messaging.getToken();
    if (token == null || token.isEmpty) return;
    await _registerToken(token);
  }

  static Future<void> _registerToken(String token) async {
    if (ApiService.activeToken == null) return;
    try {
      await ApiService.registerPushDevice(token: token, platform: _platform);
    } catch (error) {
      debugPrint('Push token registration failed: $error');
    }
  }

  static String get _platform {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      _ => 'unknown',
    };
  }
}
