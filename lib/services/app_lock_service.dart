import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLockSetupStatus { ready, needsDeviceSecurity, cancelled }

class AppLockActivationResult {
  final AppLockSetupStatus status;

  const AppLockActivationResult(this.status);

  bool get success => status == AppLockSetupStatus.ready;
  bool get needsDeviceSecurity =>
      status == AppLockSetupStatus.needsDeviceSecurity;
}

class AppLockService {
  static const preferenceKey = 'biometric_lock';
  static const _channel = MethodChannel('mali_compagnie/app_lock');

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(preferenceKey) ?? false;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(preferenceKey, value);
  }

  static Future<bool> isSupported() async {
    final auth = LocalAuthentication();
    try {
      return await auth.isDeviceSupported() || await auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> authenticate({required String reason}) async {
    final result = await verifyForActivation(reason: reason);
    return result.success;
  }

  static Future<AppLockActivationResult> verifyForActivation({
    required String reason,
  }) async {
    final auth = LocalAuthentication();
    try {
      final secure = await hasDeviceSecurity();
      if (secure == false) {
        return const AppLockActivationResult(
          AppLockSetupStatus.needsDeviceSecurity,
        );
      }
      final supported =
          await auth.isDeviceSupported() || await auth.canCheckBiometrics;
      if (!supported) {
        return const AppLockActivationResult(
          AppLockSetupStatus.needsDeviceSecurity,
        );
      }
      final ok = await auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      return AppLockActivationResult(
        ok ? AppLockSetupStatus.ready : AppLockSetupStatus.cancelled,
      );
    } on PlatformException catch (error) {
      final code = error.code.toLowerCase();
      final message = (error.message ?? '').toLowerCase();
      if (code.contains('notenrolled') ||
          code.contains('not_enrolled') ||
          code.contains('passcodenotset') ||
          code.contains('passcode_not_set') ||
          message.contains('not enrolled') ||
          message.contains('passcode') ||
          message.contains('screen lock')) {
        return const AppLockActivationResult(
          AppLockSetupStatus.needsDeviceSecurity,
        );
      }
      return const AppLockActivationResult(AppLockSetupStatus.cancelled);
    } catch (_) {
      return const AppLockActivationResult(AppLockSetupStatus.cancelled);
    }
  }

  static Future<bool> openSecuritySettings() async {
    try {
      return await _channel.invokeMethod<bool>('openSecuritySettings') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool?> hasDeviceSecurity() async {
    try {
      return await _channel.invokeMethod<bool>('isDeviceSecure');
    } catch (_) {
      return null;
    }
  }
}
