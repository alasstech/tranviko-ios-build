import 'dart:async';

import 'package:flutter/foundation.dart';

class ActiveCallService extends ChangeNotifier {
  ActiveCallService._();

  static final ActiveCallService instance = ActiveCallService._();

  bool _active = false;
  bool _minimized = false;
  String _routeName = '';
  String _title = 'Appel en cours';
  String _status = 'Connexion...';
  Future<void> Function()? _onEnd;

  bool get active => _active;
  bool get minimized => _minimized;
  String get routeName => _routeName;
  String get title => _title;
  String get status => _status;

  void register({
    required String routeName,
    required String title,
    required String status,
    required Future<void> Function() onEnd,
  }) {
    final changed =
        !_active ||
        _routeName != routeName ||
        _title != title ||
        _status != status;
    _active = true;
    _routeName = routeName;
    _title = title.trim().isEmpty ? 'Appel en cours' : title.trim();
    _status = status.trim().isEmpty ? 'Connexion...' : status.trim();
    _onEnd = onEnd;
    if (changed) notifyListeners();
  }

  void update({String? status, String? title}) {
    if (!_active) return;
    var changed = false;
    if (status != null && status.trim().isNotEmpty && status != _status) {
      _status = status.trim();
      changed = true;
    }
    if (title != null && title.trim().isNotEmpty && title != _title) {
      _title = title.trim();
      changed = true;
    }
    if (changed) notifyListeners();
  }

  void minimize() {
    if (!_active || _minimized) return;
    _minimized = true;
    notifyListeners();
  }

  void restore() {
    if (!_active || !_minimized) return;
    _minimized = false;
    notifyListeners();
  }

  Future<void> end() async {
    final onEnd = _onEnd;
    if (onEnd == null) {
      clear();
      return;
    }
    await onEnd();
  }

  void clear({String? routeName}) {
    if (routeName != null && routeName.isNotEmpty && routeName != _routeName) {
      return;
    }
    if (!_active && !_minimized) return;
    _active = false;
    _minimized = false;
    _routeName = '';
    _title = 'Appel en cours';
    _status = 'Connexion...';
    _onEnd = null;
    notifyListeners();
  }
}
