import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pharmaguide/data/supabase/supabase_client.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/theme/v2/v2_theme.dart';
import 'package:pharmaguide/core/widgets/pg_frosted_nav_bar.dart';
import 'package:pharmaguide/dev/v2_gallery.dart';
// Phase 11.7i — legacy onboarding/splash imports removed after route
// swap. Files remain on disk (lib/features/onboarding/onboarding_screen.dart,
// lib/features/splash/animated_splash_screen.dart) so rollback is a
// `git revert` away. Removed to keep analyzer clean.
import 'package:pharmaguide/features/profile/profile_setup_screen.dart';
import 'package:pharmaguide/features/profile/v2/profile_setup_v2_screen.dart';
import 'package:pharmaguide/features/profile/v2/profile_wizard_v2_screen.dart';
import 'package:pharmaguide/features/scanner/camera_permission_gate.dart';
import 'package:pharmaguide/features/scanner/manual_barcode_sheet.dart';
import 'package:pharmaguide/features/scanner/scanner_screen.dart';
import 'package:pharmaguide/features/search/search_screen.dart';
import 'package:pharmaguide/features/product_detail/product_detail_screen.dart';
import 'package:pharmaguide/features/product_detail/v2/product_detail_v2_connected.dart';
import 'package:pharmaguide/features/product_detail/v2/product_detail_v2_screen.dart';
import 'package:pharmaguide/features/quick_check/quick_check_screen.dart';
import 'package:pharmaguide/features/settings/v2/settings_v2_screen.dart';
import 'package:pharmaguide/features/settings/v2/settings_v2_connected.dart';
// Legacy splash import dropped during Phase 11.7i route swap — see
// note above onboarding_screen import for the rollback story.
import 'package:pharmaguide/features/splash/v2/animated_splash_v2_screen.dart';
import 'package:pharmaguide/features/onboarding/v2/onboarding_v2_screen.dart';
import 'package:pharmaguide/features/auth/v2/auth_invitation_v2_screen.dart';
import 'package:pharmaguide/features/auth/v2/magic_link_sheet.dart';
import 'package:pharmaguide/services/auth/pg_auth_service.dart';
import 'package:pharmaguide/services/onboarding_prefs.dart';
import 'package:pharmaguide/features/home/v2/home_v2_screen.dart';
import 'package:pharmaguide/features/scanner/v2/scanner_v2_screen.dart';
import 'package:pharmaguide/features/scanner/v2/camera_permission_v2_screen.dart';
import 'package:pharmaguide/features/stack/v2/stack_v2_screen.dart';
import 'package:pharmaguide/features/medications/medication_entry_screen.dart';

/// Optional override for [GoRouter.initialLocation]. Set via:
///
///     flutter run --dart-define=DEV_ROUTE=/dev/v2
///     make run-v2     # alias for the gallery
///
/// When non-empty the router skips the splash → onboarding/home flow and
/// launches straight at the named route. Designed for v2 gallery
/// previews; ignored on release builds (the default empty value means
/// the normal launch path applies).
const String _devRoute = String.fromEnvironment(
  'DEV_ROUTE',
  defaultValue: '',
);

/// App-wide [ScaffoldMessenger] key. `main.dart` uses this to show the
/// "catalog updated" snackbar from outside the widget tree when the OTA
/// in-session swap completes (T0.6). Defining it here keeps the
/// `MaterialApp.router(scaffoldMessengerKey: …)` wiring colocated with
/// the messenger consumers.
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

// Placeholder screens — will be replaced by real implementations
class _PlaceholderScreen extends StatelessWidget {
  final String title;
  const _PlaceholderScreen({required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Text(title, style: Theme.of(context).textTheme.headlineMedium),
      ),
    );
  }
}

class ScanScreen extends StatelessWidget {
  const ScanScreen({super.key});
  @override
  Widget build(BuildContext context) => CameraPermissionGate(
    childBuilder: () => const ScannerScreen(),
    onManualEntry: () => showManualBarcodeSheet(context),
  );
}

class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const _PlaceholderScreen(title: 'AI Pharmacist');
}

class CatalogUnavailableScreen extends StatelessWidget {
  final String? message;
  final VoidCallback? onRetry;

  const CatalogUnavailableScreen({super.key, this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Catalog Unavailable')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 56),
              const SizedBox(height: 16),
              Text(
                message ??
                    'The verified supplement catalog is not available on this device yet.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go(Routes.profile),
                child: const Text('Open Profile'),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: onRetry,
                  child: const Text('Retry Catalog Download'),
                ),
              ],
            ],
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
  bool useV2Theme = false,
  bool useV2ProductDetail = false,
  bool useV2ProfileSetup = false,
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
  final String initialLocation = _devRoute.isNotEmpty
      ? _devRoute
      : '${Routes.splashIntro}?next='
          '${Uri.encodeComponent(hasSeenOnboarding ? Routes.home : Routes.onboarding)}';

  final router = GoRouter(
    // Fresh installs start at onboarding; returning users go straight to
    // home. `OnboardingPrefs.markSeen()` is called in the onboarding
    // screen's Next/Skip handlers so this only fires once per device.
    initialLocation: initialLocation,
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
            // Legacy SettingsScreen import kept for now; remove in
            // Phase 11.5 when all routes are swapped.
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
      GoRoute(
        path: '/dev/v2',
        builder: (_, __) => const V2Gallery(),
      ),
      // v2 Settings (Profile tab) preview. `?signedIn=1` toggles the
      // hero into the signed-in variant.
      //
      // Phase 8.1.0 cleanup (2026-05-14): Product Detail / Home / Scanner /
      // Stack / floating-shell preview routes were retired. Those v2
      // screens were built on misbuilt primitives (PGScoreRing,
      // PGSeverityBadge, chip-based ingredients, floating nav) that
      // didn't mirror production patterns. Mirror-based rebuilds land
      // in Phase 8.1.1+ and re-register their routes there.
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
        pageBuilder: (_, state) => _platformPage(
          state,
          const OnboardingV2Screen(autoFinish: false),
        ),
      ),
      // v2 ProfileSetup mirror — preview the 5-step editor against the
      // live `profileProvider` without committing to the env-flag swap.
      // This route renders ProfileSetupV2Screen unconditionally; the
      // production `/profile/setup` route honors `useV2ProfileSetup`.
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
      // v2 Product Detail flagship — composes every Phase 8.1.1–8.1.5
      // mirror against fixture data so reviewers can see the full
      // scroll story end-to-end. Production wiring (later phase)
      // swaps the fixtures for provider data while reusing the same
      // components.
      GoRoute(
        path: '/dev/v2/product-detail',
        pageBuilder: (_, state) =>
            _platformPage(state, const ProductDetailV2Screen()),
      ),
      // Phase 11.7b — Product Detail V2 *Connected*. Same components as
      // the fixture screen above, but driven by a real `dsldId` and the
      // production provider stack (coreDatabaseProvider, detailBlob,
      // personalizedInteractionWarnings, profileProvider, fitScore).
      // Section bodies fill in across 11.7c–11.7f; 11.7g flips the
      // production /product/:dsldId route over once stakeholder review
      // passes. Until then this lives behind a parallel route so
      // production stays on the legacy screen.
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
      // v2 Auth Invitation — sits between onboarding completion and
      // home. Phase 9.0 ships the visual mirror only; Supabase wiring
      // (magic link → Apple → Google) lands in Phase 9.1–9.3.
      // Preview wrapper toasts on each button so reviewers can verify
      // the tap targets without leaving the gallery.
      GoRoute(
        path: '/dev/v2/auth',
        pageBuilder: (_, state) =>
            _platformPage(state, const AuthInvitationV2Preview()),
      ),
      // v2 Home — Phase 10.0 visual mirror of home_screen.dart with
      // fixture data + retinted frosted nav bar. Production wiring
      // (real providers + pinned-search scroll chrome) lands in the
      // Phase 8.x wiring sweep.
      GoRoute(
        path: '/dev/v2/home',
        pageBuilder: (_, state) =>
            _platformPage(state, const HomeV2Preview()),
      ),
      // v2 Scanner — Phase 10.1 visual mirror with PGVerdictReveal
      // demo chips for each severity tier. Camera surrogate stands in
      // for MobileScanner in the gallery preview.
      GoRoute(
        path: '/dev/v2/scan',
        pageBuilder: (_, state) =>
            _platformPage(state, const ScannerV2Preview()),
      ),
      // v2 camera permission gate — first-ask + denied states.
      // ?denied=1 flips into the denied variant.
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
      // v2 Stack — Phase 10.2 visual mirror of stack_screen.dart.
      // Two pinned tabs (Stack / Wishlist), summary card with status
      // tier (no numeric score), supplement + medication list with
      // swipe-to-remove.
      GoRoute(
        path: '/dev/v2/stack',
        pageBuilder: (_, state) =>
            _platformPage(state, const StackV2Preview()),
      ),
      // Phase 11.7i — Splash + Onboarding production routes flipped to
      // v2 widgets. Legacy widgets (AnimatedSplashScreen, OnboardingScreen)
      // stay imported above so a single-line revert here restores the
      // pre-v2 path if needed. Same risk profile as the Home/Profile/Stack
      // swaps in Phases 11.0–11.5: these are first-impression surfaces
      // with no safety-critical clinical content.
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
            // Phase 11.7L.B.9 — skip routes through the wizard gate
            // so guest accounts get the same one-shot first-time
            // profile setup chance signed-in accounts get. Both
            // paths converge on the same wizard surface.
            onSkip: () async {
              final dest = await _postAuthDestination();
              if (!context.mounted) return;
              context.go(dest);
            },
          ),
        ),
      ),
      GoRoute(
        path: Routes.profileSetup,
        pageBuilder: (_, state) {
          // Phase 11.7L.B staged route swap — same env-toggle pattern
          // as Product Detail v2. Both screens share `profileProvider`
          // and the `saveToDb` semantics, so flipping the flag is a
          // pure visual change with no behavior risk.
          final Widget screen = useV2ProfileSetup
              ? const ProfileSetupV2Screen()
              : const ProfileSetupScreen();
          return _platformPage(state, screen);
        },
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
        pageBuilder: (_, state) => _platformPage(
          state,
          catalogRoute(
            SearchScreen(
              initialCategory: state.uri.queryParameters['category'],
              initialQuery: state.uri.queryParameters['query'],
            ),
          ),
        ),
      ),
      GoRoute(
        path: Routes.medicationEntry,
        pageBuilder: (_, state) =>
            _platformPage(state, const MedicationEntryScreen()),
      ),
      GoRoute(
        path: Routes.quickCheck,
        pageBuilder: (_, state) =>
            _platformPage(state, catalogRoute(const QuickCheckScreen())),
      ),
      GoRoute(
        path: '${Routes.product}/:dsldId',
        pageBuilder: (context, state) {
          final dsldId = state.pathParameters['dsldId'] ?? '';
          // Optional `?section=interactions|ingredients|alternatives` deep
          // link — scrolls to that anchor on first paint. Validation lives
          // in the screen (unknown values fall through cleanly).
          final section = state.uri.queryParameters['section'];
          // Phase 11.7g.3 staged route swap — when `useV2ProductDetail`
          // is true (driven by `--dart-define=USE_V2_PRODUCT_DETAIL=true`),
          // serve the v2 ConnectedScreen on the production route. Legacy
          // path stays intact so rollback is a single Makefile flag flip.
          // The `/dev/v2/product/:dsldId` dev route remains active for QA.
          final Widget productScreen = useV2ProductDetail
              ? ProductDetailV2ConnectedScreen(
                  dsldId: dsldId,
                  initialSection: section,
                )
              : ProductDetailScreen(
                  dsldId: dsldId,
                  initialSection: section,
                );
          return _platformPage(
            state,
            catalogRoute(productScreen),
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

/// Phase 11.7L.B.9 — pick the right landing screen after the user
/// completes (or skips) the auth invitation. First-time users land
/// on the profile wizard; everyone else goes straight home.
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
        // Phase 11.5 — production shell uses the v2 nav tone since
        // production Home / Stack / Profile now render v2 widgets.
        useV2Tones: true,
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

class PharmaGuideApp extends StatelessWidget {
  final bool catalogAvailable;
  final String? catalogUnavailableReason;
  final VoidCallback? onRetryCatalogLoad;
  final bool hasSeenOnboarding;

  /// Experimental v2 design system toggle. While `false` (default),
  /// production `AppTheme` ships. When `true`, the app boots against
  /// `V2Theme` and the `/dev/v2` gallery reflects live tokens.
  ///
  /// Wire to a debug flag during the `design/v2-mobile-polish` branch;
  /// flip the default to `true` only when Phase 8 sign-off is complete
  /// (see `.claude/plans/your-original-prompt-communicates-streamed-liskov.md`).
  final bool useV2Theme;

  /// **Phase 11.7g.3 staged route swap.** When `true`, the production
  /// `/product/:dsldId` route renders `ProductDetailV2ConnectedScreen`
  /// instead of the legacy `ProductDetailScreen`. Leave `false` until
  /// the TestFlight cycle completes — see
  /// `knowledge/product-detail-v2-route-swap-readiness.md`.
  ///
  /// Driven via `--dart-define=USE_V2_PRODUCT_DETAIL=true` at launch so
  /// it can be toggled per build (Makefile target / TestFlight scheme)
  /// without modifying source. Legacy route is preserved so rollback
  /// is a single Makefile flag flip.
  final bool useV2ProductDetail;

  /// Phase 11.7L.B ProfileSetup v2 mirror toggle. When true, the
  /// production `/profile/setup` route renders `ProfileSetupV2Screen`
  /// instead of the legacy `ProfileSetupScreen`. Logic, providers,
  /// and save semantics are identical between the two — pure visual
  /// swap. Driven via `--dart-define=USE_V2_PROFILE_SETUP=true` so
  /// the flag can be flipped per build / TestFlight scheme without
  /// modifying source.
  final bool useV2ProfileSetup;

  const PharmaGuideApp({
    super.key,
    this.catalogAvailable = true,
    this.catalogUnavailableReason,
    this.onRetryCatalogLoad,
    this.hasSeenOnboarding = true,
    this.useV2Theme = false,
    this.useV2ProductDetail = false,
    this.useV2ProfileSetup = false,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'PharmaGuide',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: useV2Theme ? V2Theme.light : AppTheme.light,
      darkTheme: useV2Theme ? V2Theme.dark : AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: _buildRouter(
        catalogAvailable: catalogAvailable,
        hasSeenOnboarding: hasSeenOnboarding,
        catalogUnavailableReason: catalogUnavailableReason,
        onRetryCatalogLoad: onRetryCatalogLoad,
        useV2Theme: useV2Theme,
        useV2ProductDetail: useV2ProductDetail,
        useV2ProfileSetup: useV2ProfileSetup,
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
      _sub = supabase.auth.onAuthStateChange.listen(_onAuth);
    } on Object catch (_) {
      // Supabase wasn't initialized (placeholder mode) — silent.
    }
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
        // legacy production root replaces this with Routes.home when
        // the Phase-8 wiring sweep flips the global useV2Theme. Only
        // route when the listener fires from an auth path — bail if
        // we're already on a home-adjacent route to avoid a flicker
        // from token-refresh events that happen on a live home.
        final router = _appRouter;
        if (router != null) {
          final loc = router.routerDelegate.currentConfiguration.uri.path;
          final onAuthPath = loc.startsWith('/dev/v2/auth') ||
              loc == Routes.splashIntro ||
              loc == Routes.onboarding ||
              loc == Routes.authInvitation;
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
