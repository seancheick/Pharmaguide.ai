import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';

/// Trust strip — shown at the bottom of product detail and interaction
/// screens. Tells the user how many sources back a claim, when the data was
/// last reviewed, and gives them a way to audit it.
///
/// ```dart
/// PGCitationStrip(
///   sourceCount: 12,
///   updatedAt: DateTime(2026, 4, 1),
///   disclaimer: 'Not medical advice. Consult your healthcare provider.',
///   onTap: () => showSourcesSheet(context),
/// )
/// ```
class PGCitationStrip extends StatelessWidget {
  final int sourceCount;
  final DateTime? updatedAt;
  final String? disclaimer;
  final VoidCallback? onTap;

  const PGCitationStrip({
    super.key,
    required this.sourceCount,
    this.updatedAt,
    this.disclaimer,
    this.onTap,
  });

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String _formatDate(DateTime d) =>
      '${_months[d.month - 1]} ${d.day}, ${d.year}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final content = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space12,
        vertical: AppTheme.space12,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: scheme.outlineVariant, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.verified_outlined,
                size: 15,
                color: AppTheme.evidenceStrong,
              ),
              const SizedBox(width: AppTheme.space6),
              Text(
                'Reviewed sources',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(width: AppTheme.space6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.evidenceStrong.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                ),
                child: Text(
                  '$sourceCount',
                  style: AppTheme.numeric(
                    const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.evidenceStrong,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              if (updatedAt != null)
                Text(
                  'Updated ${_formatDate(updatedAt!)}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              if (onTap != null) ...[
                const SizedBox(width: AppTheme.space4),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ],
          ),
          if (disclaimer != null) ...[
            const SizedBox(height: AppTheme.space6),
            Text(
              disclaimer!,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: scheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return content;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}
