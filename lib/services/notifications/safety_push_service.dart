import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:pharmaguide/data/supabase/supabase_client.dart';

/// Firebase is transport only: it receives a generic nudge, then the device
/// re-fetches and checksum-verifies the public safety feed before displaying
/// any authored regulatory copy.
class SafetyPushService with WidgetsBindingObserver {
  SafetyPushService({FirebaseMessaging? messaging})
    : _messaging = messaging ?? FirebaseMessaging.instance;

  final FirebaseMessaging _messaging;
  StreamSubscription<String>? _tokenRefresh;
  StreamSubscription<RemoteMessage>? _foreground;
  StreamSubscription<RemoteMessage>? _opened;
  StreamSubscription<dynamic>? _authState;
  FutureOr<void> Function()? _onSafetyAlert;

  Future<bool> initialize({required FutureOr<void> Function() onSafetyAlert}) async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.android)) {
      return false;
    }
    try {
      _onSafetyAlert = onSafetyAlert;
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: false,
        sound: false,
      );
      _foreground = FirebaseMessaging.onMessage.listen((message) {
        if (message.data['type'] == 'safety_alert') {
          unawaited(Future<void>.sync(onSafetyAlert));
        }
      });
      _opened = FirebaseMessaging.onMessageOpenedApp.listen((message) {
        if (message.data['type'] == 'safety_alert') {
          unawaited(Future<void>.sync(onSafetyAlert));
        }
      });
      final initial = await _messaging.getInitialMessage();
      if (initial?.data['type'] == 'safety_alert') await onSafetyAlert();
      _tokenRefresh = _messaging.onTokenRefresh.listen((token) {
        unawaited(_register(token));
      });
      _authState = supabase.auth.onAuthStateChange.listen((state) {
        if (state.session == null) return;
        unawaited(_registerCurrentToken());
      });
      final token = await _messaging.getToken();
      if (token != null) await _register(token);
      WidgetsBinding.instance.addObserver(this);
      return true;
    } on Object catch (error) {
      // Native Firebase configuration is intentionally deployment-supplied;
      // an unconfigured build still has in-app, pull-on-launch safety checks.
      debugPrint('Safety push unavailable: $error');
      return false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final refresh = _onSafetyAlert;
      if (refresh != null) unawaited(Future<void>.sync(refresh));
    }
  }

  Future<void> _register(String token) async {
    if (supabase.auth.currentUser == null) return;
    final platform = defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
    await supabase.functions.invoke(
      'register-push-token',
      body: {'token': token, 'platform': platform},
    );
  }

  Future<void> _registerCurrentToken() async {
    final token = await _messaging.getToken();
    if (token != null) await _register(token);
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    await _tokenRefresh?.cancel();
    await _foreground?.cancel();
    await _opened?.cancel();
    await _authState?.cancel();
  }
}
