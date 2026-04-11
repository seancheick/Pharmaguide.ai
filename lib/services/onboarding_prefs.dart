import 'package:shared_preferences/shared_preferences.dart';

/// Thin wrapper around [SharedPreferences] for the onboarding "has seen"
/// flag. Centralized so the key string isn't duplicated across callers.
abstract final class OnboardingPrefs {
  static const _key = 'hasSeenOnboarding';

  /// Returns `true` if the user has already seen the 3-slide onboarding.
  /// Defaults to `false` on a fresh install.
  static Future<bool> hasSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  /// Marks onboarding as seen so it never shows again. Call from the
  /// "Get started" and "Skip" buttons on the onboarding screen.
  static Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
  }

  /// Testing / debug only — clears the flag so the onboarding fires again
  /// on next launch. Wire this to a "Reset tutorials" option in settings.
  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
