import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/app.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('isOnMagicLinkCallback', () {
    GoRouter router() => GoRouter(
      initialLocation: Routes.home,
      routes: [
        GoRoute(path: Routes.home, builder: (_, __) => const Text('Home')),
        GoRoute(
          path: Routes.authInvitation,
          builder: (_, __) => const Text('Sign in'),
        ),
        GoRoute(
          path: '/auth/callback',
          builder: (_, __) => const Text('Finishing sign-in'),
        ),
      ],
    );

    testWidgets('true only on the callback page', (tester) async {
      final r = router();
      addTearDown(r.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: r));
      expect(isOnMagicLinkCallback(r), isFalse);

      r.go('/auth/callback?code=abc');
      await tester.pumpAndSettle();
      expect(isOnMagicLinkCallback(r), isTrue);

      r.go(Routes.authInvitation);
      await tester.pumpAndSettle();
      expect(isOnMagicLinkCallback(r), isFalse);
    });
  });

  group('authStreamErrorResponse', () {
    // Sentry PHARMAGUIDE-23: a signed-in phone woke up, GoTrue's background
    // token refresh hit a dead socket, and the app reported it and told the
    // user "Sign-in could not be completed". GoTrue keeps the session and
    // retries on its own.
    final droppedRefresh = AuthRetryableFetchException(
      message:
          'ClientException: Bad file descriptor, uri=https://project.supabase.co'
          '/auth/v1/token?grant_type=refresh_token',
    );

    test('a dropped background refresh is neither reported nor shown', () {
      final response = authStreamErrorResponse(
        droppedRefresh,
        onMagicLinkCallback: false,
      );

      expect(response.report, isFalse);
      expect(response.tellUser, isFalse);
    });

    test('a dropped connection on the magic-link page is shown', () {
      // The user is waiting on this exchange, so silence would strand them.
      final response = authStreamErrorResponse(
        droppedRefresh,
        onMagicLinkCallback: true,
      );

      expect(response.report, isFalse);
      expect(response.tellUser, isTrue);
    });

    test('a server error during a refresh is reported but not shown', () {
      final response = authStreamErrorResponse(
        AuthRetryableFetchException(
          message: 'Internal Server Error',
          statusCode: '500',
        ),
        onMagicLinkCallback: false,
      );

      expect(response.report, isTrue);
      expect(response.tellUser, isFalse);
    });

    test('an expired magic link is shown, not reported', () {
      final response = authStreamErrorResponse(
        const AuthException(
          'Email link is invalid or has expired',
          statusCode: 'otp_expired',
          code: 'access_denied',
        ),
        onMagicLinkCallback: true,
      );

      expect(response.report, isFalse);
      expect(response.tellUser, isTrue);
    });

    test('any other auth error is reported and shown', () {
      final response = authStreamErrorResponse(
        const AuthException('Unexpected failure'),
        onMagicLinkCallback: false,
      );

      expect(response.report, isTrue);
      expect(response.tellUser, isTrue);
    });
  });
}
