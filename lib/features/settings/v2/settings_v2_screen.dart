import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/components/pg_pill_button.dart';
import 'package:pharmaguide/core/components/pg_settings_tile.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/features/settings/v2/beta_feedback_sheet.dart';
import 'package:pharmaguide/services/analytics_service.dart';
import 'package:pharmaguide/services/auth/pg_auth_service.dart';
import 'package:url_launcher/url_launcher.dart';

/// v2 Settings (Profile tab) — calm and utility-focused.
///
/// Keeps the established information architecture (Account & Security,
/// Health Profile, Privacy & Data, Analysis History, Settings, About)
/// and renders it with v2 components:
/// - Serif first-name greeting under a mono caps "ACCOUNT" eyebrow
/// - Avatar = accent-tint circle with mono caps initials (privacy-first,
///   never asks for a photo)
/// - Compact stats line ("5 in stack · 2 medications · 18 scans")
/// - PGSettingsGroup with hairline dividers indented past the icon column
/// - PGSettingsTile carries icon + label + optional caption + optional
///   trailing (chevron auto-rendered when there's an onTap)
/// - Destructive actions render in calm muted contraindicated red, never
///   bright Material error red
class SettingsV2Screen extends StatelessWidget {
  final String nickname;
  final int stackCount;
  final int medicationCount;
  final int scanCount;
  final bool signedIn;
  final String? accountEmail;
  final Future<void> Function()? onSignOut;
  final Future<bool> Function(Uri uri)? onOpenExternal;

  const SettingsV2Screen({
    super.key,
    this.nickname = 'Sean',
    this.stackCount = 5,
    this.medicationCount = 2,
    this.scanCount = 18,
    this.signedIn = false,
    this.accountEmail,
    this.onSignOut,
    this.onOpenExternal,
  });

  @override
  Widget build(BuildContext context) {
    final openExternal =
        onOpenExternal ??
        (Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

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
                  caption: signedIn
                      ? accountEmail ??
                            'Unlimited early-access scans · stack saved'
                      : 'Save stack, profile, and history',
                  onTap: signedIn
                      ? null
                      : () => context.push(Routes.authInvitation),
                ),
                if (signedIn)
                  PGSettingsTile(
                    icon: Icons.logout_rounded,
                    title: 'Sign out',
                    caption: 'Keep local health data on this device',
                    destructive: true,
                    onTap: () => _signOut(context, onSignOut),
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
                // Allergies are health context and live inside the
                // profile editor next to conditions + medications,
                // not as a disconnected setting. The Edit profile
                // entry point reaches the unified editor where every
                // health-context group is one tap away.
                PGSettingsTile(
                  icon: Icons.person_outline_rounded,
                  title: 'Edit profile',
                  caption: 'Goals, conditions, allergies, medications',
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
                  onTap: () => _showPrivacyDashboard(context),
                ),
                const PGSettingsTile(
                  icon: Icons.analytics_outlined,
                  title: 'Anonymized analytics',
                  caption: 'Never includes health data',
                  trailing: _AnalyticsSettingsSwitch(),
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
                  onTap: () => _showSettingSheet(
                    context,
                    title: 'Theme',
                    body:
                        'PharmaGuide follows your device appearance. '
                        'The app now uses the v2 theme system across '
                        'production screens.',
                  ),
                ),
                PGSettingsTile(
                  icon: Icons.notifications_outlined,
                  title: 'Notifications',
                  caption: 'Reminders, weekly summary',
                  onTap: () => _showSettingSheet(
                    context,
                    title: 'Notifications',
                    body:
                        'Reminder controls will appear here once push '
                        'notifications are enabled for this build.',
                  ),
                ),
                PGSettingsTile(
                  icon: Icons.accessibility_new_rounded,
                  title: 'Accessibility',
                  caption: 'Dynamic type, reduce motion',
                  onTap: () => _showSettingSheet(
                    context,
                    title: 'Accessibility',
                    body:
                        'PharmaGuide respects your system text-size and '
                        'reduce-motion settings. Layouts clamp extreme '
                        'text scaling so safety content remains readable.',
                  ),
                ),
                PGSettingsTile(
                  icon: Icons.cloud_download_outlined,
                  title: 'Offline mode',
                  caption: 'Download catalog for travel',
                  onTap: () => _showSettingSheet(
                    context,
                    title: 'Offline catalog',
                    body:
                        'The product catalog ships on device for lookup. '
                        'When an approved catalog update is available, '
                        'PharmaGuide can refresh it without uploading '
                        'your health data.',
                  ),
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
                  caption: 'pharmaguide.io/terms',
                  onTap: () => _openExternal(
                    context,
                    openExternal,
                    Uri.https('pharmaguide.io', '/terms'),
                  ),
                ),
                PGSettingsTile(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacy policy',
                  caption: 'pharmaguide.io/privacy',
                  onTap: () => _openExternal(
                    context,
                    openExternal,
                    Uri.https('pharmaguide.io', '/privacy'),
                  ),
                ),
                PGSettingsTile(
                  icon: Icons.support_outlined,
                  title: 'Contact support',
                  caption: 'support@pharmaguide.io',
                  onTap: () => _openExternal(
                    context,
                    openExternal,
                    Uri(
                      scheme: 'mailto',
                      path: 'support@pharmaguide.io',
                      queryParameters: {'subject': 'PharmaGuide support'},
                    ),
                  ),
                ),
                PGSettingsTile(
                  icon: Icons.feedback_outlined,
                  title: 'Send beta feedback',
                  caption: 'Quick note — no health details',
                  onTap: () =>
                      showBetaFeedbackSheet(context, openExternal: openExternal),
                ),
                PGSettingsTile(
                  icon: Icons.star_outline_rounded,
                  title: 'Rate PharmaGuide',
                  caption: 'Enabled after App Store release',
                  onTap: () => _showSettingSheet(
                    context,
                    title: 'Rate PharmaGuide',
                    body:
                        'Ratings will open here after PharmaGuide is live '
                        'on the App Store. For TestFlight builds, send '
                        'feedback through the tester invitation.',
                  ),
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
                  onTap: () => _showSettingSheet(
                    context,
                    title: 'Export my data',
                    body:
                        'Your stack, profile, and scan history are stored '
                        'locally on this device. Export will be enabled '
                        'after the secure file-save flow is wired.',
                  ),
                ),
                PGSettingsTile(
                  icon: Icons.delete_outline_rounded,
                  title: 'Delete account',
                  caption: 'Permanently remove all data',
                  destructive: true,
                  onTap: () => _showSettingSheet(
                    context,
                    title: 'Delete account',
                    body:
                        'Account deletion requires a signed-in account. '
                        'Guest health data remains local to this device.',
                    destructive: true,
                  ),
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

Future<void> _signOut(
  BuildContext context,
  Future<void> Function()? onSignOut,
) async {
  try {
    await (onSignOut ?? PGAuthService().signOut)();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Signed out'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  } on Object {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Could not sign out. Try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }
}

Future<void> _openExternal(
  BuildContext context,
  Future<bool> Function(Uri uri) opener,
  Uri uri,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final opened = await opener(uri);
    if (opened || !context.mounted) return;
  } on Object {
    if (!context.mounted) return;
  }

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      const SnackBar(
        content: Text('Could not open link. Try again.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
}

void _showPrivacyDashboard(BuildContext context) {
  PGModal.bottomSheet<void>(
    context: context,
    builder: (_) => const _SettingsInfoSheet(
      title: 'Privacy dashboard',
      body:
          'PharmaGuide keeps your health profile, stack, medications, '
          'and scan history on this device. Supabase is used for account '
          'and sync plumbing only; health data is not uploaded.',
      bullets: [
        'Health profile: on device',
        'Supplement stack: on device',
        'Medication list: on device',
        'Recent scans: on device',
        'Account email: Supabase auth',
      ],
    ),
  );
}

void _showSettingSheet(
  BuildContext context, {
  required String title,
  required String body,
  bool destructive = false,
}) {
  PGModal.bottomSheet<void>(
    context: context,
    builder: (_) =>
        _SettingsInfoSheet(title: title, body: body, destructive: destructive),
  );
}

class _SettingsInfoSheet extends StatelessWidget {
  final String title;
  final String body;
  final List<String> bullets;
  final bool destructive;

  const _SettingsInfoSheet({
    required this.title,
    required this.body,
    this.bullets = const [],
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final tone = destructive ? V2Colors.contraindicated : V2Colors.accent;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        V2Spacing.space24,
        V2Spacing.space8,
        V2Spacing.space24,
        V2Spacing.space24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: V2Typography.titleSm(color: V2Colors.fg)),
          const SizedBox(height: V2Spacing.space8),
          Text(body, style: V2Typography.body(color: V2Colors.fgMuted)),
          if (bullets.isNotEmpty) ...[
            const SizedBox(height: V2Spacing.space16),
            for (final bullet in bullets)
              Padding(
                padding: const EdgeInsets.only(bottom: V2Spacing.space8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle_outline, size: 18, color: tone),
                    const SizedBox(width: V2Spacing.space8),
                    Expanded(
                      child: Text(
                        bullet,
                        style: V2Typography.bodySm(color: V2Colors.fg),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: V2Spacing.space16),
          PGPillButton(
            label: 'Done',
            variant: PGPillVariant.secondary,
            expand: true,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _AnalyticsSettingsSwitch extends StatefulWidget {
  const _AnalyticsSettingsSwitch();

  @override
  State<_AnalyticsSettingsSwitch> createState() =>
      _AnalyticsSettingsSwitchState();
}

class _AnalyticsSettingsSwitchState extends State<_AnalyticsSettingsSwitch> {
  bool _enabled = AnalyticsService().collectionEnabled;
  bool _saving = false;

  Future<void> _setEnabled(bool value) async {
    setState(() {
      _enabled = value;
      _saving = true;
    });
    await AnalyticsService().setCollectionEnabled(value);
    if (!mounted) return;
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Switch.adaptive(
      key: const Key('settings-analytics-toggle'),
      value: _enabled,
      onChanged: _saving ? null : _setEnabled,
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
      parts.add(
        '$medicationCount ${medicationCount == 1 ? "medication" : "medications"}',
      );
    }
    if (scanCount > 0) {
      parts.add('$scanCount ${scanCount == 1 ? "scan" : "scans"}');
    }
    return parts.isEmpty
        ? 'New here — let’s get you set up.'
        : parts.join(' · ');
  }
}
