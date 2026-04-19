// Manufacturer violations — per-violation detail with Dr. Pham-authored
// brand_trust_summary copy.
//
// Blob shape (from scripts/build_final_db.py manufacturer_detail pass-
// through):
//   manufacturer_detail.violations = {
//     "found": true/false,
//     "total_deduction_applied": -N.N,
//     "violations": [
//       {
//         "violation_id": "V029",
//         "violation_type": "Class III Recall",
//         "severity_level": "critical" | "high" | "moderate",
//         "date": "2023-05-12",
//         "matched_manufacturer": "Acme Supps",
//         "brand_trust_summary": "Class I recall for ... . Check your supply.",
//         "reason": "Original FDA recall description...",
//         ...
//       },
//       ...
//     ]
//   }
//
// Rendering rule: if found==true and violations list is non-empty,
// render a section surfacing each violation with severity-matched
// styling and Dr. Pham's brand_trust_summary as the primary copy.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';

class ManufacturerViolationsSection extends StatelessWidget {
  final Map<String, dynamic>? manufacturerDetail;
  const ManufacturerViolationsSection({super.key, this.manufacturerDetail});

  @override
  Widget build(BuildContext context) {
    if (manufacturerDetail == null) return const SizedBox.shrink();
    final violations = ((manufacturerDetail!['violations']
                as Map<String, dynamic>?)?['violations']
            as List?)
        ?.whereType<Map<String, dynamic>>()
        .toList() ??
        [];
    if (violations.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // Sort critical → high → moderate so the most serious lands first.
    final severityRank = <String, int>{
      'critical': 0,
      'high': 1,
      'moderate': 2,
    };
    final sorted = List<Map<String, dynamic>>.from(violations)
      ..sort((a, b) {
        final ra = severityRank[
                (a['severity_level']?.toString() ?? '').toLowerCase()] ??
            99;
        final rb = severityRank[
                (b['severity_level']?.toString() ?? '').toLowerCase()] ??
            99;
        return ra.compareTo(rb);
      });

    return PGCard(
      padding: const EdgeInsets.all(AppTheme.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.factory_outlined, size: 18, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                'Manufacturer History',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.15,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius:
                      BorderRadius.circular(AppTheme.radiusFull),
                ),
                child: Text(
                  '${sorted.length}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Past FDA enforcement actions tied to this brand.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTheme.space12),
          ...sorted.take(5).map((v) {
            final severity =
                (v['severity_level']?.toString() ?? 'moderate').toLowerCase();
            final summary = v['brand_trust_summary']?.toString() ?? '';
            final reason = v['reason']?.toString() ?? '';
            // Prefer Dr. Pham's authored brand_trust_summary; fall back to
            // the original FDA reason field when the authored copy isn't
            // yet populated (e.g. pre-Path-C blobs).
            final primaryCopy = summary.isNotEmpty ? summary : reason;
            final violationType = v['violation_type']?.toString() ?? '';
            final date = v['date']?.toString() ?? '';
            final violationId = v['violation_id']?.toString() ?? '';

            // Severity styling — critical=error, high=warning, moderate=neutral.
            final severityColor = switch (severity) {
              'critical' => AppTheme.severityAvoid,
              'high' => AppTheme.severityCaution,
              _ => scheme.onSurfaceVariant,
            };

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.all(AppTheme.space12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLowest,
                  borderRadius:
                      BorderRadius.circular(AppTheme.radiusMedium),
                  border: Border.all(
                    color: severity == 'critical'
                        ? severityColor.withValues(alpha: 0.5)
                        : scheme.outlineVariant,
                    width: severity == 'critical' ? 1.0 : 0.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: severityColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            severity.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: severityColor,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            violationType.isNotEmpty
                                ? violationType
                                : 'FDA Action',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (date.isNotEmpty)
                          Text(
                            date,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                    if (primaryCopy.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        primaryCopy,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface,
                          height: 1.35,
                        ),
                      ),
                    ],
                    if (violationId.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Ref: $violationId',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontFeatures: const [
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
          if (sorted.length > 5) ...[
            const SizedBox(height: 4),
            Text(
              '+ ${sorted.length - 5} more historical violation(s)',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
