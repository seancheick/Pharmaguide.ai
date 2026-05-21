import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// One population callout — a group with special caution flags
/// (pregnancy, lactation, pediatric, cardiovascular condition, etc.).
class PGPopulationCallout {
  final String label;

  /// Short description of why this population should take extra care.
  final String body;

  /// Icon used in the left column. Production maps from canonical
  /// population enum (pregnancy → pregnant_woman, kidney → bloodtype, …).
  final IconData icon;

  /// Optional tap action — production opens an explainer modal.
  final VoidCallback? onTap;

  const PGPopulationCallout({
    required this.label,
    required this.body,
    required this.icon,
    this.onTap,
  });
}

/// v2 populations section.
///
/// Lists affected population groups (typically 1-3) as tappable rows
/// under a "Populations to watch" eyebrow. Each row: caution-tinted icon
/// + label + body. Hidden entirely when there are no population flags.
class PGPopulationsSection extends StatelessWidget {
  final List<PGPopulationCallout> callouts;
  final String title;

  const PGPopulationsSection({
    super.key,
    required this.callouts,
    this.title = 'Populations to watch',
  });

  @override
  Widget build(BuildContext context) {
    if (callouts.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(V2Spacing.space16),
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: V2Colors.outline),
        boxShadow: V2Shadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: V2Typography.titleSm(color: V2Colors.fg)),
          const SizedBox(height: V2Spacing.space12),
          for (var i = 0; i < callouts.length; i++)
            _PopulationRow(
              callout: callouts[i],
              isLast: i == callouts.length - 1,
            ),
        ],
      ),
    );
  }
}

class _PopulationRow extends StatelessWidget {
  final PGPopulationCallout callout;
  final bool isLast;

  const _PopulationRow({required this.callout, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: V2Spacing.space8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: V2Colors.cautionTint,
              borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
            ),
            child: Icon(
              callout.icon,
              size: 18,
              color: V2Colors.caution,
            ),
          ),
          const SizedBox(width: V2Spacing.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  callout.label,
                  style: V2Typography.bodyMedium(color: V2Colors.fg),
                ),
                const SizedBox(height: 2),
                Text(
                  callout.body,
                  style: V2Typography.bodySm(color: V2Colors.fgMuted),
                ),
              ],
            ),
          ),
          if (callout.onTap != null) ...[
            const SizedBox(width: V2Spacing.space8),
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: V2Colors.fgMuted,
            ),
          ],
        ],
      ),
    );

    final wrapped = callout.onTap != null
        ? Material(
            color: Colors.transparent,
            child: InkWell(onTap: callout.onTap, child: row),
          )
        : row;

    if (isLast) return wrapped;
    return Column(
      children: [
        wrapped,
        const Divider(color: V2Colors.outline, height: 1, thickness: 0.4),
      ],
    );
  }
}
