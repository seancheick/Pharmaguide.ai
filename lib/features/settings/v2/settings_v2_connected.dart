import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/features/settings/v2/settings_v2_screen.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';
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

    // Auth state — Supabase exposes the currentUser sync, so we don't
    // need a stream subscription here. Settings rebuilds on profile/
    // stack changes anyway, which is enough cadence for the auth pill
    // (a fresh sign-in re-renders Settings via the global auth
    // listener routing to home → user navigates back to settings).
    final user = _safeCurrentUser();
    final signedIn = user != null;
    // TODO(phase-11): once SettingsV2Screen exposes an email caption
    // override, pass `user?.email` here.

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
      // TODO(phase-11): pass `email` once SettingsV2Screen exposes
      // an Email-tile caption override. For now the email caption
      // stays at the fixture value when signed in; the gallery sign-
      // out tile already surfaces the real address.
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
