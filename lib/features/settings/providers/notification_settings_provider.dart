import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show Provider;
import 'package:flutter_riverpod/legacy.dart' show ChangeNotifierProvider;
import 'package:pharmaguide/services/notifications/notification_authorization_service.dart';

final notificationAuthorizationServiceProvider =
    Provider<NotificationAuthorizationService>((ref) {
      return FlutterNotificationAuthorizationService();
    });

final notificationSettingsControllerProvider =
    ChangeNotifierProvider<NotificationSettingsController>((ref) {
      return NotificationSettingsController(
        service: ref.watch(notificationAuthorizationServiceProvider),
      );
    });

abstract interface class NotificationLifecycleBinding {
  void addObserver(WidgetsBindingObserver observer);

  void removeObserver(WidgetsBindingObserver observer);
}

class NotificationSettingsController extends ChangeNotifier
    with WidgetsBindingObserver {
  NotificationSettingsController({
    required this.service,
    NotificationLifecycleBinding? lifecycleBinding,
  }) : _lifecycleBinding =
           lifecycleBinding ?? _WidgetsBindingNotificationLifecycleBinding() {
    _lifecycleBinding.addObserver(this);
    initialRefresh = refresh();
  }

  final NotificationAuthorizationService service;
  final NotificationLifecycleBinding _lifecycleBinding;

  late final Future<void> initialRefresh;
  NotificationAuthorizationStatus _status =
      NotificationAuthorizationStatus.notDetermined;
  bool _isLoading = false;
  bool _isActionInProgress = false;
  bool _disposed = false;
  int _statusRevision = 0;

  NotificationAuthorizationStatus get status => _status;
  bool get isLoading => _isLoading;
  bool get isActionInProgress => _isActionInProgress;

  Future<void> refresh() async {
    if (_isActionInProgress) return;

    final revision = ++_statusRevision;
    _isLoading = true;
    _notifyListenersIfMounted();

    try {
      final status = await service.readStatus();
      if (revision == _statusRevision) _status = status;
    } on Object catch (_) {
      if (revision == _statusRevision) {
        _status = NotificationAuthorizationStatus.unavailable;
      }
    } finally {
      if (revision == _statusRevision) {
        _isLoading = false;
        _notifyListenersIfMounted();
      }
    }
  }

  Future<void> requestPermission() async {
    if (_isActionInProgress) return;

    final revision = ++_statusRevision;
    _isLoading = false;
    _isActionInProgress = true;
    _notifyListenersIfMounted();

    try {
      _status = await service.requestPermission();
    } on Object catch (_) {
      _status = NotificationAuthorizationStatus.unavailable;
    } finally {
      if (revision == _statusRevision) {
        _isActionInProgress = false;
        _notifyListenersIfMounted();
      }
    }
  }

  Future<void> openSettings() async {
    if (_isActionInProgress) return;

    final revision = ++_statusRevision;
    _isLoading = false;
    _isActionInProgress = true;
    _notifyListenersIfMounted();

    try {
      await service.openNotificationSettings();
    } on Object catch (_) {
      _status = NotificationAuthorizationStatus.unavailable;
    } finally {
      if (revision == _statusRevision) {
        _isActionInProgress = false;
        _notifyListenersIfMounted();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  void _notifyListenersIfMounted() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _lifecycleBinding.removeObserver(this);
    super.dispose();
  }
}

class _WidgetsBindingNotificationLifecycleBinding
    implements NotificationLifecycleBinding {
  @override
  void addObserver(WidgetsBindingObserver observer) {
    WidgetsBinding.instance.addObserver(observer);
  }

  @override
  void removeObserver(WidgetsBindingObserver observer) {
    WidgetsBinding.instance.removeObserver(observer);
  }
}
