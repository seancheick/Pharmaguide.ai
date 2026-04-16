// Formulation detail — delivery form, absorption enhancers, botanicals.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';

class FormulationDetailSection extends StatelessWidget {
  final Map<String, dynamic>? formulationDetail;
  const FormulationDetailSection({super.key, this.formulationDetail});

  @override
  Widget build(BuildContext context) {
    if (formulationDetail == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final deliveryForm = formulationDetail!['delivery_form']?.toString() ?? '';
    final deliveryTier = formulationDetail!['delivery_tier']?.toString() ?? '';
    final enhancers = (formulationDetail!['absorption_enhancers'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    final botanicals = (formulationDetail!['standardized_botanicals'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    if (deliveryForm.isEmpty && enhancers.isEmpty && botanicals.isEmpty) {
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
              const SizedBox(width: 6),
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
            const SizedBox(height: 8),
            Text(
              'Absorption enhancers',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
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
          if (botanicals.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Standardized botanicals',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            ...botanicals.map((b) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    children: [
                      Icon(Icons.eco_outlined,
                          size: 13, color: scheme.primary),
                      const SizedBox(width: 6),
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
        const SizedBox(width: 8),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        if (badge != null) ...[
          const SizedBox(width: 6),
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
