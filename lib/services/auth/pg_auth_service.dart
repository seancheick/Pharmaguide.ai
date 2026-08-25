import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' show Random;

import 'package:crypto/crypto.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/supabase/supabase_client.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';
import 'package:pharmaguide/services/notifications/safety_push_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─── Shared-device account hygiene — "clear on account switch" ─────────────
//
// The next user on a device must not inherit or upload the previous
// user's medical data. We persist the OWNER uid durably; on each auth
// event a PURE function decides between keep / adopt / clearAndAdopt,
// and only clearAndAdopt is destructive.
//
// CRITICAL SAFETY: the clear is destructive and there is NO cloud backup
// for profile/meds/conditions/allergens. It fires ONLY on a genuine
// different-uid sign-in — never on tokenRefreshed, userUpdated, the same
// uid reappearing, initialSession with the same uid, or signedOut.

/// What the account-switch gate decided for an auth event.
enum AccountSwitchAction {
  /// No ownership change — leave local data and the owner record alone.
  keep,

  /// First sign-in ever recorded on this install: stamp the incoming uid
  /// as owner and KEEP all local (guest-era) data. Non-destructive.
  adopt,

  /// A DIFFERENT real uid signed in: clear ALL local user data (and with
  /// it every sync-dirty row), then stamp the new owner. Destructive.
  clearAndAdopt,
}

/// PURE decision for the account-switch gate. No I/O — every branch is
/// unit-tested in test/services/auth/account_switch_gate_test.dart.
///
/// Destructive `clearAndAdopt` is possible ONLY for sign-in-shaped events
/// ([AuthChangeEvent.signedIn], [AuthChangeEvent.initialSession]) carrying
/// a real uid that differs from a real stored owner. Session-maintenance
/// events ([AuthChangeEvent.tokenRefreshed], [AuthChangeEvent.userUpdated])
/// may stamp ownership when none is recorded (an active session means the
/// current human IS that uid) but can NEVER clear. Everything else —
/// signedOut, passwordRecovery, MFA, unknown future events — is keep.
AccountSwitchAction decideAccountAction({
  required String? storedOwner,
  required String? incomingUid,
  required AuthChangeEvent event,
}) {
  // No uid → nothing to adopt and, above all, nothing to justify a clear.
  if (incomingUid == null || incomingUid.isEmpty) {
    return AccountSwitchAction.keep;
  }
  final hasOwner = storedOwner != null && storedOwner.isNotEmpty;
  switch (event) {
    case AuthChangeEvent.signedIn || AuthChangeEvent.initialSession:
      if (!hasOwner) return AccountSwitchAction.adopt;
      if (storedOwner == incomingUid) return AccountSwitchAction.keep;
      return AccountSwitchAction.clearAndAdopt;
    case AuthChangeEvent.tokenRefreshed || AuthChangeEvent.userUpdated:
      // Never destructive: a refresh for a mismatched uid means a sign-in
      // event was missed — the sync owner gate (ownerAllowsPush) blocks
      // uploads until a genuine sign-in resolves it.
      return hasOwner ? AccountSwitchAction.keep : AccountSwitchAction.adopt;
    default:
      // signedOut (owner intentionally stays — same user returning keeps
      // their data; a different next sign-in triggers the clear),
      // passwordRecovery, mfaChallengeVerified, and any future events.
      return AccountSwitchAction.keep;
  }
}

/// Durable record of which uid owns the local user data on this install.
/// SharedPreferences-backed (the user DB has no kv/meta table): survives
/// restarts and sign-outs, dies with an uninstall — exactly like the user
/// DB itself, so the two can't outlive each other.
class AccountOwnerStore {
  static const String prefsKey = 'account_owner_uid';

  /// The uid that owns local data, or null if no one ever signed in on
  /// this install (genuine guest data).
  Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(prefsKey);
  }

  Future<void> write(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, uid);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefsKey);
  }
}

/// Applies [decideAccountAction] to a live auth event: reads the durable
/// owner, decides, and performs the (possibly destructive) side effects.
///
/// Ordering on clearAndAdopt is load-bearing: clear FIRST, stamp owner
/// LAST. If anything fails mid-clear the owner still reads as the
/// previous uid, so the next sign-in retries the clear and the sync
/// owner gate keeps blocking cross-account uploads in the meantime.
class AccountSwitchGuard {
  final AccountOwnerStore _ownerStore;
  final UserDatabase _db;

  /// Clears per-user data living outside the user DB (e.g. recent
  /// searches in SharedPreferences). Injected by the composition root so
  /// this class doesn't grow feature imports.
  final Future<void> Function()? _clearPerUserPrefs;

  AccountSwitchGuard({
    required this._ownerStore,
    required this._db,
    this._clearPerUserPrefs,
  });

  /// Handle one auth event. Completes only after all side effects are
  /// done — callers MUST await this before flipping the app's auth mode,
  /// because the guest→signedIn transition is what triggers sync pushes.
  Future<AccountSwitchAction> onAuthEvent({
    required AuthChangeEvent event,
    required String? uid,
  }) async {
    final storedOwner = await _ownerStore.read();
    final action = decideAccountAction(
      storedOwner: storedOwner,
      incomingUid: uid,
      event: event,
    );
    switch (action) {
      case AccountSwitchAction.keep:
        break;
      case AccountSwitchAction.adopt:
        await _ownerStore.write(uid!);
      case AccountSwitchAction.clearAndAdopt:
        // Destructive path — see class doc for the clear-first ordering.
        await _db.clearAllLocalUserData();
        await _clearPerUserPrefs?.call();
        await _ownerStore.write(uid!);
    }
    return action;
  }
}

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
            "Apple didn't return an identity token. Try again.",
          );
        }
        final response = await supabase.auth.signInWithIdToken(
          provider: OAuthProvider.apple,
          idToken: idToken,
          nonce: rawNonce,
        );
        final session = response.session;
        if (session == null) {
          return const PGAuthError(
            'Something went wrong on our side. Try again.',
          );
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
    } on SignInWithAppleAuthorizationException catch (e, st) {
      if (e.code == AuthorizationErrorCode.canceled) {
        return const PGAuthCancelled();
      }
      CrashReportingService().recordError(e, st, hint: 'pg_auth:apple_authz');
      return PGAuthError(_friendlyAppleError(e));
    } on AuthException catch (e, st) {
      CrashReportingService().recordError(
        e,
        st,
        hint: 'pg_auth:apple_supabase',
      );
      return PGAuthError(_friendlySupabaseError(e));
    } on Object catch (e, st) {
      CrashReportingService().recordError(e, st, hint: 'pg_auth:apple_unknown');
      return const PGAuthError(
        "We couldn't reach the network. Try again in a moment.",
      );
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
      // Clear any cached Google credential first. A stale session can hand
      // back an id_token that still carries a nonce we never set (google_sign_in
      // 6.x exposes no nonce API), which Supabase rejects with "Passed nonce
      // and nonce in id_token should either both exist or not." Forcing a fresh
      // interactive sign-in guarantees a nonce-free token.
      // ponytail: best-effort cache clear; swallow if nothing was signed in.
      try {
        await googleSignIn.signOut();
      } on Object {
        // Nothing cached — proceed to interactive sign-in.
      }
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) return const PGAuthCancelled();
      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;
      if (idToken == null) {
        return const PGAuthError(
          "Google didn't return an identity token. Try again.",
        );
      }
      final response = await supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );
      final session = response.session;
      if (session == null) {
        return const PGAuthError(
          'Something went wrong on our side. Try again.',
        );
      }
      return PGAuthSuccess(session);
    } on AuthException catch (e, st) {
      CrashReportingService().recordError(
        e,
        st,
        hint: 'pg_auth:google_supabase',
      );
      return PGAuthError(_friendlySupabaseError(e));
    } on Object catch (e, st) {
      // GoogleSignIn errors don't have a useful exception subclass —
      // surface the message and map common cases to friendly copy.
      final msg = e.toString().toLowerCase();
      // User-cancel path: don't record — user intent, not an error.
      if (msg.contains('sign_in_canceled')) {
        return const PGAuthError('Sign in canceled.');
      }
      CrashReportingService().recordError(
        e,
        st,
        hint: 'pg_auth:google_unknown',
      );
      if (msg.contains('network')) {
        return const PGAuthError(
          "We couldn't reach the network. Try again in a moment.",
        );
      }
      return const PGAuthError(
        'Something went wrong with Google sign-in. Try again.',
      );
    }
  }

  /// Sign out — wipes the local Supabase session; the auth listener
  /// fires `signedOut` and the UI reacts.
  ///
  /// Intentionally does NOT touch local user data or the
  /// [AccountOwnerStore] record: the owner stays the last signed-in uid,
  /// so the SAME user returning keeps their data and a DIFFERENT next
  /// sign-in triggers the account-switch clear. Do not add a wipe here.
  ///
  /// Push teardown is transport cleanup, not user data: the device token must
  /// be unregistered while the session JWT can still authorize it, or the
  /// signed-out device keeps receiving this account's notifications.
  Future<void> signOut() async {
    await SafetyPushService.active?.unregisterBeforeSignOut();
    await supabase.auth.signOut();
  }

  /// Clears only the session cached on this device.
  ///
  /// Account deletion happens server-side first. At that point a global
  /// sign-out request can no longer authenticate, so the deletion flow uses
  /// this local scope to guarantee the retired session cannot reopen the app.
  Future<void> signOutLocal() =>
      supabase.auth.signOut(scope: SignOutScope.local);

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

  static String _friendlyAppleError(SignInWithAppleAuthorizationException e) {
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
