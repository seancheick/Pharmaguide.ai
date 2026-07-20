import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef AnalyticsPropertyValueValidator =
    bool Function(String eventName, String propertyName, Object value);

enum AnalyticsContractViolationReason {
  unknownEvent,
  invalidPropertyKeys,
  invalidPropertyValue,
}

/// A strict analytics contract rejected an event before consent/buffering.
///
/// The exception deliberately omits the rejected name, key, and value so a
/// caller cannot accidentally copy private input into logs or crash reports.
class AnalyticsContractViolation implements Exception {
  final AnalyticsContractViolationReason reason;

  const AnalyticsContractViolation(this.reason);

  @override
  String toString() => 'AnalyticsContractViolation($reason)';
}

/// Analytics facade for PharmaGuide.
///
/// ## Status
///
/// This is an intentional stub. PharmaGuide is a privacy-first, medical-grade
/// app — health data NEVER leaves the device, and adding a third-party
/// analytics backend is a product-level decision that requires privacy review,
/// DPA review, and user consent UI. Until that's done, this service records
/// consented events only in a bounded local in-memory ring buffer. Nothing is
/// transmitted; debug builds additionally print sanitized diagnostics.
///
/// ## Integration
///
/// When a backend is chosen (Firebase Analytics, Mixpanel, PostHog, etc.):
///
///   1. Add the SDK dependency in `pubspec.yaml`.
///   2. In [initialize], construct the client and store it as a private
///      field. Flush [_eventBuffer] to the client.
///   3. In [trackEvent] / [setUserProperty] / [setUserId], forward calls to
///      the client when available. Do NOT remove the buffer — it's still
///      useful for debugging and offline replay.
///   4. Ensure the existing [_sanitize] hook strips any disallowed PII keys
///      before anything leaves the device.
///
/// The public API is stable — call sites (e.g. `trackEvent('product_view')`)
/// will not need to change when the backend is wired up.
class AnalyticsService {
  static final AnalyticsService _instance = AnalyticsService._();
  factory AnalyticsService() => _instance;
  AnalyticsService._();

  static const String _collectionEnabledKey =
      'settings.analyticsCollectionEnabled';

  /// Bounded ring buffer of recent events. Useful for debugging and for
  /// replay once a real backend is wired up. Capped to prevent unbounded
  /// memory growth in long sessions.
  static const int _bufferMax = 200;
  final List<AnalyticsEvent> _eventBuffer = <AnalyticsEvent>[];

  bool _initialized = false;
  bool _collectionEnabled = false;
  bool get isInitialized => _initialized;
  bool get collectionEnabled => _collectionEnabled;

  /// Read-only view of the event buffer (debug tooling, tests).
  List<AnalyticsEvent> get bufferedEvents => List.unmodifiable(_eventBuffer);

  /// Initialize analytics. Safe to call multiple times.
  Future<void> initialize() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    _collectionEnabled = prefs.getBool(_collectionEnabledKey) ?? false;
    _initialized = true;
    if (kDebugMode) debugPrint('AnalyticsService initialized (stub)');
  }

  /// Persist the user's local analytics preference.
  Future<void> setCollectionEnabled(bool enabled) async {
    _collectionEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_collectionEnabledKey, enabled);
  }

  /// Track a named event with optional properties.
  void trackEvent(String name, [Map<String, Object>? properties]) {
    if (!_collectionEnabled) return;
    final sanitized = properties == null ? null : _sanitize(properties);
    _record(AnalyticsEvent.event(name, sanitized));
    if (kDebugMode) debugPrint('Analytics: $name ${sanitized ?? ""}');
  }

  /// Validate an exact event contract, then use the normal consent-gated path.
  ///
  /// Validation intentionally runs before [trackEvent]. Invalid input is
  /// therefore rejected even when collection is disabled instead of being
  /// hidden by the consent no-op. Existing analytics call sites retain the
  /// original sanitize-and-drop behavior of [trackEvent].
  void trackAllowlistedEvent({
    required String name,
    required Map<String, Object> properties,
    required Map<String, Set<String>> eventPropertyKeys,
    required AnalyticsPropertyValueValidator isAllowedValue,
  }) {
    final allowedKeys = eventPropertyKeys[name];
    if (allowedKeys == null) {
      throw const AnalyticsContractViolation(
        AnalyticsContractViolationReason.unknownEvent,
      );
    }
    if (properties.length != allowedKeys.length ||
        properties.keys.any((key) => !allowedKeys.contains(key))) {
      throw const AnalyticsContractViolation(
        AnalyticsContractViolationReason.invalidPropertyKeys,
      );
    }
    for (final entry in properties.entries) {
      if (!isAllowedValue(name, entry.key, entry.value)) {
        throw const AnalyticsContractViolation(
          AnalyticsContractViolationReason.invalidPropertyValue,
        );
      }
    }
    trackEvent(name, properties);
  }

  /// Track a screen view.
  void trackScreen(String screenName) {
    trackEvent('screen_view', {'screen_name': screenName});
  }

  /// Set a user property.
  void setUserProperty(String name, String value) {
    if (!_collectionEnabled) return;
    _record(AnalyticsEvent.property(name, value));
    if (kDebugMode) debugPrint('Analytics: property $name=$value');
  }

  /// Set user ID for attribution. Pass null to clear.
  void setUserId(String? userId) {
    if (!_collectionEnabled) return;
    _record(AnalyticsEvent.userId(userId));
    if (kDebugMode) debugPrint('Analytics: userId=$userId');
  }

  void _record(AnalyticsEvent event) {
    _eventBuffer.add(event);
    if (_eventBuffer.length > _bufferMax) {
      _eventBuffer.removeRange(0, _eventBuffer.length - _bufferMax);
    }
  }

  /// PII scrub hook. Drops any key in [_piiKeys] so health data never
  /// leaks into analytics — even if a caller accidentally passes it.
  Map<String, Object> _sanitize(Map<String, Object> props) {
    final clean = <String, Object>{};
    for (final entry in props.entries) {
      if (_piiKeys.contains(entry.key.toLowerCase())) continue;
      clean[entry.key] = entry.value;
    }
    return clean;
  }

  /// Keys that must never be sent to analytics. Expand as needed.
  static const Set<String> _piiKeys = {
    'email',
    'phone',
    'conditions',
    'medications',
    'allergies',
    'date_of_birth',
    'dob',
    'first_name',
    'last_name',
    'full_name',
  };

  /// Test-only helper to clear the buffer between tests.
  @visibleForTesting
  void clearBufferForTest() => _eventBuffer.clear();

  /// Test-only helper to reset singleton state between preference tests.
  @visibleForTesting
  void resetForTest() {
    _eventBuffer.clear();
    _collectionEnabled = false;
    _initialized = false;
  }
}

/// A recorded analytics event. Immutable.
class AnalyticsEvent {
  final String kind; // 'event' | 'property' | 'userId'
  final String name;
  final Object? value;
  final DateTime at;

  AnalyticsEvent._(this.kind, this.name, this.value) : at = DateTime.now();

  factory AnalyticsEvent.event(String name, Map<String, Object>? props) =>
      AnalyticsEvent._('event', name, _immutableValue(props));
  factory AnalyticsEvent.property(String propName, String value) =>
      AnalyticsEvent._('property', propName, value);
  factory AnalyticsEvent.userId(String? userId) =>
      AnalyticsEvent._('userId', 'user_id', userId);

  static Object? _immutableValue(Object? value) {
    if (value is Map) {
      return Map<Object?, Object?>.unmodifiable(
        value.map<Object?, Object?>(
          (key, nestedValue) => MapEntry(key, _immutableValue(nestedValue)),
        ),
      );
    }
    if (value is List) {
      return List<Object?>.unmodifiable(value.map<Object?>(_immutableValue));
    }
    if (value is Set) {
      return Set<Object?>.unmodifiable(value.map<Object?>(_immutableValue));
    }
    return value;
  }

  @override
  String toString() => '[$kind] $name=$value @ $at';
}
