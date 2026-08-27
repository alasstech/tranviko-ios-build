import 'package:flutter/services.dart';

class DevicePermissionStatus {
  final String key;
  final String title;
  final String subtitle;
  final bool granted;

  const DevicePermissionStatus({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.granted,
  });

  factory DevicePermissionStatus.fromMap(Map<String, dynamic> map) {
    return DevicePermissionStatus(
      key: map['key']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      subtitle: map['subtitle']?.toString() ?? '',
      granted: map['granted'] == true,
    );
  }
}

class PermissionStatusService {
  static const MethodChannel _channel = MethodChannel('tranviko/permissions');

  static Future<List<DevicePermissionStatus>> statuses() async {
    final raw = await _channel.invokeMethod<List<dynamic>>('getStatuses');
    return (raw ?? const [])
        .whereType<Map>()
        .map((item) => DevicePermissionStatus.fromMap(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ))
        .toList();
  }

  static Future<bool> request(String key) async {
    return await _channel.invokeMethod<bool>('request', {'key': key}) ?? false;
  }

  static Future<bool> openAppSettings() async {
    return await _channel.invokeMethod<bool>('openAppSettings') ?? false;
  }
}
