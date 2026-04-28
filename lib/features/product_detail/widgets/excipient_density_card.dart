// ExcipientDensityCard — shows the ratio of active ingredients to
// inactive fillers/excipients. Uses counts as a proxy (we don't have
// gram weights for excipients). Hidden when both lists are empty OR
// when every excipient is whitelisted standard manufacturing material
// AND the count is within the form's allowance (T0.5 Phase 1 — see
// `standard_excipients.dart`).

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/data/standard_excipients.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';

class ExcipientDensityCard extends StatelessWidget {
  final List<Map<String, dynamic>> activeIngredients;
  final List<Map<String, dynamic>> inactiveIngredients;

  /// Pipeline `delivery_form` string (e.g. "Vegetable Capsule",
  /// "Tablet", "Powder", "Gummy"). Optional — `null` is treated as
  /// `DosageForm.unknown` and falls back to capsule-like thresholds.
  final String? dosageForm;

  const ExcipientDensityCard({
    super.key,
    required this.activeIngredients,
    required this.inactiveIngredients,
    this.dosageForm,
  });

  /// Human-readable purity label based on active vs inactive counts.
  static String densityLabel(int active, int inactive) {
    if (inactive == 0) return 'Minimal fillers';
    final ratio = inactive / (active + inactive);
    if (ratio < 0.3) return 'Minimal fillers';
    if (ratio < 0.55) return 'Moderate fillers';
    return 'High filler load';
  }

  static Color _densityColor(int active, int inactive) {
    if (inactive == 0) return AppTheme.severitySafe;
    final ratio = inactive / (active + inactive);
    if (ratio < 0.3) return AppTheme.severitySafe;
    if (ratio < 0.55) return AppTheme.severityCaution;
    return AppTheme.severityAvoid;
  }

  @override
  Widget build(BuildContext context) {
    if (activeIngredients.isEmpty && inactiveIngredients.isEmpty) {
      return const SizedBox.shrink();
    }

    // T0.5: hide-when-clean. If every inactive entry is a whitelisted
    // standard manufacturing component AND the count is within the
    // form's allowance, suppress the card entirely.
    final inactiveNames = inactiveIngredients
        .map((m) =>
            (m['name'] ?? m['display_name'] ?? '').toString())
        .toList(growable: false);
    final form = parseDosageForm(dosageForm);
    if (!shouldShowPurityCard(form: form, inactiveNames: inactiveNames)) {
      return const SizedBox.shrink();
    }

    final active = activeIngredients.length;
    final inactive = inactiveIngredients.length;
    final label = densityLabel(active, inactive);
    final color = _densityColor(active, inactive);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final total = active + inactive;
    final activeFill = total > 0 ? active / total : 0.0;

    return PGCard(
      padding: const EdgeInsets.all(AppTheme.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.science_outlined, size: 18, color: color),
              const SizedBox(width: 6),
              Text(
                'Formulation Purity',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.15,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                  border: Border.all(color: color.withValues(alpha: 0.35)),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space12),
          // Stacked bar: active (teal) | inactive (gray)
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusFull),
            child: Row(
              children: [
                Expanded(
                  flex: (activeFill * 100).round().clamp(1, 99),
                  child: Container(height: 8, color: AppTheme.brandTeal),
                ),
                if (inactive > 0)
                  Expanded(
                    flex: ((1 - activeFill) * 100).round().clamp(1, 99),
                    child: Container(
                        height: 8, color: scheme.surfaceContainerHighest),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.space8),
          Row(
            children: [
              const _LegendDot(color: AppTheme.brandTeal),
              const SizedBox(width: 4),
              Text('$active active', style: theme.textTheme.labelSmall),
              const SizedBox(width: 12),
              _LegendDot(color: scheme.surfaceContainerHighest),
              const SizedBox(width: 4),
              Text(
                '$inactive ${inactive == 1 ? "filler" : "fillers"}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  const _LegendDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 0.5,
        ),
      ),
    );
  }
}
