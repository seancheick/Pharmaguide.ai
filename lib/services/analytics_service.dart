import 'package:flutter/foundation.dart';

/// Analytics stub — replace with Firebase Analytics or Mixpanel in production.
///
/// Initializes without error. All methods are no-ops in this stub.
class AnalyticsService {
  static final AnalyticsService _instance = AnalyticsService._();
  factory AnalyticsService() => _instance;
  AnalyticsService._();

  bool _initialized = false;
  bool get isInitialized => _initialized;

  /// Initialize analytics. Safe to call multiple times.
  Future<void> initialize() async {
    if (_initialized) return;
    // TODO: Replace with FirebaseAnalytics.instance or Mixpanel.init()
    _initialized = true;
    if (kDebugMode) debugPrint('AnalyticsService initialized (stub)');
  }

  /// Track a named event with optional properties.
  void trackEvent(String name, [Map<String, Object>? properties]) {
    if (kDebugMode) debugPrint('Analytics: $name ${properties ?? ""}');
  }

  /// Track a screen view.
  void trackScreen(String screenName) {
    trackEvent('screen_view', {'screen_name': screenName});
  }

  /// Set a user property.
  void setUserProperty(String name, String value) {
    if (kDebugMode) debugPrint('Analytics: property $name=$value');
  }

  /// Set user ID for attribution.
  void setUserId(String? userId) {
    if (kDebugMode) debugPrint('Analytics: userId=$userId');
  }
}
