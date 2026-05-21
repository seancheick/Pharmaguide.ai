import 'package:shared_preferences/shared_preferences.dart';

/// Thin wrapper around [SharedPreferences] for the onboarding "has seen"
/// flags. Centralized so the key strings aren't duplicated across callers.
abstract final class OnboardingPrefs {
  static const _kOnboardingKey = 'hasSeenOnboarding';
  static const _kProfileWizardKey = 'hasSeenProfileWizard';

  /// Returns `true` if the user has already seen the 4-step brand
  /// onboarding (`OnboardingV2Screen`). Defaults to `false` on a fresh
  /// install.
  static Future<bool> hasSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kOnboardingKey) ?? false;
  }

  /// Marks brand onboarding as seen so it never shows again. Call from
  /// the "Get started" and "Skip" buttons on the onboarding screen.
  static Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOnboardingKey, true);
  }

  /// Returns `true` if the user has already seen the 3-step
  /// first-time profile wizard (`ProfileWizardV2Screen`). Phase
  /// 11.7L.B.9 — the wizard is the guided counterpart to the
  /// `ProfileSetupV2Screen` dashboard. After the first run, users
  /// edit their profile via the dashboard directly.
  static Future<bool> hasSeenProfileWizard() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kProfileWizardKey) ?? false;
  }

  /// Marks the profile wizard as seen. Call this whether the user
  /// completes Save or taps "Skip" — the wizard's job is to give
  /// every user one chance to fill in their profile, not to gate the
  /// app on doing so.
  static Future<void> markProfileWizardSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kProfileWizardKey, true);
  }

  /// Testing / debug only — clears every onboarding-related flag so
  /// the brand onboarding AND the profile wizard fire again on next
  /// launch. Wire to a "Reset tutorials" option in settings.
  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kOnboardingKey);
    await prefs.remove(_kProfileWizardKey);
  }
}
