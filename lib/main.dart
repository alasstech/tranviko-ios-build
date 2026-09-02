import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; // 1. Import package de base
import 'firebase_options.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'screens/onboarding_screen.dart';
import 'screens/home_screen.dart';
import 'screens/company_selection_screen.dart';
import 'screens/bus_selection_screen.dart';
import 'screens/seat_plan_screen.dart';
import 'screens/passenger_details_screen.dart';
import 'screens/order_summary_screen.dart';
import 'screens/payment_screen.dart';
import 'screens/confirmation_screen.dart';
import 'screens/package_tracking_screen.dart';
import 'screens/history_screen.dart';
import 'screens/admin_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/messages_screen.dart';
import 'screens/trip_chat_screen.dart';
import 'screens/audio_call_screen.dart';
import 'screens/contact_service_screen.dart';
import 'screens/route_map_screen.dart';
import 'screens/qr_device_login_screen.dart';
import 'app_state.dart';
import 'l10n/app_text.dart';
import 'models/reservation_store.dart';
import 'services/api_service.dart';
import 'services/account_warmup_service.dart';
import 'services/app_lock_service.dart';
import 'services/active_call_service.dart';
import 'services/push_notification_service.dart';
import 'services/native_call_service.dart';
import 'services/local_cache_service.dart';
import 'services/story_cache_service.dart';
import 'services/websocket_connector.dart';
import 'services/interaction_feedback_service.dart';
import 'widgets/tranviko_interaction_surface.dart';

final GlobalKey<ScaffoldMessengerState> rootMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
Map<String, dynamic>? _pendingAcceptedCall;
const String _pendingNativeAcceptedCallKey = 'pending_native_accepted_call';
const String _recentNativeAcceptPrefix = 'recent_native_accept_';
const String _programmaticNativeEndPrefix = 'programmatic_native_end_';
String? _activeAudioCallRouteId;

void _installFrameDiagnostics() {
  var slowFrameCount = 0;
  var frameCount = 0;
  var worstFrameMs = 0.0;
  Timer? reportingTimer;

  SchedulerBinding.instance.addTimingsCallback((timings) {
    for (final timing in timings) {
      frameCount += 1;
      final frameMs =
          (timing.buildDuration + timing.rasterDuration).inMicroseconds / 1000;
      if (frameMs >= 32) slowFrameCount += 1;
      if (frameMs > worstFrameMs) worstFrameMs = frameMs;
    }
    reportingTimer ??= Timer(const Duration(seconds: 60), () {
      final total = frameCount;
      final slow = slowFrameCount;
      final worst = worstFrameMs;
      reportingTimer = null;
      frameCount = 0;
      slowFrameCount = 0;
      worstFrameMs = 0;
      if (total < 20 || slow < 6) return;
      unawaited(
        ApiService.reportClientDiagnostic(
          eventType: 'performance',
          severity: slow / total >= .35 ? 'warning' : 'info',
          message: 'Ralentissements UI detectes sur $slow images sur $total.',
          screen: 'flutter_frames',
          extra: {
            'frameCount': total,
            'slowFrameCount': slow,
            'slowFrameRatio': slow / total,
            'worstFrameMs': worst,
          },
        ),
      );
    });
  });
}

Future<FirebaseApp> initializeTranvikoFirebase() {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    // Apple builds use the app-specific GoogleService-Info.plist bundled by Xcode.
    return Firebase.initializeApp();
  }
  return Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}

void activateCacheScopeForCurrentSession() {
  final agent = ApiService.currentAgent;
  if (agent != null) {
    LocalCacheService.activateAccountScope(
      accountType: 'agent',
      accountId: agent['id'] ?? agent['userId'],
      companyId:
          agent['companyId'] ?? ApiService.companyId ?? ApiService.companySlug,
    );
    return;
  }
  final user = ApiService.currentUser;
  if (user != null) {
    LocalCacheService.activateAccountScope(
      accountType: 'traveler',
      accountId: user['id'] ?? user['userId'],
    );
    return;
  }
  LocalCacheService.useAnonymousScope();
}

Future<void> restoreApiSessionFromPrefs(SharedPreferences preferences) async {
  await ApiService.loadStoredCompany();
  final storedAgentJson = preferences.getString('current_agent');
  final storedAgentToken = preferences.getString('agent_token');
  final storedUserJson = preferences.getString('current_user');
  final storedUserToken = preferences.getString('user_token');
  if (storedAgentJson != null && storedAgentToken != null) {
    ApiService.userToken = null;
    ApiService.currentUser = null;
    ApiService.agentToken = storedAgentToken;
    try {
      ApiService.currentAgent =
          jsonDecode(storedAgentJson) as Map<String, dynamic>;
      final company = ApiService.currentAgent?['company'];
      if (company is Map) {
        ApiService.companyId = company['id']?.toString();
        ApiService.companySlug = company['slug']?.toString();
      }
    } catch (_) {
      ApiService.currentAgent = null;
    }
    activateCacheScopeForCurrentSession();
    return;
  }
  ApiService.agentToken = null;
  ApiService.currentAgent = null;
  ApiService.userToken = storedUserToken;
  if (storedUserJson != null) {
    try {
      ApiService.currentUser =
          jsonDecode(storedUserJson) as Map<String, dynamic>;
    } catch (_) {
      ApiService.currentUser = null;
    }
  }
  activateCacheScopeForCurrentSession();
}

@pragma('vm:entry-point')
Future<void> callkitBackgroundHandler(CallEvent event) async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  await restoreApiSessionFromPrefs(preferences);
  CallKitParams? params;
  if (event is CallEventActionCallAccept) params = event.callKitParams;
  if (event is CallEventActionCallDecline) params = event.callKitParams;
  if (event is CallEventActionCallEnded) params = event.callKitParams;
  final extra = Map<String, dynamic>.from(params?.extra ?? const {});
  final id = extra['callId']?.toString().isNotEmpty == true
      ? extra['callId'].toString()
      : params?.id ?? '';
  if (id.isNotEmpty) extra['callId'] = id;
  if (event is CallEventActionCallAccept) {
    extra['nativeAction'] = 'accept';
    extra['type'] = 'incoming_audio_call';
    if (id.isNotEmpty) {
      await preferences.setInt(
        '$_recentNativeAcceptPrefix$id',
        DateTime.now().millisecondsSinceEpoch,
      );
    }
    await preferences.setString(
      _pendingNativeAcceptedCallKey,
      jsonEncode(extra),
    );
    await sendNativeCallAction(extra, 'call_accept');
  } else if (event is CallEventActionCallDecline) {
    await preferences.remove(_pendingNativeAcceptedCallKey);
    await sendNativeCallAction(extra, 'call_reject');
  } else if (event is CallEventActionCallEnded) {
    if (id.isNotEmpty) {
      final programmaticEndAt = preferences.getInt(
        '$_programmaticNativeEndPrefix$id',
      );
      if (programmaticEndAt != null &&
          DateTime.now().millisecondsSinceEpoch - programmaticEndAt < 120000) {
        return;
      }
      final acceptedAt = preferences.getInt('$_recentNativeAcceptPrefix$id');
      if (acceptedAt != null &&
          DateTime.now().millisecondsSinceEpoch - acceptedAt < 4000) {
        return;
      }
    }
    await preferences.remove(_pendingNativeAcceptedCallKey);
    await sendNativeCallAction(extra, 'call_end');
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await initializeTranvikoFirebase();
  final preferences = await SharedPreferences.getInstance();
  await restoreApiSessionFromPrefs(preferences);
  try {
    final pushType = message.data['type']?.toString().toLowerCase() ?? '';
    final pushCategory =
        message.data['category']?.toString().toLowerCase() ?? '';
    final hasMessageId =
        (message.data['messageId']?.toString().isNotEmpty ?? false) ||
        (message.data['message_id']?.toString().isNotEmpty ?? false);
    if (pushType == 'message' ||
        pushType == 'chat' ||
        pushType == 'chat_message' ||
        (pushCategory == 'message' && hasMessageId)) {
      await PushNotificationService.showMessageNotificationFromData(
        message.data,
        source: 'firebase_background',
      );
      return;
    }
    if (pushType == 'story_update') {
      await StoryCacheService.fetchAndCacheStories();
      return;
    }
    await PushNotificationService.acknowledgeMessageDelivery(
      message.data,
      source: 'firebase_background',
    );
    if (message.data['type'] == 'incoming_audio_call') {
      await NativeCallService.showIncomingCall(
        Map<String, dynamic>.from(message.data),
      );
    }
    if (message.data['type'] == 'call_closed') {
      final callId = message.data['callId']?.toString() ?? '';
      final acceptedDeviceId = message.data['acceptedDeviceId']?.toString();
      if (acceptedDeviceId != null && acceptedDeviceId.isNotEmpty) {
        final localDeviceId = await ApiService.callDeviceId();
        if (acceptedDeviceId == localDeviceId) return;
      }
      if (callId.isNotEmpty) await NativeCallService.endCall(callId);
    }
  } catch (error) {
    debugPrint('Background call notification failed: $error');
  }
}

Future<void> sendNativeCallAction(
  Map<String, dynamic> data,
  String action,
) async {
  final callerId = int.tryParse(
    data['callerId']?.toString() ?? data['fromId']?.toString() ?? '',
  );
  final callId = data['callId']?.toString();
  if (callerId == null ||
      callId == null ||
      callId.isEmpty ||
      ApiService.activeToken == null) {
    return;
  }
  try {
    final deviceId = await ApiService.callDeviceId();
    final channel = connectAppWebSocket(ApiService.callWebSocketUri());
    await channel.ready.timeout(const Duration(seconds: 8));
    final payload = <String, dynamic>{
      'action': action,
      'targetId': callerId,
      'callId': callId,
      'payload': {
        'deviceId': deviceId,
        if (action == 'call_accept') ...{
          'acceptedDevice': 'mobile-native',
          'acceptedDeviceId': deviceId,
          'media':
              data['media']?.toString() == 'video' ||
                  data['callMode']?.toString() == 'video'
              ? 'video'
              : 'audio',
        },
      },
    };
    channel.sink.add(jsonEncode(payload));
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await channel.sink.close();
  } catch (_) {}
}

void handleNativeCallAccepted(Map<String, dynamic> data) {
  final callId = data['callId']?.toString() ?? '';
  if (callId.isNotEmpty) {
    unawaited(_rememberAcceptedNativeCall(callId, data));
  }
  unawaited(sendNativeCallAction(data, 'call_accept'));
  _openIncomingAudioCall(data);
}

Future<void> _rememberAcceptedNativeCall(
  String callId,
  Map<String, dynamic> data,
) async {
  final preferences = await SharedPreferences.getInstance();
  await preferences.setInt(
    '$_recentNativeAcceptPrefix$callId',
    DateTime.now().millisecondsSinceEpoch,
  );
  await preferences.setString(
    _pendingNativeAcceptedCallKey,
    jsonEncode({...data, 'callId': callId, 'nativeAction': 'accept'}),
  );
}

void _openIncomingAudioCall(Map<String, dynamic> data) {
  final callerId = int.tryParse(
    data['callerId']?.toString() ?? data['fromId']?.toString() ?? '',
  );
  final callId = data['callId']?.toString();
  final callerName = data['callerName']?.toString().isNotEmpty == true
      ? data['callerName'].toString()
      : 'Appel entrant';
  if (callerId == null || callId == null || callId.isEmpty) return;
  final navigator = rootNavigatorKey.currentState;
  if (navigator == null) {
    _pendingAcceptedCall = Map<String, dynamic>.from(data);
    return;
  }
  if (_activeAudioCallRouteId == callId) return;
  _activeAudioCallRouteId = callId;
  navigator
      .push(
        MaterialPageRoute(
          settings: RouteSettings(name: AudioCallScreen.routeNameFor(callId)),
          builder: (_) => AudioCallScreen(
            targetId: callerId,
            title: callerName,
            incoming: true,
            acceptedByNative: data['nativeAction'] == 'accept',
            initialCallId: callId,
            callerId: callerId,
            callerName: callerName,
            videoCall:
                data['media']?.toString() == 'video' ||
                data['callMode']?.toString() == 'video',
          ),
        ),
      )
      .whenComplete(() {
        if (_activeAudioCallRouteId == callId) {
          _activeAudioCallRouteId = null;
        }
      });
}

Future<void> drainPendingAcceptedCall() async {
  final preferences = await SharedPreferences.getInstance();
  final rawPending = preferences.getString(_pendingNativeAcceptedCallKey);
  if (rawPending != null && rawPending.isNotEmpty) {
    await preferences.remove(_pendingNativeAcceptedCallKey);
    try {
      _pendingAcceptedCall = Map<String, dynamic>.from(
        jsonDecode(rawPending) as Map,
      );
    } catch (_) {}
  }
  if (_pendingAcceptedCall == null) {
    try {
      final activeCalls = await FlutterCallkitIncoming.activeCalls();
      for (final call in activeCalls) {
        final extra = Map<String, dynamic>.from(call.extra ?? const {});
        if (extra['type'] != 'incoming_audio_call') continue;
        final callId = extra['callId']?.toString().isNotEmpty == true
            ? extra['callId'].toString()
            : call.id;
        if (callId.isEmpty) continue;
        final acceptedAt = preferences.getInt(
          '$_recentNativeAcceptPrefix$callId',
        );
        if (acceptedAt == null ||
            DateTime.now().millisecondsSinceEpoch - acceptedAt >= 300000) {
          continue;
        }
        extra['callId'] = callId;
        extra['nativeAction'] = 'accept';
        _pendingAcceptedCall = extra;
        break;
      }
    } catch (_) {}
  }
  final data = _pendingAcceptedCall;
  if (data == null) return;
  _pendingAcceptedCall = null;
  _openIncomingAudioCall(data);
}

void handlePushNotificationTap(Map<String, dynamic> data) {
  final type = data['type']?.toString() ?? data['category']?.toString();
  if (type == 'call_closed') {
    final callId = data['callId']?.toString() ?? '';
    final acceptedDeviceId = data['acceptedDeviceId']?.toString();
    if (acceptedDeviceId != null && acceptedDeviceId.isNotEmpty) {
      unawaited(
        ApiService.callDeviceId().then((localDeviceId) {
          if (acceptedDeviceId != localDeviceId && callId.isNotEmpty) {
            return NativeCallService.endCall(callId);
          }
        }),
      );
      return;
    }
    if (callId.isNotEmpty) unawaited(NativeCallService.endCall(callId));
    return;
  }
  if (type == 'incoming_audio_call') {
    _openIncomingAudioCall(data);
    return;
  }
  if (type == 'ongoing_audio_call') {
    _restoreActiveCallRoute();
    return;
  }
  if (type == 'ticket_reminder') {
    rootNavigatorKey.currentState?.pushNamed('/history', arguments: data);
    return;
  }
  if (type == 'seat_available') {
    final tripId = int.tryParse(data['tripId']?.toString() ?? '');
    if (tripId == null) return;
    final requestedSeats =
        int.tryParse(data['requestedSeats']?.toString() ?? '') ?? 1;
    final totalSeats = int.tryParse(data['totalSeats']?.toString() ?? '') ?? 40;
    final priceValue = int.tryParse(data['priceValue']?.toString() ?? '') ?? 0;
    rootNavigatorKey.currentState?.pushNamed(
      '/seat_plan',
      arguments: {
        'departure': data['departure']?.toString() ?? '',
        'destination': data['destination']?.toString() ?? '',
        'date': data['travelDate']?.toString() ?? '',
        'passengerCount': requestedSeats,
        'allowFlexibleSeatCount': true,
        'bus': {
          'id': tripId,
          'companyId': data['companyId']?.toString(),
          'companyName': data['companyName']?.toString(),
          'travelDate': data['travelDate']?.toString(),
          'time': data['departureTime']?.toString(),
          'arrival': data['arrivalTime']?.toString(),
          'type': data['busType']?.toString(),
          'price': '$priceValue FCFA',
          'priceValue': priceValue,
          'totalSeats': totalSeats,
          'occupiedSeats': const <int>[],
        },
      },
    );
    return;
  }
  if (type == 'message' ||
      type == 'chat' ||
      data['sender_id'] != null ||
      data['senderId'] != null) {
    rootNavigatorKey.currentState?.pushNamed('/messages', arguments: data);
    return;
  }
  rootNavigatorKey.currentState?.pushNamed('/notifications');
}

void _restoreActiveCallRoute() {
  final routeName = ActiveCallService.instance.routeName;
  final navigator = rootNavigatorKey.currentState;
  if (navigator == null || routeName.isEmpty) return;
  var found = false;
  navigator.popUntil((route) {
    found = route.settings.name == routeName;
    return found || route.isFirst;
  });
  if (found) ActiveCallService.instance.restore();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _installFrameDiagnostics();
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    unawaited(
      ApiService.reportClientDiagnostic(
        eventType: 'flutter_error',
        severity: 'error',
        message: details.exceptionAsString(),
        stack: details.stack?.toString() ?? '',
        screen: 'flutter_global',
        extra: {
          'library': details.library,
          'context': details.context?.toDescription(),
        },
      ),
    );
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    unawaited(
      ApiService.reportClientDiagnostic(
        eventType: 'crash',
        severity: 'fatal',
        message: error.toString(),
        stack: stack.toString(),
        screen: 'platform_dispatcher',
      ),
    );
    return true;
  };
  try {
    await lk.LiveKitClient.initialize(
      initialAudioSessionOptions: const lk.AudioSessionOptions.communication(),
    );
  } catch (error) {
    debugPrint('Initialisation audio LiveKit differee: $error');
  }
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  try {
    await initializeTranvikoFirebase();
    debugPrint("Firebase initialise avec succes.");
  } catch (e) {
    debugPrint("Erreur initialisation Firebase : $e");
  }
  // Initialiser les donnÃ©es de locales pour le franÃ§ais
  await initializeDateFormatting('fr_FR', null);
  await initializeDateFormatting('en_US', null);
  await initializeDateFormatting('es_ES', null);
  await initializeDateFormatting('ar', null);
  await initializeDateFormatting('pt_PT', null);
  final preferences = await SharedPreferences.getInstance();
  await TranvikoInteractionFeedback.configure(preferences: preferences);
  unawaited(TranvikoInteractionFeedback.warmUp());
  unawaited(ApiService.flushQueuedClientDiagnostics());
  await ApiService.loadStoredCompany();
  final themeMode = preferences.getString('theme_mode') ?? 'system';
  appThemeMode.value = switch (themeMode) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
  final language = preferences.getString('language') ?? 'fr';
  appLocale.value = Locale(language);
  appTextScale.value = preferences.getDouble('text_scale') ?? 1.0;
  final seed =
      preferences.getInt('seed_color') ??
      preferences.getInt('company_primary_color');
  if (seed != null) {
    if (seed == 0xFF60A5FA) {
      appSeedColor.value = const Color(0xFF075EF5);
      await preferences.setInt('seed_color', 0xFF075EF5);
    } else {
      appSeedColor.value = Color(seed);
    }
  }
  Intl.defaultLocale = appIntlLocale(language);
  if (preferences.getBool('remember_me') == true) {
    ApiService.userToken = preferences.getString('user_token');
    ApiService.agentToken = preferences.getString('agent_token');
    final userJson = preferences.getString('current_user');
    final agentJson = preferences.getString('current_agent');
    if (agentJson != null) {
      ApiService.currentAgent = jsonDecode(agentJson) as Map<String, dynamic>;
      ApiService.userToken = null;
      ApiService.currentUser = null;
      await preferences.remove('user_token');
      await preferences.remove('current_user');
    } else if (userJson != null) {
      ApiService.currentUser = jsonDecode(userJson) as Map<String, dynamic>;
      ApiService.agentToken = null;
      ApiService.currentAgent = null;
      await preferences.remove('agent_token');
      await preferences.remove('current_agent');
    }
  }
  activateCacheScopeForCurrentSession();
  await NativeCallService.configure(
    onAccepted: handleNativeCallAccepted,
    onDeclined: (data) => unawaited(sendNativeCallAction(data, 'call_reject')),
    onEnded: (data) => unawaited(sendNativeCallAction(data, 'call_end')),
  );
  await FlutterCallkitIncoming.onBackgroundMessage(callkitBackgroundHandler);
  PushNotificationService.onNotificationTap = handlePushNotificationTap;
  if (ApiService.companyId != null || ApiService.companySlug != null) {
    unawaited(PushNotificationService.configure());
  }
  final hasSelectedCompany =
      ApiService.companyId != null || ApiService.companySlug != null;
  final rememberedAuthRoute = preferences.getString('last_auth_route');
  final initialRoute = hasSelectedCompany
      ? (preferences.getBool('onboarding_seen') != true
            ? '/onboarding'
            : ApiService.activeToken == null &&
                  (rememberedAuthRoute == '/login' ||
                      rememberedAuthRoute == '/register')
            ? rememberedAuthRoute!
            : '/')
      : '/company_select';
  runApp(MyApp(initialRoute: initialRoute));
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(NativeCallService.warmUp());
    if (ApiService.activeToken != null) {
      if (preferences.getBool('onboarding_seen') == true) {
        unawaited(NativeCallService.requestPermissions());
      }
      unawaited(ReservationStore.loadFromCache());
      unawaited(AccountWarmupService.warmCurrentAccount());
    }
    unawaited(drainPendingAcceptedCall());
  });
}

class _ActiveCallMiniOverlay extends StatelessWidget {
  const _ActiveCallMiniOverlay();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ActiveCallService.instance,
      builder: (context, _) {
        final call = ActiveCallService.instance;
        if (!call.active || !call.minimized) {
          return const SizedBox.shrink();
        }
        final scheme = Theme.of(context).colorScheme;
        final top = MediaQuery.of(context).padding.top + 8;
        return Positioned(
          top: top,
          right: 12,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: _restoreActiveCallRoute,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 260),
                padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    scheme.primary.withValues(alpha: .18),
                    scheme.surface,
                  ),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: .35),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .18),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.call_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            call.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w900,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            call.status,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              height: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: 'Raccrocher',
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: Colors.white,
                        backgroundColor: const Color(0xFFEF4444),
                        fixedSize: const Size(32, 32),
                      ),
                      onPressed: () => unawaited(call.end()),
                      icon: const Icon(Icons.call_end_rounded, size: 16),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ShareTargetBootstrap extends StatefulWidget {
  const _ShareTargetBootstrap();

  @override
  State<_ShareTargetBootstrap> createState() => _ShareTargetBootstrapState();
}

class _ShareTargetBootstrapState extends State<_ShareTargetBootstrap>
    with WidgetsBindingObserver {
  static const MethodChannel _channel = MethodChannel('tranviko/share_target');
  bool _checking = false;
  String _lastSignature = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumeShare());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _consumeShare();
  }

  Future<void> _consumeShare() async {
    if (_checking) return;
    _checking = true;
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
        'consumePendingMedia',
      );
      final items = (raw ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .where((item) => (item['uri'] ?? '').toString().isNotEmpty)
          .toList();
      if (items.isEmpty) return;
      final signature = jsonEncode(items.map((item) => item['uri']).toList());
      if (signature == _lastSignature) return;
      _lastSignature = signature;
      final navigator = rootNavigatorKey.currentState;
      if (navigator == null) return;
      navigator.pushNamed('/messages', arguments: {'sharedMedia': items});
    } catch (_) {
      // Channel absent on non-Android platforms.
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class MyApp extends StatelessWidget {
  final String initialRoute;

  const MyApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appThemeMode,
      builder: (context, mode, _) => ValueListenableBuilder<Locale>(
        valueListenable: appLocale,
        builder: (context, locale, _) => ValueListenableBuilder<double>(
          valueListenable: appTextScale,
          builder: (context, textScale, _) => ValueListenableBuilder<Color>(
            valueListenable: appSeedColor,
            builder: (context, seed, _) => MaterialApp(
              title: 'Tranviko',
              scaffoldMessengerKey: rootMessengerKey,
              navigatorKey: rootNavigatorKey,
              themeMode: mode,
              locale: locale,
              supportedLocales: const [
                Locale('fr'),
                Locale('en'),
                Locale('es'),
                Locale('ar'),
                Locale('pt'),
              ],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              builder: (context, child) {
                final media = MediaQuery.of(context);
                return MediaQuery(
                  data: media.copyWith(
                    textScaler: TextScaler.linear(textScale),
                  ),
                  child: TranvikoInteractionSurface(
                    child: AppLockGate(
                      child: CallSocketHost(
                        child: NotificationSocketHost(
                          child: Stack(
                            children: [
                              child ?? const SizedBox.shrink(),
                              const _ShareTargetBootstrap(),
                              const _ActiveCallMiniOverlay(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
              theme: _buildTheme(brightness: Brightness.light, seed: seed),
              darkTheme: _buildTheme(brightness: Brightness.dark, seed: seed),
              initialRoute: initialRoute,
              routes: {
                '/company_select': (context) => const CompanySelectionScreen(),
                '/onboarding': (context) => const OnboardingScreen(),
                '/': (context) => const HomeScreen(),
                '/bus_selection': (context) => const BusSelectionScreen(),
                '/seat_plan': (context) => const SeatPlanScreen(),
                '/passenger_details': (context) =>
                    const PassengerDetailsScreen(),
                '/order_summary': (context) => const OrderSummaryScreen(),
                '/payment': (context) => const PaymentScreen(),
                '/confirmation': (context) => const ConfirmationScreen(),
                '/package_tracking': (context) => const PackageTrackingScreen(),
                '/history': (context) => const HistoryScreen(),
                '/admin': (context) => const AdminScreen(),
                '/notifications': (context) => const NotificationsScreen(),
                '/settings': (context) => const SettingsScreen(),
                '/profile': (context) => const ProfileScreen(),
                '/messages': (context) {
                  final args = ModalRoute.of(context)?.settings.arguments;
                  int? targetUserId;
                  List<Map<String, dynamic>> sharedMedia = const [];
                  if (args is Map) {
                    targetUserId = int.tryParse(
                      (args['userId'] ??
                              args['senderId'] ??
                              args['sender_id'] ??
                              args['fromId'] ??
                              args['conversationId'])
                          .toString(),
                    );
                    final rawShared = args['sharedMedia'];
                    if (rawShared is List) {
                      sharedMedia = rawShared
                          .whereType<Map>()
                          .map((item) => Map<String, dynamic>.from(item))
                          .toList();
                    }
                  }
                  return MessagesScreen(
                    initialUserId: targetUserId,
                    initialSharedMedia: sharedMedia,
                  );
                },
                '/contact_service': (context) => const ContactServiceScreen(),
                '/route_map': (context) => const RouteMapScreen(),
                '/trip_chat': (context) => TripChatScreen(
                  reservationCode:
                      ModalRoute.of(context)!.settings.arguments as String,
                ),
                '/login': (context) => const LoginScreen(),
                '/register': (context) => const RegisterScreen(),
                '/forgot-password': (context) => const ForgotPasswordScreen(),
                '/qr-device-login': (context) {
                  final args = ModalRoute.of(context)?.settings.arguments;
                  final map = args is Map ? args : const {};
                  return QrDeviceLoginScreen(
                    allowAccountQr: map['allowAccountQr'] != false,
                    loginMode: map['loginMode'] == true,
                  );
                },
              },
            ),
          ),
        ),
      ),
    );
  }

  ThemeData _buildTheme({required Brightness brightness, required Color seed}) {
    final isDark = brightness == Brightness.dark;
    final baseSeed = seed;
    final surface = isDark ? const Color(0xFF06101D) : const Color(0xFFFFFFFF);
    final card = isDark ? const Color(0xFF0C1A2B) : const Color(0xFFFFFFFF);
    final outline = isDark ? const Color(0xFF29405E) : const Color(0xFFD8E3F0);
    final generatedScheme = ColorScheme.fromSeed(
      seedColor: baseSeed,
      brightness: brightness,
      primary: baseSeed,
      secondary: isDark ? const Color(0xFF66DCD2) : const Color(0xFF008F88),
      tertiary: isDark ? const Color(0xFFFFA384) : const Color(0xFFE05F3C),
      surface: surface,
      error: isDark ? const Color(0xFFFF7B82) : const Color(0xFFD9364B),
    );
    final scheme = generatedScheme.copyWith(
      surface: surface,
      surfaceContainerLowest: surface,
      surfaceContainerLow: isDark
          ? const Color(0xFF091522)
          : const Color(0xFFFCFCFD),
      surfaceContainer: isDark
          ? const Color(0xFF0D1B2A)
          : const Color(0xFFF7F8F9),
      surfaceContainerHigh: isDark
          ? const Color(0xFF122235)
          : const Color(0xFFF1F3F5),
      surfaceContainerHighest: isDark
          ? const Color(0xFF182B42)
          : const Color(0xFFE9EDF0),
      onSurface: isDark ? const Color(0xFFF7FAFC) : const Color(0xFF101418),
      onSurfaceVariant: isDark
          ? const Color(0xFFB9C8D8)
          : const Color(0xFF4B5563),
      outline: isDark ? const Color(0xFF486078) : const Color(0xFFCDD4DC),
      outlineVariant: isDark
          ? const Color(0xFF263C54)
          : const Color(0xFFE4E8ED),
    );
    final textTheme = ThemeData(useMaterial3: true, brightness: brightness)
        .textTheme
        .copyWith(
          displayLarge: TextStyle(
            color: scheme.onSurface,
            fontSize: 40,
            height: 1.08,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
          headlineLarge: TextStyle(
            color: scheme.onSurface,
            fontSize: 30,
            height: 1.12,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
          headlineMedium: TextStyle(
            color: scheme.onSurface,
            fontSize: 24,
            height: 1.16,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
          titleLarge: TextStyle(
            color: scheme.onSurface,
            fontSize: 20,
            height: 1.22,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
          titleMedium: TextStyle(
            color: scheme.onSurface,
            fontSize: 16,
            height: 1.3,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
          bodyLarge: TextStyle(
            color: scheme.onSurface,
            fontSize: 16,
            height: 1.45,
            letterSpacing: 0,
          ),
          bodyMedium: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 14,
            height: 1.42,
            letterSpacing: 0,
          ),
          labelLarge: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: 'Roboto',
      primaryColor: baseSeed,
      colorScheme: scheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: surface,
      canvasColor: surface,
      dividerColor: outline,
      splashFactory: InkRipple.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _TranvikoPageTransitionsBuilder(),
          TargetPlatform.iOS: _TranvikoPageTransitionsBuilder(),
          TargetPlatform.windows: _TranvikoPageTransitionsBuilder(),
          TargetPlatform.macOS: _TranvikoPageTransitionsBuilder(),
          TargetPlatform.linux: _TranvikoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: isDark ? Colors.white : const Color(0xFF071B4A),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: isDark ? Colors.white : const Color(0xFF071B4A),
          fontSize: 20,
          fontWeight: FontWeight.w900,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: card,
        selectedItemColor: baseSeed,
        unselectedItemColor: isDark ? Colors.white70 : const Color(0xFF667996),
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shadowColor: baseSeed.withValues(alpha: isDark ? 0.28 : 0.14),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: outline),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: baseSeed,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: baseSeed,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: baseSeed,
          side: BorderSide(color: outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          minimumSize: const Size(64, 50),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: baseSeed,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: scheme.onSurfaceVariant,
          minimumSize: const Size(44, 44),
          shape: const CircleBorder(),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: card,
        indicatorColor: baseSeed.withValues(alpha: isDark ? .24 : .12),
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        indicatorShape: const CircleBorder(),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? baseSeed
                : scheme.onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? baseSeed
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? const Color(0xFF142338) : Colors.white,
        selectedColor: isDark ? const Color(0xFF1B2C43) : Colors.white,
        labelStyle: TextStyle(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: outline),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF12233A) : Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 17,
          vertical: 17,
        ),
        labelStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
        floatingLabelStyle: TextStyle(
          color: baseSeed,
          fontWeight: FontWeight.w800,
        ),
        hintStyle: TextStyle(
          color: scheme.onSurfaceVariant.withValues(alpha: .72),
          fontWeight: FontWeight.w500,
        ),
        errorStyle: TextStyle(
          color: scheme.error,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: baseSeed, width: 1.7),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.error, width: 1.4),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.error, width: 1.8),
        ),
        prefixIconColor: baseSeed,
      ),
      searchBarTheme: SearchBarThemeData(
        backgroundColor: WidgetStatePropertyAll(card),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(0),
        side: WidgetStatePropertyAll(BorderSide(color: outline)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        textStyle: WidgetStatePropertyAll(
          TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w600),
        ),
        hintStyle: WidgetStatePropertyAll(
          TextStyle(color: scheme.onSurfaceVariant),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.onPrimary
                : scheme.onSurfaceVariant,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? baseSeed : card,
          ),
          side: WidgetStatePropertyAll(BorderSide(color: outline)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0),
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.onPrimary
              : scheme.outline,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? baseSeed : outline,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? baseSeed
              : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(scheme.onPrimary),
        side: BorderSide(color: outline, width: 1.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark
            ? const Color(0xFF17263A)
            : const Color(0xFF071B4A),
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF071B4A),
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: TextStyle(
          color: isDark ? const Color(0xFF071B4A) : Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.primary,
        textColor: scheme.onSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      dividerTheme: DividerThemeData(color: outline, thickness: 1, space: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: baseSeed,
        linearTrackColor: outline,
        circularTrackColor: outline,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: baseSeed,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class _TranvikoPageTransitionsBuilder extends PageTransitionsBuilder {
  const _TranvikoPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion || route.isFirst) return child;
    final entrance = animation.drive(CurveTween(curve: Curves.easeOutCubic));
    return FadeTransition(
      opacity: Tween<double>(begin: .9, end: 1).animate(entrance),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, .018),
          end: Offset.zero,
        ).animate(entrance),
        child: child,
      ),
    );
  }
}

class AppLockGate extends StatefulWidget {
  final Widget? child;

  const AppLockGate({super.key, required this.child});

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  Timer? _resumeTimer;
  bool _locked = false;
  bool _authenticating = false;
  DateTime? _lastUnlock;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkLock());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _locked = ApiService.activeToken != null;
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(drainPendingAcceptedCall());
      _resumeTimer?.cancel();
      _resumeTimer = Timer(const Duration(milliseconds: 450), _checkLock);
    }
  }

  Future<void> _checkLock() async {
    if (_authenticating) return;
    final enabled = await AppLockService.isEnabled();
    final hasSession = ApiService.activeToken != null;
    final callIsOpening =
        _pendingAcceptedCall != null || _activeAudioCallRouteId != null;
    if (!enabled || !hasSession || callIsOpening) {
      if (mounted) setState(() => _locked = false);
      return;
    }
    final lastUnlock = _lastUnlock;
    if (lastUnlock != null &&
        DateTime.now().difference(lastUnlock) < const Duration(seconds: 2)) {
      if (mounted) setState(() => _locked = false);
      return;
    }
    if (!mounted) return;
    await _authenticate();
  }

  Future<void> _authenticate() async {
    if (_authenticating) return;
    setState(() {
      _locked = true;
      _authenticating = true;
    });
    final result = await AppLockService.verifyForActivation(
      reason: appT('unlockApp'),
    );
    if (!mounted) return;
    if (result.needsDeviceSecurity) {
      await AppLockService.setEnabled(false);
      if (!mounted) return;
      setState(() {
        _authenticating = false;
        _locked = false;
        _lastUnlock = DateTime.now();
      });
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text(
            'Verrouillage local desactive: le telephone n a plus de code de securite.',
          ),
        ),
      );
      return;
    }
    final ok = result.success;
    setState(() {
      _authenticating = false;
      _locked = !ok;
      if (ok) _lastUnlock = DateTime.now();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resumeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.child ?? const SizedBox.shrink();
    if (!_locked) return child;
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: Material(
            color: scheme.scrim.withValues(alpha: .72),
            child: SafeArea(
              child: Center(
                child: Container(
                  width: 320,
                  margin: const EdgeInsets.all(24),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: scheme.outlineVariant),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .22),
                        blurRadius: 34,
                        offset: const Offset(0, 18),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 74,
                        height: 74,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [scheme.primary, scheme.secondary],
                          ),
                        ),
                        child: const Icon(
                          Icons.fingerprint_rounded,
                          color: Colors.white,
                          size: 38,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        appT('appLocked'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        appT('unlockAppBody'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _authenticating ? null : _authenticate,
                          icon: _authenticating
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.lock_open_rounded),
                          label: Text(
                            _authenticating
                                ? appT('pleaseWait')
                                : appT('unlock'),
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
      ],
    );
  }
}

class CallSocketHost extends StatefulWidget {
  final Widget? child;

  const CallSocketHost({super.key, required this.child});

  @override
  State<CallSocketHost> createState() => _CallSocketHostState();
}

class _CallSocketHostState extends State<CallSocketHost>
    with WidgetsBindingObserver {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  Timer? _tokenWatchTimer;
  String? _connectedToken;
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tokenWatchTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (ApiService.activeToken != _connectedToken) _connect();
    });
    _connect();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _connect();
  }

  void _connect() {
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    final token = ApiService.activeToken;
    _connectedToken = token;
    if (token == null) return;
    try {
      final channel = connectAppWebSocket(ApiService.callWebSocketUri());
      _channel = channel;
      _subscription = channel.stream.listen(
        _handleEvent,
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
      );
      if (ApiService.agentToken != null) {
        channel.sink.add(
          jsonEncode({
            'action': 'register_service_agent',
            'company': 'default',
          }),
        );
      }
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (!mounted || ApiService.activeToken == null) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 4), _connect);
  }

  void _handleEvent(dynamic event) {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(event.toString()) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final eventName = data['event']?.toString();
    if (eventName == 'call_end' || eventName == 'call_reject') {
      final callId = data['callId']?.toString() ?? '';
      if (callId.isNotEmpty) unawaited(NativeCallService.endCall(callId));
      return;
    }
    if (eventName != 'call_invite') return;
    _showIncomingCall(data);
  }

  Future<void> _showIncomingCall(Map<String, dynamic> data) async {
    if (_dialogOpen) return;
    final payload = Map<String, dynamic>.from(
      data['payload'] as Map? ?? const {},
    );
    final callerId = (data['fromId'] as num?)?.toInt();
    if (callerId == null) return;
    _dialogOpen = true;
    await NativeCallService.showIncomingCall({
      'type': 'incoming_audio_call',
      'media': data['media']?.toString() == 'video' ? 'video' : 'audio',
      'callMode': data['media']?.toString() == 'video' ? 'video' : 'audio',
      'callId': data['callId']?.toString() ?? '',
      'callerId': callerId.toString(),
      'fromId': callerId.toString(),
      'callerName': payload['title']?.toString().isNotEmpty == true
          ? payload['title'].toString()
          : 'Agent #$callerId',
    });
    _dialogOpen = false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tokenWatchTimer?.cancel();
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child ?? const SizedBox.shrink();
}

class NotificationSocketHost extends StatefulWidget {
  final Widget? child;

  const NotificationSocketHost({super.key, required this.child});

  @override
  State<NotificationSocketHost> createState() => _NotificationSocketHostState();
}

class _NotificationSocketHostState extends State<NotificationSocketHost>
    with WidgetsBindingObserver {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  Timer? _presenceTimer;
  Timer? _tokenWatchTimer;
  String? _connectedToken;
  DateTime? _lastInactiveAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tokenWatchTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (ApiService.activeToken != _connectedToken) _connect();
    });
    _connect();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _connect();
  }

  void _connect() {
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    final token = ApiService.activeToken;
    _connectedToken = token;
    if (token == null) return;
    try {
      final channel = WebSocketChannel.connect(
        ApiService.notificationWebSocketUri(),
      );
      _channel = channel;
      _startPresenceHeartbeat();
      _subscription = channel.stream.listen(
        _handleEvent,
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (!mounted || ApiService.activeToken == null) return;
    _presenceTimer?.cancel();
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 4), _connect);
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

  void _closeSocket() {
    _reconnectTimer?.cancel();
    _presenceTimer?.cancel();
    _subscription?.cancel();
    _subscription = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  void _handleEvent(dynamic event) {
    final payload = jsonDecode(event.toString()) as Map<String, dynamic>;
    final notifications = payload['notifications'];
    if (notifications is List) {
      final items = notifications
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      if (items.isNotEmpty) {
        final visibleItems = items
            .where((item) => !_isMessageNotification(item))
            .toList();
        final wasAwayLongEnough =
            _lastInactiveAt != null &&
            DateTime.now().difference(_lastInactiveAt!) >
                const Duration(minutes: 5);
        if (wasAwayLongEnough && visibleItems.isNotEmpty) {
          _showNotificationDigestBanner(visibleItems);
        }
        _markSyncedNotificationsRead(items);
      }
      if (items.isNotEmpty) return;
      _markSyncedNotificationsRead(items);
      if (items.length == 1) {
        if (_isValidationNotification(items.first)) {
          _showValidationBanner(items.first);
        }
      } else if (items.isNotEmpty) {
        for (final item in items) {
          if (_isValidationNotification(item)) _showValidationBanner(item);
          /*
          'message': '${items.length} notifications recues pendant l’absence.',
          'category': 'general',
          */
        }
      }
      return;
    }
    final notification = payload['notification'] as Map<String, dynamic>?;
    if (notification == null) return;
    if (_isMessageNotification(notification)) return;
    if (_isValidationNotification(notification)) {
      _showValidationBanner(notification);
    } else {
      _showNotificationDigestBanner([notification]);
    }
  }

  void _markSyncedNotificationsRead(List<Map<String, dynamic>> items) {
    final ids = items
        .map((item) => int.tryParse(item['id']?.toString() ?? ''))
        .whereType<int>()
        .where((id) => id > 0)
        .toSet()
        .toList();
    if (ids.isNotEmpty) {
      unawaited(ApiService.notificationAction('read', ids));
    }
  }

  bool _isValidationNotification(Map<String, dynamic> notification) {
    final text = [
      notification['category'],
      notification['type'],
      notification['title'],
      notification['message'],
    ].whereType<Object>().join(' ').toLowerCase();
    return text.contains('validation') ||
        text.contains('valider') ||
        text.contains('confirm') ||
        text.contains('ticket_check') ||
        text.contains('package_check');
  }

  bool _isMessageNotification(Map<String, dynamic> notification) {
    final data = notification['data'];
    final type = notification['type']?.toString().toLowerCase() ?? '';
    final dataType = data is Map
        ? data['type']?.toString().toLowerCase() ?? ''
        : '';
    final dataCategory = data is Map
        ? data['category']?.toString().toLowerCase() ?? ''
        : '';
    final hasMessageId =
        notification['messageId'] != null ||
        notification['message_id'] != null ||
        (data is Map &&
            (data['messageId'] != null || data['message_id'] != null));
    return type == 'message' ||
        type == 'chat' ||
        type == 'chat_message' ||
        dataType == 'message' ||
        dataType == 'chat' ||
        dataType == 'chat_message' ||
        (dataCategory == 'message' && hasMessageId);
  }

  void _showValidationBanner(Map<String, dynamic> notification) {
    final overlay = rootNavigatorKey.currentState?.overlay;
    if (overlay == null) return;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          left: 14,
          right: 14,
          child: Material(
            color: Colors.transparent,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: -18, end: 0),
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              builder: (context, offset, child) =>
                  Transform.translate(offset: Offset(0, offset), child: child),
              child: Dismissible(
                key: ValueKey(
                  "validation-${notification['id'] ?? notification.hashCode}",
                ),
                direction: DismissDirection.up,
                onDismissed: (_) {
                  if (entry.mounted) entry.remove();
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: .28),
                        blurRadius: 22,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: scheme.onPrimary.withValues(alpha: .16),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          Icons.verified_rounded,
                          color: scheme.onPrimary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              notification['title']?.toString() ?? 'Validation',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: scheme.onPrimary,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              notification['message']?.toString() ?? '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: scheme.onPrimary.withValues(alpha: .88),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Ouvrir',
                        onPressed: () {
                          if (entry.mounted) entry.remove();
                          rootNavigatorKey.currentState?.pushNamed(
                            '/notifications',
                          );
                        },
                        icon: Icon(
                          Icons.arrow_forward_rounded,
                          color: scheme.onPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(entry);
    Timer(const Duration(seconds: 4), () {
      if (entry.mounted) entry.remove();
    });
  }

  void _showNotificationDigestBanner(List<Map<String, dynamic>> items) {
    if (items.isEmpty) return;
    final overlay = rootNavigatorKey.currentState?.overlay;
    if (overlay == null) return;
    final latest = items.last;
    final extraCount = items.length - 1;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          left: 14,
          right: 14,
          child: Material(
            color: Colors.transparent,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: -18, end: 0),
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              builder: (context, offset, child) =>
                  Transform.translate(offset: Offset(0, offset), child: child),
              child: Dismissible(
                key: ValueKey(
                  "digest-${latest['id'] ?? latest.hashCode}-$extraCount",
                ),
                direction: DismissDirection.up,
                onDismissed: (_) {
                  if (entry.mounted) entry.remove();
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: scheme.primary.withValues(alpha: .24),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .18),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [scheme.primary, scheme.secondary],
                          ),
                          borderRadius: BorderRadius.circular(17),
                        ),
                        child: const Icon(
                          Icons.notifications_active_rounded,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    latest['title']?.toString() ??
                                        'Nouvelle notification',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: scheme.onSurface,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                if (extraCount > 0)
                                  Container(
                                    margin: const EdgeInsets.only(left: 8),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: scheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      '+$extraCount',
                                      style: TextStyle(
                                        color: scheme.onPrimaryContainer,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              latest['message']?.toString() ?? '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 12,
                                height: 1.2,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Voir',
                        onPressed: () {
                          if (entry.mounted) entry.remove();
                          rootNavigatorKey.currentState?.pushNamed(
                            '/notifications',
                          );
                        },
                        icon: Icon(
                          Icons.arrow_forward_rounded,
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(entry);
    Timer(const Duration(seconds: 4), () {
      if (entry.mounted) entry.remove();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tokenWatchTimer?.cancel();
    _closeSocket();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child ?? const SizedBox.shrink();
}
