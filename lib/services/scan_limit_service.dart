import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages scan usage limits.
///
/// Guest users: 3 scans/day (stored locally via SharedPreferences).
/// Signed-in users: unlimited scans for the current release.
class ScanLimitService {
  static const _guestScanCountKey = 'guest_daily_scan_count';
  static const _guestScanDateKey = 'guest_daily_scan_date';
  static const _guestDailyLimit = 3;

  final SharedPreferences _prefs;
  final bool _isSignedIn;

  ScanLimitService({required this._prefs, required this._isSignedIn});

  /// How many scans the guest has used today.
  int get guestScansUsed {
    if (_prefs.getString(_guestScanDateKey) != _todayKey()) return 0;
    return _prefs.getInt(_guestScanCountKey) ?? 0;
  }

  /// Whether the current user is exempt from the local scan cap.
  bool get hasUnlimitedScans => _isSignedIn;

  /// How many scans remain for the current user.
  ///
  /// Null means unlimited. This keeps signed-in display logic honest:
  /// there is no fake "20/day" cap until server-side enforcement ships.
  int? get scansRemaining {
    if (_isSignedIn) return null;
    return (_guestDailyLimit - guestScansUsed).clamp(0, _guestDailyLimit);
  }

  /// The total limit for the current user type.
  ///
  /// Null means unlimited.
  int? get scanLimit => _isSignedIn ? null : _guestDailyLimit;

  /// Whether the user can perform another scan.
  bool get canScan => _isSignedIn || (scansRemaining ?? 0) > 0;

  /// Record a scan. Returns true if allowed, false if limit hit.
  Future<bool> recordScan() async {
    if (!canScan) return false;

    if (_isSignedIn) {
      // Signed-in users are intentionally unlimited for this release.
      // Server-side quota/RPC work will add enforcement later.
      return true;
    }

    final current = guestScansUsed;
    await _prefs.setInt(_guestScanCountKey, current + 1);
    await _prefs.setString(_guestScanDateKey, _todayKey());
    return true;
  }

  /// Label for display: "3 of 10 scans used" etc.
  String get usageLabel {
    if (_isSignedIn) {
      return 'Unlimited scans';
    }
    return '$guestScansUsed of $_guestDailyLimit scans used today';
  }

  static String _todayKey() =>
      DateTime.now().toUtc().toIso8601String().split('T').first;
}

/// Provider for ScanLimitService. Requires SharedPreferences and auth state.
final scanLimitServiceProvider = Provider<ScanLimitService>((ref) {
  throw UnimplementedError(
    'scanLimitServiceProvider must be overridden with SharedPreferences instance',
  );
});
