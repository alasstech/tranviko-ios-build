import 'dart:io';

import 'package:flutter/services.dart';

class ScreenAwakeService {
  static const MethodChannel _channel = MethodChannel(
    'mali_compagnie/screen_awake',
  );
  static final Set<String> _owners = <String>{};

  static Future<void> acquire(String owner) async {
    final wasEmpty = _owners.isEmpty;
    _owners.add(owner);
    if (!wasEmpty || !Platform.isAndroid) return;
    await _setNative(true);
  }

  static Future<void> release(String owner) async {
    _owners.remove(owner);
    if (_owners.isNotEmpty || !Platform.isAndroid) return;
    await _setNative(false);
  }

  static Future<void> _setNative(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setKeepScreenOn', {
        'enabled': enabled,
      });
    } on PlatformException {
      // Older installed builds keep Android's normal timeout behavior.
    } on MissingPluginException {
      // This native channel is intentionally absent on desktop builds.
    }
  }
}
