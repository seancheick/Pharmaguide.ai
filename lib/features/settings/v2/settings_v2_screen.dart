import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/components/pg_settings_tile.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// v2 Settings (Profile tab) — calm and utility-focused.
///
/// Preserves the legacy information architecture (Account & Security,
/// Health Profile, Privacy & Data, Analysis History, Settings, About)
/// because it's well-considered. Redesigns everything visually to v2:
/// - Serif first-name greeting under a mono caps "ACCOUNT" eyebrow
/// - Avatar = accent-tint circle with mono caps initials (privacy-first,
///   never asks for a photo)
/// - Compact stats line ("5 in stack · 2 medications · 18 scans")
/// - PGSettingsGroup with hairline dividers indented past the icon column
/// - PGSettingsTile carries icon + label + optional caption + optional
///   trailing (chevron auto-rendered when there's an onTap)
/// - Destructive actions render in calm muted contraindicated red, never
///   bright Material error red
///
/// Phase 6 prototype: fixture data so the gallery renders without
/// providers. Production swap wires `profileProvider` at Phase 8.
class SettingsV2Screen extends StatelessWidget {
  final String nickname;
  final int stackCount;
  final int medicationCount;
  final int scanCount;
  final bool signedIn;

  const SettingsV2Screen({
    super.key,
    this.nickname = 'Sean',
    this.stackCount = 5,
    this.medicationCount = 2,
    this.scanCount = 18,
    this.signedIn = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: V2Colors.bg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            V2Spacing.space24,
            V2Spacing.space16,
            V2Spacing.space24,
            V2Spacing.space48,
          ),
          children: [
            _ProfileHero(
              nickname: nickname,
              stackCount: stackCount,
              medicationCount: medicationCount,
              scanCount: scanCount,
              signedIn: signedIn,
            ),
            const SizedBox(height: V2Spacing.space32),
            PGSettingsGroup(
              eyebrow: 'Account & security',
              children: [
                PGSettingsTile(
                  icon: Icons.mail_outline_rounded,
                  title: signedIn ? 'Email' : 'Sign in',
                  caption: signedIn ? 'sean@example.com' : 'Sync stack across devices',
                  onTap: () {},
                ),
                const PGSettingsTile(
                  icon: Icons.fingerprint_rounded,
                  title: 'Biometric unlock',
                  caption: 'Face ID',
                  trailing: Switch.adaptive(value: true, onChanged: null),
                ),
              ],
            ),
            const SizedBox(height: V2Spacing.space24),
            PGSettingsGroup(
              eyebrow: 'Health profile',
              children: [
                // Phase 11.7j.6 — Sean 2026-05-16: was an empty
                // onTap. Wires to the multi-step profile editor
                // (ProfileSetupScreen) which already supports age,
                // goals, conditions, medications, and allergens.
                // Phase 11.10 will design a v2 mirror of that
                // screen; the legacy screen handles the data path
                // correctly today.
                PGSettingsTile(
                  icon: Icons.person_outline_rounded,
                  title: 'Edit profile',
                  caption: 'Age, goals, conditions, medications',
                  onTap: () => context.push(Routes.profileSetup),
                ),
                PGSettingsTile(
                  icon: Icons.medication_outlined,
                  title: 'Allergens',
                  caption: 'None set',
                  // Allergens live within the profile setup flow;
                  // route to the same screen — user can scroll to
                  // the allergens section.
                  onTap: () => context.push(Routes.profileSetup),
                ),
              ],
            ),
            const SizedBox(height: V2Spacing.space24),
            PGSettingsGroup(
              eyebrow: 'Privacy & data',
              children: [
                PGSettingsTile(
                  icon: Icons.shield_outlined,
                  title: 'Privacy dashboard',
                  caption: 'See where your data lives',
                  onTap: () {},
                ),
                const PGSettingsTile(
                  icon: Icons.analytics_outlined,
                  title: 'Anonymized analytics',
                  caption: 'Never includes health data',
                  trailing: Switch.adaptive(value: false, onChanged: null),
                ),
              ],
            ),
            const SizedBox(height: V2Spacing.space24),
            PGSettingsGroup(
              eyebrow: 'App',
              children: [
                PGSettingsTile(
                  icon: Icons.palette_outlined,
                  title: 'Theme',
                  caption: 'System',
                  onTap: () {},
                ),
                PGSettingsTile(
                  icon: Icons.notifications_outlined,
                  title: 'Notifications',
                  caption: 'Reminders, weekly summary',
                  onTap: () {},
                ),
                PGSettingsTile(
                  icon: Icons.accessibility_new_rounded,
                  title: 'Accessibility',
                  caption: 'Dynamic type, reduce motion',
                  onTap: () {},
                ),
                PGSettingsTile(
                  icon: Icons.cloud_download_outlined,
                  title: 'Offline mode',
                  caption: 'Download catalog for travel',
                  onTap: () {},
                ),
              ],
            ),
            const SizedBox(height: V2Spacing.space24),
            PGSettingsGroup(
              eyebrow: 'About',
              children: [
                const PGSettingsTile(
                  icon: Icons.info_outline_rounded,
                  title: 'Version',
                  caption: '1.0.0 · build 1',
                ),
                PGSettingsTile(
                  icon: Icons.description_outlined,
                  title: 'Terms of service',
                  onTap: () {},
                ),
                PGSettingsTile(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacy policy',
                  onTap: () {},
                ),
                PGSettingsTile(
                  icon: Icons.support_outlined,
                  title: 'Contact support',
                  onTap: () {},
                ),
                PGSettingsTile(
                  icon: Icons.star_outline_rounded,
                  title: 'Rate PharmaGuide',
                  onTap: () {},
                ),
              ],
            ),
            const SizedBox(height: V2Spacing.space24),
            PGSettingsGroup(
              children: [
                PGSettingsTile(
                  icon: Icons.download_outlined,
                  title: 'Export my data',
                  caption: 'Profile, stack, scans · JSON',
                  onTap: () {},
                ),
                PGSettingsTile(
                  icon: Icons.delete_outline_rounded,
                  title: 'Delete account',
                  caption: 'Permanently remove all data',
                  destructive: true,
                  onTap: () {},
                ),
              ],
            ),
            const SizedBox(height: V2Spacing.space32),
            Center(
              child: Text(
                'Your health data stays on this device.',
                style: V2Typography.caption(color: V2Colors.fgSubtle),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileHero extends StatelessWidget {
  final String nickname;
  final int stackCount;
  final int medicationCount;
  final int scanCount;
  final bool signedIn;

  const _ProfileHero({
    required this.nickname,
    required this.stackCount,
    required this.medicationCount,
    required this.scanCount,
    required this.signedIn,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(V2Spacing.space24),
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: V2Colors.outline),
        boxShadow: V2Shadows.sm,
      ),
      // **Phase 11.7j.4 — Sean 2026-05-16 profile polish.**
      // - Avatar circle removed (we never let users upload a photo,
      //   so the circle just sat as decorative noise).
      // - Eyebrow always reads "Profile" (was "Account" / "Guest profile"
      //   — the dual label felt clinical-app uncertain; "Profile" reads
      //   like the page title in both states).
      // - Title falls back to "Hello there" when nickname is empty;
      //   otherwise renders the user's nickname as the headline.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PGEyebrow('Profile'),
          const SizedBox(height: V2Spacing.space4),
          Text(
            nickname.trim().isEmpty ? 'Hello there' : nickname,
            style: V2Typography.displayXs(color: V2Colors.fg),
          ),
          const SizedBox(height: V2Spacing.space8),
          Text(
            _statsLine(),
            style: V2Typography.bodySm(color: V2Colors.fgMuted),
          ),
        ],
      ),
    );
  }

  String _statsLine() {
    final parts = <String>[];
    if (stackCount > 0) {
      parts.add('$stackCount in stack');
    }
    if (medicationCount > 0) {
      parts.add('$medicationCount ${medicationCount == 1 ? "medication" : "medications"}');
    }
    if (scanCount > 0) {
      parts.add('$scanCount ${scanCount == 1 ? "scan" : "scans"}');
    }
    return parts.isEmpty ? 'New here — let’s get you set up.' : parts.join(' · ');
  }
}
