// Excipient density section adapter for Product Detail v2.
//
// Surfaces "Minimal fillers / Moderate fillers / High filler load" as a
// formulation-quality signal alongside ingredient lists. Keeps the
// dose-form-aware whitelist suppression from `standard_excipients.dart`.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/data/standard_excipients.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

String excipientDensityLabel(int active, int inactive) {
  if (inactive == 0) return 'Minimal fillers';
  final ratio = inactive / (active + inactive);
  if (ratio < 0.3) return 'Minimal fillers';
  if (ratio < 0.55) return 'Moderate fillers';
  return 'High filler load';
}

_DensityTone _densityTone(int active, int inactive) {
  if (inactive == 0) {
    return const _DensityTone(V2Colors.safe, V2Colors.safeTint);
  }
  final ratio = inactive / (active + inactive);
  if (ratio < 0.3) {
    return const _DensityTone(V2Colors.safe, V2Colors.safeTint);
  }
  if (ratio < 0.55) {
    return const _DensityTone(V2Colors.caution, V2Colors.cautionTint);
  }
  return const _DensityTone(V2Colors.avoid, V2Colors.avoidTint);
}

/// Build the Excipient density section. Returns `SizedBox.shrink()`
/// when both ingredient lists are empty OR when every excipient is a
/// whitelisted standard manufacturing material within the form allowance.
Widget buildExcipientDensitySection({
  required List<Map<String, dynamic>> activeIngredients,
  required List<Map<String, dynamic>> inactiveIngredients,
  required String? dosageForm,
}) {
  if (activeIngredients.isEmpty && inactiveIngredients.isEmpty) {
    return const SizedBox.shrink();
  }

  final inactiveNames = inactiveIngredients
      .map((m) => (m['name'] ?? m['display_name'] ?? '').toString())
      .toList(growable: false);
  final form = parseDosageForm(dosageForm);
  if (!shouldShowPurityCard(form: form, inactiveNames: inactiveNames)) {
    return const SizedBox.shrink();
  }

  return _ExcipientDensitySection(
    activeCount: activeIngredients.length,
    inactiveCount: inactiveIngredients.length,
  );
}

class _ExcipientDensitySection extends StatelessWidget {
  final int activeCount;
  final int inactiveCount;

  const _ExcipientDensitySection({
    required this.activeCount,
    required this.inactiveCount,
  });

  @override
  Widget build(BuildContext context) {
    final total = activeCount + inactiveCount;
    final activeFill = total > 0 ? activeCount / total : 0.0;
    final label = excipientDensityLabel(activeCount, inactiveCount);
    final tone = _densityTone(activeCount, inactiveCount);

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
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: tone.tint,
                  borderRadius: BorderRadius.circular(V2Spacing.space8),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.science_outlined,
                  size: 18,
                  color: tone.color,
                ),
              ),
              const SizedBox(width: V2Spacing.space12),
              Expanded(
                child: Text(
                  'Formulation purity',
                  style: V2Typography.titleSm(color: V2Colors.fg),
                ),
              ),
              _DensityPill(label: label, tone: tone),
            ],
          ),
          const SizedBox(height: V2Spacing.space16),
          ClipRRect(
            borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
            child: Row(
              children: [
                Expanded(
                  flex: (activeFill * 100).round().clamp(1, 99),
                  child: Container(height: 8, color: V2Colors.accentStrong),
                ),
                if (inactiveCount > 0)
                  Expanded(
                    flex: ((1 - activeFill) * 100).round().clamp(1, 99),
                    child: Container(
                      height: 8,
                      color: V2Colors.surfaceContainerHighest,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: V2Spacing.space8),
          Row(
            children: [
              const _LegendDot(color: V2Colors.accentStrong),
              const SizedBox(width: V2Spacing.space4),
              Text(
                '$activeCount active',
                style: V2Typography.caption(color: V2Colors.fgMuted),
              ),
              const SizedBox(width: V2Spacing.space12),
              const _LegendDot(color: V2Colors.surfaceContainerHighest),
              const SizedBox(width: V2Spacing.space4),
              Text(
                '$inactiveCount ${inactiveCount == 1 ? "filler" : "fillers"}',
                style: V2Typography.caption(color: V2Colors.fgMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DensityPill extends StatelessWidget {
  final String label;
  final _DensityTone tone;

  const _DensityPill({required this.label, required this.tone});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: V2Spacing.space8,
        vertical: V2Spacing.space4,
      ),
      decoration: BoxDecoration(
        color: tone.tint,
        borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
        border: Border.all(color: tone.color.withValues(alpha: 0.35)),
      ),
      child: Text(label, style: V2Typography.caption(color: tone.color)),
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
        border: Border.all(color: V2Colors.outline),
      ),
    );
  }
}

class _DensityTone {
  final Color color;
  final Color tint;

  const _DensityTone(this.color, this.tint);
}
