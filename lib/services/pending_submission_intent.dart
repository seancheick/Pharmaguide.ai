import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persists a barcode the user tried to submit while signed out, so the
/// capture sheet can reopen after authentication completes.
///
/// The naive alternative — `await context.push(authRoute)` then reopening —
/// cannot work here: the global auth listener navigates with `router.go(...)`
/// on sign-in (destroying the awaited route), and a magic link may restart
/// the app entirely. A small persisted intent survives both.
///
/// Consumption is one-shot and TTL-bounded: a stale intent silently expires
/// instead of surprising the user with a capture sheet days later.
class PendingSubmissionIntent {
  static const storageKey = 'pg_pending_submission_intent';
  static const ttl = Duration(minutes: 15);

  /// Remember that [upc] was waiting on sign-in.
  static Future<void> save(String upc, {DateTime Function()? now}) async {
    final digits = upc.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      storageKey,
      jsonEncode({
        'upc': digits,
        'created_at': (now ?? DateTime.now)().toUtc().toIso8601String(),
      }),
    );
  }

  /// Return the pending barcode exactly once, or null when absent, expired,
  /// or malformed. Always clears the stored value.
  static Future<String?> consume({DateTime Function()? now}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null) return null;
    await prefs.remove(storageKey);
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final upc = decoded['upc'];
      final createdAtRaw = decoded['created_at'];
      if (upc is! String || upc.isEmpty || createdAtRaw is! String) {
        return null;
      }
      final createdAt = DateTime.tryParse(createdAtRaw)?.toUtc();
      if (createdAt == null) return null;
      final age = (now ?? DateTime.now)().toUtc().difference(createdAt);
      if (age.isNegative || age > ttl) return null;
      return upc;
    } on FormatException {
      return null;
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(storageKey);
  }
}
