// Synergy section adapter for Product Detail v2.
//
// Closes the v2 "Works well with" gap — Sprint 21's 54-cluster synergy
// data was reaching v1 Product Detail but never wired into v2. Per
// Sean's "v2 was a reskin, leave nothing behind" mandate: this thin
// adapter reuses the v1 `SynergyDetailSection` widget verbatim — same
// T22 filter (evidence_tier ≤ 2, match_count ≥ 2, all_adequate), same
// 3-chip cap, same tap-to-modal explainer.
//
// Data source: `detailBlob['synergy_detail']` (pipeline-baked from the
// 5,450 cluster rows in the bundled DB).

import 'package:flutter/material.dart';
import 'package:pharmaguide/features/product_detail/widgets/pipeline_sections/synergy_detail_section.dart';

/// Build the Synergy section. Returns `SizedBox.shrink()` when the
/// blob is missing `synergy_detail` OR when zero clusters survive the
/// T22 high-confidence filter (Sean's rule: never render a "we tried
/// but found nothing" placeholder for synergy — it's a trust-positive
/// surface, not a "0 results" page).
Widget buildSynergySection({
  required Map<String, dynamic>? detailBlob,
}) {
  if (detailBlob == null) return const SizedBox.shrink();
  final synergyDetail = detailBlob['synergy_detail'];
  if (synergyDetail is! Map<String, dynamic>) {
    return const SizedBox.shrink();
  }
  return SynergyDetailSection(synergyDetail: synergyDetail);
}
