import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/app_colors.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';

/// Profile tab — the user's personal control panel.
/// Sections: Account, Health Profile, Privacy, Analysis History, Settings, About
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        children: [
          // Profile summary card
          _ProfileSummaryCard(profile: profile),
          const _SectionDivider(),

          // 1. Account & Security
          const _SectionHeader(title: 'Account & Security'),
          _SettingsTile(
            icon: Icons.email_outlined,
            title: 'Email',
            subtitle: 'Not signed in',
            onTap: () {}, // TODO: Auth flow
          ),
          _SettingsTile(
            icon: Icons.login,
            title: 'Sign In / Create Account',
            onTap: () {}, // TODO: Auth flow
          ),
          const _SectionDivider(),

          // 2. Health Profile
          const _SectionHeader(title: 'Health Profile'),
          _SettingsTile(
            icon: Icons.person_outline,
            title: 'Edit Profile',
            subtitle: '${profile.completeness}% complete',
            onTap: () => context.push('/profile/setup'),
          ),
          const _SectionDivider(),

          // 3. Privacy Controls
          const _SectionHeader(title: 'Privacy & Data'),
          _SettingsTile(
            icon: Icons.shield_outlined,
            title: 'Privacy Dashboard',
            subtitle: 'See where your data lives',
            onTap: () => _showPrivacyDashboard(context),
          ),
          const SwitchListTile(
            title: Text('Help Improve App'),
            subtitle: Text('Share anonymized usage data (no health info)'),
            value: false, // TODO: Wire to preference
            onChanged: null,
            secondary: Icon(Icons.analytics_outlined),
          ),
          const _SectionDivider(),

          // 4. Stack Analysis History
          const _SectionHeader(title: 'Analysis History'),
          _SettingsTile(
            icon: Icons.history,
            title: 'Saved Reports',
            subtitle: 'No saved analyses yet',
            onTap: () {}, // TODO: Navigate to saved reports
          ),
          const _SectionDivider(),

          // 5. Settings & Customization
          const _SectionHeader(title: 'Settings'),
          _SettingsTile(
            icon: Icons.palette_outlined,
            title: 'Theme',
            subtitle: 'System default',
            onTap: () {}, // TODO: Theme picker
          ),
          _SettingsTile(
            icon: Icons.notifications_outlined,
            title: 'Notifications',
            subtitle: 'Manage alerts and reminders',
            onTap: () {},
          ),
          _SettingsTile(
            icon: Icons.accessibility_new,
            title: 'Accessibility',
            subtitle: 'Dynamic type, high contrast, reduce motion',
            onTap: () {},
          ),
          _SettingsTile(
            icon: Icons.cloud_download_outlined,
            title: 'Offline Mode',
            subtitle: 'Auto-download for offline use',
            onTap: () {},
          ),
          _SettingsTile(
            icon: Icons.download_outlined,
            title: 'Export My Data',
            subtitle: 'Download profile, stack, and favorites (JSON)',
            onTap: () {},
          ),
          _SettingsTile(
            icon: Icons.delete_outline,
            title: 'Delete Account',
            subtitle: 'Permanently remove all data',
            onTap: () {},
            titleColor: AppColors.red,
          ),
          const _SectionDivider(),

          // 6. About
          const _SectionHeader(title: 'About'),
          _SettingsTile(
            icon: Icons.info_outline,
            title: 'Version',
            subtitle: '1.0.0 (build 1)',
            onTap: () {},
          ),
          _SettingsTile(
            icon: Icons.description_outlined,
            title: 'Terms of Service',
            onTap: () {},
          ),
          _SettingsTile(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy Policy',
            onTap: () {},
          ),
          _SettingsTile(
            icon: Icons.support_outlined,
            title: 'Contact Support',
            onTap: () {},
          ),
          _SettingsTile(
            icon: Icons.star_outline,
            title: 'Rate PharmaGuide',
            onTap: () {},
          ),
          _SettingsTile(
            icon: Icons.share_outlined,
            title: 'Share PharmaGuide',
            onTap: () {},
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _showPrivacyDashboard(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => const Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your Data Location',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            _PrivacyItem(
              icon: Icons.phone_android,
              label: 'STAYS ON YOUR DEVICE',
              items: [
                'Health profile & conditions',
                'Scan history & stack data',
                'AI conversation history',
                'Personal notes & reminders',
              ],
            ),
            SizedBox(height: 16),
            _PrivacyItem(
              icon: Icons.cloud_outlined,
              label: 'SYNCED TO CLOUD (If Enabled)',
              items: [
                'App settings and account preferences',
                'Anonymous usage analytics',
              ],
            ),
            SizedBox(height: 16),
            _PrivacyItem(
              icon: Icons.block,
              label: 'NEVER SHARED',
              items: [
                'Personal health information',
              ],
            ),
            SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// --- Helper Widgets ---

class _ProfileSummaryCard extends StatelessWidget {
  final ProfileState profile;
  const _ProfileSummaryCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: AppTheme.brandTeal.withValues(alpha: 0.12),
            child: Text(
              (profile.nickname?.isNotEmpty == true)
                  ? profile.nickname![0].toUpperCase()
                  : '?',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppTheme.brandTeal,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.nickname?.isNotEmpty == true
                      ? profile.nickname!
                      : 'Guest User',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Profile ${profile.completenessLabel} (${profile.completeness}%)',
                  style: TextStyle(color: colors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
          letterSpacing: 0.5,
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
  final Color? titleColor;
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: titleColor ?? AppColors.textSecondary),
      title: Text(title, style: TextStyle(color: titleColor)),
      subtitle: subtitle != null
          ? Text(subtitle!, style: const TextStyle(fontSize: 13))
          : null,
      trailing:
          const Icon(Icons.chevron_right, color: AppColors.textSecondary),
      onTap: onTap,
    );
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, indent: 16, endIndent: 16);
  }
}

class _PrivacyItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final List<String> items;
  const _PrivacyItem({
    required this.icon,
    required this.label,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: AppTheme.brandTeal),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(left: 28, top: 4),
            child: Text(
              '- $item',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
