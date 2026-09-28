import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/app.dart';
import 'package:pharmaguide/core/constants/routes.dart';

void main() {
  group('normalizePharmaGuideDeepLink', () {
    test('turns custom-scheme product links into router paths', () {
      final out = normalizePharmaGuideDeepLink(
        Uri.parse('pharmaguide://product/1038?section=ingredients'),
      );

      expect(out, '/product/1038?section=ingredients');
    });

    test('handles triple-slash app paths', () {
      final out = normalizePharmaGuideDeepLink(
        Uri.parse('pharmaguide:///quick-check'),
      );

      expect(out, '/quick-check');
    });

    test('keeps auth callback routable while Supabase finishes exchange', () {
      final out = normalizePharmaGuideDeepLink(
        Uri.parse('pharmaguide://auth/callback?code=abc'),
      );

      expect(out, '/auth/callback?code=abc');
    });

    test('ignores non-PharmaGuide links', () {
      final out = normalizePharmaGuideDeepLink(
        Uri.parse('https://example.com/product/1038'),
      );

      expect(out, isNull);
    });
  });

  group('compareSelfRedirect', () {
    test('/compare/X/X redirects to /product/X', () {
      expect(compareSelfRedirect('12345', '12345'), '/product/12345');
    });

    test('distinct ids do not redirect', () {
      expect(compareSelfRedirect('12345', '67890'), isNull);
    });

    test('empty ids do not redirect (route 404s normally)', () {
      expect(compareSelfRedirect('', ''), isNull);
    });
  });

  // `pharmaguide://dev/v2/...` reached the design gallery and its fixture
  // screens (a fake signed-in profile with no way back) in release builds,
  // because every /dev route was registered unconditionally.
  group('withDevPreviewRoutes', () {
    final production = [
      GoRoute(path: '/', builder: (_, __) => const SizedBox()),
    ];

    test('release builds register no /dev routes', () {
      final routes = withDevPreviewRoutes(production, debugBuild: false);

      expect(routes.whereType<GoRoute>().map((r) => r.path), ['/']);
    });

    test('debug builds keep the preview gallery', () {
      final paths = withDevPreviewRoutes(
        production,
        debugBuild: true,
      ).whereType<GoRoute>().map((r) => r.path).toList();

      expect(paths.first, '/');
      expect(paths, contains('/dev/v2'));
      expect(paths.skip(1), everyElement(startsWith('/dev/')));
    });
  });

  // The 1.3 s animated splash played on every launch. HIG launching:
  // "Launch instantly"; a splash belongs at the start of onboarding. First
  // run keeps it; returning users open straight on Home.
  group('initialAppLocation', () {
    test('first run plays the splash into onboarding', () {
      expect(
        initialAppLocation(hasSeenOnboarding: false),
        '${Routes.splashIntro}?next=${Uri.encodeComponent(Routes.onboarding)}',
      );
    });

    test('returning users open on Home with no splash', () {
      expect(initialAppLocation(hasSeenOnboarding: true), Routes.home);
    });
  });
}
