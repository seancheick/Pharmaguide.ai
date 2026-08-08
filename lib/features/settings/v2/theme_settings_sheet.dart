import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/components/pg_toast.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/features/settings/providers/app_preferences_provider.dart';
import 'package:pharmaguide/services/settings/app_preferences.dart';

String themePreferenceLabel(AppThemePreference preference) =>
    switch (preference) {
      AppThemePreference.system => 'System',
      AppThemePreference.light => 'Light',
      AppThemePreference.dark => 'Dark',
    };

class ThemeSettingsSheet extends ConsumerWidget {
  const ThemeSettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref
        .watch(appPreferencesControllerProvider)
        .preferences
        .theme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        V2Spacing.space24,
        V2Spacing.space8,
        V2Spacing.space24,
        V2Spacing.space24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Appearance', style: V2Typography.titleSm(color: context.v2.fg)),
          const SizedBox(height: V2Spacing.space4),
          Text(
            'Choose how PharmaGuide looks.',
            style: V2Typography.bodySm(color: context.v2.fgMuted),
          ),
          const SizedBox(height: V2Spacing.space16),
          Material(
            color: context.v2.surface,
            borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: context.v2.outline),
                borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  _ThemeChoice(
                    key: const Key('theme-system'),
                    icon: Icons.brightness_auto_outlined,
                    title: 'System',
                    subtitle: 'Follows your device',
                    selected: selected == AppThemePreference.system,
                    onTap: () =>
                        _select(context, ref, AppThemePreference.system),
                  ),
                  Divider(height: 1, thickness: 1, color: context.v2.outline),
                  _ThemeChoice(
                    key: const Key('theme-light'),
                    icon: Icons.light_mode_outlined,
                    title: 'Light',
                    subtitle: 'Always use light appearance',
                    selected: selected == AppThemePreference.light,
                    onTap: () =>
                        _select(context, ref, AppThemePreference.light),
                  ),
                  Divider(height: 1, thickness: 1, color: context.v2.outline),
                  _ThemeChoice(
                    key: const Key('theme-dark'),
                    icon: Icons.dark_mode_outlined,
                    title: 'Dark',
                    subtitle: 'Always use dark appearance',
                    selected: selected == AppThemePreference.dark,
                    onTap: () => _select(context, ref, AppThemePreference.dark),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _select(
    BuildContext context,
    WidgetRef ref,
    AppThemePreference preference,
  ) async {
    final controller = ref.read(appPreferencesControllerProvider);
    if (controller.preferences.theme == preference) return;

    try {
      await controller.updateTheme(preference);
    } on Object {
      if (!context.mounted) return;
      PGToast.show(
        context,
        'Could not save appearance. Try again.',
        variant: PGToastVariant.error,
      );
    }
  }
}

class _ThemeChoice extends StatelessWidget {
  const _ThemeChoice({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      excludeSemantics: true,
      label: '$title appearance. $subtitle',
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: V2Spacing.space16,
              vertical: V2Spacing.space12,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: selected ? context.v2.accent : context.v2.fgMuted,
                ),
                const SizedBox(width: V2Spacing.space16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: V2Typography.bodyMedium(color: context.v2.fg),
                      ),
                      const SizedBox(height: V2Spacing.space4),
                      Text(
                        subtitle,
                        style: V2Typography.bodySm(color: context.v2.fgMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: V2Spacing.space12),
                if (selected)
                  Icon(Icons.check_rounded, color: context.v2.accent, size: 22)
                else
                  const SizedBox(width: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
