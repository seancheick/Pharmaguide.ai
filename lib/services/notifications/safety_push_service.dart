import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:pharmaguide/data/supabase/supabase_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Firebase is transport only: it receives a generic nudge, then the device
/// re-fetches and checksum-verifies the public safety feed before displaying
/// any authored regulatory copy.
class SafetyPushService with WidgetsBindingObserver {
  SafetyPushService({
    FirebaseMessaging? messaging,
    this._invokeFunction,
  }) : _messaging = messaging ?? FirebaseMessaging.instance;

  /// The one live transport instance, set by [initialize]. Sign-out flows use
  /// it to tear down the device token while the session can still authorize
  /// the server-side removal.
  static SafetyPushService? active;

  final FirebaseMessaging _messaging;
  final Future<void> Function(String functionName, Map<String, dynamic> body)?
      _invokeFunction;
  bool _tokenRegistered = false;
  StreamSubscription<String>? _tokenRefresh;
  StreamSubscription<RemoteMessage>? _foreground;
  StreamSubscription<RemoteMessage>? _opened;
  StreamSubscription<dynamic>? _authState;
  FutureOr<void> Function()? _onSafetyAlert;

  Future<bool> initialize({
    required FutureOr<void> Function() onSafetyAlert,
    // Foreground nudge: refresh data quietly (no banner shows in foreground).
    FutureOr<void> Function()? onSubmissionUpdate,
    // The user tapped the OS notification: navigating is expected.
    FutureOr<void> Function()? onSubmissionUpdateOpened,
  }) async {
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
        } else if (message.data['type'] == 'submission_update' &&
            onSubmissionUpdate != null) {
          unawaited(Future<void>.sync(onSubmissionUpdate));
        }
      });
      _opened = FirebaseMessaging.onMessageOpenedApp.listen((message) {
        if (message.data['type'] == 'safety_alert') {
          unawaited(Future<void>.sync(onSafetyAlert));
        } else if (message.data['type'] == 'submission_update' &&
            onSubmissionUpdateOpened != null) {
          unawaited(Future<void>.sync(onSubmissionUpdateOpened));
        }
      });
      final initial = await _messaging.getInitialMessage();
      if (initial?.data['type'] == 'safety_alert') await onSafetyAlert();
      if (initial?.data['type'] == 'submission_update' &&
          onSubmissionUpdateOpened != null) {
        await onSubmissionUpdateOpened();
      }
      _tokenRefresh = _messaging.onTokenRefresh.listen((token) {
        unawaited(_register(token));
      });
      _authState = supabase.auth.onAuthStateChange.listen((state) {
        if (state.event == AuthChangeEvent.signedOut) {
          // A signed-out device must stop receiving the previous account's
          // pushes even when sign-out happened outside our own flow (session
          // expiry, account deletion, dev tools): invalidating the FCM token
          // makes every queued row for it come back UNREGISTERED and pruned.
          _tokenRegistered = false;
          unawaited(_deleteLocalToken());
          return;
        }
        if (state.session == null) return;
        unawaited(_registerCurrentToken());
      });
      await acquireAndRegisterToken();
      WidgetsBinding.instance.addObserver(this);
      active = this;
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
      // First-launch APNs readiness can outlast startup; finish registration
      // on the next foreground instead of staying dark for the session.
      if (!_tokenRegistered && supabase.auth.currentUser != null) {
        unawaited(acquireAndRegisterToken());
      }
    }
  }

  /// Permission → APNs readiness → FCM token, the order Firebase requires on
  /// Apple platforms. Failure is non-fatal: [FirebaseMessaging.onTokenRefresh]
  /// and the resumed-lifecycle retry complete registration later.
  @visibleForTesting
  Future<void> acquireAndRegisterToken() async {
    try {
      await _messaging.requestPermission();
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        String? apnsToken;
        for (var attempt = 0; attempt < 6; attempt++) {
          apnsToken = await _messaging.getAPNSToken();
          if (apnsToken != null) break;
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        // getToken() throws while the APNs token is missing; onTokenRefresh
        // fires once the platform delivers it, and registration follows then.
        if (apnsToken == null) return;
      }
      final token = await _messaging.getToken();
      if (token != null) await _register(token);
    } on Object catch (error) {
      debugPrint('Push token acquisition failed: $error');
    }
  }

  /// Best-effort push teardown while the session JWT still authorizes it:
  /// remove this device's row server-side, then invalidate the FCM token so
  /// any row that survived comes back UNREGISTERED and is pruned on the next
  /// dispatch. Never throws — sign-out must not block on push cleanup.
  Future<void> unregisterBeforeSignOut() async {
    _tokenRegistered = false;
    String? token;
    try {
      token = await _messaging.getToken().timeout(const Duration(seconds: 2));
    } on Object {
      token = null;
    }
    if (token != null) {
      try {
        await _invoke('register-push-token', {
          'action': 'unregister',
          'token': token,
        }).timeout(const Duration(seconds: 5));
      } on Object catch (error) {
        debugPrint('Push unregister failed (token will be pruned): $error');
      }
    }
    await _deleteLocalToken();
  }

  Future<void> _deleteLocalToken() async {
    try {
      await _messaging.deleteToken();
    } on Object catch (error) {
      debugPrint('FCM token delete failed: $error');
    }
  }

  Future<void> _register(String token) async {
    if (supabase.auth.currentUser == null) return;
    final platform = defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
    await _invoke('register-push-token', {'token': token, 'platform': platform});
    _tokenRegistered = true;
  }

  Future<void> _invoke(String functionName, Map<String, dynamic> body) async {
    final custom = _invokeFunction;
    if (custom != null) return custom(functionName, body);
    await supabase.functions.invoke(functionName, body: body);
  }

  Future<void> _registerCurrentToken() async {
    final token = await _messaging.getToken();
    if (token != null) await _register(token);
  }

  Future<void> dispose() async {
    if (identical(active, this)) active = null;
    WidgetsBinding.instance.removeObserver(this);
    await _tokenRefresh?.cancel();
    await _foreground?.cancel();
    await _opened?.cancel();
    await _authState?.cancel();
  }
}
