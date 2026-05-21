import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';
import 'package:pharmaguide/core/widgets/pg_frosted_app_bar.dart';
import 'package:pharmaguide/core/widgets/pg_frosted_nav_bar.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/core/widgets/pg_pressable.dart';
import 'package:pharmaguide/core/widgets/pg_section_header.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/services/onboarding_prefs.dart';

/// Profile tab — the user's personal control panel.
/// Sections: Account, Health Profile, Privacy, Analysis History,
/// Settings, About.
///
/// Fully migrated to the PG design system — no direct AppColors refs,
/// no hardcoded typography, proper theme-aware rendering.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(loadedProfileProvider);
    final profile = profileAsync.asData?.value;
    final mq = MediaQuery.of(context);

    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          const PGFrostedAppBar(
            title: 'Profile',
            automaticallyImplyLeading: false, // tab root
          ),
          SliverPadding(
            padding: EdgeInsets.only(
              top: AppTheme.space8,
              bottom: mq.padding.bottom + kPGNavBarHeight + AppTheme.space16,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Summary card
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppTheme.space20,
                    AppTheme.space8,
                    AppTheme.space20,
                    0,
                  ),
                  child: _ProfileSummaryCard(
                    profile: profile,
                    isLoading: profileAsync.isLoading,
                  ),
                ),

                // -------- Health Profile --------
                const PGSectionHeader(title: 'Health profile'),
                _SettingsGroup(
                  children: [
                    _SettingsTile(
                      icon: Icons.person_outline_rounded,
                      title: 'Edit profile',
                      onTap: () => context.push(Routes.profileSetup),
                    ),
                  ],
                ),

                // -------- Privacy & Data --------
                const PGSectionHeader(title: 'Privacy & data'),
                _SettingsGroup(
                  children: [
                    _SettingsTile(
                      icon: Icons.shield_outlined,
                      title: 'Privacy dashboard',
                      subtitle: 'See where your data lives',
                      onTap: () => _showPrivacyDashboard(context),
                    ),
                    const _SettingsTile(
                      icon: Icons.analytics_outlined,
                      title: 'Help improve the app',
                      subtitle: 'Share anonymized usage data (no health info)',
                      trailing: Switch.adaptive(value: false, onChanged: null),
                    ),
                  ],
                ),

                // -------- Analysis History --------
                const PGSectionHeader(title: 'Analysis history'),
                _SettingsGroup(
                  children: [
                    _SettingsTile(
                      icon: Icons.history_rounded,
                      title: 'Saved reports',
                      subtitle: 'No saved analyses yet',
                      onTap: () {},
                    ),
                  ],
                ),

                // -------- Settings --------
                const PGSectionHeader(title: 'Settings'),
                _SettingsGroup(
                  children: [
                    _SettingsTile(
                      icon: Icons.palette_outlined,
                      title: 'Theme',
                      subtitle: 'System default',
                      onTap: () {},
                    ),
                    _SettingsTile(
                      icon: Icons.notifications_outlined,
                      title: 'Notifications',
                      subtitle: 'Manage alerts and reminders',
                      onTap: () {},
                    ),
                    _SettingsTile(
                      icon: Icons.accessibility_new_rounded,
                      title: 'Accessibility',
                      subtitle: 'Dynamic type, high contrast, reduce motion',
                      onTap: () {},
                    ),
                    _SettingsTile(
                      icon: Icons.cloud_download_outlined,
                      title: 'Offline mode',
                      subtitle: 'Auto-download for offline use',
                      onTap: () {},
                    ),
                    _SettingsTile(
                      icon: Icons.download_outlined,
                      title: 'Export my data',
                      subtitle: 'Download profile, stack, and favorites (JSON)',
                      onTap: () {},
                    ),
                    _SettingsTile(
                      icon: Icons.delete_outline_rounded,
                      title: 'Delete account',
                      subtitle: 'Permanently remove all data',
                      destructive: true,
                      onTap: () {},
                    ),
                  ],
                ),

                // -------- About --------
                const PGSectionHeader(title: 'About'),
                _SettingsGroup(
                  children: [
                    const _SettingsTile(
                      icon: Icons.info_outline_rounded,
                      title: 'Version',
                      subtitle: '1.0.0 (build 1)',
                    ),
                    _SettingsTile(
                      icon: Icons.description_outlined,
                      title: 'Terms of service',
                      onTap: () {},
                    ),
                    _SettingsTile(
                      icon: Icons.privacy_tip_outlined,
                      title: 'Privacy policy',
                      onTap: () {},
                    ),
                    _SettingsTile(
                      icon: Icons.support_outlined,
                      title: 'Contact support',
                      onTap: () {},
                    ),
                    _SettingsTile(
                      icon: Icons.star_outline_rounded,
                      title: 'Rate PharmaGuide',
                      onTap: () {},
                    ),
                    _SettingsTile(
                      icon: Icons.ios_share_rounded,
                      title: 'Share PharmaGuide',
                      onTap: () {},
                    ),
                  ],
                ),

                // -------- Debug (kDebugMode only) --------
                if (kDebugMode) ...[
                  const PGSectionHeader(title: 'Debug'),
                  _SettingsGroup(
                    children: [
                      _SettingsTile(
                        icon: Icons.replay_rounded,
                        title: 'Reset onboarding',
                        subtitle: 'Show the 3-slide intro on next launch',
                        onTap: () => _resetOnboarding(context),
                      ),
                    ],
                  ),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _resetOnboarding(BuildContext context) async {
    await OnboardingPrefs.reset();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Onboarding reset — restart the app to see it again'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showPrivacyDashboard(BuildContext context) {
    PGModal.bottomSheet<void>(
      context: context,
      showDragHandle: false,
      builder: (_) => const _PrivacyDashboardSheet(),
    );
  }
}

// ---------------------------------------------------------------------------
// Profile summary card
// ---------------------------------------------------------------------------

class _ProfileSummaryCard extends StatelessWidget {
  final ProfileState? profile;
  final bool isLoading;
  const _ProfileSummaryCard({required this.profile, this.isLoading = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final nickname = profile?.nickname;
    final hasNickname = nickname?.isNotEmpty == true;
    final name = isLoading
        ? 'Loading profile'
        : (hasNickname ? nickname! : 'Guest');
    final initial = isLoading
        ? ''
        : (hasNickname ? nickname![0].toUpperCase() : '?');

    return PGCard(
      padding: const EdgeInsets.all(AppTheme.space16),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppTheme.radiusFull),
            ),
            alignment: Alignment.center,
            child: isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: scheme.primary,
                    ),
                  )
                : Text(
                    initial,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.primary,
                    ),
                  ),
          ),
          const SizedBox(width: AppTheme.space16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: AppTheme.space2),
                Text(
                  'Your health settings',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Settings group — a PGCard wrapping a list of rows with inline dividers
// ---------------------------------------------------------------------------

class _SettingsGroup extends StatelessWidget {
  final List<Widget> children;
  const _SettingsGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space20,
        0,
        AppTheme.space20,
        AppTheme.space8,
      ),
      child: PGCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 56),
                  child: Divider(
                    height: 0.5,
                    thickness: 0.5,
                    color: scheme.outlineVariant,
                  ),
                ),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool destructive;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = destructive ? scheme.error : scheme.onSurfaceVariant;
    final titleColor = destructive ? scheme.error : scheme.onSurface;

    final tile = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space16,
        vertical: AppTheme.space12,
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: accent),
          const SizedBox(width: AppTheme.space16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: titleColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: AppTheme.space2),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null)
            trailing!
          else if (onTap != null)
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: scheme.onSurfaceVariant,
            ),
        ],
      ),
    );

    if (onTap == null) return tile;

    return PGPressable(
      onTap: onTap,
      pressedScale: 0.98, // settings rows are dense — keep press subtle
      child: tile,
    );
  }
}

// ---------------------------------------------------------------------------
// Privacy dashboard sheet
// ---------------------------------------------------------------------------

class _PrivacyDashboardSheet extends StatelessWidget {
  const _PrivacyDashboardSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space20,
        AppTheme.space8,
        AppTheme.space20,
        AppTheme.space32 + kPGNavBarHeight,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Where your data lives',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: AppTheme.space20),
          const _PrivacyItem(
            icon: Icons.phone_iphone_rounded,
            label: 'STAYS ON YOUR DEVICE',
            tone: _PrivacyTone.primary,
            items: [
              'Health profile & conditions',
              'Medications and scan history',
              'AI conversation history',
              'Personal notes & reminders',
            ],
          ),
          const SizedBox(height: AppTheme.space16),
          const _PrivacyItem(
            icon: Icons.cloud_outlined,
            label: 'SYNCED TO CLOUD (if enabled)',
            tone: _PrivacyTone.info,
            items: [
              'Supplement stack entries',
              'App settings and account preferences',
              'Anonymous usage analytics',
            ],
          ),
          const SizedBox(height: AppTheme.space16),
          const _PrivacyItem(
            icon: Icons.block_rounded,
            label: 'NEVER SHARED',
            tone: _PrivacyTone.safe,
            items: [
              'Medications (PHI-sensitive)',
              'Conditions, allergies, and health profile',
            ],
          ),
        ],
      ),
    );
  }
}

enum _PrivacyTone { primary, info, safe }

class _PrivacyItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final List<String> items;
  final _PrivacyTone tone;
  const _PrivacyItem({
    required this.icon,
    required this.label,
    required this.items,
    required this.tone,
  });

  Color _accent(ColorScheme scheme) {
    switch (tone) {
      case _PrivacyTone.primary:
        return scheme.primary;
      case _PrivacyTone.info:
        return AppTheme.info;
      case _PrivacyTone.safe:
        return AppTheme.severitySafe;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = _accent(scheme);

    return PGCard(
      padding: const EdgeInsets.all(AppTheme.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: AppTheme.space8),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space8),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(top: 4, left: 26),
              child: Text(
                '• $item',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
