import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/features/settings/v2/settings_v2_screen.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';
import 'package:pharmaguide/services/auth_state_service.dart';
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

    final authMode = ref.watch(authStateProvider);
    final user = _safeCurrentUser();
    final signedIn = authMode == AuthMode.signedIn;

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
