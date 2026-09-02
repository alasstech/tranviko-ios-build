import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as raw_http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

final BoundedHttpClient http = BoundedHttpClient();

class BoundedHttpClient {
  static const Duration _defaultTimeout = Duration(seconds: 30);
  static const Duration _authTimeout = Duration(seconds: 12);

  Duration _timeoutFor(Uri url) =>
      url.path.contains('/auth/') ? _authTimeout : _defaultTimeout;

  Future<raw_http.Response> _bounded(
    Uri url,
    Future<raw_http.Response> request,
  ) async {
    final stopwatch = Stopwatch()..start();
    try {
      final response = await request.timeout(_timeoutFor(url));
      stopwatch.stop();
      if (!url.path.contains('/client-diagnostics/')) {
        if (response.statusCode >= 500) {
          unawaited(
            ApiService.reportClientDiagnostic(
              eventType: 'http_error',
              severity: 'error',
              message: 'HTTP ${response.statusCode} sur ${url.path}',
              screen: url.path,
              extra: {
                'methodEndpoint': url.path,
                'statusCode': response.statusCode,
                'durationMs': stopwatch.elapsedMilliseconds,
              },
            ),
          );
        } else if (stopwatch.elapsedMilliseconds >= 8000) {
          unawaited(
            ApiService.reportClientDiagnostic(
              eventType: 'performance',
              severity: 'warning',
              message: 'Requete lente sur ${url.path}',
              screen: url.path,
              extra: {'durationMs': stopwatch.elapsedMilliseconds},
            ),
          );
        }
      }
      return response;
    } on TimeoutException {
      stopwatch.stop();
      if (!url.path.contains('/client-diagnostics/')) {
        unawaited(
          ApiService.reportClientDiagnostic(
            eventType: 'http_error',
            severity: 'warning',
            message: 'Delai reseau depasse sur ${url.path}',
            screen: url.path,
            extra: {'durationMs': stopwatch.elapsedMilliseconds},
          ),
        );
      }
      throw const ApiException(
        'La connexion est trop lente. Verifiez le reseau puis reessayez.',
        statusCode: 408,
        code: 'network_timeout',
      );
    }
  }

  Future<raw_http.Response> get(Uri url, {Map<String, String>? headers}) =>
      _bounded(url, raw_http.get(url, headers: headers));

  Future<raw_http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) => _bounded(
    url,
    raw_http.post(url, headers: headers, body: body, encoding: encoding),
  );

  Future<raw_http.Response> patch(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) => _bounded(
    url,
    raw_http.patch(url, headers: headers, body: body, encoding: encoding),
  );

  Future<raw_http.Response> put(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) => _bounded(
    url,
    raw_http.put(url, headers: headers, body: body, encoding: encoding),
  );

  Future<raw_http.Response> delete(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) => _bounded(
    url,
    raw_http.delete(url, headers: headers, body: body, encoding: encoding),
  );
}

class ApiException implements Exception {
  final String message;
  final int statusCode;
  final String code;
  final int? retryAfterSeconds;

  const ApiException(
    this.message, {
    required this.statusCode,
    this.code = '',
    this.retryAfterSeconds,
  });

  @override
  String toString() => message;
}

class ApiService {
  static final ValueNotifier<int> friendshipRevision = ValueNotifier<int>(0);
  static const bool useLiveKitForCalls = bool.fromEnvironment(
    'USE_LIVEKIT_FOR_CALLS',
    defaultValue: true,
  );
  static const String _configuredCompanyId = String.fromEnvironment(
    'COMPANY_ID',
  );
  static const String _configuredCompanySlug = String.fromEnvironment(
    'COMPANY_SLUG',
  );

  static String? userToken;
  static Map<String, dynamic>? currentUser;
  static String? agentToken;
  static Map<String, dynamic>? currentAgent;
  static String? companyId = _configuredCompanyId.isEmpty
      ? null
      : _configuredCompanyId;
  static String? companySlug = _configuredCompanySlug.isEmpty
      ? null
      : _configuredCompanySlug;
  static String? _callDeviceId;
  static PackageInfo? _packageInfo;
  static bool _flushingDiagnostics = false;
  static const String _queuedDiagnosticsKey = 'queued_client_diagnostics_v1';

  static String get baseUrl {
    const configured = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://tranviko.app/api',
    );
    return _normalizedHttpBaseUrl(configured);
  }

  static String _normalizedHttpBaseUrl(String value) {
    final raw = value.trim().isEmpty
        ? 'https://tranviko.app/api'
        : value.trim();
    final withScheme = raw.contains('://') ? raw : 'https://$raw';
    final uri = Uri.parse(withScheme);
    // Release/profile traffic is HTTPS-only. Local HTTP remains available in
    // debug builds for development on an emulator or a trusted LAN.
    final scheme = kDebugMode && uri.scheme == 'http' ? 'http' : 'https';
    final host = uri.host.isEmpty ? 'tranviko.app' : uri.host;
    final hasUsefulPort =
        uri.hasPort &&
        uri.port > 0 &&
        !((scheme == 'https' && uri.port == 443) ||
            (scheme == 'http' && uri.port == 80));
    final port = hasUsefulPort ? ':${uri.port}' : '';
    final path = uri.path.isEmpty ? '/api' : uri.path;
    final normalizedPath = path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    return '$scheme://$host$port$normalizedPath';
  }

  static Future<void> loadStoredCompany() async {
    if (_configuredCompanyId.isNotEmpty || _configuredCompanySlug.isNotEmpty) {
      companyId = _configuredCompanyId.isEmpty ? null : _configuredCompanyId;
      companySlug = _configuredCompanySlug.isEmpty
          ? null
          : _configuredCompanySlug;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('selected_company');
    if (raw != null && raw.isNotEmpty) {
      try {
        final company = jsonDecode(raw) as Map<String, dynamic>;
        companyId = company['id']?.toString();
        companySlug = company['slug']?.toString();
      } catch (_) {
        companyId = prefs.getString('company_id');
        companySlug = prefs.getString('company_slug');
      }
    } else {
      companyId = prefs.getString('company_id');
      companySlug = prefs.getString('company_slug');
    }
  }

  static Future<String> callDeviceId() async {
    final cached = _callDeviceId;
    if (cached != null && cached.isNotEmpty) return cached;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('call_device_id');
    if (stored != null && stored.isNotEmpty) {
      _callDeviceId = stored;
      return stored;
    }
    final random = math.Random.secure().nextInt(0x7fffffff).toRadixString(16);
    final generated = 'mobile-${DateTime.now().microsecondsSinceEpoch}-$random';
    await prefs.setString('call_device_id', generated);
    _callDeviceId = generated;
    return generated;
  }

  static Future<Map<String, String>> deviceMetadata() async {
    final id = await callDeviceId();
    var platform = 'unknown';
    var name = '';
    var osVersion = '';
    try {
      final plugin = DeviceInfoPlugin();
      if (kIsWeb) {
        final info = await plugin.webBrowserInfo;
        platform = 'web';
        name = '${info.browserName.name} Web'.trim();
      } else {
        switch (defaultTargetPlatform) {
          case TargetPlatform.android:
            final info = await plugin.androidInfo;
            platform = 'android';
            final brand = info.manufacturer.trim();
            final model = info.model.trim();
            name = model.toLowerCase().contains(brand.toLowerCase())
                ? model
                : '$brand $model'.trim();
            osVersion =
                'Android ${info.version.release} (SDK ${info.version.sdkInt})';
            break;
          case TargetPlatform.iOS:
            final info = await plugin.iosInfo;
            platform = 'ios';
            name = (info.name.trim().isNotEmpty ? info.name : info.model)
                .trim();
            osVersion = '${info.systemName} ${info.systemVersion}'.trim();
            break;
          case TargetPlatform.windows:
            final info = await plugin.windowsInfo;
            platform = 'windows';
            name = 'Desktop-${info.computerName}'.trim();
            osVersion = info.displayVersion.trim();
            break;
          case TargetPlatform.macOS:
            final info = await plugin.macOsInfo;
            platform = 'macos';
            name = info.computerName.trim();
            osVersion = info.osRelease.trim();
            break;
          case TargetPlatform.linux:
            final info = await plugin.linuxInfo;
            platform = 'linux';
            name = info.prettyName.trim();
            osVersion = info.version ?? info.prettyName;
            break;
          default:
            break;
        }
      }
    } catch (_) {}
    if (name.isEmpty) {
      final suffix = id.length > 6 ? id.substring(id.length - 6) : id;
      name = "${platform == 'unknown' ? 'Appareil' : platform}-$suffix";
    }
    return {
      'deviceId': id,
      'deviceName': name,
      'platform': platform,
      'osVersion': osVersion,
    };
  }

  static Future<void> persistTravelerSession(
    Map<String, dynamic> payload, {
    bool remember = true,
  }) async {
    agentToken = null;
    currentAgent = null;
    userToken = payload['token'] as String?;
    currentUser = payload['user'] as Map<String, dynamic>?;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('agent_token');
    await prefs.remove('current_agent');
    if (remember && userToken != null) {
      await prefs.setBool('remember_me', true);
      await prefs.setString('user_token', userToken!);
      if (currentUser != null) {
        await prefs.setString('current_user', jsonEncode(currentUser));
      }
    }
    _syncCompanyFromPayload(payload);
  }

  static Future<List<Map<String, dynamic>>> fetchCompanies() async {
    final response = await http.get(Uri.parse('$baseUrl/companies/'));
    _ensureSuccess(response);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(payload['results'] as List? ?? []);
  }

  static Future<void> selectCompany(Map<String, dynamic> company) async {
    final prefs = await SharedPreferences.getInstance();
    final nextId = company['id']?.toString();
    final nextSlug = company['slug']?.toString();
    final previousId = companyId ?? prefs.getString('company_id');
    final previousSlug = companySlug ?? prefs.getString('company_slug');
    final firstSelection = previousId == null && previousSlug == null;
    final changed =
        (previousId != null && nextId != null && previousId != nextId) ||
        (previousSlug != null && nextSlug != null && previousSlug != nextSlug);

    companyId = nextId;
    companySlug = nextSlug;
    if (nextId != null && nextId.isNotEmpty) {
      await prefs.setString('company_id', nextId);
    }
    if (nextSlug != null && nextSlug.isNotEmpty) {
      await prefs.setString('company_slug', nextSlug);
    }
    await prefs.setString('selected_company', jsonEncode(company));
    final colorValue = parseColorValue(company['primaryColor']);
    if (colorValue != null) {
      await prefs.setInt('company_primary_color', colorValue);
      if (firstSelection || changed || !prefs.containsKey('seed_color')) {
        await prefs.setInt('seed_color', colorValue);
      }
    }
    if (changed) {
      await clearAccountSession();
    }
  }

  static Future<void> clearAccountSession() async {
    try {
      await unregisterAppleVoipDevice();
    } catch (_) {}
    userToken = null;
    agentToken = null;
    currentUser = null;
    currentAgent = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('remember_me');
    await prefs.remove('user_token');
    await prefs.remove('agent_token');
    await prefs.remove('current_user');
    await prefs.remove('current_agent');
  }

  static int? parseColorValue(dynamic value) {
    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty) return null;
    final hex = raw
        .replaceFirst('#', '')
        .replaceFirst('0x', '')
        .replaceFirst('0X', '');
    if (hex.length == 6) {
      return int.tryParse('FF$hex', radix: 16);
    }
    if (hex.length == 8) {
      return int.tryParse(hex, radix: 16);
    }
    return null;
  }

  static Future<List<Map<String, dynamic>>> fetchTrips({
    required String departure,
    required String destination,
    required String date,
    bool acrossCompanies = false,
  }) async {
    final uri = Uri.parse('$baseUrl/trips/').replace(
      queryParameters: {
        'departure': departure,
        'destination': destination,
        'date': DateTime.parse(date).toIso8601String().split('T').first,
        if (acrossCompanies) 'scope': 'all',
      },
    );
    final response = await http.get(uri, headers: _tenantHeaders());
    _ensureSuccess(response);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(payload['results'] as List);
  }

  static Future<List<Map<String, dynamic>>> fetchHomeStories() async {
    final response = await http.get(
      Uri.parse('$baseUrl/home-stories/'),
      headers: _tenantHeaders(),
    );
    _ensureSuccess(response);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(payload['results'] as List? ?? []);
  }

  static Future<Map<String, dynamic>> fetchAppControlStatus({
    required String version,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/app-control/',
    ).replace(queryParameters: {'version': version});
    final response = await http.get(uri, headers: _tenantHeaders());
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> createReservation(
    Map<String, dynamic> reservation, {
    String? userToken,
  }) async {
    final payload = Map<String, dynamic>.from(reservation);
    final bus = payload['bus'];
    if (payload['tripId'] == null && bus is Map && bus['id'] != null) {
      payload['tripId'] = bus['id'];
    }
    final response = await http.post(
      Uri.parse('$baseUrl/reservations/'),
      headers: {
        ..._tenantHeaders(),
        'Content-Type': 'application/json',
        if ((userToken ?? ApiService.userToken) != null)
          'X-User-Token': userToken ?? ApiService.userToken!,
      },
      body: jsonEncode(payload),
    );
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<List<Map<String, dynamic>>> fetchReservations() async {
    final response = await http.get(
      Uri.parse('$baseUrl/reservations/'),
      headers: _accountHeaders(),
    );
    _ensureSuccess(response);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(payload['results'] as List);
  }

  static Future<Map<String, dynamic>> claimGuestReservations(
    List<Map<String, dynamic>> reservations,
  ) async {
    final candidates = reservations
        .where(
          (item) =>
              (item['id']?.toString().isNotEmpty ?? false) &&
              (item['guestAccessToken']?.toString().isNotEmpty ?? false),
        )
        .map(
          (item) => {
            'id': item['id'],
            'guestAccessToken': item['guestAccessToken'],
          },
        )
        .toList();
    if (candidates.isEmpty) {
      return const {
        'results': <Map<String, dynamic>>[],
        'claimedIds': <String>[],
        'rejectedIds': <String>[],
      };
    }
    final response = await http.post(
      Uri.parse('$baseUrl/reservations/claim-guest/'),
      headers: {'Content-Type': 'application/json', ..._accountHeaders()},
      body: jsonEncode({'reservations': candidates}),
    );
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<List<Map<String, dynamic>>> fetchAccountPackages() async {
    final response = await http.get(
      Uri.parse('$baseUrl/account/packages/'),
      headers: _accountHeaders(),
    );
    _ensureSuccess(response);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(payload['results'] as List? ?? []);
  }

  static Future<List<String>> fetchCities() async {
    final response = await http.get(
      Uri.parse('$baseUrl/cities/'),
      headers: _tenantHeaders(),
    );
    _ensureSuccess(response);
    final payload = jsonDecode(response.body);
    final items = payload is Map<String, dynamic>
        ? payload['results']
        : payload;
    return List<Map<String, dynamic>>.from(items as List)
        .map((city) => (city['name'] ?? city['nom'] ?? '').toString().trim())
        .where((name) => name.isNotEmpty)
        .toList();
  }

  static Future<Map<String, dynamic>> loginUser({
    required String username,
    required String password,
    String? loginChallengeId,
    String? loginVerificationCode,
  }) async {
    final metadata = await deviceMetadata();
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login/'),
      headers: {'Content-Type': 'application/json', ..._tenantHeaders()},
      body: jsonEncode({
        'username': username,
        'password': password,
        if (loginChallengeId != null && loginChallengeId.isNotEmpty)
          'loginChallengeId': loginChallengeId,
        if (loginVerificationCode != null && loginVerificationCode.isNotEmpty)
          'loginVerificationCode': loginVerificationCode,
        ...metadata,
      }),
    );
    _ensureSuccess(response);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (payload['requiresEmailCode'] != true && payload['token'] != null) {
      await persistTravelerSession(payload, remember: false);
    }
    return payload;
  }

  static Future<Map<String, dynamic>> registerUser({
    required String fullName,
    required String username,
    required String email,
    required String password,
    String? phone,
    String? verificationCode,
    String? verificationChannel,
    String? profilePhotoBase64,
  }) async {
    final metadata = await deviceMetadata();
    final response = await http.post(
      Uri.parse('$baseUrl/auth/register/'),
      headers: {'Content-Type': 'application/json', ..._tenantHeaders()},
      body: jsonEncode({
        'fullName': fullName,
        'username': username,
        'phone': phone ?? username,
        'email': email,
        'password': password,
        if (verificationCode != null) 'verificationCode': verificationCode,
        if (verificationChannel != null)
          'verificationChannel': verificationChannel,
        if (profilePhotoBase64 != null && profilePhotoBase64.isNotEmpty)
          'profilePhotoBase64': profilePhotoBase64,
        ...metadata,
      }),
    );
    _ensureSuccess(response);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    await persistTravelerSession(payload, remember: false);
    return payload;
  }

  static Future<Map<String, dynamic>> requestPhoneVerification({
    required String phone,
    String? email,
    String channel = 'email',
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/request-phone-code/'),
      headers: {'Content-Type': 'application/json', ..._tenantHeaders()},
      body: jsonEncode({
        'phone': phone,
        if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
        'channel': channel,
      }),
    );
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> requestPasswordReset({
    required String identifier,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/password-reset/request/'),
      headers: {'Content-Type': 'application/json', ..._tenantHeaders()},
      body: jsonEncode({'identifier': identifier}),
    );
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> confirmPasswordReset({
    required String identifier,
    required String code,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/password-reset/confirm/'),
      headers: {'Content-Type': 'application/json', ..._tenantHeaders()},
      body: jsonEncode({
        'identifier': identifier,
        'code': code,
        'password': password,
      }),
    );
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> fetchNotificationsPage({
    String? userToken,
    bool archived = false,
    String search = '',
    int limit = 20,
    int offset = 0,
  }) async {
    final uri = Uri.parse('$baseUrl/notifications/').replace(
      queryParameters: {
        'archived': '$archived',
        'limit': '$limit',
        'offset': '$offset',
        if (search.isNotEmpty) 'search': search,
      },
    );
    final response = await http.get(uri, headers: _accountHeaders(userToken));
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<List<Map<String, dynamic>>> fetchNotifications({
    String? userToken,
    bool archived = false,
    String search = '',
  }) async {
    final payload = await fetchNotificationsPage(
      userToken: userToken,
      archived: archived,
      search: search,
      limit: 20,
      offset: 0,
    );
    return List<Map<String, dynamic>>.from(payload['results'] as List);
  }

  static Future<Map<String, dynamic>> sendReservationFeedback({
    required int reservationId,
    required int rating,
    required String comment,
    String? userToken,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/reservations/$reservationId/feedback/'),
      headers: {
        ..._tenantHeaders(),
        'Content-Type': 'application/json',
        if ((userToken ?? ApiService.userToken) != null)
          'X-User-Token': userToken ?? ApiService.userToken!,
      },
      body: jsonEncode({'rating': rating, 'comment': comment}),
    );
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> cancelReservation({
    required int reservationId,
    String reason = '',
    String? userToken,
    String guestAccessToken = '',
    String reservationCode = '',
    String payerPhone = '',
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/reservations/$reservationId/cancel/'),
      headers: {
        ..._accountHeaders(userToken),
        'Content-Type': 'application/json',
        if (guestAccessToken.isNotEmpty)
          'X-Reservation-Token': guestAccessToken,
        if (reservationCode.isNotEmpty) 'X-Reservation-Code': reservationCode,
        if (payerPhone.isNotEmpty) 'X-Reservation-Payer': payerPhone,
      },
      body: jsonEncode({'reason': reason}),
    );
    _ensureSuccess(response);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return payload['reservation'] as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> fetchCancellationQuote({
    required int reservationId,
    String? userToken,
    String guestAccessToken = '',
    String reservationCode = '',
    String payerPhone = '',
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/reservations/$reservationId/cancel/'),
      headers: {
        ..._accountHeaders(userToken),
        if (guestAccessToken.isNotEmpty)
          'X-Reservation-Token': guestAccessToken,
        if (reservationCode.isNotEmpty) 'X-Reservation-Code': reservationCode,
        if (payerPhone.isNotEmpty) 'X-Reservation-Payer': payerPhone,
      },
    );
    _ensureSuccess(response);
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  static Future<Map<String, dynamic>> setTripSeatAlert({
    required int tripId,
    required String travelDate,
    int requestedSeats = 1,
    bool active = true,
  }) async {
    final uri = Uri.parse('$baseUrl/trips/$tripId/seat-alert/');
    final response = active
        ? await http.post(
            uri,
            headers: {..._accountHeaders(), 'Content-Type': 'application/json'},
            body: jsonEncode({
              'travelDate': travelDate,
              'requestedSeats': requestedSeats,
            }),
          )
        : await http.delete(
            uri.replace(queryParameters: {'date': travelDate}),
            headers: _accountHeaders(),
          );
    _ensureSuccess(response);
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  static Future<Map<String, dynamic>> trackPackage(String code) async {
    final response = await http.get(
      Uri.parse('$baseUrl/tracking/$code/'),
      headers: _tenantHeaders(),
    );
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> loginAgent({
    required String username,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/agent/login/'),
      headers: {'Content-Type': 'application/json', ..._tenantHeaders()},
      body: jsonEncode({'username': username, 'password': password}),
    );
    _ensureSuccess(response);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    userToken = null;
    currentUser = null;
    agentToken = payload['token'] as String?;
    currentAgent = payload['agent'] as Map<String, dynamic>?;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_token');
    await prefs.remove('current_user');
    _syncCompanyFromPayload(payload);
    return payload;
  }

  static Future<String> createManagerMobileEntry(String token) async {
    final response = await http.post(
      Uri.parse('$baseUrl/manager/mobile-entry/'),
      headers: {..._tenantHeaders(), 'X-Agent-Token': token},
    );
    _ensureSuccess(response);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final url = payload['url']?.toString().trim() ?? '';
    if (url.isEmpty) {
      throw const ApiException('Lien WebAdmin indisponible.', statusCode: 502);
    }
    return url;
  }

  static Future<List<Map<String, dynamic>>> fetchAgentTickets(
    String token, {
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/agent/tickets/?limit=$limit&offset=$offset'),
      headers: {..._tenantHeaders(), 'X-Agent-Token': token},
    );
    _ensureSuccess(response);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(payload['results'] as List);
  }

  static Future<List<Map<String, dynamic>>> fetchAgentBuses(
    String token, {
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/agent/buses/?limit=$limit&offset=$offset'),
      headers: {..._tenantHeaders(), 'X-Agent-Token': token},
    );
    _ensureSuccess(response);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(payload['results'] as List);
  }

  static Future<Map<String, dynamic>> validateTicket({
    required String token,
    required String code,
    required String method,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/agent/validate-ticket/'),
      headers: {
        'Content-Type': 'application/json',
        ..._tenantHeaders(),
        'X-Agent-Token': token,
      },
      body: jsonEncode({'code': code, 'method': method}),
    );
    if (response.statusCode == 409) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> updateBusStatus({
    required String token,
    required int busId,
    required String status,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/agent/buses/$busId/status/'),
      headers: {
        'Content-Type': 'application/json',
        ..._tenantHeaders(),
        'X-Agent-Token': token,
      },
      body: jsonEncode({'status': status}),
    );
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> fetchBiometricProfile(
    String token,
  ) async {
    final response = await http.get(
      Uri.parse('$baseUrl/biometric/profile/'),
      headers: {..._tenantHeaders(), 'X-Agent-Token': token},
    );
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> verifyBiometricPassword({
    required String token,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/biometric/verify-password/'),
      headers: {
        'Content-Type': 'application/json',
        ..._tenantHeaders(),
        'X-Agent-Token': token,
      },
      body: jsonEncode({'password': password}),
    );
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> enrollAgentFace({
    required String token,
    required List<String> imagesBase64,
    String? password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/biometric/enroll/'),
      headers: {
        'Content-Type': 'application/json',
        ..._tenantHeaders(),
        'X-Agent-Token': token,
      },
      body: jsonEncode({
        'images': imagesBase64,
        'liveness': true,
        if (password != null && password.isNotEmpty) 'password': password,
      }),
    );
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> checkInWithFace({
    required String token,
    required String imageBase64,
    String location = 'App mobile agent',
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/biometric/facial/'),
      headers: {
        'Content-Type': 'application/json',
        ..._tenantHeaders(),
        'X-Agent-Token': token,
      },
      body: jsonEncode({'image': imageBase64, 'location': location}),
    );
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> manualBiometricCheckIn({
    required String token,
    String location = 'Pointage manuel app mobile',
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/biometric/manual-check-in/'),
      headers: {
        'Content-Type': 'application/json',
        ..._tenantHeaders(),
        'X-Agent-Token': token,
      },
      body: jsonEncode({'location': location}),
    );
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> verifyPassengerFace({
    required String token,
    required String reservationCode,
    required int passengerId,
    required String imageBase64,
    required bool enroll,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/biometric/passenger/'),
      headers: {
        'Content-Type': 'application/json',
        ..._tenantHeaders(),
        'X-Agent-Token': token,
      },
      body: jsonEncode({
        'reservationCode': reservationCode,
        'passengerId': passengerId,
        'image': imageBase64,
        'mode': enroll ? 'enroll' : 'verify',
      }),
    );
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> createAgentPackage({
    required String token,
    required Map<String, dynamic> data,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/agent/packages/create/'),
      headers: {
        'Content-Type': 'application/json',
        ..._tenantHeaders(),
        'X-Agent-Token': token,
      },
      body: jsonEncode(data),
    );
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> requestPackageValidation({
    required String token,
    required String trackingCode,
    required String arrivalPhotoBase64,
    required String agentSignatureBase64,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/agent/packages/$trackingCode/validation-request/'),
      headers: {
        'Content-Type': 'application/json',
        ..._tenantHeaders(),
        'X-Agent-Token': token,
      },
      body: jsonEncode({
        'arrivalPhoto': 'data:image/jpeg;base64,$arrivalPhotoBase64',
        'agentSignature': 'data:image/jpeg;base64,$agentSignatureBase64',
      }),
    );
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> confirmPackageValidation({
    required String token,
    required String trackingCode,
    required String managerSignatureBase64,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/manager/packages/$trackingCode/confirm-validation/'),
      headers: {
        'Content-Type': 'application/json',
        ..._tenantHeaders(),
        'X-Agent-Token': token,
      },
      body: jsonEncode({
        'managerSignature': 'data:image/jpeg;base64,$managerSignatureBase64',
      }),
    );
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> createAgentExpense({
    required String token,
    required String title,
    required String category,
    required double amount,
    String description = '',
    DateTime? expenseDate,
    int? busId,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/agent/expenses/'),
      headers: {
        'Content-Type': 'application/json',
        ..._tenantHeaders(),
        'X-Agent-Token': token,
      },
      body: jsonEncode({
        'title': title,
        'category': category,
        'amount': amount,
        'description': description,
        if (expenseDate != null)
          'expenseDate': expenseDate.toIso8601String().substring(0, 10),
        if (busId != null) 'busId': busId,
      }),
    );
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> startDriverJourney({
    required String token,
    required int tripId,
    String? origin,
    String? destination,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/driver/journey/start/'),
      headers: {
        'Content-Type': 'application/json',
        ..._tenantHeaders(),
        'X-Agent-Token': token,
      },
      body: jsonEncode({
        'tripId': tripId,
        if (origin != null) 'origin': origin,
        if (destination != null) 'destination': destination,
      }),
    );
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>?> fetchCurrentJourney(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/driver/journey/current/'),
      headers: {..._tenantHeaders(), 'X-Agent-Token': token},
    );
    _ensureSuccess(response);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return payload['journey'] as Map<String, dynamic>?;
  }

  static Future<Map<String, dynamic>> pushDriverLocation({
    required String token,
    required int journeyId,
    required double latitude,
    required double longitude,
    required double speedKmh,
    required double bearing,
    required double accuracyM,
    required DateTime recordedAt,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/driver/journey/$journeyId/location/'),
      headers: {
        'Content-Type': 'application/json',
        ..._tenantHeaders(),
        'X-Agent-Token': token,
      },
      body: jsonEncode({
        'latitude': latitude,
        'longitude': longitude,
        'speedKmh': speedKmh,
        'bearing': bearing,
        'accuracyM': accuracyM,
        'recordedAt': recordedAt.toUtc().toIso8601String(),
        'liveSample':
            DateTime.now().difference(recordedAt.toLocal()).abs() <
            const Duration(minutes: 2),
      }),
    );
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> finishDriverJourney({
    required String token,
    required int journeyId,
    String? reason,
    String? severity,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/driver/journey/$journeyId/finish/'),
      headers: {
        'Content-Type': 'application/json',
        ..._tenantHeaders(),
        'X-Agent-Token': token,
      },
      body: jsonEncode({
        if (reason != null) 'reason': reason,
        if (severity != null) 'severity': severity,
      }),
    );
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> sendContactServiceMessage({
    required String name,
    required String email,
    required String message,
    String phone = '',
    String subject = 'Demande service client',
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/contact-service/'),
      headers: {'Content-Type': 'application/json', ..._accountHeaders()},
      body: jsonEncode({
        'name': name,
        'email': email,
        'phone': phone,
        'subject': subject,
        'message': message,
      }),
    );
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Map<String, String> _accountHeaders([String? explicitToken]) {
    final headers = _tenantHeaders();
    if (explicitToken != null && explicitToken.isNotEmpty) {
      if (agentToken != null && explicitToken == agentToken) {
        headers['X-Agent-Token'] = explicitToken;
      } else {
        headers['X-User-Token'] = explicitToken;
      }
      return headers;
    }
    final signedInAsAgent = currentAgent != null && agentToken != null;
    if (signedInAsAgent) {
      headers['X-Agent-Token'] = agentToken!;
      return headers;
    }
    if (userToken != null) headers['X-User-Token'] = userToken!;
    if (agentToken != null) headers['X-Agent-Token'] = agentToken!;
    return headers;
  }

  static Map<String, String> _tenantHeaders() {
    return {
      if (companyId != null && companyId!.trim().isNotEmpty)
        'X-Company-Id': companyId!.trim(),
      if (companySlug != null && companySlug!.trim().isNotEmpty)
        'X-Company-Slug': companySlug!.trim(),
    };
  }

  static Map<String, String> _tenantQuery([Map<String, String>? base]) {
    return {
      if (companyId != null && companyId!.trim().isNotEmpty)
        'companyId': companyId!.trim(),
      if (companySlug != null && companySlug!.trim().isNotEmpty)
        'companySlug': companySlug!.trim(),
      // Explicit route ownership (for example a trip returned by the global
      // marketplace search) must override the currently selected storefront.
      ...?base,
    };
  }

  static void _syncCompanyFromPayload(Map<String, dynamic> payload) {
    final account = payload['user'] ?? payload['agent'];
    if (account is! Map) return;
    final company = account['company'];
    if (company is! Map) return;
    final id = company['id']?.toString();
    final slug = company['slug']?.toString();
    if (id != null && id.isNotEmpty) companyId = id;
    if (slug != null && slug.isNotEmpty) companySlug = slug;
  }

  static String? get activeToken {
    if (currentAgent != null && agentToken != null) return agentToken;
    return userToken ?? agentToken;
  }

  static Uri _webSocketUri(
    String path, [
    Map<String, String>? queryParameters,
  ]) {
    final apiUri = Uri.parse(baseUrl);
    final secure = apiUri.scheme == 'https' || apiUri.scheme == 'wss';
    final scheme = secure ? 'wss' : 'ws';
    final hasUsefulPort =
        apiUri.hasPort &&
        apiUri.port > 0 &&
        !((secure && apiUri.port == 443) || (!secure && apiUri.port == 80));
    final port = hasUsefulPort ? ':${apiUri.port}' : '';
    final query = Uri(queryParameters: _tenantQuery(queryParameters)).query;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final url =
        '$scheme://${apiUri.host}$port$normalizedPath${query.isEmpty ? '' : '?$query'}';
    return Uri.parse(url);
  }

  static Future<Map<String, dynamic>> fetchProfile() async {
    final response = await http.get(
      Uri.parse('$baseUrl/account/profile/'),
      headers: _accountHeaders(),
    );
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> updateProfile(
    Map<String, dynamic> data,
  ) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/account/profile/'),
      headers: {'Content-Type': 'application/json', ..._accountHeaders()},
      body: jsonEncode(data),
    );
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> updatePreferences(
    Map<String, dynamic> data,
  ) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/account/preferences/'),
      headers: {'Content-Type': 'application/json', ..._accountHeaders()},
      body: jsonEncode(data),
    );
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/account/change-password/'),
      headers: {'Content-Type': 'application/json', ..._accountHeaders()},
      body: jsonEncode({
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      }),
    );
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<List<Map<String, dynamic>>> fetchAccountSessions() async {
    final response = await http.get(
      Uri.parse('$baseUrl/account/sessions/'),
      headers: _accountHeaders(),
    );
    _ensureSuccess(response);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(payload['results'] as List? ?? []);
  }

  static Future<Map<String, dynamic>> revokeAccountSession({
    required String type,
    required int id,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/account/sessions/revoke/'),
      headers: {'Content-Type': 'application/json', ..._accountHeaders()},
      body: jsonEncode({'type': type, 'id': id}),
    );
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> createQrLoginChallenge() async {
    final response = await http.post(
      Uri.parse('$baseUrl/account/qr-login/challenge/'),
      headers: {'Content-Type': 'application/json', ..._accountHeaders()},
      body: '{}',
    );
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> requestQrLoginValidation({
    required String challenge,
  }) async {
    final metadata = await deviceMetadata();
    final response = await http.post(
      Uri.parse('$baseUrl/account/qr-login/request/'),
      headers: {'Content-Type': 'application/json', ..._tenantHeaders()},
      body: jsonEncode({'challenge': challenge, ...metadata}),
    );
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> approveQrLoginValidation({
    required String validation,
  }) async {
    final metadata = await deviceMetadata();
    final response = await http.post(
      Uri.parse('$baseUrl/account/qr-login/approve/'),
      headers: {'Content-Type': 'application/json', ..._accountHeaders()},
      body: jsonEncode({'validation': validation, ...metadata}),
    );
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> completeQrLoginValidation({
    required String validation,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/account/qr-login/complete/'),
      headers: {'Content-Type': 'application/json', ..._tenantHeaders()},
      body: jsonEncode({'validation': validation}),
    );
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<void> notificationAction(String action, List<int> ids) async {
    final response = await http.post(
      Uri.parse('$baseUrl/notifications/action/'),
      headers: {'Content-Type': 'application/json', ..._accountHeaders()},
      body: jsonEncode({'action': action, 'ids': ids}),
    );
    _ensureSuccess(response);
  }

  static Future<List<Map<String, dynamic>>> fetchConversations({
    bool archived = false,
    bool favoritesOnly = false,
  }) async {
    final uri = Uri.parse('$baseUrl/chat/conversations/').replace(
      queryParameters: {
        'archived': '$archived',
        if (favoritesOnly) 'favorite': 'true',
      },
    );
    final response = await http.get(uri, headers: _accountHeaders());
    _ensureSuccess(response);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(payload['results'] as List);
  }

  static Future<List<Map<String, dynamic>>> syncPhoneContacts(
    List<Map<String, dynamic>> contacts,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/chat/contacts/sync/'),
      headers: {'Content-Type': 'application/json', ..._accountHeaders()},
      body: jsonEncode({'contacts': contacts}),
    );
    _ensureSuccess(response);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(payload['results'] as List? ?? []);
  }

  static Future<List<Map<String, dynamic>>> searchTravelerContacts(
    String query,
  ) async {
    final clean = query.trim();
    if (clean.length < 2) return [];
    final uri = Uri.parse(
      '$baseUrl/chat/contacts/search/',
    ).replace(queryParameters: {'q': clean});
    final response = await http.get(uri, headers: _accountHeaders());
    _ensureSuccess(response);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(payload['results'] as List? ?? []);
  }

  static Future<List<Map<String, dynamic>>> fetchFriendRequests() async {
    final response = await http.get(
      Uri.parse('$baseUrl/chat/friends/'),
      headers: _accountHeaders(),
    );
    _ensureSuccess(response);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(payload['results'] as List? ?? []);
  }

  static Future<Map<String, dynamic>> sendFriendRequest(
    int targetUserId,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/chat/friends/'),
      headers: {'Content-Type': 'application/json', ..._accountHeaders()},
      body: jsonEncode({'targetUserId': targetUserId}),
    );
    _ensureSuccess(response);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    friendshipRevision.value++;
    return payload;
  }

  static Future<Map<String, dynamic>> friendRequestAction({
    required int requestId,
    required String action,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/chat/friends/$requestId/action/'),
      headers: {'Content-Type': 'application/json', ..._accountHeaders()},
      body: jsonEncode({'action': action}),
    );
    _ensureSuccess(response);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    friendshipRevision.value++;
    return payload;
  }

  static Future<Map<String, dynamic>> fetchMessagesPage(
    int userId, {
    int limit = 40,
    String? before,
  }) async {
    final uri = Uri.parse('$baseUrl/chat/messages/$userId/').replace(
      queryParameters: {
        'limit': '$limit',
        if (before != null && before.isNotEmpty) 'before': before,
      },
    );
    final response = await http.get(uri, headers: _accountHeaders());
    _ensureSuccess(response);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return {
      'results': List<Map<String, dynamic>>.from(payload['results'] as List),
      'hasMore': payload['hasMore'] == true,
      'nextBefore': payload['nextBefore']?.toString(),
    };
  }

  static Future<Map<String, dynamic>> fetchChatMedia({
    String kind = 'gif',
    String query = '',
    int offset = 0,
    int limit = 24,
  }) async {
    final uri = Uri.parse('$baseUrl/chat/media/search/').replace(
      queryParameters: {
        'kind': kind,
        if (query.trim().isNotEmpty) 'q': query.trim(),
        'offset': '$offset',
        'limit': '$limit',
      },
    );
    final response = await http.get(uri, headers: _accountHeaders());
    _ensureSuccess(response);
    final payload = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    return {
      ...payload,
      'results': List<Map<String, dynamic>>.from(
        payload['results'] as List? ?? const [],
      ),
    };
  }

  static Future<List<Map<String, dynamic>>> fetchMessages(int userId) async {
    final payload = await fetchMessagesPage(userId, limit: 80);
    return List<Map<String, dynamic>>.from(payload['results'] as List);
  }

  static Future<Map<String, dynamic>> sendChatMessage({
    required int userId,
    required String body,
    String type = 'text',
    Map<String, dynamic>? metadata,
    String? audioBase64,
    int? audioDurationSeconds,
    String? fileBase64,
    String? fileName,
    String? attachmentType,
    int? attachmentSize,
    String? attachmentUrl,
    String? attachmentObjectKey,
    String? uploadToken,
    String? toolAction,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/chat/messages/$userId/'),
      headers: {'Content-Type': 'application/json', ..._accountHeaders()},
      body: jsonEncode({
        'body': body,
        'type': type,
        if (metadata != null) 'metadata': metadata,
        if (audioBase64 != null) 'audioBase64': audioBase64,
        if (audioDurationSeconds != null)
          'audioDurationSeconds': audioDurationSeconds,
        if (fileBase64 != null) 'fileBase64': fileBase64,
        if (fileName != null) 'fileName': fileName,
        if (attachmentType != null) 'attachmentType': attachmentType,
        if (attachmentSize != null) 'attachmentSize': attachmentSize,
        if (attachmentUrl != null) 'attachmentUrl': attachmentUrl,
        if (attachmentObjectKey != null)
          'attachmentObjectKey': attachmentObjectKey,
        if (uploadToken != null) 'uploadToken': uploadToken,
        if (toolAction != null) 'toolAction': toolAction,
      }),
    );
    _ensureSuccess(response);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return payload['message'] as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> createChatUploadIntent({
    required int userId,
    required String fileName,
    required String mimeType,
    required int size,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/chat/uploads/presign/'),
      headers: {'Content-Type': 'application/json', ..._accountHeaders()},
      body: jsonEncode({
        'recipientId': userId,
        'fileName': fileName,
        'mimeType': mimeType,
        'size': size,
      }),
    );
    _ensureSuccess(response);
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  static Future<void> uploadBytesToSignedUrl({
    required String uploadUrl,
    required Uint8List bytes,
    required String mimeType,
    Map<String, dynamic> headers = const {},
  }) async {
    final requestHeaders = <String, String>{
      'Content-Type': mimeType,
      for (final entry in headers.entries)
        if (entry.value != null) entry.key.toString(): entry.value.toString(),
    };
    final response = await http
        .put(Uri.parse(uploadUrl), headers: requestHeaders, body: bytes)
        .timeout(const Duration(minutes: 3));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Upload media indisponible.');
    }
  }

  static Future<void> ackChatDelivered(
    List<int> messageIds, {
    String source = 'device_ack',
  }) async {
    final ids = messageIds.where((id) => id > 0).toSet().toList();
    if (ids.isEmpty || activeToken == null) return;
    final response = await http.post(
      Uri.parse('$baseUrl/chat/messages/delivered/'),
      headers: {'Content-Type': 'application/json', ..._accountHeaders()},
      body: jsonEncode({'messageIds': ids, 'source': source}),
    );
    _ensureSuccess(response);
  }

  static Future<void> chatConversationAction({
    required int userId,
    required String action,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/chat/conversations/$userId/action/'),
      headers: {'Content-Type': 'application/json', ..._accountHeaders()},
      body: jsonEncode({'action': action}),
    );
    _ensureSuccess(response);
  }

  static Future<Map<String, dynamic>> fetchChatConversationInfo(
    int userId,
  ) async {
    final response = await http.get(
      Uri.parse('$baseUrl/chat/conversations/$userId/info/'),
      headers: _accountHeaders(),
    );
    _ensureSuccess(response);
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  static Future<void> reportChatConversation({
    required int userId,
    required String reason,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/chat/conversations/$userId/report/'),
      headers: {'Content-Type': 'application/json', ..._accountHeaders()},
      body: jsonEncode({'reason': reason}),
    );
    _ensureSuccess(response);
  }

  static Future<List<Map<String, dynamic>>> fetchTravelStories() async {
    final response = await http.get(
      Uri.parse('$baseUrl/chat/stories/'),
      headers: _accountHeaders(),
    );
    _ensureSuccess(response);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return (payload['results'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  static Future<Map<String, dynamic>> fetchTravelStory(int storyId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/chat/stories/$storyId/'),
      headers: _accountHeaders(),
    );
    _ensureSuccess(response);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return Map<String, dynamic>.from(payload['story'] as Map);
  }

  static Future<List<Map<String, dynamic>>> fetchHiddenTravelStories() async {
    final response = await http.get(
      Uri.parse('$baseUrl/chat/stories/hidden/'),
      headers: _accountHeaders(),
    );
    _ensureSuccess(response);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return (payload['results'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  static Future<Map<String, dynamic>> createTravelStory({
    required Uint8List bytes,
    required String name,
    required String mimeType,
    String caption = '',
    bool allowReshare = false,
    String audienceMode = 'friends',
    List<int> audienceUserIds = const [],
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/chat/stories/'),
      headers: {'Content-Type': 'application/json', ..._accountHeaders()},
      body: jsonEncode({
        'mediaBase64': base64Encode(bytes),
        'fileName': name,
        'mimeType': mimeType,
        'mediaType': mimeType.startsWith('video/') ? 'video' : 'image',
        'caption': caption,
        'allowReshare': allowReshare,
        'audienceMode': audienceMode,
        'audienceUserIds': audienceUserIds,
      }),
    );
    _ensureSuccess(response);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return Map<String, dynamic>.from(payload['story'] as Map);
  }

  static Future<void> deleteTravelStory(int storyId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/chat/stories/$storyId/'),
      headers: _accountHeaders(),
    );
    _ensureSuccess(response);
  }

  static Future<void> hideTravelStory(int storyId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/chat/stories/$storyId/hide/'),
      headers: {'Content-Type': 'application/json', ..._accountHeaders()},
      body: '{}',
    );
    _ensureSuccess(response);
  }

  static Future<void> unhideTravelStoryAuthor(int authorId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/chat/stories/hidden/$authorId/unhide/'),
      headers: {'Content-Type': 'application/json', ..._accountHeaders()},
      body: '{}',
    );
    _ensureSuccess(response);
  }

  static Future<Map<String, dynamic>> reshareTravelStory(int storyId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/chat/stories/$storyId/reshare/'),
      headers: {'Content-Type': 'application/json', ..._accountHeaders()},
      body: '{}',
    );
    _ensureSuccess(response);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return Map<String, dynamic>.from(payload['story'] as Map);
  }

  static Future<Map<String, dynamic>> reactToTravelStory({
    required int storyId,
    required String action,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/chat/stories/$storyId/reaction/'),
      headers: {'Content-Type': 'application/json', ..._accountHeaders()},
      body: jsonEncode({'action': action}),
    );
    _ensureSuccess(response);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return Map<String, dynamic>.from(payload['story'] as Map);
  }

  static Future<Map<String, dynamic>> replyToTravelStory({
    required int storyId,
    required String body,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/chat/stories/$storyId/reply/'),
      headers: {'Content-Type': 'application/json', ..._accountHeaders()},
      body: jsonEncode({'body': body}),
    );
    _ensureSuccess(response);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return Map<String, dynamic>.from(payload['message'] as Map);
  }

  static Future<Map<String, dynamic>> chatMessageAction({
    required int messageId,
    required String action,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/chat/messages/action/$messageId/'),
      headers: {'Content-Type': 'application/json', ..._accountHeaders()},
      body: jsonEncode({'action': action}),
    );
    _ensureSuccess(response);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return payload['message'] as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> reactToChatMessage({
    required int messageId,
    String? emoji,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/chat/messages/action/$messageId/'),
      headers: {'Content-Type': 'application/json', ..._accountHeaders()},
      body: jsonEncode({'action': 'reaction', 'emoji': emoji ?? 'remove'}),
    );
    _ensureSuccess(response);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return Map<String, dynamic>.from(payload['message'] as Map);
  }

  static Future<List<Map<String, dynamic>>> chatMessagesBatchAction({
    required List<int> messageIds,
    required String action,
    int? targetUserId,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/chat/messages/batch-action/'),
      headers: {'Content-Type': 'application/json', ..._accountHeaders()},
      body: jsonEncode({
        'messageIds': messageIds,
        'action': action,
        if (targetUserId != null) 'targetUserId': targetUserId,
      }),
    );
    _ensureSuccess(response);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return (payload['results'] as List? ?? [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  static Future<Map<String, dynamic>> chatToolTaskAction({
    required int taskId,
    required String action,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/chat/tools/$taskId/action/'),
      headers: {'Content-Type': 'application/json', ..._accountHeaders()},
      body: jsonEncode({'action': action}),
    );
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> fetchTripChat(
    String reservationCode,
  ) async {
    final response = await http.get(
      Uri.parse('$baseUrl/trip-chat/$reservationCode/'),
      headers: _accountHeaders(),
    );
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> sendTripChatMessage({
    required String reservationCode,
    required String body,
    String type = 'text',
    Map<String, dynamic>? metadata,
    String? audioBase64,
    int? audioDurationSeconds,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/trip-chat/$reservationCode/'),
      headers: {'Content-Type': 'application/json', ..._accountHeaders()},
      body: jsonEncode({
        'body': body,
        'type': type,
        if (metadata != null) 'metadata': metadata,
        if (audioBase64 != null) 'audioBase64': audioBase64,
        if (audioDurationSeconds != null)
          'audioDurationSeconds': audioDurationSeconds,
      }),
    );
    _ensureSuccess(response);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return payload['message'] as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> reportTripChatMessage({
    required String reservationCode,
    required int messageId,
    String reason = '',
  }) async {
    final response = await http.post(
      Uri.parse(
        '$baseUrl/trip-chat/$reservationCode/messages/$messageId/report/',
      ),
      headers: {'Content-Type': 'application/json', ..._accountHeaders()},
      body: jsonEncode({'reason': reason}),
    );
    _ensureSuccess(response);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return payload['message'] as Map<String, dynamic>;
  }

  static Uri chatWebSocketUri() {
    return _webSocketUri('/ws/chat/', {'token': activeToken ?? ''});
  }

  static Uri notificationWebSocketUri() {
    return _webSocketUri('/ws/notifications/', {'token': activeToken ?? ''});
  }

  static Uri callWebSocketUri() {
    return _webSocketUri('/ws/calls/', {'token': activeToken ?? ''});
  }

  static Future<Map<String, dynamic>> createLiveKitCallToken({
    required String roomName,
    String? callId,
    int? targetId,
    String? participantId,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/calls/livekit-token/'),
      headers: {'Content-Type': 'application/json', ..._accountHeaders()},
      body: jsonEncode({
        'roomName': roomName,
        if (callId != null) 'callId': callId,
        if (targetId != null) 'targetId': targetId,
        if (participantId != null) 'participantId': participantId,
      }),
    );
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Uri tripChatWebSocketUri(String reservationCode) {
    return _webSocketUri(
      '/ws/trip-chat/${Uri.encodeComponent(reservationCode)}/',
      {'token': activeToken ?? ''},
    );
  }

  static Uri trackingWebSocketUri() {
    return _webSocketUri('/ws/tracking/');
  }

  static Uri seatWebSocketUri({
    required int tripId,
    required String clientId,
    String? travelDate,
    String? tenantCompanyId,
  }) {
    return _webSocketUri('/ws/trips/$tripId/seats/', {
      'clientId': clientId,
      if (travelDate != null && travelDate.isNotEmpty) 'travelDate': travelDate,
      if (tenantCompanyId != null && tenantCompanyId.isNotEmpty)
        'companyId': tenantCompanyId,
    });
  }

  static void _ensureSuccess(raw_http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    var message = 'Une erreur est survenue. Reessayez dans un instant.';
    var code = '';
    int? retryAfterSeconds;
    try {
      final payload = jsonDecode(response.body);
      if (payload is Map) {
        final value =
            payload['message'] ?? payload['error'] ?? payload['detail'];
        if (value != null && value.toString().trim().isNotEmpty) {
          message = value.toString().trim();
        }
        code = payload['code']?.toString() ?? '';
        final retry = payload['retryAfterSeconds'];
        if (retry is num) {
          retryAfterSeconds = retry.toInt();
        } else {
          retryAfterSeconds = int.tryParse(retry?.toString() ?? '');
        }
      }
    } catch (_) {
      if (response.statusCode == 401) {
        message = 'Veuillez vous reconnecter.';
      } else if (response.statusCode == 403) {
        message =
            'Vous nÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾Ãƒâ€šÃ‚Â¢avez pas la permission pour cette action.';
      } else if ({502, 503, 504}.contains(response.statusCode)) {
        message =
            'Le serveur ne repond pas correctement (HTTP ${response.statusCode}). Verifiez votre historique avant de reessayer le paiement.';
      } else if (response.statusCode >= 500) {
        message =
            'Erreur serveur HTTP ${response.statusCode}. Reessayez puis communiquez l heure de la tentative au support Tranviko.';
      }
    }
    throw ApiException(
      message,
      statusCode: response.statusCode,
      code: code,
      retryAfterSeconds: retryAfterSeconds,
    );
  }

  Future<Map<String, dynamic>> getTripSeats(int tripId) async {
    final response = await http.get(
      Uri.parse("$baseUrl/api/trips/$tripId/seats/"),
      headers: _tenantHeaders(),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }

    throw Exception("Erreur");
  }

  static Future<Map<String, dynamic>> registerPushDevice({
    required String token,
    required String platform,
  }) async {
    final metadata = await deviceMetadata();
    final response = await http.post(
      Uri.parse('$baseUrl/push/register/'),
      headers: {
        'Content-Type': 'application/json',
        ..._accountHeaders(), // Injecte automatiquement X-User-Token ou X-Agent-Token
      },
      body: jsonEncode({'token': token, 'platform': platform, ...metadata}),
    );
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> registerAppleVoipDevice({
    required String token,
    required String environment,
    bool active = true,
  }) async {
    final metadata = await deviceMetadata();
    final response = await http.post(
      Uri.parse('$baseUrl/push/voip/register/'),
      headers: {'Content-Type': 'application/json', ..._accountHeaders()},
      body: jsonEncode({
        'token': token,
        'environment': environment,
        'active': active,
        'bundleId': 'app.tranviko.mobile',
        ...metadata,
      }),
    );
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<void> unregisterAppleVoipDevice() async {
    if (activeToken == null) return;
    final metadata = await deviceMetadata();
    final response = await http.post(
      Uri.parse('$baseUrl/push/voip/register/'),
      headers: {'Content-Type': 'application/json', ..._accountHeaders()},
      body: jsonEncode({
        'token': '',
        'environment': kDebugMode ? 'development' : 'production',
        'active': false,
        'bundleId': 'app.tranviko.mobile',
        ...metadata,
      }),
    );
    _ensureSuccess(response);
  }

  static Future<void> reportClientDiagnostic({
    required String eventType,
    required String severity,
    required String message,
    String stack = '',
    String screen = '',
    Map<String, dynamic>? extra,
  }) async {
    Map<String, dynamic>? body;
    try {
      final metadata = await deviceMetadata().timeout(
        const Duration(seconds: 2),
        onTimeout: () => const <String, String>{},
      );
      _packageInfo ??= await PackageInfo.fromPlatform().timeout(
        const Duration(seconds: 2),
        onTimeout: () => PackageInfo(
          appName: 'Tranviko',
          packageName: 'app.tranviko.mobile',
          version: 'unknown',
          buildNumber: 'unknown',
        ),
      );
      final platform = metadata['platform'] ?? defaultTargetPlatform.name;
      body = <String, dynamic>{
        'eventType': eventType,
        'severity': severity,
        'platform': platform,
        'appVersion': _packageInfo?.version ?? 'unknown',
        'buildNumber': _packageInfo?.buildNumber ?? 'unknown',
        'releaseChannel': kReleaseMode ? 'release' : 'debug',
        'screen': screen,
        'message': message.length > 700 ? message.substring(0, 700) : message,
        'stack': stack.length > 6000 ? stack.substring(0, 6000) : stack,
        'deviceId': metadata['deviceId'] ?? '',
        'deviceName': metadata['deviceName'] ?? '',
        'osVersion': metadata['osVersion'] ?? '',
        'extra': extra ?? const <String, dynamic>{},
      };
      await _sendDiagnosticBody(body);
      unawaited(flushQueuedClientDiagnostics());
    } catch (_) {
      if (body != null) await _queueDiagnostic(body);
    }
  }

  static Future<void> _sendDiagnosticBody(Map<String, dynamic> body) async {
    final response = await raw_http
        .post(
          Uri.parse('$baseUrl/client-diagnostics/'),
          headers: {'Content-Type': 'application/json', ..._accountHeaders()},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 5));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Diagnostic refuse (${response.statusCode})');
    }
  }

  static Future<void> _queueDiagnostic(Map<String, dynamic> body) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final queued = prefs.getStringList(_queuedDiagnosticsKey) ?? <String>[];
      queued.add(jsonEncode(body));
      while (queued.length > 30) {
        queued.removeAt(0);
      }
      await prefs.setStringList(_queuedDiagnosticsKey, queued);
    } catch (_) {}
  }

  static Future<void> flushQueuedClientDiagnostics() async {
    if (_flushingDiagnostics) return;
    _flushingDiagnostics = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final queued = List<String>.from(
        prefs.getStringList(_queuedDiagnosticsKey) ?? const <String>[],
      );
      if (queued.isEmpty) return;
      final remaining = <String>[];
      for (var index = 0; index < queued.length; index += 1) {
        final raw = queued[index];
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            await _sendDiagnosticBody(Map<String, dynamic>.from(decoded));
          }
        } catch (_) {
          remaining.addAll(queued.skip(index));
          break;
        }
      }
      if (remaining.isEmpty) {
        await prefs.remove(_queuedDiagnosticsKey);
      } else {
        await prefs.setStringList(_queuedDiagnosticsKey, remaining);
      }
    } catch (_) {
      // The queue remains available for the next connected launch.
    } finally {
      _flushingDiagnostics = false;
    }
  }
}
