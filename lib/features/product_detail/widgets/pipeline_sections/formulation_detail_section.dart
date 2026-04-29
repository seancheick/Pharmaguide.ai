// Formulation detail — delivery form, absorption enhancers, botanicals.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/extensions/json_helpers.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';

/// Extract display names from a pipeline list field that may ship in
/// either of two shapes:
///
/// 1. Legacy: `["Piperine", "BioPerine"]` (older catalogs)
/// 2. Current: `[{"name": "Ashwagandha (KSM-66)", "evidence_source": ...,
///    "meets_threshold": true}]`
///
/// Strings pass through trimmed; maps get their `name` field extracted.
/// Non-list values, non-string non-map entries, and entries with empty
/// names are dropped. The previous `.toString()` path was the source of
/// the "Ashwagandha {name: ..., evidence_source: ...}" JSON-leak users
/// saw in the formulation section (T0.3).
List<String> extractIngredientNames(dynamic raw) {
  if (raw is! List) return const <String>[];
  return raw
      .map<String>((e) {
        if (e is String) return e.trim();
        if (e is Map) return (e['name']?.toString() ?? '').trim();
        return '';
      })
      .where((s) => s.isNotEmpty)
      .toList(growable: false);
}

class FormulationDetailSection extends StatelessWidget {
  final Map<String, dynamic>? formulationDetail;
  final Map<String, dynamic>? ingredientQualityData;
  const FormulationDetailSection({
    super.key,
    this.formulationDetail,
    this.ingredientQualityData,
  });

  @override
  Widget build(BuildContext context) {
    if (formulationDetail == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final deliveryForm = formulationDetail!['delivery_form']?.toString() ?? '';
    final deliveryTier = formulationDetail!['delivery_tier']?.toString() ?? '';
    final enhancers =
        extractIngredientNames(formulationDetail!['absorption_enhancers']);
    final botanicals =
        extractIngredientNames(formulationDetail!['standardized_botanicals']);
    // `demoted_absorption_enhancers` is a list of {name, quantity, unit}
    // records; `safeList` returns const [] on any non-list shape, then we
    // filter to maps only via `whereType` before constructing the value
    // object.
    final demotedEnhancers = (ingredientQualityData ?? const <String, dynamic>{})
        .safeList('demoted_absorption_enhancers')
        .whereType<Map<dynamic, dynamic>>()
        .map((raw) => _BioavailabilityAid.fromMap(raw))
        .where((aid) => aid.label.isNotEmpty)
        .toList(growable: false);

    if (deliveryForm.isEmpty &&
        enhancers.isEmpty &&
        botanicals.isEmpty &&
        demotedEnhancers.isEmpty) {
      return const SizedBox.shrink();
    }

    return PGCard(
      padding: const EdgeInsets.all(AppTheme.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.science_outlined, size: 18),
              const SizedBox(width: AppTheme.space6),
              Text(
                'Formulation',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.15,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space12),
          if (deliveryForm.isNotEmpty)
            _DetailRow(
              label: 'Delivery form',
              value: deliveryForm,
              badge: deliveryTier.isNotEmpty ? deliveryTier : null,
            ),
          if (enhancers.isNotEmpty) ...[
            const SizedBox(height: AppTheme.space8),
            Text(
              'Absorption enhancers',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppTheme.space4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: enhancers
                  .map((e) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.severitySafe.withValues(alpha: 0.08),
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusFull),
                          border: Border.all(
                            color: AppTheme.severitySafe.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          e,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.severitySafe,
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ],
          if (demotedEnhancers.isNotEmpty) ...[
            const SizedBox(height: AppTheme.space8),
            Container(
              padding: const EdgeInsets.all(AppTheme.space12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                border: Border.all(
                  color: scheme.outlineVariant,
                  width: 0.6,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    demotedEnhancers.length == 1
                        ? 'Includes bioavailability aid'
                        : 'Includes bioavailability aids',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppTheme.space4),
                  Text(
                    'Used to support absorption and not scored as a primary active.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppTheme.space8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: demotedEnhancers
                        .map((aid) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.surface,
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusFull,
                                ),
                                border: Border.all(
                                  color: scheme.outlineVariant,
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                aid.label,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                ],
              ),
            ),
          ],
          if (botanicals.isNotEmpty) ...[
            const SizedBox(height: AppTheme.space8),
            Text(
              'Standardized botanicals',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppTheme.space4),
            ...botanicals.map((b) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    children: [
                      Icon(Icons.eco_outlined,
                          size: 13, color: scheme.primary),
                      const SizedBox(width: AppTheme.space6),
                      Text(b,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.w500)),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }
}

class _BioavailabilityAid {
  final String label;

  const _BioavailabilityAid(this.label);

  factory _BioavailabilityAid.fromMap(Map<dynamic, dynamic> raw) {
    final name = raw['name']?.toString().trim() ?? '';
    final quantity = raw['quantity'];
    final unit = raw['unit']?.toString().trim() ?? '';

    final quantityLabel = quantity is num
        ? unit.isEmpty
            ? quantity.toString()
            : '${quantity.toString()} $unit'
        : '';
    final label = quantityLabel.isEmpty ? name : '$name $quantityLabel';
    return _BioavailabilityAid(label);
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final String? badge;
  const _DetailRow({required this.label, required this.value, this.badge});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: AppTheme.space8),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        if (badge != null) ...[
          const SizedBox(width: AppTheme.space6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              badge!,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
