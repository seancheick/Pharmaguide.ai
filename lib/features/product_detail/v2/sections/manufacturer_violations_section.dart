// Phase 11.7e — ManufacturerViolations section adapter (S15).
//
// V2 mirror of production's `ManufacturerViolationsSection`
// (lib/features/product_detail/widgets/pipeline_sections/
// manufacturer_violations_section.dart).
//
// Production reads `manufacturer_detail.violations.violations[]`
// (pipeline ships nested for forward-compat). Each violation has:
//   severity_level    (critical / high / moderate)
//   violation_type    (e.g. "GMP non-compliance", "Warning letter")
//   reason            (raw FDA reason string)
//   brand_trust_summary (Dr. Pham authored summary — preferred copy)
//   date              (ISO date string)
//   violation_id
//
// Production sorts by severity (critical → high → moderate), takes 5,
// uses brand_trust_summary OR reason as primary copy.
//
// V2 PGManufacturerViolationsSection takes List<PGViolation> with
// severity (PGReviewTone) + type + date + trustSummary + onTap.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_manufacturer_violations_section.dart';
import 'package:pharmaguide/core/components/pg_review_before_use_card.dart';
import 'package:pharmaguide/core/extensions/json_helpers.dart';

/// Build the ManufacturerViolations section. Returns `SizedBox.shrink()`
/// when the blob is null or contains no violations.
Widget buildManufacturerViolationsSection({
  required Map<String, dynamic>? manufacturerDetail,
}) {
  if (manufacturerDetail == null) return const SizedBox.shrink();

  // Pipeline nests violations under `violations.violations` — both
  // levels need defensive parsing (matches production lines 42-44).
  final violations = manufacturerDetail
      .safeMap('violations')
      .safeMapList('violations');
  if (violations.isEmpty) return const SizedBox.shrink();

  // Sort critical → high → moderate (verbatim from production line 51).
  final severityRank = <String, int>{
    'critical': 0,
    'high': 1,
    'moderate': 2,
  };
  final sorted = List<Map<String, dynamic>>.from(violations)
    ..sort((a, b) {
      final ra = severityRank[(a['severity_level']?.toString() ?? '')
              .toLowerCase()] ??
          99;
      final rb = severityRank[(b['severity_level']?.toString() ?? '')
              .toLowerCase()] ??
          99;
      return ra.compareTo(rb);
    });

  final mapped = sorted.map((v) {
    final severity =
        (v['severity_level']?.toString() ?? 'moderate').toLowerCase();
    final summary = v['brand_trust_summary']?.toString().trim() ?? '';
    final reason = v['reason']?.toString().trim() ?? '';
    // Prefer authored summary, fall back to FDA reason (production
    // line 115).
    final trustSummary = summary.isNotEmpty ? summary : reason;
    final violationType =
        v['violation_type']?.toString().trim() ?? 'FDA violation';
    final date = v['date']?.toString().trim();

    return PGViolation(
      severity: _toneFromSeverity(severity),
      type: violationType,
      date: date != null && date.isNotEmpty ? date : null,
      trustSummary: trustSummary,
    );
  }).toList(growable: false);

  return PGManufacturerViolationsSection(violations: mapped);
}

/// Map production severity ladder → v2 PGReviewTone for the row tint.
/// Production: critical=avoid(red), high=caution(amber), moderate=neutral.
PGReviewTone _toneFromSeverity(String severity) {
  switch (severity) {
    case 'critical':
      return PGReviewTone.danger;
    case 'high':
      return PGReviewTone.caution;
    default:
      return PGReviewTone.info;
  }
}
