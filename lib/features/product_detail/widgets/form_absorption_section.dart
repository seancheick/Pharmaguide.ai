// FormAbsorptionSection — shows per-ingredient bioavailability comparison.
//
// Reads `ingredients[].bio_score` (0–18 pipeline score) and
// `ingredients[].form` from the detail blob. Only renders when ≥ 2
// ingredients have a non-null `bio_score`, so it stays hidden for
// products where bioavailability data is absent.
//
// Design principle: show comparative context (glycinate vs oxide) not just
// a number — that's what helps users make better choices.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';

class FormAbsorptionSection extends StatelessWidget {
  final List<Map<String, dynamic>> ingredients;

  const FormAbsorptionSection({super.key, required this.ingredients});

  /// Human-readable label for a bio_score (0–18).
  static String bioLabel(num score) {
    if (score >= 12) return 'Excellent';
    if (score >= 8) return 'Good';
    if (score >= 4) return 'Fair';
    return 'Poor';
  }

  static Color _bioColor(num score) {
    if (score >= 12) return AppTheme.severitySafe;
    if (score >= 8) return AppTheme.scoreGood;
    if (score >= 4) return AppTheme.severityCaution;
    return AppTheme.severityAvoid;
  }

  @override
  Widget build(BuildContext context) {
    // Only include ingredients that actually have a bio_score.
    final scored = ingredients
        .where((i) => i['bio_score'] != null)
        .toList()
      ..sort((a, b) =>
          (b['bio_score'] as num).compareTo(a['bio_score'] as num));

    // Need at least 2 scored ingredients to make a comparison meaningful.
    if (scored.length < 2) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const maxScore = 18.0;

    return PGCard(
      padding: const EdgeInsets.all(AppTheme.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.biotech_outlined,
                  size: 18, color: AppTheme.evidenceStrong),
              const SizedBox(width: 6),
              Text(
                'Form & Absorption',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.15,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => _showExplainer(context),
                child: Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space12),
          // Per-ingredient bars, ranked highest first.
          ...scored.take(6).map((ing) {
            final name = ing['name']?.toString() ??
                ing['standard_name']?.toString() ??
                '';
            final form = ing['form']?.toString() ?? '';
            final score = (ing['bio_score'] as num).toDouble();
            final fillPct = (score / maxScore).clamp(0.0, 1.0);
            final color = _bioColor(score);
            final label = bioLabel(score);

            return Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.space12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                  if (form.isNotEmpty)
                    Text(
                      form,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontSize: 10,
                      ),
                    ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                    child: LinearProgressIndicator(
                      value: fillPct,
                      minHeight: 6,
                      backgroundColor: scheme.surfaceContainerHigh,
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                ],
              ),
            );
          }),
          // Caption explaining scale.
          Text(
            'Higher absorption = more gets into your bloodstream.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontSize: 10,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  void _showExplainer(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppTheme.radiusXLarge)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(AppTheme.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'About Bioavailability Scores',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: AppTheme.space12),
            const Text(
              'Bioavailability measures how much of an ingredient your body can actually absorb and use. '
              'The score (0–18) is based on the ingredient\'s chemical form, known absorption rates, '
              'and presence of absorption enhancers.\n\n'
              'Example: Magnesium glycinate (score 15) absorbs ~4x better than magnesium oxide (score 4), '
              'which passes through largely unchanged.',
            ),
            const SizedBox(height: AppTheme.space16),
            const _ExplainerRow(
                label: 'Excellent (12–18)',
                description: 'Highly bioavailable form',
                tier: 'excellent'),
            const _ExplainerRow(
                label: 'Good (8–11)',
                description: 'Well-absorbed form',
                tier: 'good'),
            const _ExplainerRow(
                label: 'Fair (4–7)',
                description: 'Moderate absorption',
                tier: 'fair'),
            const _ExplainerRow(
                label: 'Poor (0–3)',
                description: 'Low bioavailability',
                tier: 'poor'),
            const SizedBox(height: AppTheme.space8),
          ],
        ),
      ),
    );
  }
}

class _ExplainerRow extends StatelessWidget {
  final String label;
  final String description;
  final String tier;

  const _ExplainerRow({
    required this.label,
    required this.description,
    required this.tier,
  });

  Color get _color {
    switch (tier) {
      case 'excellent':
        return AppTheme.severitySafe;
      case 'good':
        return AppTheme.scoreGood;
      case 'fair':
        return AppTheme.severityCaution;
      default:
        return AppTheme.severityAvoid;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.space8),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: _color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(width: 4),
          Text(
            '— $description',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
