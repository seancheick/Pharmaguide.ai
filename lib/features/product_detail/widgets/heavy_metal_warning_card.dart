// HeavyMetalWarningCard — displays heavy metal risk signals from the
// pipeline's `heavy_metal_detail` blob field.
//
// This card is a NO-OP until the pipeline adds `heavy_metal_detail` to
// the detail blob. It auto-hides when the field is null or has no signals.
// Schema (future pipeline output):
//   heavy_metal_detail: {
//     signals: [{ingredient, limit_source, risk_level, notes}]
//   }

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';

class HeavyMetalWarningCard extends StatelessWidget {
  final Map<String, dynamic>? heavyMetalDetail;

  const HeavyMetalWarningCard({super.key, this.heavyMetalDetail});

  @override
  Widget build(BuildContext context) {
    if (heavyMetalDetail == null) return const SizedBox.shrink();
    final signals = (heavyMetalDetail!['signals'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        [];
    if (signals.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return PGCard(
      padding: const EdgeInsets.all(AppTheme.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 18, color: AppTheme.severityAvoid),
              const SizedBox(width: 6),
              Text(
                'Heavy Metal Risk',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.15,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.severityAvoid.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                ),
                child: Text(
                  '${signals.length} ingredient${signals.length == 1 ? "" : "s"}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.severityAvoid,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space12),
          ...signals.take(5).map((sig) {
            final ingredient = sig['ingredient']?.toString() ?? '';
            final limitSource = sig['limit_source']?.toString() ?? '';
            final notes = sig['notes']?.toString() ?? '';
            final riskLevel = sig['risk_level']?.toString() ?? '';
            final color = riskLevel == 'high'
                ? AppTheme.severityAvoid
                : AppTheme.severityCaution;

            return Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.space8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(top: 4, right: 8),
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              ingredient,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (limitSource.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Text(
                                limitSource,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (notes.isNotEmpty)
                          Text(
                            notes,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
          Text(
            'Source: Prop 65 / EPA reference doses. Applies to raw materials from certain origins.',
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
}
