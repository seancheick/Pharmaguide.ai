import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/app.dart' show scaffoldMessengerKey;
import 'package:pharmaguide/core/components/pg_toast.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/features/ai_share/ai_connections_screen.dart';
import 'package:pharmaguide/features/history/health_history_screen.dart';
import 'package:pharmaguide/features/contributions/providers/product_submission_providers.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/features/settings/v2/delete_account_sheet.dart';
import 'package:pharmaguide/features/settings/v2/notification_settings_sheet.dart';
import 'package:pharmaguide/features/settings/v2/settings_v2_screen.dart';
import 'package:pharmaguide/features/settings/v2/sign_out_choice_sheet.dart';
import 'package:pharmaguide/features/settings/v2/theme_settings_sheet.dart';
import 'package:pharmaguide/features/settings/providers/app_preferences_provider.dart';
import 'package:pharmaguide/features/settings/providers/notification_settings_provider.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';
import 'package:pharmaguide/features/stack/widgets/clinician_report_preview_screen.dart';
import 'package:pharmaguide/services/auth/account_deletion_service.dart';
import 'package:pharmaguide/services/auth/pg_auth_service.dart';
import 'package:pharmaguide/services/auth_state_service.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Production-wired settings screen. Reads:
///   - `profileProvider`: nickname for the avatar hero
///   - `activeStackProvider`: supplement + medication counts for the
///     hero stat row
///   - `userDatabaseProvider.getRecentScans` (limit 999): total scans
///     count
///   - `Supabase.instance.client.auth.currentUser`: signed-in flag +
///     email — drives the "Email" tile vs the "Sign in" tile and the
///     "Sign out" affordance in the auth-tools section
///
/// Hands all of those into the pure-visual [SettingsV2Screen]. The
/// gallery preview at `/dev/v2/settings` keeps using the fixture
/// inputs; this Connected variant only renders inside production
/// routes that pass through GoRouter's shell.
class SettingsV2Connected extends ConsumerWidget {
  const SettingsV2Connected({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final stackAsync = ref.watch(activeStackProvider);
    final scanCountAsync = ref.watch(_scanCountProvider);
    final preferences = ref.watch(appPreferencesControllerProvider).preferences;
    final notificationSettings = ref.watch(
      notificationSettingsControllerProvider,
    );

    final authMode = ref.watch(authStateProvider);
    final user = _safeCurrentUser();
    final signedIn = authMode == AuthMode.signedIn;
    final pendingProductSubmissionCount = signedIn
        ? ref.watch(pendingSubmissionCountProvider)
        : 0;

    final stack = stackAsync.asData?.value ?? const [];
    final supplementCount = stack.where((e) => e.type == 'supplement').length;
    final medicationCount = stack.where((e) => e.type == 'medication').length;
    final scanCount = scanCountAsync.asData?.value ?? 0;
    final stackCount = supplementCount + medicationCount;

    return SettingsV2Screen(
      // Phase 11.7j.4 — Sean 2026-05-16: when nickname is unset,
      // pass an empty string instead of the literal placeholder
      // "there". The hero falls back to "Hello there" as a friendly
      // greeting; rendering the literal "there" as if it were a
      // name looked broken.
      nickname: profile.nickname ?? '',
      stackCount: stackCount,
      medicationCount: medicationCount,
      scanCount: scanCount,
      signedIn: signedIn,
      accountEmail: user?.email,
      onOpenHealthHistory: () =>
          Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute<void>(
              builder: (_) => const HealthHistoryScreen(),
            ),
          ),
      onOpenClinicianReport: () =>
          Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute<void>(
              builder: (_) => const ClinicianReportPreviewScreen(),
            ),
          ),
      onOpenAiConnections: () =>
          Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute<void>(
              builder: (_) => const AiConnectionsScreen(),
            ),
          ),
      onOpenProductSubmissions: signedIn
          ? () => context.push(Routes.productSubmissions)
          : null,
      pendingProductSubmissionCount: pendingProductSubmissionCount,
      themeCaption: themePreferenceLabel(preferences.theme),
      notificationCaption: notificationSettingsCaption(
        notificationSettings.status,
        preferences.notifications,
        isLoading: notificationSettings.isLoading,
      ),
      onOpenThemeSettings: () => PGModal.bottomSheet<void>(
        context: context,
        builder: (_) => const ThemeSettingsSheet(),
      ),
      onOpenNotificationSettings: () => PGModal.bottomSheet<void>(
        context: context,
        builder: (_) => const NotificationSettingsSheet(),
      ),
      onSignOut: () => _signOutWithChoice(context, ref),
      onDeleteAccount: signedIn ? () => _openDeleteAccount(context, ref) : null,
    );
  }

  static Future<bool> _signOutWithChoice(BuildContext context, WidgetRef ref) {
    final guard = ref.read(accountSwitchGuardProvider);
    return signOutWithChoice(
      choose: () => PGModal.bottomSheet<SignOutChoice>(
        context: context,
        builder: (_) => const SignOutChoiceSheet(),
      ),
      signOut: PGAuthService().signOut,
      currentUid: () => _safeCurrentUser()?.id,
      removeAccountData: (uid) async {
        try {
          await guard?.removeAccountData(uid);
        } on Object catch (error, stackTrace) {
          CrashReportingService().recordError(
            error,
            stackTrace,
            hint: 'sign_out:remove_failed',
          );
          PGToast.showWith(
            scaffoldMessengerKey.currentState,
            "Couldn't remove your data from this phone. It stays locked to "
            'your account.',
            variant: PGToastVariant.error,
          );
        }
      },
    );
  }

  static Future<void> _openDeleteAccount(BuildContext context, WidgetRef ref) {
    final guard = ref.read(accountSwitchGuardProvider);
    final uid = _safeCurrentUser()?.id;
    final service = AccountDeletionService.production(
      localPurges: [
        PGAuthService().signOutLocal,
        if (guard != null && uid != null) () => guard.removeAccountData(uid),
      ],
    );
    return PGModal.bottomSheet<void>(
      context: context,
      builder: (_) => DeleteAccountSheet(
        onDelete: (confirmation) async {
          final result = await service.deleteAccount(
            confirmation: confirmation,
          );
          // The sign-out replaced this tree and its sheet, so tell the user here.
          switch (result) {
            case AccountDeletionResult.deleted:
              PGToast.showWith(
                scaffoldMessengerKey.currentState,
                'Your account was deleted.',
                variant: PGToastVariant.info,
              );
            case AccountDeletionResult.deletedLocalCleanupIncomplete:
              PGToast.showWith(
                scaffoldMessengerKey.currentState,
                'Your online account was deleted, but this device could not '
                'confirm every local cleanup step. Close and reinstall the app '
                'before giving this device to someone else.',
                variant: PGToastVariant.error,
                duration: const Duration(seconds: 10),
              );
            case AccountDeletionResult.remoteFailed ||
                AccountDeletionResult.confirmationRequired:
              break;
          }
          return result;
        },
        onDeleted: () {},
      ),
    );
  }

  /// Supabase's `currentUser` throws if initialize() hasn't been
  /// called. Wrap it so placeholder builds don't crash settings.
  static User? _safeCurrentUser() {
    try {
      return Supabase.instance.client.auth.currentUser;
    } on Object catch (_) {
      return null;
    }
  }
}

/// Total scan count for the hero stat. Reads the recent-scans table
/// with a high limit — production volume is bounded by user behavior
/// (most users will have <50 scans). Auto-disposes when Settings
/// unmounts.
final _scanCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final userDb = ref.watch(userDatabaseProvider);
  final scans = await userDb.getRecentScans(limit: 999);
  return scans.length;
});
