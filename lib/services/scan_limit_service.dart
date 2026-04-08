import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages scan usage limits.
///
/// Guest users: 10 lifetime scans (stored locally via SharedPreferences).
/// Signed-in users: 20 scans/day (tracked via Supabase user_usage, UTC reset).
class ScanLimitService {
  static const _guestScanCountKey = 'guest_scan_count';
  static const _guestLifetimeLimit = 10;
  static const _signedInDailyLimit = 20;

  final SharedPreferences _prefs;
  final bool _isSignedIn;

  ScanLimitService({
    required SharedPreferences prefs,
    required bool isSignedIn,
  })  : _prefs = prefs,
        _isSignedIn = isSignedIn;

  /// How many scans the guest has used (lifetime).
  int get guestScansUsed => _prefs.getInt(_guestScanCountKey) ?? 0;

  /// How many scans remain for the current user.
  int get scansRemaining {
    if (_isSignedIn) {
      // TODO: Read from Supabase user_usage table with UTC daily reset.
      // For now, return full daily limit (server-side enforcement pending).
      return _signedInDailyLimit;
    }
    return (_guestLifetimeLimit - guestScansUsed).clamp(0, _guestLifetimeLimit);
  }

  /// The total limit for the current user type.
  int get scanLimit =>
      _isSignedIn ? _signedInDailyLimit : _guestLifetimeLimit;

  /// Whether the user can perform another scan.
  bool get canScan => scansRemaining > 0;

  /// Record a scan. Returns true if allowed, false if limit hit.
  Future<bool> recordScan() async {
    if (!canScan) return false;

    if (_isSignedIn) {
      // TODO: Call Supabase increment_usage RPC.
      return true;
    }

    final current = guestScansUsed;
    await _prefs.setInt(_guestScanCountKey, current + 1);
    return true;
  }

  /// Label for display: "3 of 10 scans used" etc.
  String get usageLabel {
    if (_isSignedIn) {
      return 'Scans today: unlimited sync pending';
    }
    return '$guestScansUsed of $_guestLifetimeLimit lifetime scans used';
  }
}

/// Provider for ScanLimitService. Requires SharedPreferences and auth state.
final scanLimitServiceProvider = Provider<ScanLimitService>((ref) {
  throw UnimplementedError(
    'scanLimitServiceProvider must be overridden with SharedPreferences instance',
  );
});
