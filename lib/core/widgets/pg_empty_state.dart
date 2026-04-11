import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_motion.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';

/// Variants for [PGEmptyState].
enum PGEmptyStateVariant {
  /// Plain empty state — neutral surface, for "nothing to show yet" moments.
  plain,

  /// Informational — tinted with `info` color, for "here's what this area does".
  info,

  /// Error — tinted with the theme error color, for failed loads.
  error,

  /// Offline — neutral gray with cloud-off icon, for network failures.
  offline,
}

/// A reusable empty state with icon + headline + description + optional action.
///
/// Every empty state in the app should use this. Teaches the interface
/// instead of just saying "nothing here".
///
/// ```dart
/// PGEmptyState(
///   icon: Icons.history_rounded,
///   title: 'Nothing scanned yet',
///   description: 'Your last 10 scans will appear here.',
///   actionLabel: 'Scan now',
///   onAction: () => context.go('/scan'),
/// )
/// ```
class PGEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;
  final PGEmptyStateVariant variant;
  final EdgeInsetsGeometry padding;

  const PGEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
    this.variant = PGEmptyStateVariant.plain,
    this.padding = const EdgeInsets.fromLTRB(
      AppTheme.space16,
      AppTheme.space24,
      AppTheme.space16,
      AppTheme.space20,
    ),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    late final Color iconColor;
    late final Color iconBg;
    switch (variant) {
      case PGEmptyStateVariant.plain:
        iconColor = scheme.onSurfaceVariant;
        iconBg = scheme.surfaceContainerHigh;
        break;
      case PGEmptyStateVariant.info:
        iconColor = AppTheme.info;
        iconBg = AppTheme.info.withValues(alpha: 0.12);
        break;
      case PGEmptyStateVariant.error:
        iconColor = scheme.error;
        iconBg = scheme.error.withValues(alpha: 0.10);
        break;
      case PGEmptyStateVariant.offline:
        iconColor = scheme.onSurfaceVariant;
        iconBg = scheme.surfaceContainerHigh;
        break;
    }

    return PGCard(
      variant: PGCardVariant.recessed,
      padding: padding,
      child: AnimatedSwitcher(
        duration: AppMotion.medium,
        switchInCurve: AppMotion.standard,
        child: Column(
          key: ValueKey(title),
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon well
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(AppTheme.radiusFull),
              ),
              child: Icon(icon, size: 26, color: iconColor),
            ),
            const SizedBox(height: AppTheme.space12),
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              description,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppTheme.space16),
              _PillButton(
                label: actionLabel!,
                onTap: onAction!,
                color: variant == PGEmptyStateVariant.error
                    ? scheme.error
                    : scheme.primary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color color;

  const _PillButton({
    required this.label,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppTheme.radiusFull),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.space16,
            vertical: AppTheme.space8,
          ),
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(AppTheme.radiusFull),
            border: Border.all(color: scheme.outlineVariant, width: 0.8),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
              letterSpacing: -0.05,
            ),
          ),
        ),
      ),
    );
  }
}
