import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/auth/pg_auth_service.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

void main() {
  for (final code in AuthorizationErrorCode.values) {
    test('Apple authorization error $code has safe display text', () {
      final message = PGAuthService.friendlyAppleError(
        SignInWithAppleAuthorizationException(
          code: code,
          message: 'private provider error details',
        ),
      );
      final expected = switch (code) {
        AuthorizationErrorCode.canceled => 'Sign in canceled.',
        AuthorizationErrorCode.notHandled =>
          'Apple sign-in is not set up on this device.',
        AuthorizationErrorCode.notInteractive =>
          'Apple sign-in requires user interaction.',
        // Error 1000 (Sentry PHARMAGUIDE-17: 35 attempts from 3 people).
        // Retrying cannot fix it, so the message names what to check.
        AuthorizationErrorCode.unknown =>
          'Apple sign-in isn’t available on this device right now. Check '
              'your Apple Account in Settings, or continue with Google or '
              'email.',
        _ => 'Apple sign-in failed. Try again.',
      };
      expect(message, expected);
      expect(message, isNot(contains('private provider error details')));
    });
  }
}
