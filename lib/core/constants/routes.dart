/// Centralized route path constants.
/// All navigation uses these instead of magic strings.
abstract final class Routes {
  static const home = '/';
  static const scan = '/scan';
  static const stack = '/stack';
  static const chat = '/chat';
  static const profile = '/profile';
  static const profileSetup = '/profile/setup';
  static const onboarding = '/onboarding';
  static const search = '/search';

  /// Product detail — append the dsldId: `'${Routes.product}/$dsldId'`
  static const product = '/product';

  /// Build a product detail path with dsldId.
  static String productDetail(String dsldId) => '/product/$dsldId';

  /// Side-by-side product comparison — append both dsldIds:
  /// `'${Routes.compare}/$idA/$idB'`.
  static const compare = '/compare';

  /// Build a compare path for two products.
  static String comparePath(String dsldIdA, String dsldIdB) =>
      '/compare/$dsldIdA/$dsldIdB';

  /// Add a medication to the user's stack (RxNorm search + class fallback).
  static const medicationEntry = '/medication-entry';

  /// "Safe to Take Together?" quick pair interaction check.
  static const quickCheck = '/quick-check';

  /// Brand-reveal splash intro played between the native splash and
  /// the app's first content screen. The destination route after the
  /// animation is passed as the `next` query parameter (e.g.
  /// `/splash?next=/home`).
  static const splashIntro = '/splash';

  /// **Phase 11.7i — production sign-in step.** Sits between
  /// onboarding completion and the home screen. v2 AuthInvitation
  /// screen with calm Apple / Google / Magic-link / Skip options.
  /// Wired to `PGAuthService`; skip lands at `home` as guest.
  static const authInvitation = '/auth';

  /// **Phase 11.7L.B.9 — first-time profile wizard.** 3-step guided
  /// setup (Nickname → Basics → Health context). Shown once per
  /// install via `OnboardingPrefs.hasSeenProfileWizard()`. Returning
  /// users edit through the [profileSetup] dashboard instead.
  static const profileWizard = '/profile/wizard';
}
