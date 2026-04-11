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
    if (v is String) {
      try {
        final decoded = jsonDecode(v);
        if (decoded is Map<String, dynamic>) return decoded;
      } on FormatException {
        // Non-JSON string — fall through to empty map.
      }
    }
    return {};
  }
}
