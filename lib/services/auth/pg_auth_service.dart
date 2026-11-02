import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' show Random;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/supabase/supabase_client.dart';
import 'package:pharmaguide/services/auth/account_storage.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';
import 'package:pharmaguide/services/notifications/safety_push_service.dart';
import 'package:pharmaguide/services/recent_searches_service.dart';
import 'package:pharmaguide/services/pending_submission_intent.dart';
import 'package:pharmaguide/services/settings/app_preferences.dart';
import 'package:pharmaguide/services/sharing/ai_share_prefs_store.dart';
import 'package:pharmaguide/services/sharing/ai_share_snapshot_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─── Shared-device account separation (ADR-013) ────────────────────────
//
// Each account, and the guest, has its own folder (AccountStorage). On each
// auth event a PURE function decides whose folder should be open, and the guard
// closes the current one and opens that one. Nothing here destroys data:
// removal is a separate, explicit request.

/// What the account gate decided for an auth event.
enum AccountSwitchAction {
  /// The right person's data is already open.
  keep,

  /// First sign-in for this account on this device, from the guest: the guest's
  /// folder becomes the account's, as guest data always has on first sign-in.
  adoptGuestData,

  /// A different account signed in: open that account's own folder.
  switchAccount,

  /// Signed out: the account's data stays locked in its folder.
  switchToGuest,
}

/// PURE decision for the account gate. No I/O — every branch is unit-tested in
/// test/services/auth/account_switch_gate_test.dart.
///
/// The session is the truth about who is using the app, so any session-bearing
/// event can correct the open folder. Switching destroys nothing, which is why
/// that is safe even for a maintenance event arriving after a missed sign-in.
AccountSwitchAction decideAccountAction({
  required String? activeOwner,
  required String? incomingUid,
  required AuthChangeEvent event,
  required bool incomingHasData,
}) {
  final hasOwner = activeOwner != null && activeOwner.isNotEmpty;
  if (event == AuthChangeEvent.signedOut) {
    return hasOwner
        ? AccountSwitchAction.switchToGuest
        : AccountSwitchAction.keep;
  }
  if (incomingUid == null || incomingUid.isEmpty) {
    return AccountSwitchAction.keep;
  }
  switch (event) {
    case AuthChangeEvent.signedIn ||
        AuthChangeEvent.initialSession ||
        AuthChangeEvent.tokenRefreshed ||
        AuthChangeEvent.userUpdated:
      if (incomingUid == activeOwner) return AccountSwitchAction.keep;
      if (!hasOwner && !incomingHasData) {
        return AccountSwitchAction.adoptGuestData;
      }
      return AccountSwitchAction.switchAccount;
    default:
      // passwordRecovery, mfaChallengeVerified, and any future events.
      return AccountSwitchAction.keep;
  }
}

/// Durable record of which uid's folder is open, read by the sync owner gate
/// ([ownerAllowsPush]) and, once, to place the pre-ADR-013 store. Null means the
/// guest. SharedPreferences-backed: it dies with an uninstall, like the folders.
class AccountOwnerStore {
  static const String prefsKey = 'account_owner_uid';

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

/// The one owner of switching between people on a device (ADR-013). Holds the
/// open user database, and applies [decideAccountAction] to live auth events.
///
/// Ordering is the point. The tree using the old database comes down first, so
/// nothing can read it. The handle closes next, so work still in flight fails
/// rather than landing in someone else's data. The owner is recorded only after
/// the new database opens. If it doesn't open, [database] stays null and the app
/// shows a retry: never another person's data, and never an empty database that
/// would read as having no medications.
class AccountSwitchGuard {
  AccountSwitchGuard({
    required this._ownerStore,
    required this._storage,
    required this._openDatabase,
    this._onOwnerChange,
    this._onNotificationCleanup,
    this._onAccountRemoved,
    this._readSessionUid,
  });

  factory AccountSwitchGuard.production({
    required Future<UserDatabase> Function(String path) openDatabase,
    Future<void> Function()? onOwnerChange,
    Future<void> Function()? onNotificationCleanup,
    Future<void> Function(String uid)? onAccountRemoved,
    String? Function()? readSessionUid,
  }) => AccountSwitchGuard(
    ownerStore: AccountOwnerStore(),
    storage: AccountStorage.production(),
    openDatabase: openDatabase,
    onOwnerChange: onOwnerChange,
    onNotificationCleanup: onNotificationCleanup,
    onAccountRemoved: onAccountRemoved,
    readSessionUid: readSessionUid,
  );

  final String? Function()? _readSessionUid;

  final AccountOwnerStore _ownerStore;
  final AccountStorage _storage;
  final Future<UserDatabase> Function(String path) _openDatabase;

  /// Ends what belongs to the outgoing person but lives outside their folder,
  /// such as scheduled notifications. A failure is reported and never stops the
  /// switch.
  final Future<void> Function()? _onOwnerChange;

  /// Cancels late OS writes without clearing the incoming owner's preferences.
  final Future<void> Function()? _onNotificationCleanup;

  /// Deletes what is keyed to the account but lives outside its folder.
  final Future<void> Function(String uid)? _onAccountRemoved;

  /// Takes down whatever is using [database], and returns once it is gone.
  Future<void> Function()? releaseConsumers;

  /// Called after each switch, whether or not a database opened.
  void Function()? onChanged;

  bool _acceptingNotificationWork = false;
  final Set<Future<void>> _notificationWork = {};

  /// An OS scheduling call cannot be cancelled by disposing its provider.
  /// Keep its lifetime here so sign-out drains it before cancelling the old
  /// schedule and before a new account can publish its own notifications.
  /// Register only the OS call: a read of a disposed provider may never finish.
  Future<T> runNotificationWork<T>(
    Future<T> Function() work, {
    required ActiveAccount account,
  }) {
    if (!_acceptingNotificationWork || !identical(account, _account)) {
      return Future.error(StateError('Account is changing'));
    }
    final result = Future.sync(work);
    late final Future<void> pending;
    pending = result
        .then<void>((_) {}, onError: (Object _, StackTrace _) {})
        .whenComplete(() {
          _notificationWork.remove(pending);
        });
    _notificationWork.add(pending);
    return result;
  }

  bool _legacyMigrated = false;
  UserDatabase? _database;
  ActiveAccount _account = ActiveAccount.guest;
  String? _ownerUid;
  Future<void> Function()? _retry;
  Future<void> _tail = Future.value();

  /// Null when the owner's data could not be opened. See [retry].
  UserDatabase? get database => _database;
  ActiveAccount get account => _account;
  String? get ownerUid => _ownerUid;

  /// Serial, so overlapping auth events can't interleave a switch.
  Future<T> _enqueue<T>(Future<T> Function() work) {
    final result = _tail.then((_) => work());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  /// Opens the data for the session the app launched with. Never throws.
  Future<void> boot({required String? sessionUid}) => _enqueue(() async {
    // No owner on record means the guest was open when the app last ran, so a
    // session found now is the sign-in whose event never got handled.
    final previousOwner = await _ownerStore.read();
    final adoptGuest = sessionUid != null && previousOwner == null;
    if (previousOwner != sessionUid) {
      await _endOwnerWork(
        previousOwner: previousOwner,
        incomingUid: sessionUid,
      );
    }
    await _open(sessionUid, adoptGuest: adoptGuest);
  });

  /// Tries again after [database] came back null.
  Future<void> retry() => _enqueue(() async {
    if (_readSessionUid != null && _readSessionUid() != _ownerUid) {
      // The error screen has no provider/auth-listener tree. A session can
      // expire while it is shown; never reopen the uid captured by the failure.
      final uid = _readSessionUid();
      await _switch(uid, adoptGuest: _ownerUid == null && uid != null);
      return;
    }
    await _retry?.call();
    onChanged?.call();
  });

  /// Handle one auth event. Completes only after all side effects are done —
  /// callers MUST await this before flipping the app's auth mode, because the
  /// guest→signedIn transition is what triggers sync pushes.
  Future<AccountSwitchAction> onAuthEvent({
    required AuthChangeEvent event,
    required String? uid,
  }) => _enqueue(() async {
    // Only guest adoption needs a presence probe. A lookup failure must not
    // abort sign-out before the old account's consumers and handle are closed.
    var incomingHasData = false;
    if (_ownerUid == null &&
        uid != null &&
        uid.isNotEmpty &&
        event != AuthChangeEvent.signedOut) {
      try {
        incomingHasData = await _storage.hasData(uid);
      } on Object catch (error, stackTrace) {
        CrashReportingService().recordError(
          error,
          stackTrace,
          hint: 'account_switch:presence',
        );
        // _open checks presence again inside its fail-closed boundary before
        // adopting anything; an unreadable folder never means an empty account.
      }
    }
    final action = decideAccountAction(
      activeOwner: _ownerUid,
      incomingUid: uid,
      event: event,
      incomingHasData: incomingHasData,
    );
    switch (action) {
      case AccountSwitchAction.keep:
        break;
      case AccountSwitchAction.adoptGuestData:
        await _switch(uid, adoptGuest: true);
      case AccountSwitchAction.switchAccount:
        await _switch(uid);
      case AccountSwitchAction.switchToGuest:
        await _switch(null);
    }
    return action;
  });

  /// Deletes [uid]'s folder from this device, moving to the guest first if that
  /// account is open. Throws if the delete fails, and the data stays locked.
  Future<void> removeAccountData(String uid) => _enqueue(() async {
    if (_ownerUid == uid) await _switch(null);
    await _storage.delete(uid);
    await RecentSearchesService.deleteScope(AccountStorage.scopeFor(uid));
    await _onAccountRemoved?.call(uid);
  });

  Future<void> close() => _enqueue(() async {
    _acceptingNotificationWork = false;
    await _drainNotificationWork(_notificationWork.toList());
    await _closeDatabase();
  });

  Future<void> _switch(String? uid, {bool adoptGuest = false}) async {
    _acceptingNotificationWork = false;
    await releaseConsumers?.call();
    final pending = _notificationWork.toList();
    final drained = await _drainNotificationWork(pending);
    await _endOwnerWork(previousOwner: _ownerUid, incomingUid: uid);
    await _closeDatabase();
    await _open(uid, adoptGuest: adoptGuest);
    onChanged?.call();
    if (!drained) _cleanUpAfterLateWork(pending);
  }

  /// False when a call outlasted the limit. A hung OS call must not hold the
  /// outgoing person's data open or block every later auth event.
  Future<bool> _drainNotificationWork(List<Future<void>> pending) async {
    try {
      await Future.wait(pending).timeout(const Duration(seconds: 5));
      return true;
    } on TimeoutException catch (error, stackTrace) {
      CrashReportingService().recordError(
        error,
        stackTrace,
        hint: 'account_switch:notification_drain',
      );
      return false;
    }
  }

  /// A call that outlasted the drain can still write after the cancel. When it
  /// ends, cancel again and let the current owner's tree schedule its own.
  void _cleanUpAfterLateWork(List<Future<void>> late) {
    // Each completed write needs cleanup even if another call never returns.
    for (final pending in late) {
      unawaited(
        pending.then(
          (_) => _enqueue(() async {
            try {
              await _onNotificationCleanup?.call();
            } on Object catch (error, stackTrace) {
              CrashReportingService().recordError(
                error,
                stackTrace,
                hint: 'account_switch:late_notification_cleanup',
              );
            }
            onChanged?.call();
          }),
        ),
      );
    }
  }

  Future<void> _endOwnerWork({
    required String? previousOwner,
    required String? incomingUid,
  }) async {
    try {
      await Future.wait([
        // A guest's pending action is the reason for signing in. Preserve it
        // for post-auth navigation; discard it when leaving a signed-in owner.
        if (previousOwner != null || incomingUid == null)
          Future.sync(PendingSubmissionIntent.clear),
        if (_onOwnerChange != null) Future.sync(_onOwnerChange),
      ]);
    } on Object catch (error, stackTrace) {
      CrashReportingService().recordError(
        error,
        stackTrace,
        hint: 'account_switch:owner_change',
      );
    }
  }

  Future<void> _closeDatabase() async {
    final old = _database;
    _database = null;
    try {
      await old?.close().timeout(const Duration(seconds: 5));
    } on Object catch (error, stackTrace) {
      CrashReportingService().recordError(
        error,
        stackTrace,
        hint: 'account_switch:close',
      );
    }
  }

  Future<void> _open(String? uid, {bool adoptGuest = false}) async {
    _ownerUid = uid;
    _account = ActiveAccount(scope: AccountStorage.scopeFor(uid));
    _retry = () => _open(uid, adoptGuest: adoptGuest);
    UserDatabase? opened;
    try {
      if (!_legacyMigrated) {
        await _migrateLegacyStore();
        _legacyMigrated = true;
      }
      if (adoptGuest && !await _storage.hasData(uid)) {
        await _storage.adoptGuestFolder(uid!);
        await RecentSearchesService.moveScope(
          from: AccountStorage.guestScope,
          to: AccountStorage.scopeFor(uid),
        );
      }
      opened = await _openDatabase(await _storage.databasePathFor(uid));
      // Runs the schema migration, so a bad file fails here and not in a screen.
      await opened.customSelect('SELECT 1').get();
      if (uid == null) {
        await _ownerStore.clear();
      } else {
        await _ownerStore.write(uid);
      }
      _account = await _storage.accountFor(uid);
      if (_readSessionUid != null && _readSessionUid() != uid) {
        throw StateError('Session changed while opening account data');
      }
      _database = opened;
      _acceptingNotificationWork = true;
      _retry = null;
    } on Object catch (error, stackTrace) {
      CrashReportingService().recordError(
        error,
        stackTrace,
        hint: 'account_switch:open',
      );
      try {
        await opened?.close();
      } on Object {
        // Best-effort cleanup; the open failure is what gets reported.
      }
    }
  }

  Future<void> _migrateLegacyStore() async {
    // The file belongs to the owner on record, whoever is signed in now.
    final legacyOwner = await _ownerStore.read();
    await _storage.migrateLegacyStore(owner: legacyOwner);
    await RecentSearchesService.adoptLegacyEntries(
      AccountStorage.scopeFor(legacyOwner),
    );
  }
}

/// The app's guard, or null in a tree with no account storage behind it.
final accountSwitchGuardProvider = Provider<AccountSwitchGuard?>((ref) => null);

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
  PGAuthService({
    this._aiShareSnapshots,
    this._aiSharePrefs,
    @visibleForTesting this._signOutRemote,
  });

  final AiShareSnapshotClient? _aiShareSnapshots;
  final AiSharePrefsStore? _aiSharePrefs;
  final Future<void> Function()? _signOutRemote;

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
      return PGAuthError(friendlyAppleError(e));
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
  /// The auth listener delegates local ownership to [AccountSwitchGuard].
  /// Kept data remains in its account folder; sign-out opens the guest folder.
  /// Explicit removal is handled separately after the session ends.
  ///
  /// Push teardown is transport cleanup, not user data: the device token must
  /// be unregistered while the session JWT can still authorize it, or the
  /// signed-out device keeps receiving this account's notifications.
  ///
  /// AI-share snapshots (ADR-009 S5) are deleted here for the same reason:
  /// the edge function needs this session's JWT. The purge is best-effort;
  /// a failure is logged and sign-out still completes.
  Future<void> signOut() async {
    await SafetyPushService.active?.unregisterBeforeSignOut();
    await _purgeAiShareBeforeSignOut();
    final remote = _signOutRemote;
    if (remote != null) return remote();
    await supabase.auth.signOut();
  }

  Future<void> _purgeAiShareBeforeSignOut() async {
    // Stop every opt-in refresh first so nothing re-uploads after the purge.
    try {
      await (_aiSharePrefs ??
              AiSharePrefsStore(SharedPreferencesAsyncAppPreferencesStore()))
          .clear();
    } on Object catch (error, stackTrace) {
      CrashReportingService().recordError(
        error,
        stackTrace,
        hint: 'ai_share:signout_prefs_clear_failed',
      );
    }
    try {
      // Bounded so an offline device can still sign out.
      await (_aiShareSnapshots ?? AiShareSnapshotClient.production())
          .deleteAll()
          .timeout(const Duration(seconds: 10));
    } on AiShareNotSignedIn {
      // No session: nothing this device can authorize deleting.
    } on Object catch (error, stackTrace) {
      CrashReportingService().recordError(
        error,
        stackTrace,
        hint: 'ai_share:signout_purge_failed',
      );
    }
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

  @visibleForTesting
  static String friendlyAppleError(SignInWithAppleAuthorizationException e) {
    switch (e.code) {
      case AuthorizationErrorCode.canceled:
        return 'Sign in canceled.';
      case AuthorizationErrorCode.notHandled:
        return 'Apple sign-in is not set up on this device.';
      case AuthorizationErrorCode.notInteractive:
        return 'Apple sign-in requires user interaction.';
      case AuthorizationErrorCode.unknown:
        // ASAuthorizationError 1000 comes from the device (usually its Apple
        // Account), so "Try again" only repeats it: Sentry PHARMAGUIDE-17
        // logged 35 attempts from 3 people. Say what to check instead.
        return 'Apple sign-in isn’t available on this device right now. '
            'Check your Apple Account in Settings, or continue with Google '
            'or email.';
      case AuthorizationErrorCode.failed:
      case AuthorizationErrorCode.invalidResponse:
      default:
        // New native authorization failures are not successful sign-ins or
        // cancellations. Never expose the provider's raw error text.
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
