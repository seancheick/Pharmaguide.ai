import 'dart:convert';

extension SafeJson on Map<String, dynamic> {
  String safeString(String key, [String fallback = '']) =>
      this[key]?.toString() ?? fallback;

  double safeDouble(String key, [double fallback = 0.0]) {
    final v = this[key];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? fallback;
    return fallback;
  }

  int safeInt(String key, [int fallback = 0]) {
    final v = this[key];
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  bool safeBool(String key, [bool fallback = false]) {
    final v = this[key];
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) return v.toLowerCase() == 'true' || v == '1';
    return fallback;
  }

  List<String> safeStringList(String key) {
    final v = this[key];
    if (v is List) return v.map((e) => e.toString()).toList();
    if (v is String) {
      try {
        final decoded = jsonDecode(v);
        if (decoded is List) return decoded.map((e) => e.toString()).toList();
      } on FormatException {
        // Non-JSON string — fall through to empty list.
      }
    }
    return [];
  }

  Map<String, dynamic> safeMap(String key) {
    final v = this[key];
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    if (v is String) {
      try {
        final decoded = jsonDecode(v);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } on FormatException {
        // Non-JSON string — fall through to empty map.
      }
    }
    return {};
  }

  /// Returns an untyped list when the value is a List, otherwise an empty
  /// list. Use when you need raw access to the elements (e.g. for
  /// `whereType<X>()` or `.length`) and don't want a TypeError if the
  /// pipeline ships a non-list shape.
  List<dynamic> safeList(String key) {
    final v = this[key];
    return v is List ? v : const <dynamic>[];
  }

  /// Returns a list of map records when the value is a `List` whose
  /// elements are maps, otherwise an empty list. Equivalent to the
  /// common idiom `(raw['x'] as List?)?.whereType<Map<String,
  /// dynamic>>().toList() ?? []` but without the leading cast that
  /// would itself throw if `raw['x']` is a Map or a scalar.
  List<Map<String, dynamic>> safeMapList(String key) {
    final v = this[key];
    if (v is! List) return const <Map<String, dynamic>>[];
    return v.whereType<Map<String, dynamic>>().toList();
  }

  /// Returns a num when the value is a num or a parseable string,
  /// otherwise null. Use for fields that may legitimately be absent —
  /// callers can `?? 0` if they want a guaranteed default.
  num? safeNum(String key) {
    final v = this[key];
    if (v is num) return v;
    if (v is String) return num.tryParse(v);
    return null;
  }
}
