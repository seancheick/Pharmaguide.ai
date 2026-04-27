import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/data/supabase/supabase_client.dart';

/// Represents the current authentication state.
enum AuthMode { guest, signedIn }

/// Tracks whether the user is a guest or signed in.
///
/// Guest mode: app is fully usable with limited features (10 lifetime scans,
/// 3 AI queries/day, no cloud sync).
/// Signed-in mode: full access (20 scans/day, 5 AI/day, cloud sync).
class AuthStateService extends StateNotifier<AuthMode> {
  AuthStateService() : super(AuthMode.guest) {
    _checkCurrentSession();
  }

  void _checkCurrentSession() {
    if (SupabaseConfig.isPlaceholder) {
      state = AuthMode.guest;
      return;
    }
    try {
      final session = supabase.auth.currentSession;
      state = session != null ? AuthMode.signedIn : AuthMode.guest;
    } on Object {
      // Supabase.initialize() was not called successfully, or the client is
      // otherwise unavailable. Stay in guest mode so the app remains usable.
      state = AuthMode.guest;
    }
  }

  bool get isGuest => state == AuthMode.guest;
  bool get isSignedIn => state == AuthMode.signedIn;

  /// Called after successful sign-in.
  void onSignedIn() => state = AuthMode.signedIn;

  /// Called after sign-out.
  void onSignedOut() => state = AuthMode.guest;
}

final authStateProvider =
    StateNotifierProvider<AuthStateService, AuthMode>((ref) {
  return AuthStateService();
});
