import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' show Random;

import 'package:crypto/crypto.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:pharmaguide/data/supabase/supabase_client.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Result of a sign-in attempt. Callers pattern-match to decide UX —
/// successes hand the new Supabase session back; cancellations are
/// silent (no error toast); errors carry a human-readable message.
sealed class PGAuthResult {
  const PGAuthResult();
}

class PGAuthSuccess extends PGAuthResult {
  final Session session;
  const PGAuthSuccess(this.session);
}

/// Web OAuth fallback (Android Apple, future browser-only providers)
/// handed control to the system browser — the actual Supabase session
/// arrives async via `_AuthEventListener.onAuthStateChange`. UI should
/// dismiss the sheet and trust the listener.
class PGAuthHandoffToBrowser extends PGAuthResult {
  const PGAuthHandoffToBrowser();
}

class PGAuthCancelled extends PGAuthResult {
  const PGAuthCancelled();
}

class PGAuthError extends PGAuthResult {
  final String message;
  const PGAuthError(this.message);
}

/// Google Web OAuth client ID — the "server client" Supabase uses to
/// validate ID tokens. Sean configures the value in `.env` via
/// `GOOGLE_WEB_CLIENT_ID=...`; `make run-v2-ios` injects it via
/// `--dart-define`.
const String _googleWebClientId = String.fromEnvironment(
  'GOOGLE_WEB_CLIENT_ID',
  defaultValue: '',
);

/// Google iOS OAuth client ID — used as the `clientId` on the iOS
/// native sign-in flow so Google issues an ID token bound to the
/// PharmaGuide bundle ID. `.env` key: `GOOGLE_IOS_CLIENT_ID`.
const String _googleIosClientId = String.fromEnvironment(
  'GOOGLE_IOS_CLIENT_ID',
  defaultValue: '',
);

/// Single front door for native Apple + Google sign-in flows. Both
/// paths land at `supabase.auth.signInWithIdToken(...)`, which hands
/// the global `_AuthEventListener` in app.dart a `signedIn` event —
/// same plumbing the magic-link return uses.
class PGAuthService {
  PGAuthService();

  /// Apple Sign In. iOS uses the native AppleID dialog via
  /// [SignInWithApple.getAppleIDCredential]; the returned identity
  /// token + nonce go straight to Supabase.
  ///
  /// Android falls back to Supabase's web OAuth flow because Apple
  /// doesn't ship a native Android SDK — `signInWithOAuth` opens a
  /// browser tab, user authorizes on Apple's web page, and the
  /// `pharmaguide://auth/callback` deep link returns control here.
  Future<PGAuthResult> signInWithApple() async {
    if (SupabaseConfig.isPlaceholder) {
      return const PGAuthError('Auth is not configured in this build.');
    }
    try {
      if (Platform.isIOS || Platform.isMacOS) {
        final rawNonce = _generateNonce();
        final hashedNonce = _sha256Hex(rawNonce);
        final credential = await SignInWithApple.getAppleIDCredential(
          scopes: const [
            AppleIDAuthorizationScopes.email,
            AppleIDAuthorizationScopes.fullName,
          ],
          nonce: hashedNonce,
        );
        final idToken = credential.identityToken;
        if (idToken == null) {
          return const PGAuthError(
              "Apple didn't return an identity token. Try again.");
        }
        final response = await supabase.auth.signInWithIdToken(
          provider: OAuthProvider.apple,
          idToken: idToken,
          nonce: rawNonce,
        );
        final session = response.session;
        if (session == null) {
          return const PGAuthError(
              'Something went wrong on our side. Try again.');
        }
        return PGAuthSuccess(session);
      }
      // Android (or anything else) → web OAuth fallback. Apple
      // doesn't ship a native Android SDK; signInWithOAuth opens a
      // browser tab, the user authorizes on Apple's web page, the
      // pharmaguide://auth/callback deep link returns control here,
      // and the global _AuthEventListener catches the signedIn
      // event. We return the handoff signal so the UI can dismiss.
      await supabase.auth.signInWithOAuth(
        OAuthProvider.apple,
        redirectTo: 'pharmaguide://auth/callback',
      );
      return const PGAuthHandoffToBrowser();
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        return const PGAuthCancelled();
      }
      return PGAuthError(_friendlyAppleError(e));
    } on AuthException catch (e) {
      return PGAuthError(_friendlySupabaseError(e));
    } on Object catch (_) {
      return const PGAuthError(
          "We couldn't reach the network. Try again in a moment.");
    }
  }

  /// Google Sign In. Uses the `google_sign_in` package's native flow
  /// on both platforms — the returned ID token goes to Supabase.
  Future<PGAuthResult> signInWithGoogle() async {
    if (SupabaseConfig.isPlaceholder) {
      return const PGAuthError('Auth is not configured in this build.');
    }
    if (_googleWebClientId.isEmpty) {
      return const PGAuthError(
        'GOOGLE_WEB_CLIENT_ID is not set. Add it to .env to enable '
        'Google sign-in.',
      );
    }
    try {
      final googleSignIn = GoogleSignIn(
        // iOS reads its client ID from the reverse URL scheme in
        // Info.plist; Android resolves the package + SHA-1 from the
        // OAuth client registered in Google Cloud Console.
        clientId: Platform.isIOS && _googleIosClientId.isNotEmpty
            ? _googleIosClientId
            : null,
        // serverClientId is the web client ID Supabase validates
        // against. Required so Google embeds it in the ID token's
        // `aud` claim, which Supabase then matches.
        serverClientId: _googleWebClientId,
      );
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) return const PGAuthCancelled();
      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;
      if (idToken == null) {
        return const PGAuthError(
            "Google didn't return an identity token. Try again.");
      }
      final response = await supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );
      final session = response.session;
      if (session == null) {
        return const PGAuthError(
            'Something went wrong on our side. Try again.');
      }
      return PGAuthSuccess(session);
    } on AuthException catch (e) {
      return PGAuthError(_friendlySupabaseError(e));
    } on Object catch (e) {
      // GoogleSignIn errors don't have a useful exception subclass —
      // surface the message and map common cases to friendly copy.
      final msg = e.toString().toLowerCase();
      if (msg.contains('network')) {
        return const PGAuthError(
            "We couldn't reach the network. Try again in a moment.");
      }
      return PGAuthError(
        msg.contains('sign_in_canceled')
            ? 'Sign in canceled.'
            : 'Something went wrong with Google sign-in. Try again.',
      );
    }
  }

  /// Sign out — wipes the local Supabase session; the auth listener
  /// fires `signedOut` and the UI reacts.
  Future<void> signOut() => supabase.auth.signOut();

  // ---------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------

  /// 32-char URL-safe nonce. Apple requires a nonce on the credential
  /// request to prevent replay; the hashed value goes to Apple, the
  /// raw value goes to Supabase so it can re-verify the ID token.
  static String _generateNonce([int length = 32]) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._';
    final rand = Random.secure();
    return List<String>.generate(
      length,
      (_) => chars[rand.nextInt(chars.length)],
    ).join();
  }

  static String _sha256Hex(String input) =>
      sha256.convert(utf8.encode(input)).toString();

  static String _friendlyAppleError(
    SignInWithAppleAuthorizationException e,
  ) {
    switch (e.code) {
      case AuthorizationErrorCode.canceled:
        return 'Sign in canceled.';
      case AuthorizationErrorCode.notHandled:
        return 'Apple sign-in is not set up on this device.';
      case AuthorizationErrorCode.notInteractive:
        return 'Apple sign-in requires user interaction.';
      case AuthorizationErrorCode.failed:
      case AuthorizationErrorCode.invalidResponse:
      case AuthorizationErrorCode.unknown:
        return 'Apple sign-in failed. Try again.';
    }
  }

  static String _friendlySupabaseError(AuthException e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('rate') || msg.contains('too many')) {
      return 'Too many requests. Wait a minute and try again.';
    }
    return 'Something went wrong with sign-in. Try again in a moment.';
  }
}
