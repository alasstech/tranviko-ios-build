import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NativeCallService {
  static const Duration _acceptedNativeEndGrace = Duration(seconds: 4);
  static const Duration _incomingDedupeWindow = Duration(seconds: 90);
  static const String _recentIncomingPrefix = 'recent_native_incoming_';
  static const String _programmaticEndPrefix = 'programmatic_native_end_';
  static StreamSubscription<CallEvent?>? _eventSubscription;
  static void Function(Map<String, dynamic> data)? onCallAccepted;
  static void Function(Map<String, dynamic> data)? onCallDeclined;
  static void Function(Map<String, dynamic> data)? onCallEnded;
  static final _nativeEvents =
      StreamController<Map<String, dynamic>>.broadcast();
  static final Set<String> _visibleCallIds = <String>{};
  static final Map<String, DateTime> _acceptedAtByCallId = <String, DateTime>{};
  static final Set<String> _programmaticEndCallIds = <String>{};
  static final AudioRecorder _audioPermissionRecorder = AudioRecorder();
  static bool _permissionsRequestedThisRun = false;

  static Stream<Map<String, dynamic>> get nativeEvents => _nativeEvents.stream;

  static Future<void> configure({
    required void Function(Map<String, dynamic> data) onAccepted,
    void Function(Map<String, dynamic> data)? onDeclined,
    void Function(Map<String, dynamic> data)? onEnded,
  }) async {
    if (kIsWeb) return;
    onCallAccepted = onAccepted;
    onCallDeclined = onDeclined;
    onCallEnded = onEnded;
    _eventSubscription ??= FlutterCallkitIncoming.onEvent.listen(_handleEvent);
  }

  static Future<void> requestPermissions({bool force = false}) async {
    if (kIsWeb) return;
    if (_permissionsRequestedThisRun && !force) return;
    _permissionsRequestedThisRun = true;
    try {
      await FlutterCallkitIncoming.requestNotificationPermission({
        'rationaleMessagePermission':
            'Autorisez les notifications pour recevoir les appels entrants.',
        'postNotificationMessageRequired':
            'Les appels entrants ont besoin des notifications.',
      });
      await _audioPermissionRecorder.hasPermission();
      await FlutterCallkitIncoming.requestFullIntentPermission();
    } catch (error) {
      debugPrint('Native call permission failed: $error');
    }
  }

  static Future<void> warmUp() async {
    if (kIsWeb) return;
    try {
      await FlutterCallkitIncoming.activeCalls();
    } catch (error) {
      debugPrint('Native call warm-up failed: $error');
    }
  }

  static Future<void> showIncomingCall(Map<String, dynamic> data) async {
    if (kIsWeb) return;
    final callId = data['callId']?.toString().isNotEmpty == true
        ? data['callId'].toString()
        : DateTime.now().millisecondsSinceEpoch.toString();
    final callerName = data['callerName']?.toString().isNotEmpty == true
        ? data['callerName'].toString()
        : data['title']?.toString().isNotEmpty == true
        ? data['title'].toString()
        : 'Appel entrant';
    final callerId =
        data['callerId']?.toString() ?? data['fromId']?.toString() ?? '';
    final isVideo =
        data['media']?.toString() == 'video' ||
        data['callMode']?.toString() == 'video';
    if (!await _claimIncomingCall(callId)) return;

    final params = CallKitParams(
      id: callId,
      nameCaller: callerName,
      appName: 'Tranviko',
      handle: callerId.isEmpty ? callerName : callerId,
      type: isVideo ? 1 : 0,
      duration: 45000,
      missedCallNotification: null,
      extra: Map<String, dynamic>.from(data)
        ..['type'] = 'incoming_audio_call'
        ..['media'] = isVideo ? 'video' : 'audio'
        ..['callMode'] = isVideo ? 'video' : 'audio',
      android: const AndroidParams(
        isCustomNotification: false,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#123047',
        actionColor: '#22C55E',
        incomingCallNotificationChannelName: 'Appels entrants',
        missedCallNotificationChannelName: 'Appels manques',
        isShowCallID: false,
        isShowFullLockedScreen: true,
      ),
      ios: const IOSParams(
        iconName: 'AppIcon',
        handleType: 'generic',
        supportsVideo: true,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'voiceChat',
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        supportsDTMF: false,
        supportsHolding: false,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: 'system_ringtone_default',
      ),
    );

    try {
      await FlutterCallkitIncoming.showCallkitIncoming(params);
    } catch (error) {
      _visibleCallIds.remove(callId);
      await _forgetIncomingClaim(callId);
      debugPrint('Show native incoming call failed: $error');
    }
  }

  static Future<bool> _claimIncomingCall(String callId) async {
    if (callId.isEmpty) return true;
    if (!_visibleCallIds.add(callId)) return false;
    final acceptedAt = _acceptedAtByCallId[callId];
    if (acceptedAt != null &&
        DateTime.now().difference(acceptedAt) < _acceptedNativeEndGrace) {
      _visibleCallIds.remove(callId);
      return false;
    }
    try {
      final activeCalls = await FlutterCallkitIncoming.activeCalls();
      for (final dynamic call in activeCalls) {
        final activeId = call.id?.toString() ?? '';
        if (activeId == callId) {
          _visibleCallIds.remove(callId);
          return false;
        }
      }
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    final key = '$_recentIncomingPrefix$callId';
    final now = DateTime.now().millisecondsSinceEpoch;
    final lastShown = prefs.getInt(key);
    if (lastShown != null &&
        now - lastShown < _incomingDedupeWindow.inMilliseconds) {
      _visibleCallIds.remove(callId);
      return false;
    }
    await prefs.setInt(key, now);
    return true;
  }

  static Future<void> _forgetIncomingClaim(String callId) async {
    if (callId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_recentIncomingPrefix$callId');
    } catch (_) {}
  }

  static Future<void> _rememberIncomingHandled(String callId) async {
    if (callId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        '$_recentIncomingPrefix$callId',
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  static Future<void> endCall(String callId) async {
    if (kIsWeb || callId.isEmpty) return;
    _visibleCallIds.remove(callId);
    _programmaticEndCallIds.add(callId);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        '$_programmaticEndPrefix$callId',
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
    await FlutterCallkitIncoming.endCall(callId);
  }

  static Future<bool> _wasProgrammaticallyEnded(String callId) async {
    if (callId.isEmpty) return false;
    if (_programmaticEndCallIds.remove(callId)) return true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final endedAt = prefs.getInt('$_programmaticEndPrefix$callId');
      return endedAt != null &&
          DateTime.now().millisecondsSinceEpoch - endedAt < 120000;
    } catch (_) {
      return false;
    }
  }

  static Future<void> endAllCalls() async {
    if (kIsWeb) return;
    _visibleCallIds.clear();
    await FlutterCallkitIncoming.endAllCalls();
  }

  static Future<void> setCallConnected(String callId) async {
    if (kIsWeb || callId.isEmpty) return;
    await FlutterCallkitIncoming.setCallConnected(callId);
  }

  static void _handleEvent(CallEvent? event) {
    if (event == null) return;
    CallKitParams? params;
    if (event is CallEventActionCallAccept) params = event.callKitParams;
    if (event is CallEventActionCallDecline) params = event.callKitParams;
    if (event is CallEventActionCallEnded) params = event.callKitParams;
    final extra = Map<String, dynamic>.from(params?.extra ?? const {});
    final id = params?.id ?? extra['callId']?.toString() ?? '';
    if (id.isNotEmpty) extra['callId'] = id;
    if (event is CallEventActionCallAccept) {
      extra['nativeAction'] = 'accept';
      extra['type'] = 'incoming_audio_call';
      if (id.isNotEmpty) {
        _acceptedAtByCallId[id] = DateTime.now();
        unawaited(_rememberIncomingHandled(id));
      }
      _nativeEvents.add(Map<String, dynamic>.from(extra));
      onCallAccepted?.call(extra);
      return;
    }
    if (event is CallEventActionCallDecline) {
      extra['nativeAction'] = 'decline';
      _nativeEvents.add(Map<String, dynamic>.from(extra));
      onCallDeclined?.call(extra);
      if (id.isNotEmpty) unawaited(endCall(id));
      return;
    }
    if (event is CallEventActionCallEnded) {
      unawaited(_handleEndedEvent(extra, id));
    }
  }

  static Future<void> _handleEndedEvent(
    Map<String, dynamic> extra,
    String id,
  ) async {
    if (await _wasProgrammaticallyEnded(id)) return;
    final acceptedAt = id.isEmpty ? null : _acceptedAtByCallId[id];
    if (acceptedAt != null &&
        DateTime.now().difference(acceptedAt) < _acceptedNativeEndGrace) {
      return;
    }
    extra['nativeAction'] = 'end';
    _nativeEvents.add(Map<String, dynamic>.from(extra));
    onCallEnded?.call(extra);
  }
}
