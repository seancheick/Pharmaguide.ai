import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pharmaguide/data/supabase/supabase_client.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/components/pg_pill_button.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_theme.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_haptics.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/core/widgets/pg_frosted_nav_bar.dart';
import 'package:pharmaguide/dev/v2_gallery.dart';
// Phase 11.11 hygiene (2026-05-17): legacy v1 widget imports removed
// after the route-coherence promotion proved stable. Production
// routes (`/product/:dsldId`, `/search`, `/quick-check`,
// `/medication-entry`, `/profile/setup`) render their v2 widgets
// unconditionally. The on-disk v1 files (ProductDetailScreen,
// SearchScreen, QuickCheckScreen, MedicationEntryScreen,
// ProfileSetupScreen, AnimatedSplashScreen, OnboardingScreen) are
// removed in the same hygiene pass — rollback is a git revert away.
import 'package:pharmaguide/features/profile/v2/profile_setup_v2_screen.dart';
import 'package:pharmaguide/features/profile/v2/profile_wizard_v2_screen.dart';
import 'package:pharmaguide/features/scanner/camera_permission_gate.dart';
import 'package:pharmaguide/features/scanner/manual_barcode_sheet.dart';
import 'package:pharmaguide/features/scanner/scanner_screen.dart';
import 'package:pharmaguide/features/search/v2/search_v2_screen.dart';
import 'package:pharmaguide/features/compare/compare_screen.dart';
import 'package:pharmaguide/features/product_detail/v2/product_detail_v2_connected.dart';
import 'package:pharmaguide/features/quick_check/v2/quick_check_v2_screen.dart';
import 'package:pharmaguide/features/settings/v2/settings_v2_screen.dart';
import 'package:pharmaguide/features/settings/v2/settings_v2_connected.dart';
import 'package:pharmaguide/features/splash/v2/animated_splash_v2_screen.dart';
import 'package:pharmaguide/features/onboarding/v2/onboarding_v2_screen.dart';
import 'package:pharmaguide/features/auth/v2/auth_invitation_v2_screen.dart';
import 'package:pharmaguide/features/auth/v2/magic_link_sheet.dart';
import 'package:pharmaguide/services/auth_state_service.dart';
import 'package:pharmaguide/services/auth/pg_auth_service.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';
import 'package:pharmaguide/services/onboarding_prefs.dart';
import 'package:pharmaguide/services/scan_limit_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pharmaguide/features/home/v2/home_v2_screen.dart';
// `ScannerV2Screen` / `ScannerV2Preview` are referenced only by the
// dev gallery route below. Production keeps `ScannerScreen` because it
// owns the real MobileScanner controller and catalog lookup flow; its
// permission, fallback, lookup, and not-found surfaces use v2 styling.
import 'package:pharmaguide/features/scanner/v2/scanner_v2_screen.dart';
import 'package:pharmaguide/core/navigation/root_navigator_key.dart';
import 'package:pharmaguide/features/scanner/v2/camera_permission_v2_screen.dart';
import 'package:pharmaguide/features/stack/v2/stack_v2_screen.dart';
import 'package:pharmaguide/features/medications/v2/medication_entry_v2_screen.dart';

/// Optional override for [GoRouter.initialLocation]. Set via:
///
///     flutter run --dart-define=DEV_ROUTE=/dev/v2
///     make run-v2     # alias for the gallery
///
/// When non-empty the router skips the splash → onboarding/home flow and
/// launches straight at the named route. Designed for v2 gallery
/// previews; ignored on release builds (the default empty value means
/// the normal launch path applies).
const String _devRoute = String.fromEnvironment('DEV_ROUTE', defaultValue: '');

String? normalizePharmaGuideDeepLink(Uri uri) {
  if (uri.scheme != 'pharmaguide') return null;

  final host = uri.host.trim();
  final path = uri.path.trim();
  final normalizedPath = host.isEmpty
      ? (path.isEmpty ? Routes.home : path)
      : '/$host$path';

  final query = uri.query.isEmpty ? '' : '?${uri.query}';
  return '$normalizedPath$query';
}

/// Redirect target for the `/compare/:idA/:idB` route. Comparing a
/// product against itself (only reachable by a typed deep link — the
/// picker excludes the current product) is meaningless: land on the
/// product detail page instead. Returns null (no redirect) otherwise.
String? compareSelfRedirect(String idA, String idB) {
  if (idA.isNotEmpty && idA == idB) return Routes.productDetail(idA);
  return null;
}

/// Optional override for [GoRouter.initialLocation] used by the
/// screenshot capture script. When empty (the default in every
/// production build) the router falls back to its normal splash →
/// onboarding/home path. Setting this via:
///
///   flutter run --dart-define=SCREENSHOT_ROUTE=/product/abc123
///
/// jumps straight to the named route on launch so the capture script
/// doesn't have to script bottom-nav taps.
const String _screenshotRoute = String.fromEnvironment(
  'SCREENSHOT_ROUTE',
  defaultValue: '',
);

/// App-wide [ScaffoldMessenger] key. `main.dart` uses this to show the
/// "catalog updated" snackbar from outside the widget tree when the OTA
/// in-session swap completes (T0.6). Defining it here keeps the
/// `MaterialApp.router(scaffoldMessengerKey: …)` wiring colocated with
/// the messenger consumers.
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

class ScanScreen extends ConsumerWidget {
  const ScanScreen({super.key});

  Future<void> _openManualEntry(BuildContext context, WidgetRef ref) async {
    final barcode = await showManualBarcodeSheet(context);
    if (!context.mounted || barcode == null) return;

    try {
      final allowed = await _recordAllowedScan(ref);
      if (!context.mounted) return;
      if (!allowed) {
        _showGuestScanLimitSheet(context);
        return;
      }

      final product = await ref.read(coreDatabaseProvider).findByUpc(barcode);
      if (!context.mounted) return;

      if (product == null) {
        _showManualLookupNotFound(context, ref, barcode);
        return;
      }

      await ref
          .read(userDatabaseProvider)
          .recordScanEvent(
            dsldId: product.dsldId,
            upcSku: product.upcSku,
            productName: product.productName,
          );
      CrashReportingService().log('scan_complete_manual');
      // Home v2 picks the new scan up via its own
      // `_v2RecentScansProvider.autoDispose` on next tab focus or via
      // its pull-to-refresh control. No external invalidation needed
      // after the v1 home screen retirement.

      if (context.mounted) {
        // Verdict-result haptic — mirrors the in-camera flow at
        // `scanner_screen.dart:129`. Without this, the manual-entry-
        // via-permission-gate path silently swallows the safety-
        // critical tactile signal for CONTRAINDICATED / UNSAFE
        // verdicts. Severity tiers always fire even under reduce-
        // motion; success patterns suppress (passes context).
        unawaited(PGHaptics.forVerdict(product.verdict, context));
        await context.push(Routes.productDetail(product.dsldId));
      }
    } on Object {
      if (!context.mounted) return;
      _showManualLookupNotFound(context, ref, barcode);
    }
  }

  Future<bool> _recordAllowedScan(WidgetRef ref) async {
    final prefs = await SharedPreferences.getInstance();
    final authMode = ref.read(authStateProvider);
    final service = ScanLimitService(
      prefs: prefs,
      isSignedIn: authMode == AuthMode.signedIn,
    );
    return service.recordScan();
  }

  void _showGuestScanLimitSheet(BuildContext context) {
    PGModal.bottomSheet<void>(
      context: context,
      builder: (ctx) => GuestScanLimitSheet(
        onSignIn: () {
          Navigator.pop(ctx);
          context.push(Routes.authInvitation);
        },
      ),
    );
  }

  void _showManualLookupNotFound(
    BuildContext context,
    WidgetRef ref,
    String barcode,
  ) {
    PGModal.bottomSheet<void>(
      context: context,
      builder: (ctx) => ScannerNotFoundSheet(
        upc: barcode,
        onTryAgain: () {
          Navigator.pop(ctx);
          unawaited(_openManualEntry(context, ref));
        },
        onSearchByName: () {
          Navigator.pop(ctx);
          context.push(Routes.search);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => CameraPermissionGate(
    childBuilder: () => const ScannerScreen(),
    onManualEntry: () => unawaited(_openManualEntry(context, ref)),
  );
}

class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: V2Colors.bg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            V2Spacing.space24,
            V2Spacing.space24,
            V2Spacing.space24,
            kPGNavBarHeight + V2Spacing.space32,
          ),
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: V2Colors.surface,
                borderRadius: BorderRadius.circular(V2Spacing.radiusSheet),
                border: Border.all(color: V2Colors.outline),
                boxShadow: V2Shadows.sm,
              ),
              child: Padding(
                padding: const EdgeInsets.all(V2Spacing.space24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: V2Colors.accentTint,
                        borderRadius: BorderRadius.circular(
                          V2Spacing.radiusCard,
                        ),
                      ),
                      child: const Icon(
                        Icons.auto_awesome_rounded,
                        color: V2Colors.accent,
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: V2Spacing.space16),
                    Text(
                      'Ask PharmaGuide',
                      style: V2Typography.titleSm(color: V2Colors.fg),
                    ),
                    const SizedBox(height: V2Spacing.space8),
                    Text(
                      'Clinical-grade chat is still being prepared. For now, use the verified catalog flows below for product and interaction decisions.',
                      style: V2Typography.body(color: V2Colors.fgMuted),
                    ),
                    const SizedBox(height: V2Spacing.space24),
                    PGPillButton(
                      label: 'Search products',
                      icon: Icons.search_rounded,
                      expand: true,
                      onPressed: () => context.push(Routes.search),
                    ),
                    const SizedBox(height: V2Spacing.space12),
                    PGPillButton(
                      label: 'Quick Check',
                      icon: Icons.health_and_safety_outlined,
                      variant: PGPillVariant.secondary,
                      expand: true,
                      onPressed: () => context.push(Routes.quickCheck),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CatalogUnavailableScreen extends StatelessWidget {
  final String? message;
  final VoidCallback? onRetry;

  const CatalogUnavailableScreen({super.key, this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: V2Colors.bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(V2Spacing.space24),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: V2Colors.surface,
              borderRadius: BorderRadius.circular(V2Spacing.radiusSheet),
              border: Border.all(color: V2Colors.outline),
              boxShadow: V2Shadows.md,
            ),
            child: Padding(
              padding: const EdgeInsets.all(V2Spacing.space24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: V2Colors.cautionTint,
                      borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
                    ),
                    child: const Icon(
                      Icons.cloud_off_outlined,
                      color: V2Colors.caution,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: V2Spacing.space16),
                  Text(
                    'Catalog unavailable',
                    style: V2Typography.titleSm(color: V2Colors.fg),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: V2Spacing.space8),
                  Text(
                    message ??
                        'The verified supplement catalog is not available on this device yet.',
                    style: V2Typography.bodySm(color: V2Colors.fgMuted),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: V2Spacing.space24),
                  PGPillButton(
                    label: 'Open Profile',
                    icon: Icons.person_rounded,
                    expand: true,
                    onPressed: () => context.go(Routes.profile),
                  ),
                  if (onRetry != null) ...[
                    const SizedBox(height: V2Spacing.space12),
                    PGPillButton(
                      label: 'Retry Catalog Download',
                      icon: Icons.refresh_rounded,
                      variant: PGPillVariant.secondary,
                      expand: true,
                      onPressed: onRetry,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Returns a [Page] that maps to the platform's idiomatic page transition:
/// [CupertinoPage] on iOS (slide-from-right + edge-swipe-back gesture)
/// and [MaterialPage] elsewhere (Android slide-up / fade). Used by
/// sub-page routes so iOS users get the swipe-back-from-edge gesture
/// they expect from every other native iOS app.
Page<dynamic> _platformPage(GoRouterState state, Widget child) {
  return Platform.isIOS
      ? CupertinoPage<void>(key: state.pageKey, child: child)
      : MaterialPage<void>(key: state.pageKey, child: child);
}

/// Single-instance app router. Created on first `_buildRouter` call and
/// memoized so the global `_AuthEventListener` can call `.go(...)` after
/// the auth round-trip lands (magic link return / Apple / Google native
/// flows). MaterialApp.router rebuilding doesn't create a new router.
GoRouter? _appRouter;

GoRouter _buildRouter({
  required bool catalogAvailable,
  required bool hasSeenOnboarding,
  String? catalogUnavailableReason,
  VoidCallback? onRetryCatalogLoad,
}) {
  if (_appRouter != null) return _appRouter!;

  Widget catalogRoute(Widget child) {
    if (catalogAvailable) return child;
    return CatalogUnavailableScreen(
      message: catalogUnavailableReason,
      onRetry: onRetryCatalogLoad,
    );
  }

  // DEV_ROUTE dart-define short-circuits the normal launch path so
  // `make run-v2` (or `flutter run --dart-define=DEV_ROUTE=/dev/v2`) lands
  // straight in the v2 gallery for design review. Production builds
  // leave DEV_ROUTE empty and behave normally.
  //
  // SCREENSHOT_ROUTE is a lower-priority automation override used by the
  // marketing screenshot capture script to jump directly to a production
  // screen without bypassing explicit DEV_ROUTE previews.
  final String initialLocation = _devRoute.isNotEmpty
      ? _devRoute
      : _screenshotRoute.isNotEmpty
      ? _screenshotRoute
      : '${Routes.splashIntro}?next='
            '${Uri.encodeComponent(hasSeenOnboarding ? Routes.home : Routes.onboarding)}';

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    // Fresh installs start at onboarding; returning users go straight to
    // home. `OnboardingPrefs.markSeen()` is called in the onboarding
    // screen's Next/Skip handlers so this only fires once per device.
    initialLocation: initialLocation,
    observers: [SentryNavigatorObserver()],
    redirect: (_, state) => normalizePharmaGuideDeepLink(state.uri),
    routes: [
      ShellRoute(
        builder: (context, state, child) => _AppShell(child: child),
        routes: [
          GoRoute(
            path: Routes.home,
            // Phase 11.1 — production Home tab renders the v2 home
            // screen inside the production shell. showNavBar:false
            // because the shell already paints the frosted nav bar
            // — without this we'd stack two of them.
            builder: (_, __) =>
                catalogRoute(const HomeV2Screen(showNavBar: false)),
          ),
          GoRoute(
            path: Routes.scan,
            builder: (_, __) => catalogRoute(const ScanScreen()),
          ),
          GoRoute(
            path: Routes.stack,
            // Phase 11.2 — production Stack tab renders the v2 screen
            // inside the production shell. showNavBar:false because
            // the shell already paints the frosted nav bar.
            builder: (_, __) =>
                catalogRoute(const StackV2Screen(showNavBar: false)),
          ),
          GoRoute(path: Routes.chat, builder: (_, __) => const ChatScreen()),
          GoRoute(
            path: Routes.profile,
            // Phase 11.0 — production Profile tab now renders the v2
            // settings screen wired to real providers (profileProvider,
            // activeStackProvider, recent-scans count, Supabase auth).
            builder: (_, __) => const SettingsV2Connected(),
          ),
        ],
      ),
      // Sub-pages live outside the shell — they have their own app bar with
      // back button and (for product detail) a sticky action bar. Nesting
      // them inside the shell causes double-Scaffold conflicts.
      //
      // Use pageBuilder + _platformPage for routes that should support
      // iOS swipe-back-from-edge (Apple HIG default for stack navigation).
      // Onboarding intentionally stays Material — it's a linear flow and
      // swipe-back would let users escape it before completing.
      // ---------------------------------------------------------------
      // Debug-only v2 design system gallery. Reachable via
      // `context.go('/dev/v2')`; not registered in the app shell so it
      // never appears in the nav bar. Will be removed (or moved behind
      // a debug-settings toggle) before v2 ships to production.
      // ---------------------------------------------------------------
      GoRoute(path: '/dev/v2', builder: (_, __) => const V2Gallery()),
      // v2 Settings (Profile tab) preview. `?signedIn=1` toggles the
      // hero into the signed-in variant.
      //
      // Phase 8.1.0 cleanup (2026-05-14): Product Detail / Home / Scanner /
      // Stack / floating-shell preview routes were retired. Those v2
      // screens were built on primitives that didn't mirror production
      // patterns. Mirror-based rebuilds land in Phase 8.1.1+ and
      // re-register their routes there.
      GoRoute(
        path: '/dev/v2/settings',
        pageBuilder: (_, state) {
          final signedIn = state.uri.queryParameters['signedIn'] == '1';
          return _platformPage(state, SettingsV2Screen(signedIn: signedIn));
        },
      ),
      // v2 splash preview — `autoNavigate: false` so it doesn't redirect
      // out of the gallery after the entrance animation completes.
      GoRoute(
        path: '/dev/v2/splash',
        pageBuilder: (_, state) => _platformPage(
          state,
          const AnimatedSplashV2Screen(autoNavigate: false),
        ),
      ),
      // v2 onboarding preview — `autoFinish: false` so completing the
      // flow loops back to step 1 rather than persisting prefs +
      // navigating home.
      GoRoute(
        path: '/dev/v2/onboarding',
        pageBuilder: (_, state) =>
            _platformPage(state, const OnboardingV2Screen(autoFinish: false)),
      ),
      // v2 ProfileSetup mirror — dev gallery preview against the live
      // `profileProvider`. Production `/profile/setup` renders the
      // same widget unconditionally (Phase 11.11 hygiene).
      GoRoute(
        path: '/dev/v2/profile-setup',
        pageBuilder: (_, state) =>
            _platformPage(state, const ProfileSetupV2Screen()),
      ),
      // v2 first-time profile wizard — Phase 11.7L.B.9. The
      // `autoFinish: false` preview keeps `OnboardingPrefs` clean so
      // reviewers can replay the wizard freely from the gallery.
      GoRoute(
        path: '/dev/v2/profile-wizard',
        pageBuilder: (_, state) => _platformPage(
          state,
          const ProfileWizardV2Screen(autoFinish: false),
        ),
      ),
      // Product Detail V2 *Connected*. Driven by a real `dsldId` and
      // the production provider stack (coreDatabaseProvider, detailBlob,
      // personalizedInteractionWarnings, profileProvider, fitScore).
      GoRoute(
        path: '/dev/v2/product/:dsldId',
        pageBuilder: (_, state) {
          final dsldId = state.pathParameters['dsldId']!;
          final section = state.uri.queryParameters['section'];
          return _platformPage(
            state,
            ProductDetailV2ConnectedScreen(
              dsldId: dsldId,
              initialSection: section,
            ),
          );
        },
      ),
      // v2 Auth Invitation dev preview — uses the same PGAuthService
      // methods as production, with a gallery-only back affordance.
      GoRoute(
        path: '/dev/v2/auth',
        pageBuilder: (_, state) =>
            _platformPage(state, const AuthInvitationV2Preview()),
      ),
      // v2 Home dev preview — fixture data + retinted frosted nav
      // bar. The production `/` route uses the connected v2 widget.
      GoRoute(
        path: '/dev/v2/home',
        pageBuilder: (_, state) => _platformPage(state, const HomeV2Preview()),
      ),
      // v2 Scanner dev preview — PGVerdictReveal demo chips for each
      // severity tier. Camera surrogate stands in for MobileScanner.
      GoRoute(
        path: '/dev/v2/scan',
        pageBuilder: (_, state) =>
            _platformPage(state, const ScannerV2Preview()),
      ),
      // v2 camera permission gate — first-ask + denied states.
      // `?denied=1` flips into the denied variant.
      GoRoute(
        path: '/dev/v2/scan/permission',
        pageBuilder: (_, state) {
          final denied = state.uri.queryParameters['denied'] == '1';
          return _platformPage(
            state,
            CameraPermissionV2Preview(denied: denied),
          );
        },
      ),
      // v2 Stack dev preview — two pinned tabs (Stack / Wishlist),
      // summary card with status tier (no numeric score), supplement
      // + medication list with swipe-to-remove.
      GoRoute(
        path: '/dev/v2/stack',
        pageBuilder: (_, state) => _platformPage(state, const StackV2Preview()),
      ),
      // Splash + Onboarding production routes use the v2 widgets.
      GoRoute(
        path: Routes.splashIntro,
        builder: (_, state) {
          final next = state.uri.queryParameters['next'] ?? Routes.home;
          return AnimatedSplashV2Screen(nextRoute: next);
        },
      ),
      GoRoute(
        path: Routes.onboarding,
        builder: (_, __) => const OnboardingV2Screen(),
      ),
      // Phase 11.7i — production AuthInvitation route. Sits between
      // onboarding completion and home. Wires the four CTAs to the
      // real PGAuthService methods. Skip lands at home as guest.
      GoRoute(
        path: Routes.authInvitation,
        pageBuilder: (context, state) => _platformPage(
          state,
          AuthInvitationV2Screen(
            onApple: () => _handleSignInApple(context),
            onGoogle: () => _handleSignInGoogle(context),
            onEmail: () => showMagicLinkSheet(context),
            // Auth skip means "try as guest." Profile completion stays
            // available through Home/Profile nudges; it should not be
            // another forced step after the user explicitly skipped auth.
            onSkip: () => context.go(Routes.home),
          ),
        ),
      ),
      GoRoute(
        path: '/auth/callback',
        pageBuilder: (_, state) =>
            _platformPage(state, const _AuthCallbackScreen()),
      ),
      GoRoute(
        path: Routes.profileSetup,
        pageBuilder: (_, state) =>
            _platformPage(state, const ProfileSetupV2Screen()),
      ),
      // Phase 11.7L.B.9 — first-time profile wizard. Only reached on
      // the post-auth handoff for accounts that haven't seen it; the
      // handoff logic that decides between this and home lives in
      // `_handleSignInSuccess` / the auth flow. Returning users
      // never land here.
      GoRoute(
        path: Routes.profileWizard,
        pageBuilder: (_, state) =>
            _platformPage(state, const ProfileWizardV2Screen()),
      ),
      GoRoute(
        path: Routes.search,
        pageBuilder: (_, state) {
          final initialCategory = state.uri.queryParameters['category'];
          final initialQuery = state.uri.queryParameters['query'];
          return _platformPage(
            state,
            catalogRoute(
              SearchV2Screen(
                initialCategory: initialCategory,
                initialQuery: initialQuery,
              ),
            ),
          );
        },
      ),
      // Dev-only direct preview — bypasses both env toggle and
      // `catalogRoute` so reviewers can see the empty-state and
      // recent-search flows without a populated catalog DB.
      GoRoute(
        path: '/dev/v2/search',
        pageBuilder: (_, state) => _platformPage(state, const SearchV2Screen()),
      ),
      GoRoute(
        path: Routes.medicationEntry,
        pageBuilder: (_, state) =>
            _platformPage(state, const MedicationEntryV2Screen()),
      ),
      // Direct dev preview — bypasses the env toggle so reviewers
      // can poke at the v2 screen without restarting with a flag.
      GoRoute(
        path: '/dev/v2/medication-entry',
        pageBuilder: (_, state) =>
            _platformPage(state, const MedicationEntryV2Screen()),
      ),
      GoRoute(
        path: Routes.quickCheck,
        pageBuilder: (_, state) =>
            _platformPage(state, catalogRoute(const QuickCheckV2Screen())),
      ),
      // Dev-only direct preview — bypasses both env toggle and the
      // `catalogRoute` gate so reviewers can poke at the screen
      // without a populated catalog DB.
      GoRoute(
        path: '/dev/v2/quick-check',
        pageBuilder: (_, state) =>
            _platformPage(state, const QuickCheckV2Screen()),
      ),
      GoRoute(
        path: '${Routes.product}/:dsldId',
        pageBuilder: (context, state) {
          final dsldId = state.pathParameters['dsldId'] ?? '';
          // Optional `?section=interactions|ingredients|alternatives` deep
          // link — scrolls to that anchor on first paint. Validation lives
          // in the screen (unknown values fall through cleanly).
          final section = state.uri.queryParameters['section'];
          return _platformPage(
            state,
            catalogRoute(
              ProductDetailV2ConnectedScreen(
                dsldId: dsldId,
                initialSection: section,
              ),
            ),
          );
        },
      ),
      // Side-by-side product comparison. Both ids come from the catalog
      // (entered via the product-detail Compare action's picker sheet).
      GoRoute(
        path: '${Routes.compare}/:idA/:idB',
        // Comparing a product against itself (reachable only by typed
        // deep link — the picker excludes the current product) is
        // meaningless; land on the product page instead.
        redirect: (context, state) => compareSelfRedirect(
          state.pathParameters['idA'] ?? '',
          state.pathParameters['idB'] ?? '',
        ),
        pageBuilder: (context, state) {
          final idA = state.pathParameters['idA'] ?? '';
          final idB = state.pathParameters['idB'] ?? '';
          return _platformPage(
            state,
            catalogRoute(CompareScreen(dsldIdA: idA, dsldIdB: idB)),
          );
        },
      ),
    ],
  );
  _appRouter = router;
  return router;
}

// ─── Phase 11.7i — production sign-in handlers ────────────────────────────────
// Wire the v2 AuthInvitation CTAs to the real Supabase plumbing in
// PGAuthService. Successful sign-in fires a `signedIn` event handled
// by `_AuthEventListener` below, which navigates the user to home
// when they were on an auth path (splash / onboarding / /auth).
//
// Cancellation is silent. Errors surface a calm snackbar without
// blocking the screen.

Future<void> _handleSignInApple(BuildContext context) async {
  // BuildContext kept on the signature to satisfy the route-handler
  // call site but intentionally unused inside — snackbar uses the
  // root scaffoldMessengerKey, so there's no context-across-async-gap
  // concern.
  final result = await PGAuthService().signInWithApple();
  _surfaceAuthError(result);
}

Future<void> _handleSignInGoogle(BuildContext context) async {
  final result = await PGAuthService().signInWithGoogle();
  _surfaceAuthError(result);
}

/// Phase 11.7L.B.9 — pick the right landing screen after sign-in.
/// First-time signed-in users land on the profile wizard; everyone
/// else goes straight home. Guest auth-skip bypasses this gate.
///
/// Public so the route handlers and the auth-state listener can
/// share the same gate. Both paths mark the wizard seen via the
/// wizard's own Save/Skip handlers, so users see the wizard at
/// most once per install.
Future<String> _postAuthDestination({bool isPreview = false}) async {
  final seenWizard = await OnboardingPrefs.hasSeenProfileWizard();
  if (!seenWizard) return Routes.profileWizard;
  return isPreview ? '/dev/v2/home' : Routes.home;
}

void _surfaceAuthError(PGAuthResult result) {
  if (result is PGAuthError) {
    // Use the root scaffold messenger (set in main.dart) so the
    // snackbar isn't tied to a transient screen scope.
    scaffoldMessengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(result.message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
  }
  // Success / Handoff / Cancel — no snackbar. Auth listener handles
  // navigation on success/handoff; cancel is intentional user backout.
}

class _AppShell extends StatelessWidget {
  final Widget child;
  const _AppShell({required this.child});

  int _selectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    if (location.startsWith(Routes.scan)) return 1;
    if (location.startsWith(Routes.stack)) return 2;
    if (location.startsWith(Routes.chat)) return 3;
    if (location.startsWith(Routes.profile)) return 4;
    return 0;
  }

  void _onDestinationSelected(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go(Routes.home);
      case 1:
        context.go(Routes.scan);
      case 2:
        context.go(Routes.stack);
      case 3:
        context.go(Routes.chat);
      case 4:
        context.go(Routes.profile);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // `extendBody: true` lets scrollable content flow *under* the frosted
      // nav bar so the BackdropFilter has pixels to blur — this is what
      // makes the Apple-style glass effect actually visible. Each modal
      // bottom sheet is responsible for adding bottom padding equal to
      // [kPGNavBarHeight] so its content doesn't sit behind the nav bar.
      extendBody: true,
      body: child,
      bottomNavigationBar: PGFrostedNavBar(
        selectedIndex: _selectedIndex(context),
        onDestinationSelected: (i) => _onDestinationSelected(context, i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.qr_code_scanner_outlined),
            selectedIcon: Icon(Icons.qr_code_scanner_rounded),
            label: 'Scan',
          ),
          NavigationDestination(
            icon: Icon(Icons.layers_outlined),
            selectedIcon: Icon(Icons.layers_rounded),
            label: 'Stack',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome_rounded),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class _AuthCallbackScreen extends StatefulWidget {
  const _AuthCallbackScreen();

  @override
  State<_AuthCallbackScreen> createState() => _AuthCallbackScreenState();
}

class _AuthCallbackScreenState extends State<_AuthCallbackScreen> {
  Timer? _stuckTimer;

  @override
  void initState() {
    super.initState();
    // Race guard: if the OTP exchange already completed before this
    // screen mounted, the signedIn event is gone — route now.
    try {
      if (supabase.auth.currentSession != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.go(Routes.home);
        });
        return;
      }
    } on Object catch (_) {
      // Supabase not initialized (placeholder mode) — fall through.
    }
    // Stuck guard: an expired/invalid link never emits signedIn. Don't
    // spin forever — hand the user back to the auth screen.
    _stuckTimer = Timer(const Duration(seconds: 20), () {
      if (!mounted) return;
      scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text(
            "That sign-in link didn't complete — it may have expired. "
            'Try sending a new one.',
          ),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 4),
        ),
      );
      context.go(Routes.authInvitation);
    });
  }

  @override
  void dispose() {
    _stuckTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: V2Colors.bg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(V2Spacing.space24),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: V2Colors.surface,
                borderRadius: BorderRadius.circular(V2Spacing.radiusSheet),
                border: Border.all(color: V2Colors.outline),
                boxShadow: V2Shadows.sm,
              ),
              child: Padding(
                padding: const EdgeInsets.all(V2Spacing.space24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: V2Colors.accent,
                      ),
                    ),
                    const SizedBox(height: V2Spacing.space16),
                    Text(
                      'Finishing sign in',
                      style: V2Typography.titleSm(color: V2Colors.fg),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: V2Spacing.space8),
                    Text(
                      'We are completing the secure handoff.',
                      style: V2Typography.bodySm(color: V2Colors.fgMuted),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PharmaGuideApp extends StatelessWidget {
  final bool catalogAvailable;
  final String? catalogUnavailableReason;
  final VoidCallback? onRetryCatalogLoad;
  final bool hasSeenOnboarding;

  const PharmaGuideApp({
    super.key,
    this.catalogAvailable = true,
    this.catalogUnavailableReason,
    this.onRetryCatalogLoad,
    this.hasSeenOnboarding = true,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'PharmaGuide',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: V2Theme.light,
      darkTheme: V2Theme.dark,
      themeMode: ThemeMode.system,
      routerConfig: _buildRouter(
        catalogAvailable: catalogAvailable,
        hasSeenOnboarding: hasSeenOnboarding,
        catalogUnavailableReason: catalogUnavailableReason,
        onRetryCatalogLoad: onRetryCatalogLoad,
      ),
      // Global Dynamic Type clamp.
      //
      // Accessibility text-scale settings on iOS go up to AX5 (≈3.1x) and
      // on Android up to ≈2.0x. Letting the app scale unconstrained
      // breaks card layouts (overflowing icons, ellipsized titles,
      // truncated counts). Cap to a 0.9–1.4x band globally — large
      // enough to meaningfully help low-vision users, small enough to
      // keep editorial layouts readable. Long body content surfaces that
      // already handle large text (e.g. product detail) can opt back into
      // full Dynamic Type with a local MediaQuery override.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final clamped = mq.textScaler.clamp(
          minScaleFactor: 0.9,
          maxScaleFactor: 1.4,
        );
        return MediaQuery(
          data: mq.copyWith(textScaler: clamped),
          // _AuthEventListener wraps the router so a successful magic
          // link return (Supabase emits signedIn after the deep-link
          // handler completes the OTP exchange) produces a visible
          // event. Phase 9.1 surfaces it as a snackbar; Phase 9.4
          // swaps that for an actual routerGo(home) + guest-stack
          // merge.
          child: _AuthEventListener(child: child!),
        );
      },
    );
  }
}

/// Listens to supabase.auth.onAuthStateChange and surfaces signed-in
/// / signed-out events via the global scaffold messenger. This is the
/// hook the deep-link round trip lands on after the user taps a
/// magic-link email — the supabase_flutter SDK auto-handles the
/// `pharmaguide://auth/callback` URL when the platform configs are
/// registered.
class _AuthEventListener extends StatefulWidget {
  final Widget child;
  const _AuthEventListener({required this.child});

  @override
  State<_AuthEventListener> createState() => _AuthEventListenerState();
}

class _AuthEventListenerState extends State<_AuthEventListener> {
  StreamSubscription<dynamic>? _sub;

  @override
  void initState() {
    super.initState();
    try {
      // onError is required: supabase_flutter forwards magic-link deep-link
      // failures (e.g. an expired/used link) as ERROR events on this stream.
      // Without a handler they escape to the zone and land in Sentry as an
      // unhandled async error (PHARMAGUIDE-1B). _onAuthError treats an
      // expired link as expected user behavior, not a crash.
      _sub = supabase.auth.onAuthStateChange.listen(
        _onAuth,
        onError: _onAuthError,
      );
    } on Object catch (_) {
      // Supabase wasn't initialized (placeholder mode) — silent.
    }
  }

  /// Stream-error sink for [onAuthStateChange]. The common case is a magic
  /// link that's expired or already been used: GoTrue raises
  /// `AuthException(statusCode: otp_expired, code: access_denied)` from
  /// `getSessionFromUrl`. That's a routine, user-recoverable condition —
  /// surface a calm "request a new link" snackbar, route off the
  /// /auth/callback spinner so it doesn't hang, and do NOT report it to
  /// Sentry. Anything else is genuinely unexpected, so record it.
  void _onAuthError(Object error, StackTrace stackTrace) {
    final isExpiredLink =
        error is AuthException && _isExpiredOrUsedLink(error);
    if (!isExpiredLink) {
      CrashReportingService().recordError(
        error,
        stackTrace,
        hint: 'auth_state_stream',
      );
    }
    if (!mounted) return;
    final messenger = scaffoldMessengerKey.currentState;
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            isExpiredLink
                ? 'That sign-in link has expired. Request a new one.'
                : 'Sign-in could not be completed. Try again in a moment.',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    // A failed magic-link return lands on the /auth/callback spinner with no
    // session, so it would spin forever. Send the user back to the auth
    // entry point where they can request a fresh link.
    final router = _appRouter;
    if (router != null) {
      final loc = router.routerDelegate.currentConfiguration.uri.path;
      if (loc == '/auth/callback') router.go(Routes.authInvitation);
    }
  }

  /// True for the expired/already-consumed magic-link shape. GoTrue reports
  /// it via `otp_expired` / `access_denied`; match the message too as a
  /// backstop in case the status/code fields ever shift.
  static bool _isExpiredOrUsedLink(AuthException e) {
    final status = (e.statusCode ?? '').toLowerCase();
    final code = (e.code ?? '').toLowerCase();
    final msg = e.message.toLowerCase();
    return status == 'otp_expired' ||
        code == 'access_denied' ||
        msg.contains('invalid or has expired');
  }

  void _onAuth(dynamic data) {
    if (data is! AuthState) return;
    if (!mounted) return;
    final messenger = scaffoldMessengerKey.currentState;
    if (messenger == null) return;
    switch (data.event) {
      case AuthChangeEvent.signedIn:
      case AuthChangeEvent.tokenRefreshed
          when data.session?.user.lastSignInAt != null:
        final email = data.session?.user.email ?? 'your account';
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text('Signed in as $email'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
        // Route to home so the post-auth landing feels complete.
        // Preview routes (the v2 gallery) land at /dev/v2/home; the
        // production app lands at Routes.home. Only route when the
        // listener fires from an auth path — bail if we're already on
        // a home-adjacent route to avoid a flicker from token-refresh
        // events that happen on a live home.
        final router = _appRouter;
        if (router != null) {
          final loc = router.routerDelegate.currentConfiguration.uri.path;
          final onAuthPath =
              loc.startsWith('/dev/v2/auth') ||
              loc == Routes.splashIntro ||
              loc == Routes.onboarding ||
              loc == Routes.authInvitation ||
              // Magic-link deep links land on the /auth/callback spinner;
              // without this the signedIn event had no navigator and the
              // handoff spun forever.
              loc == '/auth/callback';
          if (onAuthPath) {
            // Honor the dev-route override: if the gallery is the
            // active root (DEV_ROUTE=/dev/v2) land at the v2 home
            // preview; otherwise the production root. Phase 11.7L.B.9
            // — first-time users land on the wizard instead.
            final isPreview = _devRoute.isNotEmpty;
            unawaited(
              _postAuthDestination(isPreview: isPreview).then((dest) {
                router.go(dest);
              }),
            );
          }
        }
      case AuthChangeEvent.signedOut:
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Signed out'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      default:
        break;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
